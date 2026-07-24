import 'dart:convert';

import '../database/app_database.dart';
import '../models/model_setup.dart';
import 'model_setup_local_store.dart';
import 'supabase_service.dart';

class ModelSetupSyncService {
  ModelSetupSyncService._();

  static final _client = SupabaseService.client;

  static Future<void> syncEntry(SyncQueueEntry entry) async {
    if (entry.operation == 'delete') {
      await _client
          .from('model_setups')
          .delete()
          .eq('user_id', entry.userId)
          .eq('model_id', entry.entityId);
      return;
    }

    if (entry.payloadJson == null) {
      throw StateError('Payload du setup absent.');
    }

    final payload = Map<String, dynamic>.from(
      jsonDecode(entry.payloadJson!) as Map,
    );
    final setup = ModelSetup.fromMap(payload);
    final data = setup.toDatabaseMap(userId: entry.userId);

    final existing = await _client
        .from('model_setups')
        .select('id')
        .eq('user_id', entry.userId)
        .eq('model_id', entry.entityId)
        .maybeSingle();

    late final Map<String, dynamic> remoteRow;

    if (existing == null) {
      final result = await _client
          .from('model_setups')
          .insert(data)
          .select()
          .single();
      remoteRow = Map<String, dynamic>.from(result);
    } else {
      final result = await _client
          .from('model_setups')
          .update(data)
          .eq('user_id', entry.userId)
          .eq('model_id', entry.entityId)
          .select()
          .single();
      remoteRow = Map<String, dynamic>.from(result);
    }

    await ModelSetupLocalStore.replaceSetupFromCloud(
      userId: entry.userId,
      modelId: entry.entityId,
      row: remoteRow,
    );
  }
}
