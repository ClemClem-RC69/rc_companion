import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseService._();

  static Future<void> initialize() async {
    const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
    const supabasePublishableKey =
        String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

    if (supabaseUrl.isEmpty || supabasePublishableKey.isEmpty) {
      throw StateError(
        'Les paramètres Supabase sont absents. '
        'Lance Flutter avec SUPABASE_URL et SUPABASE_PUBLISHABLE_KEY.',
      );
    }

    await Supabase.initialize(
      url: supabaseUrl,
      publishableKey: supabasePublishableKey,
    );
  }

  static SupabaseClient get client => Supabase.instance.client;
}