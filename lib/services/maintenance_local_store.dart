import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';

class MaintenanceLocalStore {
  MaintenanceLocalStore._();

  static final AppDatabase _database = AppDatabase.instance;

  static String localKey({
    required String userId,
    required String maintenanceId,
  }) {
    return '$userId::$maintenanceId';
  }

  static Future<bool> hasCache({required String userId}) async {
    final row =
        await (_database.select(_database.localMaintenanceRecords)
              ..where((item) => item.userId.equals(userId))
              ..limit(1))
            .getSingleOrNull();

    return row != null;
  }

  static Stream<List<Map<String, dynamic>>> watchRecords({
    required String userId,
  }) {
    final query = _database.select(_database.localMaintenanceRecords)
      ..where(
        (item) => item.userId.equals(userId) & item.isDeleted.equals(false),
      )
      ..orderBy([
        (item) => OrderingTerm.desc(item.maintenanceDate),
        (item) => OrderingTerm.desc(item.updatedAt, nulls: NullsOrder.last),
        (item) => OrderingTerm.desc(item.cachedAt),
      ]);

    return query.watch().map(
      (rows) => rows
          .map(
            (row) =>
                Map<String, dynamic>.from(jsonDecode(row.payloadJson) as Map),
          )
          .toList(growable: false),
    );
  }

  static Future<List<Map<String, dynamic>>> getRecords({
    required String userId,
  }) async {
    final rows =
        await (_database.select(_database.localMaintenanceRecords)
              ..where(
                (item) =>
                    item.userId.equals(userId) & item.isDeleted.equals(false),
              )
              ..orderBy([
                (item) => OrderingTerm.desc(item.maintenanceDate),
                (item) =>
                    OrderingTerm.desc(item.updatedAt, nulls: NullsOrder.last),
                (item) => OrderingTerm.desc(item.cachedAt),
              ]))
            .get();

    return rows
        .map(
          (row) =>
              Map<String, dynamic>.from(jsonDecode(row.payloadJson) as Map),
        )
        .toList(growable: false);
  }

  static Future<Map<String, dynamic>?> getRecord({
    required String userId,
    required String maintenanceId,
  }) async {
    final row =
        await (_database.select(_database.localMaintenanceRecords)
              ..where(
                (item) =>
                    item.userId.equals(userId) &
                    item.maintenanceId.equals(maintenanceId) &
                    item.isDeleted.equals(false),
              )
              ..limit(1))
            .getSingleOrNull();

    if (row == null) {
      return null;
    }

    return Map<String, dynamic>.from(jsonDecode(row.payloadJson) as Map);
  }

  static Future<void> replaceRecords({
    required String userId,
    required List<Map<String, dynamic>> rows,
  }) async {
    await _database.transaction(() async {
      final pendingIds = await _database.getPendingEntityIds(
        userId: userId,
        entityType: 'maintenance',
      );

      await (_database.delete(_database.localMaintenanceRecords)..where(
            (item) =>
                item.userId.equals(userId) &
                item.maintenanceId.isNotIn(pendingIds.toList()),
          ))
          .go();

      for (final row in rows) {
        final maintenanceId = row['id']?.toString();

        if (maintenanceId == null ||
            maintenanceId.trim().isEmpty ||
            pendingIds.contains(maintenanceId)) {
          continue;
        }

        await upsertRow(userId: userId, row: row);
      }
    });
  }

  static Future<void> upsertRow({
    required String userId,
    required Map<String, dynamic> row,
    bool isDeleted = false,
  }) async {
    final maintenanceId = row['id']?.toString();
    final modelId = row['model_id']?.toString();
    final recordType = row['record_type']?.toString();
    final maintenanceDate = _parseDate(row['maintenance_date']);

    if (maintenanceId == null || maintenanceId.trim().isEmpty) {
      throw StateError('La maintenance doit posséder un identifiant.');
    }

    if (modelId == null || modelId.trim().isEmpty) {
      throw StateError('La maintenance doit être liée à un modèle.');
    }

    if (recordType == null || recordType.trim().isEmpty) {
      throw StateError('Le type de maintenance est obligatoire.');
    }

    if (maintenanceDate == null) {
      throw StateError('La date de maintenance est invalide.');
    }

    final normalizedRow = Map<String, dynamic>.from(row)
      ..['id'] = maintenanceId
      ..['user_id'] = userId
      ..['model_id'] = modelId
      ..['record_type'] = recordType
      ..['maintenance_date'] = maintenanceDate.toUtc().toIso8601String();

    await _database
        .into(_database.localMaintenanceRecords)
        .insert(
          LocalMaintenanceRecordsCompanion.insert(
            localKey: localKey(userId: userId, maintenanceId: maintenanceId),
            userId: userId,
            maintenanceId: maintenanceId,
            modelId: modelId,
            recordType: recordType,
            maintenanceDate: maintenanceDate,
            payloadJson: jsonEncode(normalizedRow),
            createdAt: Value(_parseDate(row['created_at'])),
            updatedAt: Value(_parseDate(row['updated_at'])),
            isDeleted: Value(isDeleted),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  static Future<void> markDeleted({
    required String userId,
    required String maintenanceId,
  }) async {
    final existing =
        await (_database.select(_database.localMaintenanceRecords)
              ..where(
                (item) =>
                    item.userId.equals(userId) &
                    item.maintenanceId.equals(maintenanceId),
              )
              ..limit(1))
            .getSingleOrNull();

    if (existing == null) {
      return;
    }

    await (_database.update(_database.localMaintenanceRecords)..where(
          (item) =>
              item.userId.equals(userId) &
              item.maintenanceId.equals(maintenanceId),
        ))
        .write(
          LocalMaintenanceRecordsCompanion(
            isDeleted: const Value(true),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  static Future<void> removePermanently({
    required String userId,
    required String maintenanceId,
  }) async {
    await (_database.delete(_database.localMaintenanceRecords)..where(
          (item) =>
              item.userId.equals(userId) &
              item.maintenanceId.equals(maintenanceId),
        ))
        .go();
  }

  static Future<int> countRecords({required String userId}) async {
    final countExpression = _database.localMaintenanceRecords.localKey.count();

    final query = _database.selectOnly(_database.localMaintenanceRecords)
      ..addColumns([countExpression])
      ..where(
        _database.localMaintenanceRecords.userId.equals(userId) &
            _database.localMaintenanceRecords.isDeleted.equals(false),
      );

    final row = await query.getSingle();
    return row.read(countExpression) ?? 0;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is DateTime) {
      return value;
    }

    final text = value.toString().trim();
    if (text.isEmpty) {
      return null;
    }

    return DateTime.tryParse(text);
  }
}
