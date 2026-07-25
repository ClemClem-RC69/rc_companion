import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../database/app_database.dart';
import 'battery_local_store.dart';
import 'model_document_sync_service.dart';
import 'model_setup_sync_service.dart';
import 'model_sync_service.dart';
import 'session_sync_service.dart';
import 'supabase_service.dart';

class BatterySyncService {
  BatterySyncService._();

  static final AppDatabase _database = AppDatabase.instance;

  static StreamSubscription<List<ConnectivityResult>>? _subscription;
  static Timer? _retryTimer;
  static bool _running = false;
  static bool _rerunRequested = false;

  static Future<void> initialize() async {
    await _subscription?.cancel();

    _subscription = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((result) => result != ConnectivityResult.none);
      if (online) {
        unawaited(syncNow());
      }
    });

    unawaited(syncNow());
  }

  static Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _retryTimer?.cancel();
    _retryTimer = null;
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

    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity.isEmpty ||
        connectivity.every((result) => result == ConnectivityResult.none)) {
      return;
    }

    _retryTimer?.cancel();
    _retryTimer = null;
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
            final delayMinutes = (entry.attemptCount + 1).clamp(1, 30);

            await _database.markSyncOperationFailed(
              id: entry.id,
              error: error,
              nextAttemptAt: DateTime.now().add(
                Duration(minutes: delayMinutes),
              ),
            );

            _scheduleRetry(Duration(minutes: delayMinutes));
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

  static void _scheduleRetry(Duration delay) {
    final currentTimer = _retryTimer;

    if (currentTimer != null && currentTimer.isActive) {
      return;
    }

    _retryTimer = Timer(delay, () {
      _retryTimer = null;
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
      case 'model_setup':
        await ModelSetupSyncService.syncEntry(entry);
      case 'model':
        await ModelSyncService.syncEntry(entry);
      case 'model_document':
        await ModelDocumentSyncService.syncEntry(entry);
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
