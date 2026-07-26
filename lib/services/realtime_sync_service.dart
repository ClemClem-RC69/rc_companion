import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'battery_service.dart';
import 'model_service.dart';
import 'supabase_service.dart';

/// Pont temps réel global pour les données Drift.
///
/// Architecture :
/// Supabase Realtime -> refresh ciblé cloud -> Drift -> streams UI.
///
/// Les écritures locales restent Drift-first et continuent d'être envoyées
/// par la SyncQueue existante. Ce service sert uniquement à faire arriver
/// immédiatement sur cet appareil les changements effectués sur les autres
/// supports.
class RealtimeSyncService {
  RealtimeSyncService._();

  static StreamSubscription<AuthState>? _authSubscription;
  static RealtimeChannel? _channel;

  static Timer? _modelsDebounce;
  static Timer? _batteriesDebounce;

  static bool _started = false;
  static String? _subscribedUserId;

  static Future<void> initialize() async {
    if (_started) {
      return;
    }
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
    _modelsDebounce?.cancel();
    _modelsDebounce = null;
    _batteriesDebounce?.cancel();
    _batteriesDebounce = null;

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
        );

    _channel = channel;
    channel.subscribe();

    // À la connexion/authentification, on rapproche immédiatement Drift de
    // l'état distant. Les stores locaux protègent déjà les entités qui ont
    // une opération de synchronisation en attente.
    _scheduleModelsRefresh(immediate: true);
    _scheduleBatteriesRefresh(immediate: true);
  }

  static Future<void> _stopChannel() async {
    _modelsDebounce?.cancel();
    _modelsDebounce = null;
    _batteriesDebounce?.cancel();
    _batteriesDebounce = null;

    final channel = _channel;
    _channel = null;
    _subscribedUserId = null;

    if (channel != null) {
      try {
        await SupabaseService.client.removeChannel(channel);
      } catch (_) {
        // Le canal peut déjà être fermé lors d'une déconnexion réseau/auth.
      }
    }
  }

  static void _scheduleModelsRefresh({bool immediate = false}) {
    _modelsDebounce?.cancel();
    _modelsDebounce = Timer(
      immediate ? Duration.zero : const Duration(milliseconds: 120),
      () async {
        try {
          await ModelService.refreshModels();
        } catch (_) {
          // Hors ligne : Drift reste la source locale.
        }
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
        } catch (_) {
          // Hors ligne : Drift reste la source locale.
        }
      },
    );
  }
}
