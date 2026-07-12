import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/radio.dart';

class RadioService {
  RadioService({
    SupabaseClient? client,
  }) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<RcRadio>> fetchRadios() async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError(
        'Aucun utilisateur connecté.',
      );
    }

    final response = await _client
        .from('radios')
        .select()
        .eq('user_id', user.id)
        .order('brand')
        .order('model');

    return (response as List<dynamic>)
        .map(
          (item) => RcRadio.fromMap(
            item as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<RcRadio> addRadio({
    required String brand,
    required String model,
    required String level,
    required String type,
    required int channels,
    required List<String> protocols,
    required bool programmable,
  }) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError(
        'Aucun utilisateur connecté.',
      );
    }

    final response = await _client
        .from('radios')
        .insert({
          'user_id': user.id,
          'brand': brand,
          'model': model,
          'level': level,
          'type': type,
          'channels': channels,
          'protocols': protocols,
          'programmable': programmable,
        })
        .select()
        .single();

    return RcRadio.fromMap(
      response,
    );
  }

  Future<void> deleteRadio(
    String radioId,
  ) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError(
        'Aucun utilisateur connecté.',
      );
    }

    await _client
        .from('radios')
        .delete()
        .eq('id', radioId)
        .eq('user_id', user.id);
  }

  Future<bool> radioAlreadyExists({
    required String brand,
    required String model,
  }) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError(
        'Aucun utilisateur connecté.',
      );
    }

    final response = await _client
        .from('radios')
        .select('id')
        .eq('user_id', user.id)
        .eq('brand', brand)
        .eq('model', model)
        .limit(1);

    return (response as List<dynamic>).isNotEmpty;
  }
}