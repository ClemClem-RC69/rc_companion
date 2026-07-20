import '../models/model_history_event.dart';
import 'supabase_service.dart';

class ModelHistoryEventService {
  ModelHistoryEventService._();

  static final _client = SupabaseService.client;

  static Future<List<ModelHistoryEvent>> getEvents(String modelId) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      return [];
    }

    final response = await _client
        .from('model_history_events')
        .select()
        .eq('user_id', user.id)
        .eq('model_id', modelId)
        .order('event_date', ascending: false);

    return response
        .map<ModelHistoryEvent>(
          (row) => ModelHistoryEvent.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  static Future<ModelHistoryEvent> createEvent(ModelHistoryEvent event) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError('Utilisateur non connecté');
    }

    final inserted = await _client
        .from('model_history_events')
        .insert({'user_id': user.id, ...event.toJson()})
        .select()
        .single();

    return ModelHistoryEvent.fromJson(Map<String, dynamic>.from(inserted));
  }

  static Future<ModelHistoryEvent> updateEvent(ModelHistoryEvent event) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError('Utilisateur non connecté');
    }

    final updated = await _client
        .from('model_history_events')
        .update({
          ...event.toJson(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', event.id)
        .eq('user_id', user.id)
        .select()
        .single();

    return ModelHistoryEvent.fromJson(Map<String, dynamic>.from(updated));
  }

  static Future<void> deleteEvent(String eventId) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError('Utilisateur non connecté');
    }

    await _client
        .from('model_history_events')
        .delete()
        .eq('id', eventId)
        .eq('user_id', user.id);
  }
}
