import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../models/rc_model.dart';

class ModelLocalStore {
  ModelLocalStore._();

  static final AppDatabase _database = AppDatabase.instance;

  static String _localKey({required String userId, required String modelId}) {
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

  static Future<List<RcModel>> getModels({required String userId}) async {
    final rows =
        await (_database.select(_database.localModels)
              ..where(
                (item) =>
                    item.userId.equals(userId) & item.isDeleted.equals(false),
              )
              ..orderBy([(item) => OrderingTerm.asc(item.createdAt)]))
            .get();

    return rows
        .map((row) => _modelFromJson(jsonDecode(row.payloadJson)))
        .toList(growable: false);
  }

  static Future<void> replaceModels({
    required String userId,
    required List<Map<String, dynamic>> rows,
  }) async {
    await _database.transaction(() async {
      await (_database.delete(
        _database.localModels,
      )..where((item) => item.userId.equals(userId))).go();

      for (final row in rows) {
        final modelId = row['id']?.toString();
        if (modelId == null || modelId.isEmpty) {
          continue;
        }

        await _database
            .into(_database.localModels)
            .insert(
              LocalModelsCompanion.insert(
                localKey: _localKey(userId: userId, modelId: modelId),
                userId: userId,
                modelId: modelId,
                payloadJson: jsonEncode(row),
                createdAt: Value(_parseDate(row['created_at'])),
                updatedAt: Value(_parseDate(row['updated_at'])),
              ),
              mode: InsertMode.insertOrReplace,
            );
      }
    });
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

    return RcModel(
      id: json['id'] as String?,
      name: json['name'] as String? ?? 'Modèle sans nom',
      brand: json['brand'] as String? ?? 'Marque non renseignée',
      category: json['category'] as String? ?? '',
      discipline: json['discipline'] as String? ?? '',
      motorization: json['motorization'] as String? ?? 'Électrique',
      scale: json['scale'] as String? ?? '',
      weightKg: (json['weight_kg'] as num?)?.toDouble(),
      batteryCount: (batteryCountValue as num?)?.toInt() ?? 0,
      maxCells: maxCellsValue == null
          ? 'Aucune'
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
