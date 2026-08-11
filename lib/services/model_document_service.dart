import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../database/app_database.dart';
import '../models/model_document.dart';
import 'battery_sync_service.dart';
import 'model_document_file_store.dart';
import 'model_document_local_store.dart';
import 'storage_service.dart';
import 'supabase_service.dart';

class ModelDocumentService {
  ModelDocumentService._();

  static final _client = SupabaseService.client;
  static final _database = AppDatabase.instance;

  static Future<List<ModelDocument>> getDocuments(String modelId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Aucun utilisateur connecté.');
    }

    final cached = await ModelDocumentLocalStore.getDocuments(
      userId: user.id,
      modelId: modelId,
    );
    final hasCache = await ModelDocumentLocalStore.hasCache(
      userId: user.id,
      modelId: modelId,
    );

    if (hasCache) {
      unawaited(_refreshDocumentsSilently(userId: user.id, modelId: modelId));
      return cached;
    }

    try {
      return await _refreshDocumentsFromCloud(
        userId: user.id,
        modelId: modelId,
      );
    } catch (_) {
      return cached;
    }
  }

  static Stream<List<ModelDocument>> watchDocuments(String modelId) {
    final user = _client.auth.currentUser;
    if (user == null) {
      return const Stream.empty();
    }

    return ModelDocumentLocalStore.watchDocuments(
      userId: user.id,
      modelId: modelId,
    );
  }

  static Future<List<ModelDocument>> refreshDocuments(String modelId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Aucun utilisateur connecté.');
    }

    return _refreshDocumentsFromCloud(userId: user.id, modelId: modelId);
  }

  static Future<PickedModelDocument?> pickDocument() {
    return StorageService.pickModelDocument();
  }

  static Future<ModelDocument> addDocument({
    required String modelId,
    required String documentType,
    required PickedModelDocument picked,
    required String documentName,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Aucun utilisateur connecté.');
    }

    final cleanName = documentName.trim();
    if (cleanName.isEmpty) {
      throw Exception('Le nom du document ne peut pas être vide.');
    }

    final documentId = _newUuid();
    final sourcePath = picked.path?.trim();

    late final String localPath;
    if (sourcePath != null && sourcePath.isNotEmpty) {
      localPath = await ModelDocumentFileStore.saveFile(
        userId: user.id,
        modelId: modelId,
        documentId: documentId,
        originalFilename: picked.name,
        sourcePath: sourcePath,
      );
    } else {
      final bytes = picked.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Impossible de lire le document sélectionné.');
      }

      localPath = await ModelDocumentFileStore.saveBytes(
        userId: user.id,
        modelId: modelId,
        documentId: documentId,
        originalFilename: picked.name,
        bytes: bytes,
      );
    }

    final document = ModelDocument(
      id: documentId,
      userId: user.id,
      modelId: modelId,
      documentName: cleanName,
      documentType: documentType,
      storagePath: '',
      createdAt: DateTime.now(),
      localPath: localPath,
      pendingUpload: true,
    );

    await ModelDocumentLocalStore.upsertDocument(
      userId: user.id,
      document: document,
    );
    await _database.replacePendingSyncOperation(
      userId: user.id,
      entityType: 'model_document',
      entityId: document.id,
      operation: 'upsert',
      payloadJson: jsonEncode(document.toMap()),
    );

    unawaited(BatterySyncService.syncNow());
    return document;
  }

  static Future<ModelDocument> renameDocument({
    required ModelDocument document,
    required String newName,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Aucun utilisateur connecté.');
    }

    final cleanName = newName.trim();
    if (cleanName.isEmpty) {
      throw Exception('Le nom du document ne peut pas être vide.');
    }

    final updated = document.copyWith(documentName: cleanName);

    await ModelDocumentLocalStore.upsertDocument(
      userId: user.id,
      document: updated,
    );
    await _database.replacePendingSyncOperation(
      userId: user.id,
      entityType: 'model_document',
      entityId: document.id,
      operation: 'upsert',
      payloadJson: jsonEncode(updated.toMap()),
    );

    unawaited(BatterySyncService.syncNow());
    return updated;
  }

  static Future<void> deleteDocument(ModelDocument document) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Aucun utilisateur connecté.');
    }

    // L'objet détenu par l'interface peut être antérieur à la dernière
    // synchronisation. On relit donc Drift afin de conserver notamment le
    // storagePath Google Drive reçu après l'upload.
    final latestDocument = await ModelDocumentLocalStore.getDocument(
      userId: user.id,
      documentId: document.id,
    );
    final documentToDelete = latestDocument ?? document;

    await ModelDocumentLocalStore.markDeleted(
      userId: user.id,
      document: documentToDelete,
    );
    await _database.replacePendingSyncOperation(
      userId: user.id,
      entityType: 'model_document',
      entityId: documentToDelete.id,
      operation: 'delete',
      payloadJson: jsonEncode(documentToDelete.toMap()),
    );

    await ModelDocumentFileStore.delete(documentToDelete.localPath);
    unawaited(BatterySyncService.syncNow());
  }

  static Future<String> openDocument(ModelDocument document) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Aucun utilisateur connecté.');
    }

    if (await ModelDocumentFileStore.exists(document.localPath)) {
      return document.localPath!;
    }

    if (document.storagePath.trim().isEmpty) {
      throw StateError(
        'Le fichier local est introuvable et le document n’est pas encore '
        'synchronisé.',
      );
    }

    final bytes = await StorageService.downloadModelDocumentBytes(
      document.storagePath,
    );
    final localPath = await ModelDocumentFileStore.saveBytes(
      userId: user.id,
      modelId: document.modelId,
      documentId: document.id,
      originalFilename: document.documentName,
      bytes: bytes,
    );

    final cached = document.copyWith(
      localPath: localPath,
      pendingUpload: false,
    );
    await ModelDocumentLocalStore.upsertDocument(
      userId: user.id,
      document: cached,
    );

    return localPath;
  }

  static Future<void> _refreshDocumentsSilently({
    required String userId,
    required String modelId,
  }) async {
    try {
      await _refreshDocumentsFromCloud(userId: userId, modelId: modelId);
    } catch (_) {
      // Le cache local reste disponible hors ligne.
    }
  }

  static Future<List<ModelDocument>> _refreshDocumentsFromCloud({
    required String userId,
    required String modelId,
  }) async {
    final response = await _client
        .from('model_documents')
        .select()
        .eq('user_id', userId)
        .eq('model_id', modelId)
        .order('created_at')
        .timeout(const Duration(seconds: 8));

    final rows = response
        .map<Map<String, dynamic>>(
          (item) => Map<String, dynamic>.from(item as Map),
        )
        .toList(growable: false);

    await ModelDocumentLocalStore.replaceDocuments(
      userId: userId,
      modelId: modelId,
      rows: rows,
    );

    // Précharge automatiquement les fichiers distants afin qu'ils soient
    // disponibles hors ligne sur cet appareil sans ouverture préalable.
    final documents = await ModelDocumentLocalStore.getDocuments(
      userId: userId,
      modelId: modelId,
    );

    for (final document in documents) {
      if (!_isGoogleDrivePath(document.storagePath)) {
        // Les anciens chemins Supabase restent ouvrables manuellement via
        // openDocument(), mais ne sont jamais préchargés automatiquement.
        continue;
      }

      if (await ModelDocumentFileStore.exists(document.localPath)) {
        continue;
      }

      try {
        final bytes = await StorageService.downloadModelDocumentBytes(
          document.storagePath,
        );

        if (bytes.isEmpty) {
          continue;
        }

        final localPath = await ModelDocumentFileStore.saveBytes(
          userId: userId,
          modelId: document.modelId,
          documentId: document.id,
          originalFilename: document.documentName,
          bytes: bytes,
        );

        final cached = document.copyWith(
          localPath: localPath,
          pendingUpload: false,
        );

        await ModelDocumentLocalStore.upsertDocument(
          userId: userId,
          document: cached,
        );
      } catch (_) {
        // Un échec de téléchargement ne doit jamais empêcher la
        // synchronisation des métadonnées ni supprimer un cache existant.
      }
    }

    return ModelDocumentLocalStore.getDocuments(
      userId: userId,
      modelId: modelId,
    );
  }

  static bool _isGoogleDrivePath(String path) {
    return path.trim().startsWith('gdrive:');
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
