import 'dart:async';
import 'dart:convert';

import '../database/app_database.dart';
import '../models/model_setup.dart';
import 'battery_sync_service.dart';
import 'model_setup_local_store.dart';
import 'supabase_service.dart';

class ModelSetupService {
  ModelSetupService._();

  static final _client = SupabaseService.client;
  static final _database = AppDatabase.instance;

  static Future<ModelSetup> getSetup(String modelId) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('Aucun utilisateur connecté.');
    }

    final cached = await ModelSetupLocalStore.getSetup(
      userId: user.id,
      modelId: modelId,
    );

    if (cached != null) {
      unawaited(_refreshSetupSilently(userId: user.id, modelId: modelId));
      return cached;
    }

    try {
      return await _refreshSetupFromCloud(userId: user.id, modelId: modelId);
    } catch (_) {
      return ModelSetup.empty(modelId);
    }
  }

  static Future<ModelSetup> saveSetup(ModelSetup setup) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('Aucun utilisateur connecté.');
    }

    await ModelSetupLocalStore.upsertSetup(userId: user.id, setup: setup);

    final payload = setup.toDatabaseMap(userId: user.id);
    await _database.replacePendingSyncOperation(
      userId: user.id,
      entityType: 'model_setup',
      entityId: setup.modelId,
      operation: 'upsert',
      payloadJson: jsonEncode(payload),
    );

    unawaited(BatterySyncService.syncNow());
    return setup;
  }

  static Future<ModelSetup> restoreOriginalSetup(ModelSetup setup) {
    return saveSetup(setup.copyOriginalToCurrent());
  }

  static Future<void> _refreshSetupSilently({
    required String userId,
    required String modelId,
  }) async {
    try {
      await _refreshSetupFromCloud(userId: userId, modelId: modelId);
    } catch (_) {
      // Le cache Drift reste la source d'affichage hors ligne.
    }
  }

  static Future<ModelSetup> _refreshSetupFromCloud({
    required String userId,
    required String modelId,
  }) async {
    final response = await _client
        .from('model_setups')
        .select()
        .eq('user_id', userId)
        .eq('model_id', modelId)
        .maybeSingle()
        .timeout(const Duration(seconds: 8));

    final row = response == null ? null : Map<String, dynamic>.from(response);

    await ModelSetupLocalStore.replaceSetupFromCloud(
      userId: userId,
      modelId: modelId,
      row: row,
    );

    return row == null ? ModelSetup.empty(modelId) : ModelSetup.fromMap(row);
  }
}
