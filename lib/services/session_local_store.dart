import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';

class SessionLocalStore {
  SessionLocalStore._();

  static final AppDatabase _database = AppDatabase.instance;

  static String _sessionKey({
    required String userId,
    required String sessionId,
  }) {
    return '$userId|$sessionId';
  }

  static Future<bool> hasSessionCache({required String userId}) async {
    final row =
        await (_database.select(_database.localSessions)
              ..where((item) => item.userId.equals(userId))
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  }

  static Future<void> replaceSessions({
    required String userId,
    required List<Map<String, dynamic>> rows,
  }) async {
    await _database.transaction(() async {
      final pendingIds = await _database.getPendingEntityIds(
        userId: userId,
        entityType: 'session',
      );

      await (_database.delete(_database.localSessions)..where(
            (row) =>
                row.userId.equals(userId) &
                row.sessionId.isNotIn(pendingIds.toList()),
          ))
          .go();

      final values = rows
          .where((row) => !pendingIds.contains(row['id']?.toString()))
          .map((row) {
            final sessionId = row['id'].toString();
            return LocalSessionsCompanion.insert(
              localKey: _sessionKey(userId: userId, sessionId: sessionId),
              userId: userId,
              sessionId: sessionId,
              payloadJson: jsonEncode(row),
              startedAt: DateTime.parse(row['started_at'].toString()).toLocal(),
              updatedAt: Value(_parseNullableDate(row['updated_at'])),
            );
          })
          .toList(growable: false);

      if (values.isNotEmpty) {
        await _database.batch((batch) {
          batch.insertAll(
            _database.localSessions,
            values,
            mode: InsertMode.insertOrReplace,
          );
        });
      }
    });
  }

  static Future<void> upsertSessionRow({
    required String userId,
    required Map<String, dynamic> row,
    bool isDeleted = false,
  }) async {
    final sessionId = row['id']?.toString();
    if (sessionId == null || sessionId.isEmpty) {
      throw StateError('Identifiant de session manquant');
    }

    final startedAt = DateTime.parse(row['started_at'].toString()).toLocal();
    final now = DateTime.now();
    final normalized = Map<String, dynamic>.from(row)
      ..['user_id'] = userId
      ..['updated_at'] = now.toUtc().toIso8601String();

    await _database
        .into(_database.localSessions)
        .insert(
          LocalSessionsCompanion.insert(
            localKey: _sessionKey(userId: userId, sessionId: sessionId),
            userId: userId,
            sessionId: sessionId,
            payloadJson: jsonEncode(normalized),
            startedAt: startedAt,
            updatedAt: Value(now),
            isDeleted: Value(isDeleted),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  static Future<void> markSessionDeleted({
    required String userId,
    required String sessionId,
  }) async {
    final existing = await getSessionRow(
      userId: userId,
      sessionId: sessionId,
      includeDeleted: true,
    );

    if (existing == null) {
      return;
    }

    await upsertSessionRow(userId: userId, row: existing, isDeleted: true);
  }

  static Future<List<Map<String, dynamic>>> getSessionRows({
    required String userId,
  }) async {
    final rows =
        await (_database.select(_database.localSessions)
              ..where(
                (row) =>
                    row.userId.equals(userId) & row.isDeleted.equals(false),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.startedAt)]))
            .get();

    return rows
        .map(
          (row) =>
              Map<String, dynamic>.from(jsonDecode(row.payloadJson) as Map),
        )
        .toList(growable: false);
  }

  static Future<Map<String, dynamic>?> getSessionRow({
    required String userId,
    required String sessionId,
    bool includeDeleted = false,
  }) async {
    final query = _database.select(_database.localSessions)
      ..where(
        (row) => row.userId.equals(userId) & row.sessionId.equals(sessionId),
      );

    if (!includeDeleted) {
      query.where((row) => row.isDeleted.equals(false));
    }

    final row = await query.getSingleOrNull();
    if (row == null) {
      return null;
    }

    return Map<String, dynamic>.from(jsonDecode(row.payloadJson) as Map);
  }

  static Stream<List<Map<String, dynamic>>> watchSessionRows({
    required String userId,
  }) {
    final query = _database.select(_database.localSessions)
      ..where((row) => row.userId.equals(userId) & row.isDeleted.equals(false))
      ..orderBy([(row) => OrderingTerm.desc(row.startedAt)]);

    return query.watch().map(
      (rows) => rows
          .map(
            (row) =>
                Map<String, dynamic>.from(jsonDecode(row.payloadJson) as Map),
          )
          .toList(growable: false),
    );
  }

  static DateTime? _parseNullableDate(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) {
      return null;
    }
    return DateTime.parse(value.toString()).toLocal();
  }
}
