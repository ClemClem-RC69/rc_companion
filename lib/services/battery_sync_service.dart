import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../database/app_database.dart';
import 'battery_local_store.dart';
import 'maintenance_sync_service.dart';
import 'model_document_sync_service.dart';
import 'model_radio_setup_sync_service.dart';
import 'model_setup_sync_service.dart';
import 'model_sync_service.dart';
import 'radio_sync_service.dart';
import 'session_sync_service.dart';
import 'supabase_service.dart';

class BatterySyncService {
  BatterySyncService._();

  static final AppDatabase _database = AppDatabase.instance;

  static StreamSubscription<List<ConnectivityResult>>? _subscription;
  static Timer? _retryTimer;
  static DateTime? _retryDueAt;
  static bool _running = false;
  static bool _rerunRequested = false;

  static Future<void> initialize() async {
    await _subscription?.cancel();

    _subscription = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((result) => result != ConnectivityResult.none);
      if (online) {
        unawaited(_resumeAndSync());
      }
    });

    unawaited(_resumeAndSync());
  }

  static Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryDueAt = null;
  }

  static Future<void> _resumeAndSync() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
      return;
    }

    await _database.releasePendingSyncOperations(userId: user.id);
    await syncNow();
  }

  static Future<void> syncNow() async {
    if (_running) {
      _rerunRequested = true;
      return;
    }

    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
      return;
    }

    // Ne bloque pas la synchronisation sur la valeur retournée par
    // connectivity_plus.
    //
    // Sur certaines plateformes desktop, notamment Windows, l'interface
    // réseau peut être signalée comme absente/indéterminée alors que Supabase
    // est réellement joignable. Dans ce cas, l'ancien contrôle empêchait
    // l'envoi automatique de la SyncQueue jusqu'à une synchronisation manuelle.
    //
    // On tente donc directement la synchronisation. Si le réseau est réellement
    // indisponible, l'opération distante échoue, reste dans la queue et le
    // mécanisme de retry existant la reprendra plus tard.
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryDueAt = null;
    _running = true;

    try {
      while (true) {
        _rerunRequested = false;

        final entries = await _database.getPendingSyncOperations();

        if (entries.isEmpty) {
          if (_rerunRequested) {
            continue;
          }
          break;
        }

        for (final entry in entries) {
          if (entry.userId != user.id) {
            continue;
          }

          await _database.setSyncOperationProcessing(id: entry.id, value: true);

          try {
            await _execute(entry);
            await _database.deleteSyncOperation(entry.id);
          } catch (error) {
            final delay = _retryDelayFor(entry.attemptCount + 1);

            await _database.markSyncOperationFailed(
              id: entry.id,
              error: error,
              nextAttemptAt: DateTime.now().add(delay),
            );

            _scheduleRetry(delay);
          }
        }

        // Reboucle pour traiter les opérations ajoutées pendant une
        // synchronisation déjà en cours.
      }
    } finally {
      _running = false;

      if (_rerunRequested) {
        _rerunRequested = false;
        unawaited(syncNow());
      }
    }
  }

  static Duration _retryDelayFor(int attemptNumber) {
    if (attemptNumber <= 1) {
      return const Duration(seconds: 5);
    }
    if (attemptNumber == 2) {
      return const Duration(seconds: 15);
    }
    return const Duration(seconds: 30);
  }

  static void _scheduleRetry(Duration delay) {
    final dueAt = DateTime.now().add(delay);
    final currentTimer = _retryTimer;
    final currentDueAt = _retryDueAt;

    if (currentTimer != null &&
        currentTimer.isActive &&
        currentDueAt != null &&
        !dueAt.isBefore(currentDueAt)) {
      return;
    }

    currentTimer?.cancel();
    _retryDueAt = dueAt;
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      _retryDueAt = null;
      unawaited(syncNow());
    });
  }

  static Future<void> _execute(SyncQueueEntry entry) async {
    final payload = entry.payloadJson == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(entry.payloadJson!) as Map);

    switch (entry.entityType) {
      case 'battery':
        await _syncBattery(entry, payload);
      case 'battery_measurement':
        await _syncMeasurement(entry, payload);
      case 'session':
        await SessionSyncService.syncEntry(entry);
      case 'maintenance':
        await MaintenanceSyncService.syncEntry(entry);
      case 'model_setup':
        await ModelSetupSyncService.syncEntry(entry);
      case 'model_radio_setup':
        await ModelRadioSetupSyncService.syncEntry(entry);
      case 'model':
        await ModelSyncService.syncEntry(entry);
      case 'model_document':
        await ModelDocumentSyncService.syncEntry(entry);
      case 'radio':
        await RadioSyncService.syncEntry(entry);
      default:
        throw StateError(
          'Type de synchronisation inconnu : ${entry.entityType}',
        );
    }
  }

  static Future<void> _syncBattery(
    SyncQueueEntry entry,
    Map<String, dynamic> payload,
  ) async {
    final client = SupabaseService.client;

    if (entry.operation == 'delete') {
      await client
          .from('batteries')
          .delete()
          .eq('user_id', entry.userId)
          .eq('battery_code', entry.entityId);
      return;
    }

    final existing = await client
        .from('batteries')
        .select('battery_code')
        .eq('user_id', entry.userId)
        .eq('battery_code', entry.entityId)
        .maybeSingle();

    if (existing == null) {
      await client.from('batteries').insert(payload);
    } else {
      await client
          .from('batteries')
          .update(payload)
          .eq('user_id', entry.userId)
          .eq('battery_code', entry.entityId);
    }
  }

  static Future<void> _syncMeasurement(
    SyncQueueEntry entry,
    Map<String, dynamic> payload,
  ) async {
    final client = SupabaseService.client;
    final remoteId = payload['id'] as int?;

    if (entry.operation == 'delete') {
      if (remoteId == null) {
        return;
      }

      await client
          .from('battery_measurements')
          .delete()
          .eq('user_id', entry.userId)
          .eq('id', remoteId);
      return;
    }

    final data = Map<String, dynamic>.from(payload)..remove('id');

    if (remoteId == null) {
      final inserted = await client
          .from('battery_measurements')
          .insert(data)
          .select()
          .single();

      await BatteryLocalStore.promoteMeasurementToRemote(
        userId: entry.userId,
        previousLocalKey: entry.entityId,
        remoteRow: Map<String, dynamic>.from(inserted),
      );
      return;
    }

    await client
        .from('battery_measurements')
        .update(data)
        .eq('user_id', entry.userId)
        .eq('id', remoteId);
  }
}
