import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../database/app_database.dart';
import 'battery_sync_service.dart';
import 'maintenance_local_store.dart';
import 'supabase_service.dart';

class MaintenanceService {
  MaintenanceService._();

  static final _client = SupabaseService.client;
  static final _database = AppDatabase.instance;

  static Future<List<Map<String, dynamic>>> getLocalRecords() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const [];
    }

    return MaintenanceLocalStore.getRecords(userId: user.id);
  }

  static Future<List<Map<String, dynamic>>> getRecords() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const [];
    }

    final cached = await MaintenanceLocalStore.getRecords(userId: user.id);
    final hasCache = await MaintenanceLocalStore.hasCache(userId: user.id);

    if (hasCache) {
      unawaited(_refreshSilently(userId: user.id));
      return cached;
    }

    return _refreshFromCloud(userId: user.id);
  }

  static Future<Map<String, dynamic>?> getRecord({
    required String maintenanceId,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return null;
    }

    final local = await MaintenanceLocalStore.getRecord(
      userId: user.id,
      maintenanceId: maintenanceId,
    );

    if (local != null) {
      return local;
    }

    try {
      final remote = await _client
          .from('maintenance_records')
          .select()
          .eq('user_id', user.id)
          .eq('id', maintenanceId)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));

      if (remote == null) {
        return null;
      }

      final row = Map<String, dynamic>.from(remote);
      await MaintenanceLocalStore.upsertRow(userId: user.id, row: row);
      return row;
    } catch (_) {
      return null;
    }
  }

  static Future<void> refreshFromCloud() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return;
    }

    await _refreshFromCloud(userId: user.id);
  }

  static Future<void> _refreshSilently({required String userId}) async {
    try {
      await _refreshFromCloud(userId: userId);
    } catch (_) {
      // Le cache local reste la source d'affichage hors ligne.
    }
  }

  static Future<List<Map<String, dynamic>>> _refreshFromCloud({
    required String userId,
  }) async {
    final response = await _client
        .from('maintenance_records')
        .select()
        .eq('user_id', userId)
        .order('maintenance_date', ascending: false)
        .timeout(const Duration(seconds: 8));

    final rows = response
        .map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);

    await MaintenanceLocalStore.replaceRecords(userId: userId, rows: rows);

    return rows;
  }

  static Future<Map<String, dynamic>> createRecord({
    required String modelId,
    required DateTime maintenanceDate,
    required String recordType,
    required String title,
    required String notes,
    required Map<String, dynamic> data,
    int? packsSinceLastRevision,
    int? runtimeMinutesSinceLastRevision,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecté');
    }

    final now = DateTime.now();
    final maintenanceId = _newUuid();

    final row = <String, dynamic>{
      'id': maintenanceId,
      'user_id': user.id,
      'model_id': modelId,
      'maintenance_date': maintenanceDate.toUtc().toIso8601String(),
      'record_type': recordType,
      'title': title.trim(),
      'notes': notes.trim(),
      'data': data,
      'packs_since_last_revision': packsSinceLastRevision,
      'runtime_minutes_since_last_revision': runtimeMinutesSinceLastRevision,
      'created_at': now.toUtc().toIso8601String(),
      'updated_at': now.toUtc().toIso8601String(),
    };

    await MaintenanceLocalStore.upsertRow(userId: user.id, row: row);

    await _database.replacePendingSyncOperation(
      userId: user.id,
      entityType: 'maintenance',
      entityId: maintenanceId,
      operation: 'upsert',
      payloadJson: _encode(row),
    );

    unawaited(BatterySyncService.syncNow());
    return row;
  }

  static Future<Map<String, dynamic>> updateRecord({
    required String maintenanceId,
    required String modelId,
    required DateTime maintenanceDate,
    required String recordType,
    required String title,
    required String notes,
    required Map<String, dynamic> data,
    int? packsSinceLastRevision,
    int? runtimeMinutesSinceLastRevision,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecté');
    }

    final existing = await MaintenanceLocalStore.getRecord(
      userId: user.id,
      maintenanceId: maintenanceId,
    );

    final row = <String, dynamic>{
      ...?existing,
      'id': maintenanceId,
      'user_id': user.id,
      'model_id': modelId,
      'maintenance_date': maintenanceDate.toUtc().toIso8601String(),
      'record_type': recordType,
      'title': title.trim(),
      'notes': notes.trim(),
      'data': data,
      'packs_since_last_revision': packsSinceLastRevision,
      'runtime_minutes_since_last_revision': runtimeMinutesSinceLastRevision,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    await MaintenanceLocalStore.upsertRow(userId: user.id, row: row);

    await _database.replacePendingSyncOperation(
      userId: user.id,
      entityType: 'maintenance',
      entityId: maintenanceId,
      operation: 'upsert',
      payloadJson: _encode(row),
    );

    unawaited(BatterySyncService.syncNow());
    return row;
  }

  static Future<void> updateCounters({
    required String maintenanceId,
    required int packsSinceLastRevision,
    required int runtimeMinutesSinceLastRevision,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecté');
    }

    final existing = await MaintenanceLocalStore.getRecord(
      userId: user.id,
      maintenanceId: maintenanceId,
    );

    if (existing == null) {
      return;
    }

    final row = Map<String, dynamic>.from(existing)
      ..['packs_since_last_revision'] = packsSinceLastRevision
      ..['runtime_minutes_since_last_revision'] =
          runtimeMinutesSinceLastRevision
      ..['updated_at'] = DateTime.now().toUtc().toIso8601String();

    await MaintenanceLocalStore.upsertRow(userId: user.id, row: row);

    await _database.replacePendingSyncOperation(
      userId: user.id,
      entityType: 'maintenance',
      entityId: maintenanceId,
      operation: 'upsert',
      payloadJson: _encode(row),
    );

    unawaited(BatterySyncService.syncNow());
  }

  static Future<void> deleteRecord({required String maintenanceId}) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecté');
    }

    await MaintenanceLocalStore.markDeleted(
      userId: user.id,
      maintenanceId: maintenanceId,
    );

    await _database.replacePendingSyncOperation(
      userId: user.id,
      entityType: 'maintenance',
      entityId: maintenanceId,
      operation: 'delete',
    );

    unawaited(BatterySyncService.syncNow());
  }

  static Stream<List<Map<String, dynamic>>> watchRecords() {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const Stream.empty();
    }

    return MaintenanceLocalStore.watchRecords(userId: user.id);
  }

  static String _encode(Map<String, dynamic> row) {
    return jsonEncode(row);
  }

  static String _newUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    String hex(int value) => value.toRadixString(16).padLeft(2, '0');

    final value = bytes.map(hex).join();

    return '${value.substring(0, 8)}-'
        '${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-'
        '${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }
}
