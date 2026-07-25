import 'dart:convert';

import '../database/app_database.dart';
import 'maintenance_local_store.dart';
import 'supabase_service.dart';

class MaintenanceSyncService {
  MaintenanceSyncService._();

  static final AppDatabase _database = AppDatabase.instance;

  static Future<void> syncEntry(SyncQueueEntry entry) async {
    final payload = entry.payloadJson == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(entry.payloadJson!) as Map);

    final client = SupabaseService.client;

    if (entry.operation == 'delete') {
      await client
          .from('maintenance_records')
          .delete()
          .eq('user_id', entry.userId)
          .eq('id', entry.entityId);

      await MaintenanceLocalStore.removePermanently(
        userId: entry.userId,
        maintenanceId: entry.entityId,
      );
      return;
    }

    final data = Map<String, dynamic>.from(payload)
      ..['id'] = entry.entityId
      ..['user_id'] = entry.userId;

    final existing = await client
        .from('maintenance_records')
        .select('id')
        .eq('user_id', entry.userId)
        .eq('id', entry.entityId)
        .maybeSingle();

    Map<String, dynamic> remoteRow;

    if (existing == null) {
      final inserted = await client
          .from('maintenance_records')
          .insert(data)
          .select()
          .single();

      remoteRow = Map<String, dynamic>.from(inserted);
    } else {
      final updated = await client
          .from('maintenance_records')
          .update(data)
          .eq('user_id', entry.userId)
          .eq('id', entry.entityId)
          .select()
          .single();

      remoteRow = Map<String, dynamic>.from(updated);
    }

    await MaintenanceLocalStore.upsertRow(userId: entry.userId, row: remoteRow);
  }

  static Future<void> pullRemote({required String userId}) async {
    final rows = await SupabaseService.client
        .from('maintenance_records')
        .select()
        .eq('user_id', userId)
        .order('maintenance_date', ascending: false);

    final normalized = rows
        .map((raw) => Map<String, dynamic>.from(raw as Map))
        .toList(growable: false);

    await MaintenanceLocalStore.replaceRecords(
      userId: userId,
      rows: normalized,
    );
  }

  static Future<void> enqueueCreateOrUpdate({
    required String userId,
    required Map<String, dynamic> row,
  }) async {
    final maintenanceId = row['id']?.toString();

    if (maintenanceId == null || maintenanceId.trim().isEmpty) {
      throw StateError(
        'La maintenance doit posséder un identifiant avant synchronisation.',
      );
    }

    final payload = Map<String, dynamic>.from(row)
      ..['id'] = maintenanceId
      ..['user_id'] = userId;

    await MaintenanceLocalStore.upsertRow(userId: userId, row: payload);

    await _database.replacePendingSyncOperation(
      userId: userId,
      entityType: 'maintenance',
      entityId: maintenanceId,
      operation: 'upsert',
      payloadJson: jsonEncode(payload),
    );
  }

  static Future<void> enqueueDelete({
    required String userId,
    required String maintenanceId,
  }) async {
    await MaintenanceLocalStore.markDeleted(
      userId: userId,
      maintenanceId: maintenanceId,
    );

    await _database.replacePendingSyncOperation(
      userId: userId,
      entityType: 'maintenance',
      entityId: maintenanceId,
      operation: 'delete',
    );
  }
}
