import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../models/model_radio_setup.dart';

class ModelRadioSetupLocalStore {
  ModelRadioSetupLocalStore._();

  static final AppDatabase _database = AppDatabase.instance;

  static String localKey({required String userId, required String modelId}) {
    return '$userId::$modelId';
  }

  static Future<ModelRadioSetup?> getSetup({
    required String userId,
    required String modelId,
  }) async {
    final row =
        await (_database.select(_database.localModelRadioSetups)
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

    return ModelRadioSetup.fromMap(
      Map<String, dynamic>.from(jsonDecode(row.payloadJson) as Map),
    );
  }

  static Stream<ModelRadioSetup?> watchSetup({
    required String userId,
    required String modelId,
  }) {
    final query = _database.select(_database.localModelRadioSetups)
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

      return ModelRadioSetup.fromMap(
        Map<String, dynamic>.from(jsonDecode(row.payloadJson) as Map),
      );
    });
  }

  static Future<bool> hasCachedSetup({
    required String userId,
    required String modelId,
  }) async {
    final row =
        await (_database.select(_database.localModelRadioSetups)
              ..where(
                (item) =>
                    item.userId.equals(userId) & item.modelId.equals(modelId),
              )
              ..limit(1))
            .getSingleOrNull();

    return row != null;
  }

  static Future<void> upsertSetup({
    required String userId,
    required ModelRadioSetup setup,
    bool isDeleted = false,
  }) async {
    await upsertRow(
      userId: userId,
      row: setupToRow(userId: userId, setup: setup),
      isDeleted: isDeleted,
    );
  }

  static Future<void> upsertRow({
    required String userId,
    required Map<String, dynamic> row,
    bool isDeleted = false,
  }) async {
    final modelId = row['model_id']?.toString();
    final radioId = row['radio_id']?.toString();

    if (modelId == null || modelId.trim().isEmpty) {
      throw StateError('Le réglage radio doit posséder un model_id.');
    }

    if (!isDeleted && (radioId == null || radioId.trim().isEmpty)) {
      throw StateError('Le réglage radio doit posséder un radio_id.');
    }

    final updatedAt =
        DateTime.tryParse(row['updated_at']?.toString() ?? '') ??
        DateTime.now();

    await _database
        .into(_database.localModelRadioSetups)
        .insert(
          LocalModelRadioSetupsCompanion.insert(
            localKey: localKey(userId: userId, modelId: modelId),
            userId: userId,
            modelId: modelId,
            radioId: radioId ?? '',
            payloadJson: jsonEncode(row),
            updatedAt: Value(updatedAt),
            isDeleted: Value(isDeleted),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  static Future<void> markDeleted({
    required String userId,
    required String modelId,
    ModelRadioSetup? existingSetup,
  }) async {
    final row = existingSetup == null
        ? <String, dynamic>{
            'user_id': userId,
            'model_id': modelId,
            'radio_id': '',
            'enabled_fields': <String>[],
            'values': <String, String>{},
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }
        : setupToRow(userId: userId, setup: existingSetup);

    await upsertRow(userId: userId, row: row, isDeleted: true);
  }

  static Future<void> replaceRemoteSetup({
    required String userId,
    required String modelId,
    Map<String, dynamic>? remoteRow,
  }) async {
    final pendingIds = await _database.getPendingEntityIds(
      userId: userId,
      entityType: 'model_radio_setup',
    );

    if (pendingIds.contains(modelId)) {
      return;
    }

    if (remoteRow == null) {
      await (_database.delete(_database.localModelRadioSetups)..where(
            (item) => item.userId.equals(userId) & item.modelId.equals(modelId),
          ))
          .go();
      return;
    }

    await upsertRow(userId: userId, row: remoteRow);
  }

  static Map<String, dynamic> setupToRow({
    required String userId,
    required ModelRadioSetup setup,
  }) {
    return <String, dynamic>{
      'user_id': userId,
      'model_id': setup.modelId,
      'radio_id': setup.radioId,
      'enabled_fields': List<String>.from(setup.enabledFields),
      'values': Map<String, String>.from(setup.values),
      'updated_at': (setup.updatedAt ?? DateTime.now())
          .toUtc()
          .toIso8601String(),
    };
  }
}
