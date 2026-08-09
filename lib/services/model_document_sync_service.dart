import 'dart:convert';

import '../database/app_database.dart';
import '../models/model_document.dart';
import 'model_document_file_store.dart';
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

    final document = ModelDocument.fromMap(payload);

    if (entry.operation == 'delete') {
      var storagePath = document.storagePath.trim();

      // Sécurité supplémentaire : si le payload de suppression provient d'un
      // objet UI ancien et ne contient pas encore le storagePath final, on le
      // récupère depuis la métadonnée distante avant de la supprimer.
      if (storagePath.isEmpty) {
        final remote = await _client
            .from('model_documents')
            .select('storage_path')
            .eq('user_id', entry.userId)
            .eq('id', entry.entityId)
            .maybeSingle();

        storagePath = remote?['storage_path']?.toString().trim() ?? '';
      }

      await _client
          .from('model_documents')
          .delete()
          .eq('user_id', entry.userId)
          .eq('id', entry.entityId);

      if (storagePath.isNotEmpty) {
        try {
          await StorageService.deleteModelDocument(storagePath);
        } catch (_) {
          // La suppression de la métadonnée reste prioritaire. Une erreur
          // distante sera traitée séparément sans restaurer le document local.
        }
      }
      return;
    }

    var syncedDocument = document;

    final needsUpload =
        document.pendingUpload ||
        document.storagePath.trim().isEmpty ||
        !_hasSupportedExtension(document.storagePath);

    if (needsUpload) {
      if (!await ModelDocumentFileStore.exists(document.localPath)) {
        throw StateError('Le fichier local à synchroniser est introuvable.');
      }

      final bytes = await ModelDocumentFileStore.readBytes(document.localPath!);
      final extension = await _documentExtension(
        bytes: bytes,
        localPath: document.localPath,
        storagePath: document.storagePath,
        documentName: document.documentName,
      );
      final uploadFilename = _filenameWithExtension(
        document.documentName,
        extension,
      );
      final previousStoragePath = document.storagePath.trim();

      final storagePath = await StorageService.uploadModelDocumentBytes(
        bytes: bytes,
        originalFilename: uploadFilename,
        contentType: _contentTypeFromExtension(extension),
        modelId: document.modelId,
        driveObjectKey: 'model_document:${document.id}',
      );

      syncedDocument = document.copyWith(
        storagePath: storagePath,
        pendingUpload: false,
      );

      if (previousStoragePath.isNotEmpty &&
          previousStoragePath != storagePath) {
        try {
          await StorageService.deleteModelDocument(previousStoragePath);
        } catch (_) {
          // Le nouveau fichier et ses métadonnées restent prioritaires.
        }
      }
    }

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
          .insert(syncedDocument.toRemoteMap())
          .select()
          .single();
      remoteRow = Map<String, dynamic>.from(result);
    } else {
      final result = await _client
          .from('model_documents')
          .update({
            'document_name': syncedDocument.documentName,
            'document_type': syncedDocument.documentType,
            'storage_path': syncedDocument.storagePath,
          })
          .eq('user_id', entry.userId)
          .eq('id', entry.entityId)
          .select()
          .single();
      remoteRow = Map<String, dynamic>.from(result);
    }

    final remoteDocument = ModelDocument.fromMap(
      remoteRow,
    ).copyWith(localPath: syncedDocument.localPath, pendingUpload: false);

    await ModelDocumentLocalStore.upsertDocument(
      userId: entry.userId,
      document: remoteDocument,
    );
  }

  static bool _hasSupportedExtension(String value) {
    return _isSupportedExtension(_extensionFromValue(value));
  }

  static Future<String> _documentExtension({
    required List<int> bytes,
    required String? localPath,
    required String storagePath,
    required String documentName,
  }) async {
    for (final value in <String>[localPath ?? '', storagePath, documentName]) {
      final extension = _extensionFromValue(value);
      if (_isSupportedExtension(extension)) {
        return extension == 'jpeg' ? 'jpg' : extension;
      }
    }

    final signatureExtension = _extensionFromSignature(bytes);
    if (signatureExtension != null) {
      return signatureExtension;
    }

    throw StateError('Impossible de déterminer le format du document.');
  }

  static bool _isSupportedExtension(String extension) {
    return extension == 'pdf' ||
        extension == 'jpg' ||
        extension == 'jpeg' ||
        extension == 'png' ||
        extension == 'webp';
  }

  static String? _extensionFromSignature(List<int> bytes) {
    if (bytes.length >= 4 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46) {
      return 'pdf';
    }

    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'jpg';
    }

    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'png';
    }

    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'webp';
    }

    return null;
  }

  static String _extensionFromValue(String value) {
    final clean = value.toLowerCase().split('?').first.trim();
    final dotIndex = clean.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == clean.length - 1) {
      return '';
    }
    return clean.substring(dotIndex + 1);
  }

  static String _filenameWithExtension(String documentName, String extension) {
    final cleanName = documentName.trim().isEmpty
        ? 'document'
        : documentName.trim();

    if (_hasSupportedExtension(cleanName)) {
      return cleanName;
    }

    return '$cleanName.$extension';
  }

  static String _contentTypeFromExtension(String extension) {
    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'jpeg':
      case 'jpg':
      default:
        return 'image/jpeg';
    }
  }
}
