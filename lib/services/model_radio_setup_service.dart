import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/model_radio_setup.dart';

class ModelRadioSetupService {
  ModelRadioSetupService({
    SupabaseClient? client,
  }) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<ModelRadioSetup?> getSetup({
    required String modelId,
  }) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError(
        'Aucun utilisateur connecté.',
      );
    }

    final response = await _client
        .from('model_radio_setups')
        .select()
        .eq('user_id', user.id)
        .eq('model_id', modelId)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return ModelRadioSetup.fromMap(response);
  }

  Future<ModelRadioSetup> saveSetup(
    ModelRadioSetup setup,
  ) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError(
        'Aucun utilisateur connecté.',
      );
    }

    final normalizedValues = <String, String>{};

    for (final fieldKey in setup.enabledFields) {
      normalizedValues[fieldKey] =
          setup.values[fieldKey]?.trim() ?? '';
    }

    final response = await _client
        .from('model_radio_setups')
        .upsert(
          {
            'user_id': user.id,
            'model_id': setup.modelId,
            'radio_id': setup.radioId,
            'enabled_fields': List<String>.from(
              setup.enabledFields,
            ),
            'values': normalizedValues,
            'updated_at': DateTime.now().toIso8601String(),
          },
          onConflict: 'model_id',
        )
        .select()
        .single();

    return ModelRadioSetup.fromMap(response);
  }

  Future<void> deleteSetup({
    required String modelId,
  }) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError(
        'Aucun utilisateur connecté.',
      );
    }

    await _client
        .from('model_radio_setups')
        .delete()
        .eq('user_id', user.id)
        .eq('model_id', modelId);
  }
}