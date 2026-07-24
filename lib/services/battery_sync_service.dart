import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../database/app_database.dart';
import 'battery_local_store.dart';
import 'session_sync_service.dart';
import 'supabase_service.dart';

class BatterySyncService {
  BatterySyncService._();

  static final AppDatabase _database = AppDatabase.instance;

  static StreamSubscription<List<ConnectivityResult>>? _subscription;
  static bool _running = false;

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
  }

  static Future<void> syncNow() async {
    if (_running) {
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

    _running = true;

    try {
      final entries = await _database.getPendingSyncOperations();

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
            nextAttemptAt: DateTime.now().add(Duration(minutes: delayMinutes)),
          );
        }
      }
    } finally {
      _running = false;
    }
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
