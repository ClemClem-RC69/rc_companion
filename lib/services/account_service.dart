import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import 'google_drive_service.dart';
import 'supabase_service.dart';

class AccountService {
  AccountService._();

  static final _client = SupabaseService.client;
  static final _database = AppDatabase.instance;

  static Future<bool> isOnline() async {
    final connectivity = await Connectivity().checkConnectivity();
    return connectivity.isNotEmpty &&
        connectivity.any((result) => result != ConnectivityResult.none);
  }

  static Future<User> refreshUser() async {
    if (!await isOnline()) {
      final user = _client.auth.currentUser;
      if (user == null) {
        throw const AuthException('Aucun utilisateur connecté.');
      }
      return user;
    }

    final response = await _client.auth.getUser();
    final user = response.user;
    if (user == null) {
      throw const AuthException('Aucun utilisateur connecté.');
    }
    return user;
  }

  static Future<User> updatePseudo(String pseudo) async {
    final cleanPseudo = pseudo.trim();

    if (cleanPseudo.length < 3) {
      throw const AuthException(
        'Le pseudo doit contenir au moins 3 caractères.',
      );
    }

    if (!await isOnline()) {
      throw const AuthException(
        'Une connexion Internet est requise pour modifier le pseudo.',
      );
    }

    final response = await _client.auth.updateUser(
      UserAttributes(data: {'pseudo': cleanPseudo}),
    );

    final user = response.user;
    if (user == null) {
      throw const AuthException(
        'Impossible de récupérer le compte après la modification du pseudo.',
      );
    }
    return user;
  }

  static Future<void> updatePassword(String password) async {
    if (password.length < 6) {
      throw const AuthException(
        'Le mot de passe doit contenir au moins 6 caractères.',
      );
    }

    if (!await isOnline()) {
      throw const AuthException(
        'Une connexion Internet est requise pour modifier le mot de passe.',
      );
    }

    await _client.auth.updateUser(UserAttributes(password: password));
  }

  static DateTime? resetAtFromUser(User? user) {
    final raw = user?.userMetadata?['data_reset_at']?.toString();
    return raw == null ? null : DateTime.tryParse(raw)?.toUtc();
  }

  static Future<bool> applyRemoteResetIfNeeded() async {
    if (!await isOnline()) {
      return false;
    }

    final response = await _client.auth.getUser();
    final user = response.user;
    if (user == null) {
      return false;
    }

    final resetAt = resetAtFromUser(user);

    if (resetAt == null) {
      return false;
    }

    final handledAt = await _database.getHandledResetAt(userId: user.id);
    if (handledAt != null && !handledAt.toUtc().isBefore(resetAt.toUtc())) {
      return false;
    }

    await _database.clearUserData(userId: user.id);
    await _database.markResetHandled(userId: user.id, resetAt: resetAt);
    return true;
  }

  static Future<void> resetApplicationData() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw const AuthException('Aucun utilisateur connecté.');
    }

    if (!await isOnline()) {
      throw const AuthException(
        'Le RESET nécessite une connexion Internet afin de supprimer les '
        'données synchronisées sur tous les appareils.',
      );
    }

    final resetAt = DateTime.now().toUtc();

    // Le marqueur est enregistré AVANT les suppressions. Les autres appareils
    // le verront avant d'envoyer leur ancienne file de synchronisation.
    await _client.auth.updateUser(
      UserAttributes(
        data: {
          ...?user.userMetadata,
          'data_reset_at': resetAt.toIso8601String(),
        },
      ),
    );

    // Les fichiers lourds de RC Companion sont stockés uniquement
    // sur Google Drive. Le RESET doit les supprimer avant les métadonnées
    // Supabase afin de garantir un effacement complet.
    final driveState = await GoogleDriveService.connectionState();
    if (!driveState.connected) {
      throw const AuthException(
        'Google Drive doit être connecté pour effectuer un RESET complet.',
      );
    }

    await GoogleDriveService.resetRcCompanionFiles();

    // Sessions : les tables enfants ne portent pas toutes user_id.
    final sessions = await _client
        .from('rc_sessions')
        .select('id')
        .eq('user_id', user.id);

    for (final rawSession in sessions) {
      final sessionId = rawSession['id']?.toString();
      if (sessionId == null || sessionId.isEmpty) {
        continue;
      }

      final runs = await _client
          .from('session_runs')
          .select('id')
          .eq('session_id', sessionId);

      for (final rawRun in runs) {
        final runId = rawRun['id']?.toString();
        if (runId == null || runId.isEmpty) {
          continue;
        }

        await _client
            .from('session_run_measurements')
            .delete()
            .eq('run_id', runId);
        await _client
            .from('session_run_batteries')
            .delete()
            .eq('run_id', runId);
      }

      await _client.from('session_runs').delete().eq('session_id', sessionId);
    }

    await _client.from('rc_sessions').delete().eq('user_id', user.id);

    // Données directement rattachées au compte.
    await _client.from('maintenance_records').delete().eq('user_id', user.id);
    await _client.from('model_history_events').delete().eq('user_id', user.id);
    await _client.from('model_documents').delete().eq('user_id', user.id);
    await _client.from('model_radio_setups').delete().eq('user_id', user.id);
    await _client.from('model_setups').delete().eq('user_id', user.id);
    await _client.from('radios').delete().eq('user_id', user.id);
    await _client.from('battery_measurements').delete().eq('user_id', user.id);
    await _client.from('batteries').delete().eq('user_id', user.id);
    await _client.from('rc_models').delete().eq('user_id', user.id);

    // La file locale est supprimée en dernier pour empêcher un ancien élément
    // hors ligne de recréer des données après le RESET.
    await _database.clearUserData(userId: user.id);
    await _database.markResetHandled(userId: user.id, resetAt: resetAt);
  }
}
