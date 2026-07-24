import 'dart:convert';

import '../database/app_database.dart';
import '../models/model_document.dart';
import 'model_document_local_store.dart';
import 'storage_service.dart';
import 'supabase_service.dart';

class ModelDocumentSyncService {
  ModelDocumentSyncService._();

  static final _client = SupabaseService.client;

  static Future<void> syncEntry(SyncQueueEntry entry) async {
    final payload = entry.payloadJson == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(entry.payloadJson!) as Map);

    if (entry.operation == 'delete') {
      final storagePath = payload['storage_path']?.toString();

      await _client
          .from('model_documents')
          .delete()
          .eq('user_id', entry.userId)
          .eq('id', entry.entityId);

      if (storagePath != null && storagePath.trim().isNotEmpty) {
        try {
          await StorageService.deleteModelDocument(storagePath);
        } catch (_) {
          // La suppression de la métadonnée reste prioritaire.
        }
      }
      return;
    }

    final document = ModelDocument.fromMap(payload);
    final data = document.toMap()
      ..['user_id'] = entry.userId
      ..remove('created_at');

    final existing = await _client
        .from('model_documents')
        .select('id')
        .eq('user_id', entry.userId)
        .eq('id', entry.entityId)
        .maybeSingle();

    late final Map<String, dynamic> remoteRow;

    if (existing == null) {
      final result = await _client
          .from('model_documents')
          .insert({
            ...data,
            'created_at': document.createdAt.toUtc().toIso8601String(),
          })
          .select()
          .single();
      remoteRow = Map<String, dynamic>.from(result);
    } else {
      final result = await _client
          .from('model_documents')
          .update({
            'document_name': document.documentName,
            'document_type': document.documentType,
          })
          .eq('user_id', entry.userId)
          .eq('id', entry.entityId)
          .select()
          .single();
      remoteRow = Map<String, dynamic>.from(result);
    }

    await ModelDocumentLocalStore.upsertDocument(
      userId: entry.userId,
      document: ModelDocument.fromMap(remoteRow),
    );
  }
}
