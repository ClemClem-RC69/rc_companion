import 'dart:async';
import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import '../models/model_radio_setup.dart';
import 'model_radio_setup_local_store.dart';

class ModelRadioSetupService {
  ModelRadioSetupService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static final AppDatabase _database = AppDatabase.instance;

  Future<ModelRadioSetup?> getSetup({required String modelId}) async {
    final user = _requireUser();

    final local = await ModelRadioSetupLocalStore.getSetup(
      userId: user.id,
      modelId: modelId,
    );

    if (local != null) {
      unawaited(_refreshFromRemote(userId: user.id, modelId: modelId));
      return local;
    }

    try {
      return await _refreshFromRemote(userId: user.id, modelId: modelId);
    } catch (_) {
      return null;
    }
  }

  Future<ModelRadioSetup> saveSetup(ModelRadioSetup setup) async {
    final user = _requireUser();
    final now = DateTime.now().toUtc();

    final normalizedValues = <String, String>{
      for (final fieldKey in setup.enabledFields)
        fieldKey: setup.values[fieldKey]?.trim() ?? '',
    };

    final saved = ModelRadioSetup(
      modelId: setup.modelId,
      radioId: setup.radioId,
      enabledFields: List<String>.from(setup.enabledFields),
      values: normalizedValues,
      updatedAt: now,
    );

    final row = ModelRadioSetupLocalStore.setupToRow(
      userId: user.id,
      setup: saved,
    );

    await _database.transaction(() async {
      await ModelRadioSetupLocalStore.upsertRow(userId: user.id, row: row);

      await _database.replacePendingSyncOperation(
        userId: user.id,
        entityType: 'model_radio_setup',
        entityId: setup.modelId,
        operation: 'upsert',
        payloadJson: jsonEncode(row),
      );
    });

    return saved;
  }

  Future<void> deleteSetup({required String modelId}) async {
    final user = _requireUser();

    final existing = await ModelRadioSetupLocalStore.getSetup(
      userId: user.id,
      modelId: modelId,
    );

    await _database.transaction(() async {
      await ModelRadioSetupLocalStore.markDeleted(
        userId: user.id,
        modelId: modelId,
        existingSetup: existing,
      );

      await _database.replacePendingSyncOperation(
        userId: user.id,
        entityType: 'model_radio_setup',
        entityId: modelId,
        operation: 'delete',
      );
    });
  }

  Future<ModelRadioSetup?> _refreshFromRemote({
    required String userId,
    required String modelId,
  }) async {
    final response = await _client
        .from('model_radio_setups')
        .select()
        .eq('user_id', userId)
        .eq('model_id', modelId)
        .maybeSingle();

    final remoteRow = response == null
        ? null
        : Map<String, dynamic>.from(response);

    await ModelRadioSetupLocalStore.replaceRemoteSetup(
      userId: userId,
      modelId: modelId,
      remoteRow: remoteRow,
    );

    if (remoteRow == null) {
      return null;
    }

    return ModelRadioSetup.fromMap(remoteRow);
  }

  User _requireUser() {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError('Aucun utilisateur connecté.');
    }

    return user;
  }
}
