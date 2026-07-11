import '../models/model_setup.dart';
import 'supabase_service.dart';

class ModelSetupService {
  ModelSetupService._();

  static final _client = SupabaseService.client;

  static Future<ModelSetup> getSetup(
    String modelId,
  ) async {
    final response = await _client
        .from('model_setups')
        .select()
        .eq('model_id', modelId)
        .maybeSingle();

    if (response == null) {
      return ModelSetup.empty(modelId);
    }

    return ModelSetup.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<ModelSetup> saveSetup(
    ModelSetup setup,
  ) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw Exception('Aucun utilisateur connecté.');
    }

    final existingSetup = await _client
        .from('model_setups')
        .select('id')
        .eq('model_id', setup.modelId)
        .maybeSingle();

    final data = setup.toDatabaseMap(
      userId: user.id,
    );

    late final Map<String, dynamic> response;

    if (existingSetup == null) {
      final result = await _client
          .from('model_setups')
          .insert(data)
          .select()
          .single();

      response = Map<String, dynamic>.from(result);
    } else {
      final result = await _client
          .from('model_setups')
          .update(data)
          .eq('model_id', setup.modelId)
          .select()
          .single();

      response = Map<String, dynamic>.from(result);
    }

    return ModelSetup.fromMap(response);
  }

  static Future<ModelSetup> restoreOriginalSetup(
    ModelSetup setup,
  ) async {
    final restoredSetup = setup.copyOriginalToCurrent();

    return saveSetup(restoredSetup);
  }
}