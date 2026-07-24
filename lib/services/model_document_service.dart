import 'dart:async';
import 'dart:convert';

import '../database/app_database.dart';
import '../models/model_document.dart';
import 'battery_sync_service.dart';
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

    return _refreshDocumentsFromCloud(userId: user.id, modelId: modelId);
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

  static Future<ModelDocument> addDocument({
    required String modelId,
    required String documentType,
  }) async {
    final picked = await StorageService.pickModelDocument();
    if (picked == null) {
      throw Exception('Aucun document sélectionné.');
    }

    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Aucun utilisateur connecté.');
    }

    // V1A : le fichier doit encore être envoyé immédiatement au Storage.
    // L’ajout complet hors ligne sera traité dans Documents Offline V1B.
    final storagePath = await StorageService.uploadModelDocument(
      document: picked,
      modelId: modelId,
    );

    try {
      final response = await _client
          .from('model_documents')
          .insert({
            'user_id': user.id,
            'model_id': modelId,
            'document_name': picked.name,
            'document_type': documentType,
            'storage_path': storagePath,
          })
          .select()
          .single();

      final document = ModelDocument.fromMap(
        Map<String, dynamic>.from(response),
      );

      await ModelDocumentLocalStore.upsertDocument(
        userId: user.id,
        document: document,
      );

      return document;
    } catch (error) {
      try {
        await StorageService.deleteModelDocument(storagePath);
      } catch (_) {}
      rethrow;
    }
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

    await ModelDocumentLocalStore.markDeleted(
      userId: user.id,
      document: document,
    );
    await _database.replacePendingSyncOperation(
      userId: user.id,
      entityType: 'model_document',
      entityId: document.id,
      operation: 'delete',
      payloadJson: jsonEncode(document.toMap()),
    );

    unawaited(BatterySyncService.syncNow());
  }

  static Future<String> openDocument(ModelDocument document) {
    return StorageService.createModelDocumentSignedUrl(document.storagePath);
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

    return rows.map(ModelDocument.fromMap).toList(growable: false);
  }
}
