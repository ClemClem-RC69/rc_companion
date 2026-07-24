import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../models/model_setup.dart';

class ModelSetupLocalStore {
  ModelSetupLocalStore._();

  static final AppDatabase _database = AppDatabase.instance;

  static String localKey({required String userId, required String modelId}) {
    return '$userId::$modelId';
  }

  static Future<bool> hasSetupCache({
    required String userId,
    required String modelId,
  }) async {
    final row =
        await (_database.select(_database.localModelSetups)
              ..where(
                (item) =>
                    item.userId.equals(userId) &
                    item.modelId.equals(modelId) &
                    item.isDeleted.equals(false),
              )
              ..limit(1))
            .getSingleOrNull();

    return row != null;
  }

  static Future<ModelSetup?> getSetup({
    required String userId,
    required String modelId,
  }) async {
    final row =
        await (_database.select(_database.localModelSetups)
              ..where(
                (item) =>
                    item.userId.equals(userId) &
                    item.modelId.equals(modelId) &
                    item.isDeleted.equals(false),
              )
              ..limit(1))
            .getSingleOrNull();

    if (row == null) {
      return null;
    }

    final data = Map<String, dynamic>.from(jsonDecode(row.payloadJson) as Map);
    return ModelSetup.fromMap(data);
  }

  static Stream<ModelSetup?> watchSetup({
    required String userId,
    required String modelId,
  }) {
    final query = _database.select(_database.localModelSetups)
      ..where(
        (item) =>
            item.userId.equals(userId) &
            item.modelId.equals(modelId) &
            item.isDeleted.equals(false),
      )
      ..limit(1);

    return query.watchSingleOrNull().map((row) {
      if (row == null) {
        return null;
      }

      final data = Map<String, dynamic>.from(
        jsonDecode(row.payloadJson) as Map,
      );
      return ModelSetup.fromMap(data);
    });
  }

  static Future<void> upsertSetup({
    required String userId,
    required ModelSetup setup,
    bool isDeleted = false,
  }) async {
    final payload = setup.toDatabaseMap(userId: userId);

    await _database
        .into(_database.localModelSetups)
        .insert(
          LocalModelSetupsCompanion.insert(
            localKey: localKey(userId: userId, modelId: setup.modelId),
            userId: userId,
            modelId: setup.modelId,
            payloadJson: jsonEncode(payload),
            updatedAt: Value(DateTime.now()),
            isDeleted: Value(isDeleted),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  static Future<void> replaceSetupFromCloud({
    required String userId,
    required Map<String, dynamic>? row,
    required String modelId,
  }) async {
    final pending = await _database.getPendingEntityIds(
      userId: userId,
      entityType: 'model_setup',
    );

    if (pending.contains(modelId)) {
      return;
    }

    if (row == null) {
      await (_database.delete(_database.localModelSetups)..where(
            (item) => item.userId.equals(userId) & item.modelId.equals(modelId),
          ))
          .go();
      return;
    }

    final setup = ModelSetup.fromMap(row);
    await upsertSetup(userId: userId, setup: setup);
  }
}
