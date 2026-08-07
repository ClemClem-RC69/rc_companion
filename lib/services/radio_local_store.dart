import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../models/radio.dart';

class RadioLocalStore {
  RadioLocalStore._();

  static final AppDatabase _database = AppDatabase.instance;

  static String localKey({required String userId, required String radioId}) {
    return '$userId::$radioId';
  }

  static Future<bool> hasCache({required String userId}) async {
    final row =
        await (_database.select(_database.localRadios)
              ..where((item) => item.userId.equals(userId))
              ..limit(1))
            .getSingleOrNull();

    return row != null;
  }

  static Stream<List<RcRadio>> watchRadios({required String userId}) {
    final query = _database.select(_database.localRadios)
      ..where(
        (item) => item.userId.equals(userId) & item.isDeleted.equals(false),
      )
      ..orderBy([
        (item) => OrderingTerm.asc(item.brand),
        (item) => OrderingTerm.asc(item.model),
        (item) => OrderingTerm.desc(item.cachedAt),
      ]);

    return query.watch().map(
      (rows) => rows
          .map(
            (row) => RcRadio.fromMap(
              Map<String, dynamic>.from(jsonDecode(row.payloadJson) as Map),
            ),
          )
          .toList(growable: false),
    );
  }

  static Future<List<RcRadio>> getRadios({required String userId}) async {
    final rows =
        await (_database.select(_database.localRadios)
              ..where(
                (item) =>
                    item.userId.equals(userId) & item.isDeleted.equals(false),
              )
              ..orderBy([
                (item) => OrderingTerm.asc(item.brand),
                (item) => OrderingTerm.asc(item.model),
                (item) => OrderingTerm.desc(item.cachedAt),
              ]))
            .get();

    return rows
        .map(
          (row) => RcRadio.fromMap(
            Map<String, dynamic>.from(jsonDecode(row.payloadJson) as Map),
          ),
        )
        .toList(growable: false);
  }

  static Future<RcRadio?> getRadio({
    required String userId,
    required String radioId,
  }) async {
    final row =
        await (_database.select(_database.localRadios)
              ..where(
                (item) =>
                    item.userId.equals(userId) &
                    item.radioId.equals(radioId) &
                    item.isDeleted.equals(false),
              )
              ..limit(1))
            .getSingleOrNull();

    if (row == null) {
      return null;
    }

    return RcRadio.fromMap(
      Map<String, dynamic>.from(jsonDecode(row.payloadJson) as Map),
    );
  }

  static Future<void> replaceRadios({
    required String userId,
    required List<Map<String, dynamic>> rows,
  }) async {
    await _database.transaction(() async {
      final existingRows = await (_database.select(
        _database.localRadios,
      )..where((item) => item.userId.equals(userId))).get();

      final existingPayloadById = <String, Map<String, dynamic>>{
        for (final existingRow in existingRows)
          existingRow.radioId: Map<String, dynamic>.from(
            jsonDecode(existingRow.payloadJson) as Map,
          ),
      };

      final pendingIds = await _database.getPendingEntityIds(
        userId: userId,
        entityType: 'radio',
      );

      await (_database.delete(_database.localRadios)..where(
            (item) =>
                item.userId.equals(userId) &
                item.radioId.isNotIn(pendingIds.toList()),
          ))
          .go();

      for (final row in rows) {
        final radioId = row['id']?.toString();

        if (radioId == null ||
            radioId.trim().isEmpty ||
            pendingIds.contains(radioId)) {
          continue;
        }

        final mergedRow = Map<String, dynamic>.from(row);
        final existingPayload = existingPayloadById[radioId];

        if (existingPayload != null) {
          final incomingStorage =
              mergedRow['manual_storage_path']?.toString().trim() ?? '';
          final existingStorage =
              existingPayload['manual_storage_path']?.toString().trim() ?? '';
          final existingLocalPath =
              existingPayload['manual_local_path']?.toString().trim() ?? '';

          if (incomingStorage.isNotEmpty &&
              incomingStorage == existingStorage &&
              existingLocalPath.isNotEmpty) {
            mergedRow['manual_local_path'] = existingLocalPath;
          }
        }

        await upsertRow(userId: userId, row: mergedRow);
      }
    });
  }

  static Future<void> upsertRadio({
    required String userId,
    required RcRadio radio,
    bool isDeleted = false,
  }) async {
    await upsertRow(
      userId: userId,
      row: radioToRow(userId: userId, radio: radio),
      isDeleted: isDeleted,
    );
  }

  static Future<void> upsertRow({
    required String userId,
    required Map<String, dynamic> row,
    bool isDeleted = false,
  }) async {
    final radioId = row['id']?.toString();

    if (radioId == null || radioId.trim().isEmpty) {
      throw StateError('La radio doit posséder un identifiant.');
    }

    final existing =
        await (_database.select(_database.localRadios)
              ..where(
                (item) =>
                    item.userId.equals(userId) & item.radioId.equals(radioId),
              )
              ..limit(1))
            .getSingleOrNull();

    final mergedRow = Map<String, dynamic>.from(row);
    if (existing != null) {
      final existingPayload = Map<String, dynamic>.from(
        jsonDecode(existing.payloadJson) as Map,
      );

      final incomingStorage = mergedRow['manual_storage_path']
          ?.toString()
          .trim();
      final existingStorage = existingPayload['manual_storage_path']
          ?.toString()
          .trim();

      final existingLocalPath = existingPayload['manual_local_path']
          ?.toString()
          .trim();
      final incomingLocalPath = mergedRow['manual_local_path']
          ?.toString()
          .trim();

      if ((incomingLocalPath == null || incomingLocalPath.isEmpty) &&
          existingLocalPath != null &&
          existingLocalPath.isNotEmpty &&
          incomingStorage != null &&
          incomingStorage.isNotEmpty &&
          incomingStorage == existingStorage) {
        mergedRow['manual_local_path'] = existingLocalPath;
      }

      final existingPending = existingPayload['manual_pending_upload'] == true;
      if (!mergedRow.containsKey('manual_pending_upload')) {
        mergedRow['manual_pending_upload'] = existingPending;
      }
    }

    final now = DateTime.now();
    final brand = mergedRow['brand']?.toString().trim() ?? '';
    final model = mergedRow['model']?.toString().trim() ?? '';
    final createdAt = _parseDate(mergedRow['created_at']) ?? now;
    final updatedAt = _parseDate(mergedRow['updated_at']) ?? now;

    await _database
        .into(_database.localRadios)
        .insert(
          LocalRadiosCompanion.insert(
            localKey: localKey(userId: userId, radioId: radioId),
            userId: userId,
            radioId: radioId,
            brand: brand,
            model: model,
            payloadJson: jsonEncode(mergedRow),
            createdAt: Value(createdAt),
            updatedAt: Value(updatedAt),
            isDeleted: Value(isDeleted),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  static Future<void> markDeleted({
    required String userId,
    required RcRadio radio,
  }) {
    return upsertRadio(userId: userId, radio: radio, isDeleted: true);
  }

  static Map<String, dynamic> radioToRow({
    required String userId,
    required RcRadio radio,
    DateTime? updatedAt,
  }) {
    return <String, dynamic>{
      'id': radio.id,
      'user_id': userId,
      'brand': radio.brand,
      'model': radio.model,
      'level': radio.level,
      'type': radio.type,
      'channels': radio.channels,
      'protocols': radio.protocols,
      'programmable': radio.programmable,
      'created_at': radio.createdAt.toUtc().toIso8601String(),
      'manual_name': radio.manualName,
      'manual_storage_path': radio.manualStoragePath,
      'manual_local_path': radio.manualLocalPath,
      'manual_pending_upload': radio.manualPendingUpload,
      'updated_at': (updatedAt ?? DateTime.now()).toUtc().toIso8601String(),
    };
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) {
      return null;
    }

    return DateTime.tryParse(value.toString());
  }
}
