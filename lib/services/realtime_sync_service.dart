import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'battery_service.dart';
import 'battery_sync_service.dart';
import 'maintenance_service.dart';
import 'model_document_service.dart';
import 'model_local_store.dart';
import 'model_radio_setup_service.dart';
import 'model_setup_service.dart';
import 'radio_service.dart';
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
  static StreamSubscription<List<ConnectivityResult>>?
  _connectivitySubscription;
  static RealtimeChannel? _channel;
  static _RealtimeLifecycleObserver? _lifecycleObserver;

  static Timer? _modelsDebounce;
  static Timer? _batteriesDebounce;
  static Timer? _sessionsDebounce;
  static Timer? _maintenanceDebounce;
  static Timer? _radiosDebounce;
  static Timer? _documentsDebounce;
  static Timer? _setupsDebounce;
  static Timer? _radioSetupsDebounce;
  static Timer? _recoveryDebounce;

  static bool _started = false;
  static bool _restartRunning = false;
  static bool _restartRequested = false;
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

      // Un renouvellement de session peut arriver sans changement d'utilisateur.
      // On profite de tout nouvel état authentifié pour garantir que le canal
      // Realtime est réellement recréé si le socket a été perdu.
      unawaited(_restartForUser(userId));
    });

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      final online = results.any((result) => result != ConnectivityResult.none);
      if (online) {
        _scheduleRecovery();
      }
    });

    _lifecycleObserver = _RealtimeLifecycleObserver(_scheduleRecovery);
    WidgetsBinding.instance.addObserver(_lifecycleObserver!);

    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId != null && userId.isNotEmpty) {
      await _restartForUser(userId);
    }
  }

  static Future<void> dispose() async {
    _cancelDebounces();
    _recoveryDebounce?.cancel();
    _recoveryDebounce = null;
    await _authSubscription?.cancel();
    _authSubscription = null;
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    final observer = _lifecycleObserver;
    if (observer != null) {
      WidgetsBinding.instance.removeObserver(observer);
    }
    _lifecycleObserver = null;
    await _stopChannel();
    _started = false;
  }

  static void _scheduleRecovery() {
    _recoveryDebounce?.cancel();
    _recoveryDebounce = Timer(const Duration(milliseconds: 250), () {
      final userId = SupabaseService.client.auth.currentUser?.id;
      if (userId == null || userId.isEmpty) {
        return;
      }
      unawaited(_restartForUser(userId));
    });
  }

  static Future<void> _restartForUser(String userId) async {
    if (_restartRunning) {
      _restartRequested = true;
      return;
    }

    _restartRunning = true;
    try {
      var targetUserId = userId;
      do {
        _restartRequested = false;
        final currentUserId = SupabaseService.client.auth.currentUser?.id;
        if (currentUserId == null || currentUserId.isEmpty) {
          await _stopChannel();
          return;
        }
        targetUserId = currentUserId;
        await _startForUser(targetUserId);
      } while (_restartRequested);
    } finally {
      _restartRunning = false;
    }
  }

  static Future<void> _flushPendingWrites() async {
    try {
      await BatterySyncService.syncNow();
    } catch (_) {
      // Si le réseau vient de disparaître, les opérations restent dans la queue.
    }
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
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'radios',
          callback: (_) => _scheduleRadiosRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'model_documents',
          callback: (_) => _scheduleDocumentsRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'model_setups',
          callback: (_) => _scheduleSetupsRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'model_radio_setups',
          callback: (_) => _scheduleRadioSetupsRefresh(),
        );

    _channel = channel;
    channel.subscribe();

    // Réconciliation immédiate : on envoie d'abord les écritures locales
    // en attente, puis on recharge les caches Drift depuis le cloud. Cela évite
    // qu'un retour réseau écrase temporairement une modification locale non
    // encore envoyée.
    await _flushPendingWrites();

    _scheduleModelsRefresh(immediate: true);
    _scheduleBatteriesRefresh(immediate: true);
    _scheduleSessionsRefresh(immediate: true);
    _scheduleMaintenanceRefresh(immediate: true);
    _scheduleRadiosRefresh(immediate: true);
    _scheduleDocumentsRefresh(immediate: true);
    _scheduleSetupsRefresh(immediate: true);
    _scheduleRadioSetupsRefresh(immediate: true);
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
    _radiosDebounce?.cancel();
    _radiosDebounce = null;
    _documentsDebounce?.cancel();
    _documentsDebounce = null;
    _setupsDebounce?.cancel();
    _setupsDebounce = null;
    _radioSetupsDebounce?.cancel();
    _radioSetupsDebounce = null;
  }

  static void _scheduleModelsRefresh({bool immediate = false}) {
    _modelsDebounce?.cancel();
    _modelsDebounce = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 120),
      () async {
        try {
          await _flushPendingWrites();
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
          await _flushPendingWrites();
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
          await _flushPendingWrites();
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
          await _flushPendingWrites();
          await MaintenanceService.refreshFromCloud();
        } catch (_) {
          // Hors ligne : le cache Drift existant reste affiché.
        }
      },
    );
  }

  static void _scheduleRadiosRefresh({bool immediate = false}) {
    _radiosDebounce?.cancel();
    _radiosDebounce = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 120),
      () async {
        try {
          await _flushPendingWrites();
          await RadioService().refreshRadios();
        } catch (_) {}
      },
    );
  }

  static void _scheduleDocumentsRefresh({bool immediate = false}) {
    _documentsDebounce?.cancel();
    _documentsDebounce = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 160),
      () async {
        final user = SupabaseService.client.auth.currentUser;
        if (user == null) return;

        try {
          await _flushPendingWrites();
          final models = await ModelLocalStore.getModels(userId: user.id);
          for (final model in models) {
            final modelId = model.id?.trim();
            if (modelId != null && modelId.isNotEmpty) {
              await ModelDocumentService.refreshDocuments(modelId);
            }
          }
        } catch (_) {}
      },
    );
  }

  static void _scheduleSetupsRefresh({bool immediate = false}) {
    _setupsDebounce?.cancel();
    _setupsDebounce = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 140),
      () async {
        final user = SupabaseService.client.auth.currentUser;
        if (user == null) return;

        try {
          await _flushPendingWrites();
          final models = await ModelLocalStore.getModels(userId: user.id);
          for (final model in models) {
            final modelId = model.id?.trim();
            if (modelId != null && modelId.isNotEmpty) {
              await ModelSetupService.refreshSetup(modelId);
            }
          }
        } catch (_) {}
      },
    );
  }

  static void _scheduleRadioSetupsRefresh({bool immediate = false}) {
    _radioSetupsDebounce?.cancel();
    _radioSetupsDebounce = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 140),
      () async {
        final user = SupabaseService.client.auth.currentUser;
        if (user == null) return;

        try {
          await _flushPendingWrites();
          final models = await ModelLocalStore.getModels(userId: user.id);
          final service = ModelRadioSetupService();
          for (final model in models) {
            final modelId = model.id?.trim();
            if (modelId != null && modelId.isNotEmpty) {
              await service.refreshSetup(modelId: modelId);
            }
          }
        } catch (_) {}
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

class _RealtimeLifecycleObserver extends WidgetsBindingObserver {
  _RealtimeLifecycleObserver(this.onResume);

  final VoidCallback onResume;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      onResume();
    }
  }
}
