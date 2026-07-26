import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'battery_service.dart';
import 'maintenance_service.dart';
import 'model_service.dart';
import 'session_local_store.dart';
import 'supabase_service.dart';

/// Pont temps réel global RC Companion.
///
/// Supabase Realtime -> rapprochement cloud ciblé -> Drift -> streams UI.
///
/// Les écritures locales restent Drift-first via la SyncQueue existante.
class RealtimeSyncService {
  RealtimeSyncService._();

  static StreamSubscription<AuthState>? _authSubscription;
  static RealtimeChannel? _channel;

  static Timer? _modelsDebounce;
  static Timer? _batteriesDebounce;
  static Timer? _sessionsDebounce;
  static Timer? _maintenanceDebounce;

  static bool _started = false;
  static String? _subscribedUserId;

  static Future<void> initialize() async {
    if (_started) return;
    _started = true;

    _authSubscription = SupabaseService.client.auth.onAuthStateChange.listen((
      state,
    ) {
      final userId = state.session?.user.id;
      if (userId == null || userId.isEmpty) {
        unawaited(_stopChannel());
        return;
      }
      if (_subscribedUserId != userId) {
        unawaited(_startForUser(userId));
      }
    });

    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId != null && userId.isNotEmpty) {
      await _startForUser(userId);
    }
  }

  static Future<void> dispose() async {
    _cancelDebounces();
    await _authSubscription?.cancel();
    _authSubscription = null;
    await _stopChannel();
    _started = false;
  }

  static Future<void> _startForUser(String userId) async {
    await _stopChannel();
    _subscribedUserId = userId;

    final channel = SupabaseService.client
        .channel('rc-companion-realtime-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rc_models',
          callback: (_) => _scheduleModelsRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'batteries',
          callback: (_) => _scheduleBatteriesRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'battery_measurements',
          callback: (_) => _scheduleBatteriesRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rc_sessions',
          callback: (_) => _scheduleSessionsRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'session_runs',
          callback: (_) => _scheduleSessionsRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'session_run_batteries',
          callback: (_) => _scheduleSessionsRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'session_run_measurements',
          callback: (_) {
            _scheduleSessionsRefresh();
            _scheduleBatteriesRefresh();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'maintenance_records',
          callback: (_) => _scheduleMaintenanceRefresh(),
        );

    _channel = channel;
    channel.subscribe();

    _scheduleModelsRefresh(immediate: true);
    _scheduleBatteriesRefresh(immediate: true);
    _scheduleSessionsRefresh(immediate: true);
    _scheduleMaintenanceRefresh(immediate: true);
  }

  static Future<void> _stopChannel() async {
    _cancelDebounces();

    final channel = _channel;
    _channel = null;
    _subscribedUserId = null;

    if (channel != null) {
      try {
        await SupabaseService.client.removeChannel(channel);
      } catch (_) {
        // Le canal peut déjà être fermé lors d'une coupure réseau/auth.
      }
    }
  }

  static void _cancelDebounces() {
    _modelsDebounce?.cancel();
    _modelsDebounce = null;
    _batteriesDebounce?.cancel();
    _batteriesDebounce = null;
    _sessionsDebounce?.cancel();
    _sessionsDebounce = null;
    _maintenanceDebounce?.cancel();
    _maintenanceDebounce = null;
  }

  static void _scheduleModelsRefresh({bool immediate = false}) {
    _modelsDebounce?.cancel();
    _modelsDebounce = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 120),
      () async {
        try {
          await ModelService.refreshModels();
        } catch (_) {}
      },
    );
  }

  static void _scheduleBatteriesRefresh({bool immediate = false}) {
    _batteriesDebounce?.cancel();
    _batteriesDebounce = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 120),
      () async {
        try {
          await BatteryService.refreshBatteries();
        } catch (_) {}
      },
    );
  }

  static void _scheduleSessionsRefresh({bool immediate = false}) {
    _sessionsDebounce?.cancel();
    _sessionsDebounce = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 180),
      () async {
        try {
          await _refreshSessionsFromCloud();
        } catch (_) {
          // Hors ligne : le cache Drift existant reste affiché.
        }
      },
    );
  }

  static void _scheduleMaintenanceRefresh({bool immediate = false}) {
    _maintenanceDebounce?.cancel();
    _maintenanceDebounce = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 120),
      () async {
        try {
          await MaintenanceService.refreshFromCloud();
        } catch (_) {
          // Hors ligne : le cache Drift existant reste affiché.
        }
      },
    );
  }

  static Future<void> _refreshSessionsFromCloud() async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) return;

    final response = await SupabaseService.client
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
        .order('started_at', ascending: false)
        .timeout(const Duration(seconds: 8));

    final rows = response
        .map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);

    await SessionLocalStore.replaceSessions(userId: user.id, rows: rows);
  }
}
