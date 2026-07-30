import 'dart:convert';

import '../database/app_database.dart';
import 'session_local_store.dart';
import 'supabase_service.dart';

class SessionSyncService {
  SessionSyncService._();

  static final _client = SupabaseService.client;

  static Future<void> syncEntry(SyncQueueEntry entry) async {
    final payload = entry.payloadJson == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(entry.payloadJson!) as Map);

    if (entry.operation == 'delete') {
      await _deleteSessionRemote(
        userId: entry.userId,
        sessionId: entry.entityId,
      );
      return;
    }

    await _upsertSessionRemote(
      userId: entry.userId,
      sessionId: entry.entityId,
      payload: payload,
    );
  }

  static Future<void> _upsertSessionRemote({
    required String userId,
    required String sessionId,
    required Map<String, dynamic> payload,
  }) async {
    final sessionData = <String, dynamic>{
      'id': sessionId,
      'user_id': userId,
      'model_id': payload['model_id'],
      'model_name': payload['model_name'],
      'started_at': payload['started_at'],
      'ended_at': payload['ended_at'],
      'location': payload['location'],
      'driving_notes': payload['driving_notes'],
      'breakages': payload['breakages'],
      'parts_replaced_on_site': payload['parts_replaced_on_site'],
      'maintenance_to_do': payload['maintenance_to_do'],
      'parts_to_order': payload['parts_to_order'],
      'changes_before_next_session': payload['changes_before_next_session'],
      'general_notes': payload['general_notes'],
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    final existing = await _client
        .from('rc_sessions')
        .select('id')
        .eq('user_id', userId)
        .eq('id', sessionId)
        .maybeSingle();

    if (existing == null) {
      await _client.from('rc_sessions').insert(sessionData);
    } else {
      final updateData = Map<String, dynamic>.from(sessionData)..remove('id');
      await _client
          .from('rc_sessions')
          .update(updateData)
          .eq('user_id', userId)
          .eq('id', sessionId);
    }

    await _replaceRuns(
      userId: userId,
      sessionId: sessionId,
      rawRuns: (payload['session_runs'] as List<dynamic>? ?? const []),
    );

    final refreshed = await _client
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
        .eq('id', sessionId)
        .single();

    await SessionLocalStore.upsertSessionRow(
      userId: userId,
      row: Map<String, dynamic>.from(refreshed),
    );
  }

  static Future<void> _deleteSessionRemote({
    required String userId,
    required String sessionId,
  }) async {
    await _client
        .from('rc_sessions')
        .delete()
        .eq('user_id', userId)
        .eq('id', sessionId);
  }

  static Future<void> _replaceRuns({
    required String userId,
    required String sessionId,
    required List<dynamic> rawRuns,
  }) async {
    await _client.from('session_runs').delete().eq('session_id', sessionId);

    for (final rawRun in rawRuns) {
      final run = Map<String, dynamic>.from(rawRun as Map);
      final insertedRun = await _client
          .from('session_runs')
          .insert({
            'session_id': sessionId,
            'started_at': run['started_at'],
            'ended_at': run['ended_at'],
            'duration_minutes': run['duration_minutes'],
            'notes': run['notes'],
            'historical_batteries':
                run['historical_batteries'] ?? const <dynamic>[],
          })
          .select('id')
          .single();

      final runId = insertedRun['id'] as String;
      final batteryLinks =
          (run['session_run_batteries'] as List<dynamic>? ?? [])
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList(growable: false);

      if (batteryLinks.isNotEmpty) {
        await _client
            .from('session_run_batteries')
            .insert(
              batteryLinks
                  .map(
                    (item) => {
                      'run_id': runId,
                      'battery_code': item['battery_code'],
                    },
                  )
                  .toList(growable: false),
            );
      }

      final measurements =
          (run['session_run_measurements'] as List<dynamic>? ?? [])
              .map((item) => Map<String, dynamic>.from(item as Map))
              .where(_hasMeasurement)
              .toList(growable: false);

      if (measurements.isNotEmpty) {
        await _client
            .from('session_run_measurements')
            .insert(
              measurements
                  .map(
                    (item) => {
                      'run_id': runId,
                      'user_id': userId,
                      'battery_code': item['battery_code'],
                      'measured_at': item['measured_at'],
                      'remaining_capacity_percent':
                          item['remaining_capacity_percent'],
                      'temperature_celsius': item['temperature_celsius'],
                      'cell_voltages':
                          item['cell_voltages'] ?? const <double>[],
                      'cell_resistances': const <double>[],
                      'updated_at': DateTime.now().toUtc().toIso8601String(),
                    },
                  )
                  .toList(growable: false),
            );
      }
    }
  }

  static bool _hasMeasurement(Map<String, dynamic> item) {
    return item['remaining_capacity_percent'] != null ||
        (item['cell_voltages'] is List &&
            (item['cell_voltages'] as List).isNotEmpty);
  }
}
