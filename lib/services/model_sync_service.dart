import 'dart:convert';

import '../database/app_database.dart';
import 'model_local_store.dart';
import 'storage_service.dart';
import 'supabase_service.dart';

class ModelSyncService {
  ModelSyncService._();

  static final _client = SupabaseService.client;

  static Future<void> syncEntry(SyncQueueEntry entry) async {
    final payload = entry.payloadJson == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(entry.payloadJson!) as Map);

    if (entry.operation == 'delete') {
      await _deleteRemote(entry: entry, payload: payload);
      return;
    }

    await _upsertRemote(entry: entry, payload: payload);
  }

  static Future<void> _upsertRemote({
    required SyncQueueEntry entry,
    required Map<String, dynamic> payload,
  }) async {
    final data = Map<String, dynamic>.from(payload)
      ..['id'] = entry.entityId
      ..['user_id'] = entry.userId
      ..['updated_at'] = DateTime.now().toUtc().toIso8601String();

    final existing = await _client
        .from('rc_models')
        .select('id')
        .eq('user_id', entry.userId)
        .eq('id', entry.entityId)
        .maybeSingle();

    late final Map<String, dynamic> remoteRow;

    if (existing == null) {
      final result = await _client
          .from('rc_models')
          .insert(data)
          .select()
          .single();
      remoteRow = Map<String, dynamic>.from(result);
    } else {
      final updateData = Map<String, dynamic>.from(data)..remove('id');
      final result = await _client
          .from('rc_models')
          .update(updateData)
          .eq('user_id', entry.userId)
          .eq('id', entry.entityId)
          .select()
          .single();
      remoteRow = Map<String, dynamic>.from(result);
    }

    await ModelLocalStore.upsertRow(userId: entry.userId, row: remoteRow);
  }

  static Future<void> _deleteRemote({
    required SyncQueueEntry entry,
    required Map<String, dynamic> payload,
  }) async {
    await _client
        .from('rc_models')
        .delete()
        .eq('user_id', entry.userId)
        .eq('id', entry.entityId);

    final photoUrl = payload['photo_url']?.toString();
    if (photoUrl != null && photoUrl.trim().isNotEmpty) {
      try {
        await StorageService.deleteModelPhoto(photoUrl);
      } catch (_) {
        // La suppression de la ligne reste prioritaire.
      }
    }
  }
}
