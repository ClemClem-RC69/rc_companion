import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../database/app_database.dart';
import '../models/battery.dart';
import '../models/battery_measurement.dart';
import '../models/rc_model.dart';
import '../models/rc_session.dart';
import 'battery_local_store.dart';
import 'battery_sync_service.dart';
import 'model_operational_event_service.dart';
import 'session_local_store.dart';
import 'supabase_service.dart';

class SessionService {
  SessionService._();

  static final _client = SupabaseService.client;
  static final _database = AppDatabase.instance;

  static Future<List<RcSession>> getSessions({
    required List<RcModel> models,
    required List<Battery> batteries,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return [];
    }

    final cached = await _getCachedSessions(
      userId: user.id,
      models: models,
      batteries: batteries,
    );
    final hasCache = await SessionLocalStore.hasSessionCache(userId: user.id);

    if (hasCache) {
      unawaited(
        _refreshSessionsSilently(
          userId: user.id,
          models: models,
          batteries: batteries,
        ),
      );
      return cached;
    }

    return _refreshSessionsFromCloud(
      userId: user.id,
      models: models,
      batteries: batteries,
    );
  }

  static Future<List<RcSession>> _getCachedSessions({
    required String userId,
    required List<RcModel> models,
    required List<Battery> batteries,
  }) async {
    final rows = await SessionLocalStore.getSessionRows(userId: userId);
    return _parseSessions(rows, models: models, batteries: batteries);
  }

  static Future<void> _refreshSessionsSilently({
    required String userId,
    required List<RcModel> models,
    required List<Battery> batteries,
  }) async {
    try {
      await _refreshSessionsFromCloud(
        userId: userId,
        models: models,
        batteries: batteries,
      );
    } catch (_) {
      // Le cache local reste la source d'affichage hors ligne.
    }
  }

  static Future<List<RcSession>> _refreshSessionsFromCloud({
    required String userId,
    required List<RcModel> models,
    required List<Battery> batteries,
  }) async {
    final response = await _client
        .from('rc_sessions')
        .select('''
          *,
          session_runs (
            *,
            session_run_batteries (
              battery_code,
              created_at
            ),
            session_run_measurements (
              battery_code,
              measured_at,
              remaining_capacity_percent,
              temperature_celsius,
              cell_voltages,
              cell_resistances
            )
          )
        ''')
        .eq('user_id', userId)
        .order('started_at', ascending: false)
        .timeout(const Duration(seconds: 8));

    final rows = response
        .map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);

    await SessionLocalStore.replaceSessions(userId: userId, rows: rows);
    return _getCachedSessions(
      userId: userId,
      models: models,
      batteries: batteries,
    );
  }

  static Future<RcSession> saveSession(RcSession session) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecté');
    }

    final sessionId = (session.id == null || session.id!.trim().isEmpty)
        ? _newUuid()
        : session.id!;
    final saved = session.copyWith(id: sessionId);
    final row = _sessionToRow(userId: user.id, session: saved);

    await SessionLocalStore.upsertSessionRow(userId: user.id, row: row);
    await _database.replacePendingSyncOperation(
      userId: user.id,
      entityType: 'session',
      entityId: sessionId,
      operation: 'upsert',
      payloadJson: jsonEncode(row),
    );

    await _replaceLocalBatteryHistoryForSession(
      userId: user.id,
      session: saved,
    );

    await ModelOperationalEventService.synchronizeSession(saved);

    unawaited(BatterySyncService.syncNow());
    return saved;
  }

  static Future<void> updateRunReading({
    required String sessionId,
    required String modelName,
    required RcRun run,
    required BatteryRunReading reading,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecté');
    }

    final row = await SessionLocalStore.getSessionRow(
      userId: user.id,
      sessionId: sessionId,
    );
    if (row == null) {
      throw StateError('Session introuvable');
    }

    final runs = (row['session_runs'] as List<dynamic>? ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final targetStartedAt = run.startedAt.toUtc();
    final runIndex = runs.indexWhere((item) {
      final rawStartedAt = item['started_at'];
      if (rawStartedAt == null) {
        return false;
      }

      final parsedStartedAt = DateTime.tryParse(rawStartedAt.toString());
      if (parsedStartedAt == null) {
        return false;
      }

      return parsedStartedAt.toUtc().difference(targetStartedAt).abs() <
          const Duration(seconds: 1);
    });
    if (runIndex < 0) {
      throw StateError('Roulage introuvable');
    }

    final selectedRun = runs[runIndex];
    final measurements =
        (selectedRun['session_run_measurements'] as List<dynamic>? ?? [])
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
    final readingIndex = measurements.indexWhere(
      (item) => item['battery_code']?.toString() == reading.batteryId,
    );
    final measurementRow = _readingToRow(reading: reading, run: run);

    if (readingIndex < 0) {
      measurements.add(measurementRow);
    } else {
      measurements[readingIndex] = measurementRow;
    }

    selectedRun['session_run_measurements'] = measurements;
    runs[runIndex] = selectedRun;
    row['session_runs'] = runs;
    row['model_name'] = modelName;

    await SessionLocalStore.upsertSessionRow(userId: user.id, row: row);
    await _database.replacePendingSyncOperation(
      userId: user.id,
      entityType: 'session',
      entityId: sessionId,
      operation: 'upsert',
      payloadJson: jsonEncode(row),
    );

    await _replaceLocalBatteryHistoryFromRow(
      userId: user.id,
      sessionId: sessionId,
      modelName: modelName,
      row: row,
    );

    unawaited(BatterySyncService.syncNow());
  }

  static Future<void> deleteSession(String sessionId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Utilisateur non connecté');
    }

    await SessionLocalStore.markSessionDeleted(
      userId: user.id,
      sessionId: sessionId,
    );
    await _deleteLocalBatteryHistoryForSession(
      userId: user.id,
      sessionId: sessionId,
    );
    await ModelOperationalEventService.removeAllEventsForSession(
      userId: user.id,
      sessionId: sessionId,
    );
    await _database.replacePendingSyncOperation(
      userId: user.id,
      entityType: 'session',
      entityId: sessionId,
      operation: 'delete',
    );

    unawaited(BatterySyncService.syncNow());
  }

  static List<RcSession> _parseSessions(
    List<Map<String, dynamic>> rows, {
    required List<RcModel> models,
    required List<Battery> batteries,
  }) {
    final modelById = <String, RcModel>{
      for (final model in models)
        if (model.id != null && model.id!.isNotEmpty) model.id!: model,
    };
    final modelByName = <String, RcModel>{
      for (final model in models) model.name: model,
    };
    final batteryByCode = <String, Battery>{
      for (final battery in batteries) battery.id: battery,
    };
    final loaded = <RcSession>[];

    for (final sessionRow in rows) {
      final modelId = sessionRow['model_id'] as String?;
      final modelName = sessionRow['model_name'] as String?;
      final model =
          (modelId == null ? null : modelById[modelId]) ??
          (modelName == null ? null : modelByName[modelName]);
      if (model == null) {
        continue;
      }

      final rawRuns =
          (sessionRow['session_runs'] as List<dynamic>? ?? [])
              .map((row) => Map<String, dynamic>.from(row as Map))
              .toList()
            ..sort(
              (a, b) => a['started_at'].toString().compareTo(
                b['started_at'].toString(),
              ),
            );
      final runs = <RcRun>[];

      for (final runRow in rawRuns) {
        final links = (runRow['session_run_batteries'] as List<dynamic>? ?? [])
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
        final runBatteries = <Battery>[];
        for (final link in links) {
          final battery = batteryByCode[link['battery_code']?.toString()];
          if (battery != null) {
            runBatteries.add(battery);
          }
        }

        final readings =
            (runRow['session_run_measurements'] as List<dynamic>? ?? [])
                .map((row) => Map<String, dynamic>.from(row as Map))
                .map(
                  (row) => BatteryRunReading(
                    batteryId: row['battery_code'].toString(),
                    measuredAt: _parseNullableDate(row['measured_at']),
                    remainingCapacityPercent:
                        (row['remaining_capacity_percent'] as num?)?.toDouble(),
                    temperatureCelsius: (row['temperature_celsius'] as num?)
                        ?.toDouble(),
                    cellVoltages: _toDoubleList(row['cell_voltages']),
                  ),
                )
                .toList(growable: false);

        runs.add(
          RcRun(
            startedAt: DateTime.parse(
              runRow['started_at'].toString(),
            ).toLocal(),
            endedAt: _parseNullableDate(runRow['ended_at']),
            durationMinutes: (runRow['duration_minutes'] as num?)?.toInt(),
            batteries: List<Battery>.unmodifiable(runBatteries),
            readings: List<BatteryRunReading>.unmodifiable(readings),
            historicalBatteries:
                ((runRow['historical_batteries'] as List<dynamic>? ?? const []))
                    .map(
                      (item) => HistoricalBattery.fromJson(
                        Map<String, dynamic>.from(item as Map),
                      ),
                    )
                    .where((item) => !item.isEmpty)
                    .toList(growable: false),
            notes: runRow['notes'] as String? ?? '',
          ),
        );
      }

      loaded.add(
        RcSession(
          id: sessionRow['id'].toString(),
          model: model,
          startedAt: DateTime.parse(
            sessionRow['started_at'].toString(),
          ).toLocal(),
          endedAt: _parseNullableDate(sessionRow['ended_at']),
          runs: List<RcRun>.unmodifiable(runs),
          location: sessionRow['location'] as String? ?? '',
          drivingNotes: sessionRow['driving_notes'] as String? ?? '',
          breakages: sessionRow['breakages'] as String? ?? '',
          partsReplacedOnSite:
              sessionRow['parts_replaced_on_site'] as String? ?? '',
          maintenanceToDo: sessionRow['maintenance_to_do'] as String? ?? '',
          partsToOrder: sessionRow['parts_to_order'] as String? ?? '',
          changesBeforeNextSession:
              sessionRow['changes_before_next_session'] as String? ?? '',
          generalNotes: sessionRow['general_notes'] as String? ?? '',
          isHistorical: sessionRow['_local_is_historical'] == true,
        ),
      );
    }

    loaded.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return loaded;
  }

  static Map<String, dynamic> _sessionToRow({
    required String userId,
    required RcSession session,
  }) {
    return <String, dynamic>{
      'id': session.id,
      'user_id': userId,
      'model_id': session.model.id,
      'model_name': session.model.name,
      'started_at': session.startedAt.toUtc().toIso8601String(),
      'ended_at': session.endedAt?.toUtc().toIso8601String(),
      'location': _nullableText(session.location),
      'driving_notes': _nullableText(session.drivingNotes),
      'breakages': _nullableText(session.breakages),
      'parts_replaced_on_site': _nullableText(session.partsReplacedOnSite),
      'maintenance_to_do': _nullableText(session.maintenanceToDo),
      'parts_to_order': _nullableText(session.partsToOrder),
      'changes_before_next_session': _nullableText(
        session.changesBeforeNextSession,
      ),
      'general_notes': _nullableText(session.generalNotes),
      '_local_is_historical': session.isHistorical,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'session_runs': session.runs.map(_runToRow).toList(growable: false),
    };
  }

  static Map<String, dynamic> _runToRow(RcRun run) {
    return <String, dynamic>{
      'started_at': run.startedAt.toUtc().toIso8601String(),
      'ended_at': run.endedAt?.toUtc().toIso8601String(),
      'duration_minutes': run.durationMinutes,
      'notes': _nullableText(run.notes),
      'historical_batteries': run.historicalBatteries
          .where((battery) => !battery.isEmpty)
          .map((battery) => battery.toJson())
          .toList(growable: false),
      'session_run_batteries': run.batteries
          .map(
            (battery) => <String, dynamic>{
              'battery_code': battery.id,
              'created_at': run.startedAt.toUtc().toIso8601String(),
            },
          )
          .toList(growable: false),
      'session_run_measurements': run.readings
          .where((reading) => reading.hasMeasurements)
          .map((reading) => _readingToRow(reading: reading, run: run))
          .toList(growable: false),
    };
  }

  static Map<String, dynamic> _readingToRow({
    required BatteryRunReading reading,
    required RcRun run,
  }) {
    final measuredAt =
        reading.measuredAt ??
        run.endedAt ??
        run.startedAt.add(Duration(minutes: run.effectiveDurationMinutes));
    return <String, dynamic>{
      'battery_code': reading.batteryId,
      'measured_at': measuredAt.toUtc().toIso8601String(),
      'remaining_capacity_percent': reading.remainingCapacityPercent,
      'temperature_celsius': reading.temperatureCelsius,
      'cell_voltages': reading.cellVoltages,
      'cell_resistances': const <double>[],
    };
  }

  static const String _automaticMeasurementNotePrefix =
      'Mesure automatique après roulage|session:';

  static Future<void> _replaceLocalBatteryHistoryForSession({
    required String userId,
    required RcSession session,
  }) async {
    final sessionId = session.id;
    if (sessionId == null || sessionId.isEmpty) {
      return;
    }

    if (session.isHistorical) {
      await _deleteLocalBatteryHistoryForSession(
        userId: userId,
        sessionId: sessionId,
      );
      return;
    }

    await _deleteLocalBatteryHistoryForSession(
      userId: userId,
      sessionId: sessionId,
    );

    for (final run in session.runs) {
      for (final reading in run.readings) {
        if (!reading.isCompleteEndOfRunReading) {
          continue;
        }

        final measuredAt =
            reading.measuredAt ??
            run.endedAt ??
            run.startedAt.add(Duration(minutes: run.effectiveDurationMinutes));
        final measurement = BatteryMeasurement(
          batteryCode: reading.batteryId,
          measuredAt: measuredAt,
          measurementType: BatteryMeasurement.endOfRunType,
          chargePercent: reading.remainingCapacityPercent!.round().clamp(
            0,
            100,
          ),
          cellVoltages: List<double>.unmodifiable(reading.cellVoltages),
          batteryTemperature: reading.temperatureCelsius,
          notes: _automaticMeasurementNote(
            sessionId: sessionId,
            runStartedAt: run.startedAt,
            batteryCode: reading.batteryId,
            modelName: session.model.name,
          ),
        );

        await _queueLocalBatteryMeasurement(
          userId: userId,
          measurement: measurement,
        );
      }
    }
  }

  static Future<void> _replaceLocalBatteryHistoryFromRow({
    required String userId,
    required String sessionId,
    required String modelName,
    required Map<String, dynamic> row,
  }) async {
    await _deleteLocalBatteryHistoryForSession(
      userId: userId,
      sessionId: sessionId,
    );

    final runs = (row['session_runs'] as List<dynamic>? ?? const []).map(
      (item) => Map<String, dynamic>.from(item as Map),
    );

    for (final run in runs) {
      final runStartedAt = DateTime.parse(
        run['started_at'].toString(),
      ).toLocal();
      final measurements =
          (run['session_run_measurements'] as List<dynamic>? ?? const []).map(
            (item) => Map<String, dynamic>.from(item as Map),
          );

      for (final item in measurements) {
        final percent = item['remaining_capacity_percent'] as num?;
        final voltages = _toDoubleList(item['cell_voltages']);
        if (percent == null || voltages.isEmpty) {
          continue;
        }

        final measuredAt =
            _parseNullableDate(item['measured_at']) ?? runStartedAt;
        final measurement = BatteryMeasurement(
          batteryCode: item['battery_code'].toString(),
          measuredAt: measuredAt,
          measurementType: BatteryMeasurement.endOfRunType,
          chargePercent: percent.round().clamp(0, 100),
          cellVoltages: voltages,
          batteryTemperature: (item['temperature_celsius'] as num?)?.toDouble(),
          notes: _automaticMeasurementNote(
            sessionId: sessionId,
            runStartedAt: runStartedAt,
            batteryCode: item['battery_code'].toString(),
            modelName: modelName,
          ),
        );

        await _queueLocalBatteryMeasurement(
          userId: userId,
          measurement: measurement,
        );
      }
    }
  }

  static Future<void> _queueLocalBatteryMeasurement({
    required String userId,
    required BatteryMeasurement measurement,
  }) async {
    final entityId = BatteryLocalStore.measurementEntityId(
      userId: userId,
      measurement: measurement,
    );

    await BatteryLocalStore.upsertMeasurement(
      userId: userId,
      measurement: measurement,
      forcedLocalKey: entityId,
    );

    await _database.replacePendingSyncOperation(
      userId: userId,
      entityType: 'battery_measurement',
      entityId: entityId,
      operation: 'upsert',
      payloadJson: jsonEncode({'user_id': userId, ...measurement.toJson()}),
    );
  }

  static Future<void> _deleteLocalBatteryHistoryForSession({
    required String userId,
    required String sessionId,
  }) async {
    final measurements = await BatteryLocalStore.getMeasurements(
      userId: userId,
    );
    final marker = 'session:$sessionId';

    for (final measurement in measurements) {
      final notes = measurement.notes ?? '';
      if (!measurement.isEndOfRun || !notes.split('|').contains(marker)) {
        continue;
      }

      final entityId = BatteryLocalStore.measurementEntityId(
        userId: userId,
        measurement: measurement,
      );

      await BatteryLocalStore.markMeasurementDeleted(
        userId: userId,
        measurement: measurement,
      );

      await _database.replacePendingSyncOperation(
        userId: userId,
        entityType: 'battery_measurement',
        entityId: entityId,
        operation: 'delete',
        payloadJson: jsonEncode({
          if (measurement.id != null) 'id': measurement.id,
        }),
      );
    }
  }

  static String _automaticMeasurementNote({
    required String sessionId,
    required DateTime runStartedAt,
    required String batteryCode,
    required String modelName,
  }) {
    return '$_automaticMeasurementNotePrefix$sessionId'
        '|model:$modelName'
        '|run:${runStartedAt.toUtc().toIso8601String()}'
        '|battery:$batteryCode';
  }

  static String _newUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int value) => value.toRadixString(16).padLeft(2, '0');
    final value = bytes.map(hex).join();
    return '${value.substring(0, 8)}-'
        '${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-'
        '${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }

  static List<double> _toDoubleList(dynamic value) {
    if (value is! List) {
      return const [];
    }
    return value
        .whereType<num>()
        .map((item) => item.toDouble())
        .toList(growable: false);
  }

  static DateTime? _parseNullableDate(dynamic value) {
    if (value == null || value.toString().trim().isEmpty) {
      return null;
    }
    return DateTime.parse(value.toString()).toLocal();
  }

  static String? _nullableText(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
