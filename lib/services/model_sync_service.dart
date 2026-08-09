import 'dart:convert';

import '../database/app_database.dart';
import 'model_local_store.dart';
import 'model_photo_file_store.dart';
import 'google_drive_service.dart';
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
    final localPath = payload['photo_local_path']?.toString();
    final pendingUpload = payload['photo_pending_upload'] == true;
    final previousPhotoUrl = payload['_previous_photo_url']?.toString();
    String? finalPhotoUrl = payload['photo_url']?.toString();

    if (pendingUpload) {
      if (localPath != null && localPath.trim().isNotEmpty) {
        final bytes = await ModelPhotoFileStore.readBytes(localPath);
        if (bytes == null || bytes.isEmpty) {
          throw StateError('La photo locale du modèle est introuvable.');
        }

        finalPhotoUrl = await StorageService.uploadModelPhotoBytes(
          bytes: bytes,
          originalFilename: localPath,
          modelId: entry.entityId,
        );
      } else {
        finalPhotoUrl = null;
      }

      if (previousPhotoUrl != null &&
          previousPhotoUrl.trim().isNotEmpty &&
          previousPhotoUrl != finalPhotoUrl) {
        try {
          await StorageService.deleteModelPhoto(previousPhotoUrl);
        } catch (_) {
          // La nouvelle version du modèle reste prioritaire.
        }
      }
    }

    final data = Map<String, dynamic>.from(payload)
      ..remove('photo_local_path')
      ..remove('photo_pending_upload')
      ..remove('_previous_photo_url')
      ..['id'] = entry.entityId
      ..['user_id'] = entry.userId
      ..['photo_url'] = finalPhotoUrl
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

    remoteRow['photo_local_path'] = localPath;
    remoteRow['photo_pending_upload'] = false;
    await ModelLocalStore.upsertRow(userId: entry.userId, row: remoteRow);

    try {
      await GoogleDriveService.ensureModelFolder(
        modelId: entry.entityId,
        brand: _firstText(remoteRow, const ['brand', 'marque']),
        name: _firstText(remoteRow, const ['name', 'nom']),
      );
    } catch (_) {
      // La synchronisation des données du modèle reste prioritaire.
      // Le dossier Drive sera remis à jour lors d'une prochaine synchronisation.
    }
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

    await ModelPhotoFileStore.deletePhoto(
      payload['photo_local_path']?.toString(),
    );

    try {
      await GoogleDriveService.deleteModelFolder(entry.entityId);
    } catch (_) {
      // La suppression du modèle reste prioritaire.
    }
  }

  static String _firstText(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return '';
  }
}
