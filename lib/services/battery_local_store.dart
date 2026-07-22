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
      await (_database.delete(
        _database.localBatteries,
      )..where((row) => row.userId.equals(userId))).go();

      if (rows.isEmpty) {
        return;
      }

      final values = rows
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

      await _database.batch((batch) {
        batch.insertAll(
          _database.localBatteries,
          values,
          mode: InsertMode.insertOrReplace,
        );
      });
    });
  }

  static Future<void> replaceMeasurements({
    required String userId,
    required List<Map<String, dynamic>> rows,
  }) async {
    await _database.transaction(() async {
      await (_database.delete(
        _database.localBatteryMeasurements,
      )..where((row) => row.userId.equals(userId))).go();

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
