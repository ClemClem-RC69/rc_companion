import 'dart:convert';

import '../database/app_database.dart';
import 'model_radio_setup_local_store.dart';
import 'supabase_service.dart';

class ModelRadioSetupSyncService {
  ModelRadioSetupSyncService._();

  static final _client = SupabaseService.client;

  static Future<void> syncEntry(SyncQueueEntry entry) async {
    final payload = entry.payloadJson == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(entry.payloadJson!) as Map);

    if (entry.operation == 'delete') {
      await _client
          .from('model_radio_setups')
          .delete()
          .eq('user_id', entry.userId)
          .eq('model_id', entry.entityId);
      return;
    }

    final data = Map<String, dynamic>.from(payload)
      ..['user_id'] = entry.userId
      ..['model_id'] = entry.entityId
      ..['updated_at'] = DateTime.now().toUtc().toIso8601String();

    final response = await _client
        .from('model_radio_setups')
        .upsert(data, onConflict: 'model_id')
        .select()
        .single();

    await ModelRadioSetupLocalStore.upsertRow(
      userId: entry.userId,
      row: Map<String, dynamic>.from(response),
    );
  }
}
