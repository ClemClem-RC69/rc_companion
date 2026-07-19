import '../models/battery.dart';
import '../models/rc_model.dart';
import '../models/rc_session.dart';
import 'supabase_service.dart';

class SessionService {
  SessionService._();

  static final _client = SupabaseService.client;

  static const String _automaticMeasurementNotePrefix =
      'Mesure automatique après roulage|session:';

  static Future<List<RcSession>> getSessions({
    required List<RcModel> models,
    required List<Battery> batteries,
  }) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      return [];
    }

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
        .eq('user_id', user.id)
        .order('started_at', ascending: false);

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

    final loadedSessions = <RcSession>[];

    for (final rawSession in response) {
      final sessionRow = Map<String, dynamic>.from(rawSession);
      final modelId = sessionRow['model_id'] as String?;
      final modelName = sessionRow['model_name'] as String?;

      final model = (modelId == null ? null : modelById[modelId]) ??
          (modelName == null ? null : modelByName[modelName]);

      if (model == null) {
        continue;
      }

      final rawRuns = (sessionRow['session_runs'] as List<dynamic>? ?? [])
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList()
        ..sort(
          (a, b) => (a['started_at'] as String)
              .compareTo(b['started_at'] as String),
        );

      final runs = <RcRun>[];

      for (final runRow in rawRuns) {
        final rawBatteryLinks =
            (runRow['session_run_batteries'] as List<dynamic>? ?? [])
                .map((row) => Map<String, dynamic>.from(row as Map))
                .toList()
              ..sort(
                (a, b) => (a['created_at'] as String? ?? '')
                    .compareTo(b['created_at'] as String? ?? ''),
              );

        final runBatteries = <Battery>[];

        for (final batteryLink in rawBatteryLinks) {
          final code = batteryLink['battery_code'] as String?;
          final battery = code == null ? null : batteryByCode[code];

          if (battery != null) {
            runBatteries.add(battery);
          }
        }

        final rawMeasurements =
            (runRow['session_run_measurements'] as List<dynamic>? ?? [])
                .map((row) => Map<String, dynamic>.from(row as Map))
                .toList();

        final readings = rawMeasurements.map(
          (measurementRow) {
            return BatteryRunReading(
              batteryId: measurementRow['battery_code'] as String,
              measuredAt: _parseNullableDate(
                measurementRow['measured_at'],
              ),
              remainingCapacityPercent:
                  (measurementRow['remaining_capacity_percent'] as num?)
                      ?.toDouble(),
              cellVoltages: _toDoubleList(
                measurementRow['cell_voltages'],
              ),
            );
          },
        ).toList(growable: false);

        runs.add(
          RcRun(
            startedAt: DateTime.parse(
              runRow['started_at'] as String,
            ).toLocal(),
            endedAt: _parseNullableDate(runRow['ended_at']),
            durationMinutes:
                (runRow['duration_minutes'] as num?)?.toInt(),
            batteries: List<Battery>.unmodifiable(runBatteries),
            readings: List<BatteryRunReading>.unmodifiable(readings),
            notes: runRow['notes'] as String? ?? '',
          ),
        );
      }

      loadedSessions.add(
        RcSession(
          id: sessionRow['id'] as String,
          model: model,
          startedAt: DateTime.parse(
            sessionRow['started_at'] as String,
          ).toLocal(),
          endedAt: _parseNullableDate(sessionRow['ended_at']),
          runs: List<RcRun>.unmodifiable(runs),
          location: sessionRow['location'] as String? ?? '',
          drivingNotes:
              sessionRow['driving_notes'] as String? ?? '',
          breakages: sessionRow['breakages'] as String? ?? '',
          partsReplacedOnSite:
              sessionRow['parts_replaced_on_site'] as String? ?? '',
          maintenanceToDo:
              sessionRow['maintenance_to_do'] as String? ?? '',
          partsToOrder:
              sessionRow['parts_to_order'] as String? ?? '',
          changesBeforeNextSession:
              sessionRow['changes_before_next_session'] as String? ?? '',
          generalNotes:
              sessionRow['general_notes'] as String? ?? '',
        ),
      );
    }

    return loadedSessions;
  }

  static Future<RcSession> saveSession(RcSession session) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError('Utilisateur non connecté');
    }

    final sessionData = <String, dynamic>{
      'user_id': user.id,
      'model_id': session.model.id,
      'model_name': session.model.name,
      'started_at': session.startedAt.toUtc().toIso8601String(),
      'ended_at': session.endedAt?.toUtc().toIso8601String(),
      'location': _nullableText(session.location),
      'driving_notes': _nullableText(session.drivingNotes),
      'breakages': _nullableText(session.breakages),
      'parts_replaced_on_site':
          _nullableText(session.partsReplacedOnSite),
      'maintenance_to_do': _nullableText(session.maintenanceToDo),
      'parts_to_order': _nullableText(session.partsToOrder),
      'changes_before_next_session':
          _nullableText(session.changesBeforeNextSession),
      'general_notes': _nullableText(session.generalNotes),
    };

    late final String sessionId;

    if (session.id == null || session.id!.trim().isEmpty) {
      final insertedRow = await _client
          .from('rc_sessions')
          .insert(sessionData)
          .select('id')
          .single();

      sessionId = insertedRow['id'] as String;
    } else {
      sessionId = session.id!;

      await _client
          .from('rc_sessions')
          .update(sessionData)
          .eq('id', sessionId)
          .eq('user_id', user.id);
    }

    await _replaceRuns(
      sessionId: sessionId,
      userId: user.id,
      modelName: session.model.name,
      runs: session.runs,
    );

    return session.copyWith(id: sessionId);
  }

  static Future<void> deleteSession(String sessionId) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError('Utilisateur non connecté');
    }

    await _deleteAutomaticBatteryMeasurements(
      sessionId: sessionId,
      userId: user.id,
    );

    await _client
        .from('rc_sessions')
        .delete()
        .eq('id', sessionId)
        .eq('user_id', user.id);
  }

  static Future<void> _replaceRuns({
    required String sessionId,
    required String userId,
    required String modelName,
    required List<RcRun> runs,
  }) async {
    // Les roulages sont entièrement recréés à chaque sauvegarde.
    // On supprime donc d'abord les relevés automatiques précédemment générés
    // pour cette session afin d'éviter les doublons dans l'historique batterie.
    await _deleteAutomaticBatteryMeasurements(
      sessionId: sessionId,
      userId: userId,
    );

    await _client
        .from('session_runs')
        .delete()
        .eq('session_id', sessionId);

    for (final run in runs) {
      final insertedRun = await _client
          .from('session_runs')
          .insert({
            'session_id': sessionId,
            'started_at': run.startedAt.toUtc().toIso8601String(),
            'ended_at': run.endedAt?.toUtc().toIso8601String(),
            'duration_minutes': run.durationMinutes,
            'notes': _nullableText(run.notes),
          })
          .select('id')
          .single();

      final runId = insertedRun['id'] as String;

      if (run.batteries.isNotEmpty) {
        await _client.from('session_run_batteries').insert(
              run.batteries
                  .map(
                    (battery) => {
                      'run_id': runId,
                      'battery_code': battery.id,
                    },
                  )
                  .toList(),
            );
      }

      final validReadings = run.readings
          .where((reading) => reading.hasMeasurements)
          .toList(growable: false);

      if (validReadings.isNotEmpty) {
        await _client.from('session_run_measurements').insert(
              validReadings
                  .map(
                    (reading) => {
                      'run_id': runId,
                      'user_id': userId,
                      'battery_code': reading.batteryId,
                      'measured_at':
                          _measurementDate(reading, run)
                              .toUtc()
                              .toIso8601String(),
                      'remaining_capacity_percent':
                          reading.remainingCapacityPercent,
                      'temperature_celsius': null,
                      'cell_voltages': reading.cellVoltages,
                      'cell_resistances': const <double>[],
                      'updated_at':
                          DateTime.now().toUtc().toIso8601String(),
                    },
                  )
                  .toList(),
            );

        final batteryHistoryRows = validReadings
            .where(_canCreateBatteryHistoryMeasurement)
            .map(
              (reading) => {
                'user_id': userId,
                'battery_code': reading.batteryId,
                'measured_at':
                    _measurementDate(reading, run)
                        .toUtc()
                        .toIso8601String(),
                // La base Supabase conserve temporairement l'ancien libellé autorisé.
                // BatteryMeasurement le convertit en « Relevé fin de roulage » à la lecture.
                'measurement_type': 'Fin de session',
                'charge_percent':
                    reading.remainingCapacityPercent!
                        .round()
                        .clamp(0, 100),
                'cell_voltages': reading.cellVoltages,
                'cell_internal_resistances': const <double>[],
                'battery_temperature_c': null,
                'notes': _automaticMeasurementNote(
                  sessionId: sessionId,
                  run: run,
                  batteryCode: reading.batteryId,
                  modelName: modelName,
                ),
              },
            )
            .toList(growable: false);

        if (batteryHistoryRows.isNotEmpty) {
          await _client
              .from('battery_measurements')
              .insert(batteryHistoryRows);
        }
      }
    }
  }

  static bool _canCreateBatteryHistoryMeasurement(
    BatteryRunReading reading,
  ) {
    return reading.isCompleteEndOfRunReading;
  }

  static DateTime _measurementDate(
    BatteryRunReading reading,
    RcRun run,
  ) {
    return reading.measuredAt ??
        run.endedAt ??
        run.startedAt.add(
          Duration(minutes: run.effectiveDurationMinutes),
        );
  }

  static String _automaticMeasurementNote({
    required String sessionId,
    required RcRun run,
    required String batteryCode,
    required String modelName,
  }) {
    return '$_automaticMeasurementNotePrefix$sessionId'
        '|model:$modelName'
        '|run:${run.startedAt.toUtc().toIso8601String()}'
        '|battery:$batteryCode';
  }

  static Future<void> _deleteAutomaticBatteryMeasurements({
    required String sessionId,
    required String userId,
  }) async {
    await _client
        .from('battery_measurements')
        .delete()
        .eq('user_id', userId)
        .like(
          'notes',
          '$_automaticMeasurementNotePrefix$sessionId%',
        );
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
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();

    if (text.isEmpty) {
      return null;
    }

    return DateTime.parse(text).toLocal();
  }

  static String? _nullableText(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
