import '../models/battery.dart';
import 'supabase_service.dart';

class BatteryService {
  static final _client = SupabaseService.client;

  static Future<List<Battery>> getBatteries() async {
    final user = _client.auth.currentUser;

    if (user == null) {
      return [];
    }

    final response = await _client
        .from('batteries')
        .select()
        .eq('user_id', user.id)
        .order('created_at');

    return response
        .map<Battery>(
          (json) => Battery.fromJson(
            Map<String, dynamic>.from(json),
          ),
        )
        .toList();
  }

  static Future<void> createBattery(Battery battery) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError('Utilisateur non connecté');
    }

    await _client.from('batteries').insert({
      'user_id': user.id,
      ...battery.toJson(),
    });
  }

  static Future<void> createBatteries(List<Battery> batteries) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError('Utilisateur non connecté');
    }

    await _client.from('batteries').insert(
          batteries
              .map(
                (battery) => {
                  'user_id': user.id,
                  ...battery.toJson(),
                },
              )
              .toList(),
        );
  }

  static Future<void> updateBattery(Battery battery) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError('Utilisateur non connecté');
    }

    await _client
        .from('batteries')
        .update({
          ...battery.toJson(),
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('user_id', user.id)
        .eq('battery_code', battery.id);
  }

  static Future<void> dissolvePair(String pairId) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError('Utilisateur non connecté');
    }

    await _client
        .from('batteries')
        .update({
          'pair_id': null,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('user_id', user.id)
        .eq('pair_id', pairId);
  }

  static Future<void> deleteBattery(Battery battery) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError('Utilisateur non connecté');
    }

    final pairId = battery.pairId;

    if (pairId != null && pairId.isNotEmpty) {
      await _client
          .from('batteries')
          .update({
            'pair_id': null,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', user.id)
          .eq('pair_id', pairId)
          .neq('battery_code', battery.id);
    }

    await _client
        .from('batteries')
        .delete()
        .eq('user_id', user.id)
        .eq('battery_code', battery.id);
  }

  static Future<int> getNextBatteryNumber({
    required String technology,
    required DateTime date,
  }) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError('Utilisateur non connecté');
    }

    final prefix = '${_technologyPrefix(technology)}-${_formatDate(date)}-';

    final response = await _client
        .from('batteries')
        .select('battery_code')
        .eq('user_id', user.id)
        .like('battery_code', '$prefix%');

    var highestNumber = 0;

    for (final row in response) {
      final code = row['battery_code'] as String?;
      if (code == null) {
        continue;
      }

      final number = int.tryParse(code.split('-').last);
      if (number != null && number > highestNumber) {
        highestNumber = number;
      }
    }

    return highestNumber + 1;
  }

  static Future<int> getNextPairNumber(DateTime date) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError('Utilisateur non connecté');
    }

    final prefix = 'P-${_formatDate(date)}-';

    final response = await _client
        .from('batteries')
        .select('pair_id')
        .eq('user_id', user.id)
        .like('pair_id', '$prefix%');

    var highestNumber = 0;

    for (final row in response) {
      final pairId = row['pair_id'] as String?;
      if (pairId == null) {
        continue;
      }

      final number = int.tryParse(pairId.split('-').last);
      if (number != null && number > highestNumber) {
        highestNumber = number;
      }
    }

    return highestNumber + 1;
  }

  static String buildBatteryCode({
    required String technology,
    required DateTime date,
    required int number,
  }) {
    return '${_technologyPrefix(technology)}-'
        '${_formatDate(date)}-'
        '${number.toString().padLeft(3, '0')}';
  }

  static String buildPairId({
    required DateTime date,
    required int number,
  }) {
    return 'P-${_formatDate(date)}-'
        '${number.toString().padLeft(3, '0')}';
  }

  static String _technologyPrefix(String technology) {
    return technology
        .toUpperCase()
        .replaceAll('-', '')
        .replaceAll(' ', '');
  }

  static String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString();

    return '$day$month$year';
  }
}
