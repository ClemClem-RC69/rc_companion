import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/radio_profile.dart';

class RadioProfileService {
  RadioProfileService({
    SupabaseClient? client,
  }) : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<RadioProfile>> fetchProfiles({
    required String radioId,
  }) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError(
        'Aucun utilisateur connecté.',
      );
    }

    final response = await _client
        .from('radio_profiles')
        .select()
        .eq('user_id', user.id)
        .eq('radio_id', radioId)
        .order('created_at');

    return (response as List<dynamic>)
        .map(
          (item) => RadioProfile.fromMap(
            item as Map<String, dynamic>,
          ),
        )
        .toList();
  }

  Future<RadioProfile?> fetchProfileById(
    String profileId,
  ) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError(
        'Aucun utilisateur connecté.',
      );
    }

    final response = await _client
        .from('radio_profiles')
        .select()
        .eq('id', profileId)
        .eq('user_id', user.id)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return RadioProfile.fromMap(response);
  }

  Future<RadioProfile> addProfile({
    required String radioId,
    required String name,
    required List<String> enabledFields,
    required Map<String, String> values,
  }) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError(
        'Aucun utilisateur connecté.',
      );
    }

    final cleanName = name.trim();

    if (cleanName.isEmpty) {
      throw ArgumentError(
        'Le nom du profil est obligatoire.',
      );
    }

    final normalizedValues = <String, String>{};

    for (final fieldKey in enabledFields) {
      normalizedValues[fieldKey] =
          values[fieldKey]?.trim() ?? '';
    }

    final response = await _client
        .from('radio_profiles')
        .insert({
          'user_id': user.id,
          'radio_id': radioId,
          'name': cleanName,
          'enabled_fields': List<String>.from(
            enabledFields,
          ),
          'values': normalizedValues,
        })
        .select()
        .single();

    return RadioProfile.fromMap(response);
  }

  Future<RadioProfile> updateProfile(
    RadioProfile profile,
  ) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError(
        'Aucun utilisateur connecté.',
      );
    }

    final cleanName = profile.name.trim();

    if (cleanName.isEmpty) {
      throw ArgumentError(
        'Le nom du profil est obligatoire.',
      );
    }

    final normalizedValues = <String, String>{};

    for (final fieldKey in profile.enabledFields) {
      normalizedValues[fieldKey] =
          profile.values[fieldKey]?.trim() ?? '';
    }

    final response = await _client
        .from('radio_profiles')
        .update({
          'name': cleanName,
          'enabled_fields': List<String>.from(
            profile.enabledFields,
          ),
          'values': normalizedValues,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', profile.id)
        .eq('user_id', user.id)
        .select()
        .single();

    return RadioProfile.fromMap(response);
  }

  Future<void> deleteProfile(
    String profileId,
  ) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError(
        'Aucun utilisateur connecté.',
      );
    }

    await _client
        .from('radio_profiles')
        .delete()
        .eq('id', profileId)
        .eq('user_id', user.id);
  }

  Future<bool> profileNameAlreadyExists({
    required String radioId,
    required String name,
    String? ignoredProfileId,
  }) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError(
        'Aucun utilisateur connecté.',
      );
    }

    var query = _client
        .from('radio_profiles')
        .select('id')
        .eq('user_id', user.id)
        .eq('radio_id', radioId)
        .ilike('name', name.trim());

    if (ignoredProfileId != null) {
      query = query.neq('id', ignoredProfileId);
    }

    final response = await query.limit(1);

    return (response as List<dynamic>).isNotEmpty;
  }
}