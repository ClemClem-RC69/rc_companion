import '../models/battery.dart';
import '../models/battery_measurement.dart';
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

  static Future<List<Battery>> getAvailablePairCandidates({
    required String technology,
    required int capacity,
    required String cells,
    required int cRate,
    String? excludedBatteryCode,
  }) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError('Utilisateur non connecté');
    }

    final cellsNumber = int.parse(cells.replaceAll('S', ''));

    var query = _client
        .from('batteries')
        .select()
        .eq('user_id', user.id)
        .eq('technology', technology)
        .eq('capacity_mah', capacity)
        .eq('cells', cellsNumber)
        .eq('c_rate', cRate)
        .isFilter('pair_id', null);

    if (excludedBatteryCode != null && excludedBatteryCode.isNotEmpty) {
      query = query.neq('battery_code', excludedBatteryCode);
    }

    final response = await query.order('created_at');

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

  static Future<void> createBatteryPairedWithExisting({
    required Battery newBattery,
    required String existingBatteryCode,
  }) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError('Utilisateur non connecté');
    }

    final existingBattery = await _getBatteryByCode(existingBatteryCode);

    if (existingBattery == null) {
      throw StateError('La batterie existante est introuvable');
    }

    if (existingBattery.isPaired) {
      throw StateError(
        'Cette batterie appartient déjà à la paire ${existingBattery.pairId}',
      );
    }

    if (!arePairCompatible(newBattery, existingBattery)) {
      throw StateError(
        'Les deux batteries ne sont pas compatibles pour créer une paire',
      );
    }

    final now = DateTime.now();
    final pairNumber = await getNextPairNumber(now);
    final pairId = buildPairId(
      date: now,
      number: pairNumber,
    );

    final pairedNewBattery = newBattery.copyWith(pairId: pairId);

    await _client.from('batteries').insert({
      'user_id': user.id,
      ...pairedNewBattery.toJson(),
    });

    try {
      final updatedRows = await _client
          .from('batteries')
          .update({
            'pair_id': pairId,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', user.id)
          .eq('battery_code', existingBatteryCode)
          .isFilter('pair_id', null)
          .select('battery_code');

      if (updatedRows.isEmpty) {
        throw StateError(
          'La batterie sélectionnée vient d’être associée à une autre paire',
        );
      }
    } catch (error) {
      await _client
          .from('batteries')
          .delete()
          .eq('user_id', user.id)
          .eq('battery_code', pairedNewBattery.id);

      rethrow;
    }
  }

  static Future<String> createPairFromExistingBatteries({
    required Battery firstBattery,
    required Battery secondBattery,
  }) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError('Utilisateur non connecté');
    }

    if (firstBattery.id == secondBattery.id) {
      throw StateError('Sélectionne deux batteries différentes');
    }

    final currentFirstBattery = await _getBatteryByCode(firstBattery.id);
    final currentSecondBattery = await _getBatteryByCode(secondBattery.id);

    if (currentFirstBattery == null || currentSecondBattery == null) {
      throw StateError('Une des batteries sélectionnées est introuvable');
    }

    if (currentFirstBattery.isPaired) {
      throw StateError(
        '${currentFirstBattery.id} appartient déjà à la paire '
        '${currentFirstBattery.pairId}',
      );
    }

    if (currentSecondBattery.isPaired) {
      throw StateError(
        '${currentSecondBattery.id} appartient déjà à la paire '
        '${currentSecondBattery.pairId}',
      );
    }

    if (!arePairCompatible(currentFirstBattery, currentSecondBattery)) {
      throw StateError(
        'Les deux batteries ne sont pas compatibles pour créer une paire',
      );
    }

    final now = DateTime.now();
    final pairNumber = await getNextPairNumber(now);
    final pairId = buildPairId(
      date: now,
      number: pairNumber,
    );

    final firstUpdatedRows = await _client
        .from('batteries')
        .update({
          'pair_id': pairId,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('user_id', user.id)
        .eq('battery_code', currentFirstBattery.id)
        .isFilter('pair_id', null)
        .select('battery_code');

    if (firstUpdatedRows.isEmpty) {
      throw StateError(
        '${currentFirstBattery.id} vient d’être associée à une autre paire',
      );
    }

    try {
      final secondUpdatedRows = await _client
          .from('batteries')
          .update({
            'pair_id': pairId,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', user.id)
          .eq('battery_code', currentSecondBattery.id)
          .isFilter('pair_id', null)
          .select('battery_code');

      if (secondUpdatedRows.isEmpty) {
        throw StateError(
          '${currentSecondBattery.id} vient d’être associée à une autre paire',
        );
      }
    } catch (error) {
      await _client
          .from('batteries')
          .update({
            'pair_id': null,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', user.id)
          .eq('battery_code', currentFirstBattery.id)
          .eq('pair_id', pairId);

      rethrow;
    }

    return pairId;
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


  static Future<List<BatteryMeasurement>> getBatteryMeasurements(
    String batteryCode,
  ) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      return [];
    }

    final response = await _client
        .from('battery_measurements')
        .select()
        .eq('user_id', user.id)
        .eq('battery_code', batteryCode)
        .order('measured_at', ascending: false);

    return response
        .map<BatteryMeasurement>(
          (json) => BatteryMeasurement.fromJson(
            Map<String, dynamic>.from(json),
          ),
        )
        .toList();
  }

  static Future<BatteryMeasurement?> getReferenceMeasurement(
    String batteryCode,
  ) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      return null;
    }

    final response = await _client
        .from('battery_measurements')
        .select()
        .eq('user_id', user.id)
        .eq('battery_code', batteryCode)
        .inFilter(
          'measurement_type',
          const [
            BatteryMeasurement.referenceType,
            'Mesure de référence',
          ],
        )
        .order('measured_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return BatteryMeasurement.fromJson(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<BatteryMeasurement> saveReferenceMeasurement(
    BatteryMeasurement measurement,
  ) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError('Utilisateur non connecté');
    }

    final referenceMeasurement = measurement.copyWith(
      measurementType: BatteryMeasurement.referenceType,
      removeBatteryTemperature: true,
      removeNotes: true,
    );

    _validateMeasurement(referenceMeasurement);

    final existingRows = await _client
        .from('battery_measurements')
        .select('id')
        .eq('user_id', user.id)
        .eq('battery_code', measurement.batteryCode)
        .inFilter(
          'measurement_type',
          const [
            BatteryMeasurement.referenceType,
            'Mesure de référence',
          ],
        )
        .order('measured_at');

    final data = {
      'user_id': user.id,
      ...referenceMeasurement.toJson(),
    };

    if (existingRows.isEmpty) {
      final insertedRow = await _client
          .from('battery_measurements')
          .insert(data)
          .select()
          .single();

      return BatteryMeasurement.fromJson(
        Map<String, dynamic>.from(insertedRow),
      );
    }

    final referenceId = (existingRows.first['id'] as num).toInt();

    final updatedRow = await _client
        .from('battery_measurements')
        .update(data)
        .eq('user_id', user.id)
        .eq('id', referenceId)
        .select()
        .single();

    if (existingRows.length > 1) {
      final duplicateIds = existingRows
          .skip(1)
          .map((row) => (row['id'] as num).toInt())
          .toList(growable: false);

      await _client
          .from('battery_measurements')
          .delete()
          .eq('user_id', user.id)
          .inFilter('id', duplicateIds);
    }

    return BatteryMeasurement.fromJson(
      Map<String, dynamic>.from(updatedRow),
    );
  }

  static Future<BatteryMeasurement?> getLatestBatteryMeasurement(
    String batteryCode,
  ) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      return null;
    }

    final response = await _client
        .from('battery_measurements')
        .select()
        .eq('user_id', user.id)
        .eq('battery_code', batteryCode)
        .order('measured_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return BatteryMeasurement.fromJson(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<BatteryMeasurement> createBatteryMeasurement(
    BatteryMeasurement measurement,
  ) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError('Utilisateur non connecté');
    }

    _validateMeasurement(measurement);

    final insertedRow = await _client
        .from('battery_measurements')
        .insert({
          'user_id': user.id,
          ...measurement.toJson(),
        })
        .select()
        .single();

    return BatteryMeasurement.fromJson(
      Map<String, dynamic>.from(insertedRow),
    );
  }

  static Future<void> updateBatteryMeasurement(
    BatteryMeasurement measurement,
  ) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError('Utilisateur non connecté');
    }

    if (measurement.id == null) {
      throw StateError('Mesure introuvable');
    }

    _validateMeasurement(measurement);

    await _client
        .from('battery_measurements')
        .update(measurement.toJson())
        .eq('user_id', user.id)
        .eq('id', measurement.id!);
  }

  static Future<void> deleteBatteryMeasurement(
    BatteryMeasurement measurement,
  ) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError('Utilisateur non connecté');
    }

    if (measurement.id == null) {
      throw StateError('Mesure introuvable');
    }

    await _client
        .from('battery_measurements')
        .delete()
        .eq('user_id', user.id)
        .eq('id', measurement.id!);
  }

  static void _validateMeasurement(
    BatteryMeasurement measurement,
  ) {
    if (!BatteryMeasurement.measurementTypes.contains(
      measurement.measurementType,
    )) {
      throw StateError('Type de relevé invalide');
    }

    if (measurement.chargePercent < 0 ||
        measurement.chargePercent > 100) {
      throw StateError(
        'Le pourcentage doit être compris entre 0 et 100',
      );
    }

    if (measurement.cellVoltages.isEmpty) {
      throw StateError('Aucune tension de cellule renseignée');
    }

    if (measurement.cellVoltages.any((voltage) => voltage <= 0)) {
      throw StateError('Les tensions de cellule doivent être positives');
    }

    if (!measurement.usesInternalResistance) {
      return;
    }

    if (measurement.cellInternalResistances.isEmpty) {
      throw StateError(
        'Aucune résistance interne de cellule renseignée',
      );
    }

    if (measurement.cellVoltages.length !=
        measurement.cellInternalResistances.length) {
      throw StateError(
        'Le nombre de tensions et de résistances internes doit être identique',
      );
    }

    if (measurement.cellInternalResistances.any(
      (resistance) => resistance <= 0,
    )) {
      throw StateError(
        'Les résistances internes doivent être positives',
      );
    }
  }

  static Future<int> getNextBatteryNumber({
    required String technology,
    required DateTime date,
  }) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError('Utilisateur non connecté');
    }

    final prefix = '${_technologyPrefix(technology)}-';

    final response = await _client
        .from('batteries')
        .select('battery_code')
        .eq('user_id', user.id)
        .like('battery_code', '$prefix%');

    var highestNumber = 0;

    for (final row in response) {
      final code = row['battery_code'] as String?;

      if (code == null || !code.startsWith(prefix)) {
        continue;
      }

      final number = int.tryParse(code.substring(prefix.length));

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

    final response = await _client
        .from('batteries')
        .select('pair_id')
        .eq('user_id', user.id)
        .like('pair_id', 'P-%');

    var highestNumber = 0;

    for (final row in response) {
      final pairId = row['pair_id'] as String?;

      if (pairId == null || !pairId.startsWith('P-')) {
        continue;
      }

      final number = int.tryParse(pairId.substring(2));

      if (number != null && number > highestNumber) {
        highestNumber = number;
      }
    }

    return highestNumber + 1;
  }

  static bool arePairCompatible(Battery first, Battery second) {
    return first.technology == second.technology &&
        first.capacity == second.capacity &&
        first.cells == second.cells &&
        first.cRate == second.cRate;
  }

  static String buildBatteryCode({
    required String technology,
    required DateTime date,
    required int number,
  }) {
    return '${_technologyPrefix(technology)}-'
        '${number.toString().padLeft(3, '0')}';
  }

  static String buildPairId({
    required DateTime date,
    required int number,
  }) {
    return 'P-${number.toString().padLeft(3, '0')}';
  }

  static Future<Battery?> _getBatteryByCode(String batteryCode) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError('Utilisateur non connecté');
    }

    final response = await _client
        .from('batteries')
        .select()
        .eq('user_id', user.id)
        .eq('battery_code', batteryCode)
        .maybeSingle();

    if (response == null) {
      return null;
    }

    return Battery.fromJson(
      Map<String, dynamic>.from(response),
    );
  }

  static String _technologyPrefix(String technology) {
    final normalized = technology
        .toLowerCase()
        .replaceAll('-', '')
        .replaceAll(' ', '');

    switch (normalized) {
      case 'lipo':
        return 'LiPo';
      case 'lihv':
        return 'LiHV';
      case 'liion':
        return 'LiIon';
      case 'life':
        return 'LiFe';
      case 'nimh':
        return 'NiMH';
      case 'nicd':
        return 'NiCd';
      default:
        final cleaned = technology
            .trim()
            .replaceAll('-', '')
            .replaceAll(' ', '');

        return cleaned.isEmpty ? 'BAT' : cleaned;
    }
  }
}
