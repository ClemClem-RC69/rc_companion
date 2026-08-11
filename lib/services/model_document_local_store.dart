import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../models/model_document.dart';
import 'model_document_file_store.dart';

class ModelDocumentLocalStore {
  ModelDocumentLocalStore._();

  static final AppDatabase _database = AppDatabase.instance;

  static String localKey({required String userId, required String documentId}) {
    return '$userId::$documentId';
  }

  static Future<bool> hasCache({
    required String userId,
    required String modelId,
  }) async {
    final row =
        await (_database.select(_database.localModelDocuments)
              ..where(
                (item) =>
                    item.userId.equals(userId) & item.modelId.equals(modelId),
              )
              ..limit(1))
            .getSingleOrNull();

    return row != null;
  }

  static Future<List<ModelDocument>> getDocuments({
    required String userId,
    required String modelId,
  }) async {
    final rows =
        await (_database.select(_database.localModelDocuments)
              ..where(
                (item) =>
                    item.userId.equals(userId) &
                    item.modelId.equals(modelId) &
                    item.isDeleted.equals(false),
              )
              ..orderBy([(item) => OrderingTerm.asc(item.createdAt)]))
            .get();

    return rows
        .map(
          (row) => ModelDocument.fromMap(
            Map<String, dynamic>.from(jsonDecode(row.payloadJson) as Map),
          ),
        )
        .toList(growable: false);
  }

  static Future<ModelDocument?> getDocument({
    required String userId,
    required String documentId,
  }) async {
    final row =
        await (_database.select(_database.localModelDocuments)
              ..where(
                (item) =>
                    item.userId.equals(userId) &
                    item.documentId.equals(documentId),
              )
              ..limit(1))
            .getSingleOrNull();

    if (row == null) {
      return null;
    }

    return ModelDocument.fromMap(
      Map<String, dynamic>.from(jsonDecode(row.payloadJson) as Map),
    );
  }

  static Stream<List<ModelDocument>> watchDocuments({
    required String userId,
    required String modelId,
  }) {
    final query = _database.select(_database.localModelDocuments)
      ..where(
        (item) =>
            item.userId.equals(userId) &
            item.modelId.equals(modelId) &
            item.isDeleted.equals(false),
      )
      ..orderBy([(item) => OrderingTerm.asc(item.createdAt)]);

    return query.watch().map(
      (rows) => rows
          .map(
            (row) => ModelDocument.fromMap(
              Map<String, dynamic>.from(jsonDecode(row.payloadJson) as Map),
            ),
          )
          .toList(growable: false),
    );
  }

  static Future<void> replaceDocuments({
    required String userId,
    required String modelId,
    required List<Map<String, dynamic>> rows,
  }) async {
    final obsoleteLocalPaths = <String>{};

    await _database.transaction(() async {
      final existingRows =
          await (_database.select(_database.localModelDocuments)..where(
                (item) =>
                    item.userId.equals(userId) & item.modelId.equals(modelId),
              ))
              .get();

      final existingById = <String, ModelDocument>{
        for (final existingRow in existingRows)
          existingRow.documentId: ModelDocument.fromMap(
            Map<String, dynamic>.from(
              jsonDecode(existingRow.payloadJson) as Map,
            ),
          ),
      };

      final pendingDeleteRows =
          await (_database.select(_database.syncQueueEntries)..where(
                (item) =>
                    item.userId.equals(userId) &
                    item.entityType.equals('model_document') &
                    item.operation.equals('delete'),
              ))
              .get();

      final pendingDeleteIds = pendingDeleteRows
          .map((item) => item.entityId)
          .toSet();

      final pendingIds = await _database.getPendingEntityIds(
        userId: userId,
        entityType: 'model_document',
      );

      final incomingById = <String, ModelDocument>{};
      for (final row in rows) {
        final remoteDocument = ModelDocument.fromMap(row);
        if (remoteDocument.id.isNotEmpty) {
          incomingById[remoteDocument.id] = remoteDocument;
        }
      }

      for (final entry in existingById.entries) {
        final documentId = entry.key;
        final existing = entry.value;

        if (pendingIds.contains(documentId) ||
            pendingDeleteIds.contains(documentId)) {
          continue;
        }

        final oldLocalPath = existing.localPath?.trim() ?? '';
        if (oldLocalPath.isEmpty) {
          continue;
        }

        final incoming = incomingById[documentId];
        if (incoming == null) {
          obsoleteLocalPaths.add(oldLocalPath);
          continue;
        }

        final oldStoragePath = existing.storagePath.trim();
        final newStoragePath = incoming.storagePath.trim();

        if (oldStoragePath.isNotEmpty &&
            newStoragePath.isNotEmpty &&
            oldStoragePath != newStoragePath) {
          obsoleteLocalPaths.add(oldLocalPath);
        }
      }

      await (_database.delete(_database.localModelDocuments)..where(
            (item) =>
                item.userId.equals(userId) &
                item.modelId.equals(modelId) &
                item.documentId.isNotIn(pendingIds.toList()),
          ))
          .go();

      for (final row in rows) {
        final remoteDocument = ModelDocument.fromMap(row);

        if (remoteDocument.id.isEmpty ||
            pendingDeleteIds.contains(remoteDocument.id) ||
            pendingIds.contains(remoteDocument.id)) {
          continue;
        }

        final existing = existingById[remoteDocument.id];
        final sameRemoteFile =
            existing != null &&
            existing.storagePath.trim().isNotEmpty &&
            existing.storagePath.trim() == remoteDocument.storagePath.trim();

        final merged = remoteDocument.copyWith(
          localPath: sameRemoteFile ? existing.localPath : null,
          pendingUpload: false,
        );

        await upsertDocument(userId: userId, document: merged);
      }
    });

    for (final path in obsoleteLocalPaths) {
      try {
        await ModelDocumentFileStore.delete(path);
      } catch (_) {
        // Un support local absent, retiré ou momentanément inaccessible ne
        // doit jamais faire échouer la synchronisation ni provoquer une
        // action distante.
      }
    }
  }

  static Future<void> upsertDocument({
    required String userId,
    required ModelDocument document,
    bool isDeleted = false,
  }) async {
    await _database
        .into(_database.localModelDocuments)
        .insert(
          LocalModelDocumentsCompanion.insert(
            localKey: localKey(userId: userId, documentId: document.id),
            userId: userId,
            modelId: document.modelId,
            documentId: document.id,
            payloadJson: jsonEncode(document.toMap()),
            createdAt: Value(document.createdAt),
            updatedAt: Value(DateTime.now()),
            isDeleted: Value(isDeleted),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  static Future<void> markDeleted({
    required String userId,
    required ModelDocument document,
  }) {
    return upsertDocument(userId: userId, document: document, isDeleted: true);
  }
}
