import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../models/battery.dart';
import '../models/battery_measurement.dart';

class BatteryLocalStore {
  BatteryLocalStore._();

  static final AppDatabase _database = AppDatabase.instance;

  static String _batteryKey({
    required String userId,
    required String batteryCode,
  }) {
    return '$userId|$batteryCode';
  }

  static String _measurementKey({
    required String userId,
    required BatteryMeasurement measurement,
  }) {
    if (measurement.id != null) {
      return '$userId|remote|${measurement.id}';
    }

    return '$userId|local|${measurement.batteryCode}|'
        '${measurement.measuredAt.toUtc().toIso8601String()}|'
        '${measurement.measurementType}';
  }

  static Future<void> replaceBatteries({
    required String userId,
    required List<Map<String, dynamic>> rows,
  }) async {
    await _database.transaction(() async {
      final pendingBatteryCodes = await _database.getPendingEntityIds(
        userId: userId,
        entityType: 'battery',
      );

      await (_database.delete(_database.localBatteries)..where(
            (row) =>
                row.userId.equals(userId) &
                row.batteryCode.isNotIn(pendingBatteryCodes.toList()),
          ))
          .go();

      final cloudRows = rows.where(
        (row) => !pendingBatteryCodes.contains(row['battery_code']?.toString()),
      );

      final values = cloudRows
          .map((row) {
            final batteryCode = row['battery_code'] as String;

            return LocalBatteriesCompanion.insert(
              localKey: _batteryKey(userId: userId, batteryCode: batteryCode),
              userId: userId,
              batteryCode: batteryCode,
              payloadJson: jsonEncode(row),
              createdAt: Value(_parseNullableDate(row['created_at'])),
              updatedAt: Value(_parseNullableDate(row['updated_at'])),
            );
          })
          .toList(growable: false);

      if (values.isNotEmpty) {
        await _database.batch((batch) {
          batch.insertAll(
            _database.localBatteries,
            values,
            mode: InsertMode.insertOrReplace,
          );
        });
      }
    });
  }

  static Future<void> replaceMeasurements({
    required String userId,
    required List<Map<String, dynamic>> rows,
  }) async {
    await _database.transaction(() async {
      final pendingMeasurementKeys = await _database.getPendingEntityIds(
        userId: userId,
        entityType: 'battery_measurement',
      );

      await (_database.delete(_database.localBatteryMeasurements)..where(
            (row) =>
                row.userId.equals(userId) &
                row.localKey.isNotIn(pendingMeasurementKeys.toList()),
          ))
          .go();

      final values = rows
          .where((row) {
            final measurement = BatteryMeasurement.fromJson(row);
            final key = _measurementKey(
              userId: userId,
              measurement: measurement,
            );
            return !pendingMeasurementKeys.contains(key);
          })
          .map((row) {
            final measurement = BatteryMeasurement.fromJson(row);

            return LocalBatteryMeasurementsCompanion.insert(
              localKey: _measurementKey(
                userId: userId,
                measurement: measurement,
              ),
              userId: userId,
              remoteId: Value(measurement.id),
              batteryCode: measurement.batteryCode,
              measurementType: measurement.measurementType,
              measuredAt: measurement.measuredAt,
              payloadJson: jsonEncode(row),
            );
          })
          .toList(growable: false);

      if (values.isNotEmpty) {
        await _database.batch((batch) {
          batch.insertAll(
            _database.localBatteryMeasurements,
            values,
            mode: InsertMode.insertOrReplace,
          );
        });
      }
    });
  }

  static Future<void> replaceMeasurementsForBattery({
    required String userId,
    required String batteryCode,
    required List<Map<String, dynamic>> rows,
  }) async {
    await _database.transaction(() async {
      await (_database.delete(_database.localBatteryMeasurements)..where(
            (row) =>
                row.userId.equals(userId) & row.batteryCode.equals(batteryCode),
          ))
          .go();

      if (rows.isEmpty) {
        return;
      }

      final values = rows
          .map((row) {
            final measurement = BatteryMeasurement.fromJson(row);

            return LocalBatteryMeasurementsCompanion.insert(
              localKey: _measurementKey(
                userId: userId,
                measurement: measurement,
              ),
              userId: userId,
              remoteId: Value(measurement.id),
              batteryCode: measurement.batteryCode,
              measurementType: measurement.measurementType,
              measuredAt: measurement.measuredAt,
              payloadJson: jsonEncode(row),
            );
          })
          .toList(growable: false);

      await _database.batch((batch) {
        batch.insertAll(
          _database.localBatteryMeasurements,
          values,
          mode: InsertMode.insertOrReplace,
        );
      });
    });
  }

  static Future<void> upsertBattery({
    required String userId,
    required Battery battery,
    bool isDeleted = false,
  }) async {
    final now = DateTime.now();
    final row = <String, dynamic>{
      'user_id': userId,
      ...battery.toJson(),
      'updated_at': now.toUtc().toIso8601String(),
    };

    await _database
        .into(_database.localBatteries)
        .insert(
          LocalBatteriesCompanion.insert(
            localKey: _batteryKey(userId: userId, batteryCode: battery.id),
            userId: userId,
            batteryCode: battery.id,
            payloadJson: jsonEncode(row),
            updatedAt: Value(now),
            isDeleted: Value(isDeleted),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  static Future<void> upsertBatteries({
    required String userId,
    required List<Battery> batteries,
  }) async {
    await _database.transaction(() async {
      for (final battery in batteries) {
        await upsertBattery(userId: userId, battery: battery);
      }
    });
  }

  static Future<void> markBatteryDeleted({
    required String userId,
    required Battery battery,
  }) {
    return upsertBattery(userId: userId, battery: battery, isDeleted: true);
  }

  static Future<void> upsertMeasurement({
    required String userId,
    required BatteryMeasurement measurement,
    String? forcedLocalKey,
    bool isDeleted = false,
  }) async {
    final row = <String, dynamic>{
      'user_id': userId,
      ...measurement.toJson(),
      if (measurement.id != null) 'id': measurement.id,
    };

    await _database
        .into(_database.localBatteryMeasurements)
        .insert(
          LocalBatteryMeasurementsCompanion.insert(
            localKey:
                forcedLocalKey ??
                _measurementKey(userId: userId, measurement: measurement),
            userId: userId,
            remoteId: Value(measurement.id),
            batteryCode: measurement.batteryCode,
            measurementType: measurement.measurementType,
            measuredAt: measurement.measuredAt,
            payloadJson: jsonEncode(row),
            isDeleted: Value(isDeleted),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  static Future<void> markMeasurementDeleted({
    required String userId,
    required BatteryMeasurement measurement,
  }) {
    return upsertMeasurement(
      userId: userId,
      measurement: measurement,
      isDeleted: true,
    );
  }

  static Future<void> promoteMeasurementToRemote({
    required String userId,
    required String previousLocalKey,
    required Map<String, dynamic> remoteRow,
  }) async {
    final measurement = BatteryMeasurement.fromJson(remoteRow);

    await _database.transaction(() async {
      await (_database.delete(
        _database.localBatteryMeasurements,
      )..where((row) => row.localKey.equals(previousLocalKey))).go();

      await upsertMeasurement(userId: userId, measurement: measurement);
    });
  }

  static String measurementEntityId({
    required String userId,
    required BatteryMeasurement measurement,
  }) {
    return _measurementKey(userId: userId, measurement: measurement);
  }

  static Stream<List<Battery>> watchBatteries({required String userId}) {
    final query = _database.select(_database.localBatteries)
      ..where((row) => row.userId.equals(userId) & row.isDeleted.equals(false))
      ..orderBy([
        (row) => OrderingTerm.desc(row.updatedAt, nulls: NullsOrder.last),
        (row) => OrderingTerm.desc(row.cachedAt),
      ]);

    return query.watch().map(
      (rows) => rows
          .map((row) {
            final data = Map<String, dynamic>.from(
              jsonDecode(row.payloadJson) as Map,
            );
            return Battery.fromJson(data);
          })
          .toList(growable: false),
    );
  }

  static Stream<List<BatteryMeasurement>> watchMeasurements({
    required String userId,
  }) {
    final query = _database.select(_database.localBatteryMeasurements)
      ..where((row) => row.userId.equals(userId) & row.isDeleted.equals(false))
      ..orderBy([(row) => OrderingTerm.desc(row.measuredAt)]);

    return query.watch().map(
      (rows) => rows
          .map((row) {
            final data = Map<String, dynamic>.from(
              jsonDecode(row.payloadJson) as Map,
            );
            return BatteryMeasurement.fromJson(data);
          })
          .toList(growable: false),
    );
  }

  static Future<List<Battery>> getBatteries({required String userId}) async {
    final rows =
        await (_database.select(_database.localBatteries)
              ..where(
                (row) =>
                    row.userId.equals(userId) & row.isDeleted.equals(false),
              )
              ..orderBy([
                (row) =>
                    OrderingTerm.desc(row.updatedAt, nulls: NullsOrder.last),
                (row) => OrderingTerm.desc(row.cachedAt),
              ]))
            .get();

    return rows
        .map((row) {
          final data = Map<String, dynamic>.from(
            jsonDecode(row.payloadJson) as Map,
          );
          return Battery.fromJson(data);
        })
        .toList(growable: false);
  }

  static Future<List<BatteryMeasurement>> getMeasurements({
    required String userId,
    String? batteryCode,
  }) async {
    final query = _database.select(_database.localBatteryMeasurements)
      ..where((row) => row.userId.equals(userId) & row.isDeleted.equals(false));

    if (batteryCode != null && batteryCode.isNotEmpty) {
      query.where((row) => row.batteryCode.equals(batteryCode));
    }

    query.orderBy([(row) => OrderingTerm.desc(row.measuredAt)]);

    final rows = await query.get();

    return rows
        .map((row) {
          final data = Map<String, dynamic>.from(
            jsonDecode(row.payloadJson) as Map,
          );
          return BatteryMeasurement.fromJson(data);
        })
        .toList(growable: false);
  }

  static Future<bool> hasBatteryCache({required String userId}) async {
    final row =
        await (_database.select(_database.localBatteries)
              ..where((entry) => entry.userId.equals(userId))
              ..limit(1))
            .getSingleOrNull();

    return row != null;
  }

  static DateTime? _parseNullableDate(dynamic value) {
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();
    if (text.isEmpty) {
      return null;
    }

    return DateTime.parse(text);
  }
}
