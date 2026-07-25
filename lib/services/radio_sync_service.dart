import 'dart:convert';

import '../database/app_database.dart';
import 'radio_local_store.dart';
import 'supabase_service.dart';

class RadioSyncService {
  RadioSyncService._();

  static final _client = SupabaseService.client;

  static Future<void> syncEntry(SyncQueueEntry entry) async {
    final payload = entry.payloadJson == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(entry.payloadJson!) as Map);

    if (entry.operation == 'delete') {
      await _client
          .from('radios')
          .delete()
          .eq('user_id', entry.userId)
          .eq('id', entry.entityId);
      return;
    }

    final data = Map<String, dynamic>.from(payload)
      ..['id'] = entry.entityId
      ..['user_id'] = entry.userId
      ..remove('updated_at');

    final existing = await _client
        .from('radios')
        .select('id')
        .eq('user_id', entry.userId)
        .eq('id', entry.entityId)
        .maybeSingle();

    late final Map<String, dynamic> remoteRow;

    if (existing == null) {
      final result = await _client
          .from('radios')
          .insert(data)
          .select()
          .single();

      remoteRow = Map<String, dynamic>.from(result);
    } else {
      final updateData = Map<String, dynamic>.from(data)..remove('id');

      final result = await _client
          .from('radios')
          .update(updateData)
          .eq('user_id', entry.userId)
          .eq('id', entry.entityId)
          .select()
          .single();

      remoteRow = Map<String, dynamic>.from(result);
    }

    await RadioLocalStore.upsertRow(userId: entry.userId, row: remoteRow);
  }
}
