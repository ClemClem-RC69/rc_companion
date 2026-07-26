import 'dart:convert';

import '../database/app_database.dart';
import 'radio_local_store.dart';
import 'radio_manual_file_store.dart';
import 'storage_service.dart';
import 'supabase_service.dart';

class RadioSyncService {
  RadioSyncService._();

  static final _client = SupabaseService.client;

  static Future<void> syncEntry(SyncQueueEntry entry) async {
    final payload = entry.payloadJson == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(entry.payloadJson!) as Map);

    final previousStoragePath = payload['manual_previous_storage_path']
        ?.toString()
        .trim();

    if (entry.operation == 'delete') {
      final currentStoragePath = payload['manual_storage_path']
          ?.toString()
          .trim();
      await _client
          .from('radios')
          .delete()
          .eq('user_id', entry.userId)
          .eq('id', entry.entityId);

      if (currentStoragePath != null && currentStoragePath.isNotEmpty) {
        try {
          await StorageService.deleteModelDocument(currentStoragePath);
        } catch (_) {
          // La suppression de la radio est prioritaire. Un éventuel ancien
          // fichier orphelin ne doit pas bloquer la file de synchronisation.
        }
      }
      return;
    }

    final localPath = payload['manual_local_path']?.toString().trim();
    final manualName = payload['manual_name']?.toString().trim();
    final pendingUpload = payload['manual_pending_upload'] == true;

    String? newStoragePath = payload['manual_storage_path']?.toString().trim();

    if (pendingUpload) {
      if (localPath == null || localPath.isEmpty) {
        throw StateError('Le fichier local du manuel radio est introuvable.');
      }
      if (manualName == null || manualName.isEmpty) {
        throw StateError('Le nom du manuel radio est introuvable.');
      }

      if (!await RadioManualFileStore.exists(localPath)) {
        throw StateError('Le fichier local du manuel radio est introuvable.');
      }

      final bytes = await RadioManualFileStore.readBytes(localPath);
      newStoragePath = await StorageService.uploadModelDocumentBytes(
        bytes: bytes,
        originalFilename: manualName,
        contentType: _contentTypeFor(manualName),
        modelId: 'radios/${entry.entityId}',
      );
    }

    final data = Map<String, dynamic>.from(payload)
      ..['id'] = entry.entityId
      ..['user_id'] = entry.userId
      ..['manual_storage_path'] = (manualName == null || manualName.isEmpty)
          ? null
          : newStoragePath
      ..remove('updated_at')
      ..remove('manual_local_path')
      ..remove('manual_pending_upload')
      ..remove('manual_previous_storage_path');

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

    if (previousStoragePath != null &&
        previousStoragePath.isNotEmpty &&
        previousStoragePath != newStoragePath) {
      try {
        await StorageService.deleteModelDocument(previousStoragePath);
      } catch (_) {
        // La radio est déjà synchronisée ; un ancien fichier orphelin ne doit
        // pas bloquer la synchronisation du nouvel état.
      }
    }

    if (manualName != null && manualName.isNotEmpty && localPath != null) {
      remoteRow['manual_local_path'] = localPath;
    }
    remoteRow['manual_pending_upload'] = false;

    await RadioLocalStore.upsertRow(userId: entry.userId, row: remoteRow);
  }

  static String _contentTypeFor(String filename) {
    final clean = filename.toLowerCase().trim();
    final dot = clean.lastIndexOf('.');
    final extension = dot == -1 ? '' : clean.substring(dot + 1);

    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        throw StateError('Format de manuel radio non pris en charge.');
    }
  }
}
