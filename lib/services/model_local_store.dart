import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../models/rc_model.dart';

class ModelLocalStore {
  ModelLocalStore._();

  static final AppDatabase _database = AppDatabase.instance;

  static String localKey({required String userId, required String modelId}) {
    return '$userId::$modelId';
  }

  static Future<bool> hasModelCache({required String userId}) async {
    final row =
        await (_database.select(_database.localModels)
              ..where((item) => item.userId.equals(userId))
              ..limit(1))
            .getSingleOrNull();

    return row != null;
  }

  static Stream<List<RcModel>> watchModels({required String userId}) {
    final query = _database.select(_database.localModels)
      ..where(
        (item) => item.userId.equals(userId) & item.isDeleted.equals(false),
      )
      ..orderBy([
        (item) => OrderingTerm.desc(item.updatedAt, nulls: NullsOrder.last),
        (item) => OrderingTerm.desc(item.createdAt, nulls: NullsOrder.last),
        (item) => OrderingTerm.desc(item.cachedAt),
      ]);

    return query.watch().map(
      (rows) => rows
          .map((row) => _modelFromJson(jsonDecode(row.payloadJson)))
          .toList(growable: false),
    );
  }

  static Future<List<RcModel>> getModels({required String userId}) async {
    final rows =
        await (_database.select(_database.localModels)
              ..where(
                (item) =>
                    item.userId.equals(userId) & item.isDeleted.equals(false),
              )
              ..orderBy([
                (item) =>
                    OrderingTerm.desc(item.updatedAt, nulls: NullsOrder.last),
                (item) =>
                    OrderingTerm.desc(item.createdAt, nulls: NullsOrder.last),
                (item) => OrderingTerm.desc(item.cachedAt),
              ]))
            .get();

    return rows
        .map((row) => _modelFromJson(jsonDecode(row.payloadJson)))
        .toList(growable: false);
  }

  static Future<RcModel?> getModel({
    required String userId,
    required String modelId,
  }) async {
    final row =
        await (_database.select(_database.localModels)
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

    return _modelFromJson(jsonDecode(row.payloadJson));
  }

  static Future<void> replaceModels({
    required String userId,
    required List<Map<String, dynamic>> rows,
  }) async {
    await _database.transaction(() async {
      final pendingModelIds = await _database.getPendingEntityIds(
        userId: userId,
        entityType: 'model',
      );

      await (_database.delete(_database.localModels)..where(
            (item) =>
                item.userId.equals(userId) &
                item.modelId.isNotIn(pendingModelIds.toList()),
          ))
          .go();

      for (final row in rows) {
        final modelId = row['id']?.toString();
        if (modelId == null ||
            modelId.isEmpty ||
            pendingModelIds.contains(modelId)) {
          continue;
        }

        await upsertRow(userId: userId, row: row);
      }
    });
  }

  static Future<void> upsertModel({
    required String userId,
    required RcModel model,
    bool isDeleted = false,
  }) async {
    final modelId = model.id;
    if (modelId == null || modelId.trim().isEmpty) {
      throw StateError('Le modèle doit posséder un identifiant local.');
    }

    final now = DateTime.now();
    final row = modelToRow(userId: userId, model: model, updatedAt: now);

    await _database
        .into(_database.localModels)
        .insert(
          LocalModelsCompanion.insert(
            localKey: localKey(userId: userId, modelId: modelId),
            userId: userId,
            modelId: modelId,
            payloadJson: jsonEncode(row),
            createdAt: Value(_parseDate(row['created_at']) ?? now),
            updatedAt: Value(now),
            isDeleted: Value(isDeleted),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  static Future<void> upsertRow({
    required String userId,
    required Map<String, dynamic> row,
    bool isDeleted = false,
  }) async {
    final modelId = row['id']?.toString();
    if (modelId == null || modelId.isEmpty) {
      return;
    }

    await _database
        .into(_database.localModels)
        .insert(
          LocalModelsCompanion.insert(
            localKey: localKey(userId: userId, modelId: modelId),
            userId: userId,
            modelId: modelId,
            payloadJson: jsonEncode(row),
            createdAt: Value(_parseDate(row['created_at'])),
            updatedAt: Value(_parseDate(row['updated_at'])),
            isDeleted: Value(isDeleted),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  static Future<void> markModelDeleted({
    required String userId,
    required RcModel model,
  }) {
    return upsertModel(userId: userId, model: model, isDeleted: true);
  }

  static Map<String, dynamic> modelToRow({
    required String userId,
    required RcModel model,
    DateTime? updatedAt,
  }) {
    final maxCells =
        int.tryParse(model.maxCells.replaceAll('S', '').trim()) ?? 0;
    final now = updatedAt ?? DateTime.now();

    return <String, dynamic>{
      'id': model.id,
      'user_id': userId,
      'name': model.name,
      'brand': model.brand,
      'category': model.category,
      'discipline': model.discipline,
      'motorization': model.motorization,
      'scale': model.scale,
      'weight_kg': model.weightKg,
      'acquisition_date': model.acquisitionDate
          ?.toIso8601String()
          .split('T')
          .first,
      'purchase_type': model.purchaseType,
      'purchase_location': model.purchaseLocation,
      'battery_count': model.batteryCount,
      'max_cells': maxCells,
      'photo_url': model.photoUrl,
      'radio_id': model.radioId,
      'updated_at': now.toUtc().toIso8601String(),
    };
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) {
      return null;
    }
    return DateTime.tryParse(value.toString());
  }

  static RcModel _modelFromJson(dynamic raw) {
    final json = Map<String, dynamic>.from(raw as Map);
    final maxCellsValue = json['max_cells'];
    final batteryCountValue = json['battery_count'];
    final motorization = json['motorization'] as String? ?? 'Électrique';

    return RcModel(
      id: json['id'] as String?,
      name: json['name'] as String? ?? 'Modèle sans nom',
      brand: json['brand'] as String? ?? 'Marque non renseignée',
      category: json['category'] as String? ?? '',
      discipline: json['discipline'] as String? ?? '',
      motorization: motorization,
      scale: json['scale'] as String? ?? '',
      weightKg: (json['weight_kg'] as num?)?.toDouble(),
      batteryCount: (batteryCountValue as num?)?.toInt() ?? 0,
      maxCells: motorization != 'Électrique'
          ? 'Aucune'
          : maxCellsValue == null
          ? '0S'
          : '${(maxCellsValue as num).toInt()}S',
      photoUrl: json['photo_url'] as String?,
      acquisitionDate: json['acquisition_date'] == null
          ? null
          : DateTime.tryParse(json['acquisition_date'].toString()),
      purchaseType: json['purchase_type'] as String?,
      purchaseLocation: json['purchase_location'] as String?,
      radioId: json['radio_id'] as String?,
    );
  }
}
