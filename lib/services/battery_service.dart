import 'dart:async';

import '../models/battery.dart';
import '../models/battery_measurement.dart';
import 'battery_local_store.dart';
import 'supabase_service.dart';

class BatteryService {
  static final _client = SupabaseService.client;

  static Future<List<Battery>> getBatteries() async {
    final user = _client.auth.currentUser;

    if (user == null) {
      return [];
    }

    final cachedBatteries = await getCachedBatteries();
    final hasCache = await BatteryLocalStore.hasBatteryCache(userId: user.id);

    if (hasCache) {
      unawaited(_refreshBatteriesSilently(user.id));
      return cachedBatteries;
    }

    return _refreshBatteriesFromCloud(user.id);
  }

  static Future<List<Battery>> getCachedBatteries() async {
    final user = _client.auth.currentUser;

    if (user == null) {
      return [];
    }

    final cachedBatteries = await BatteryLocalStore.getBatteries(
      userId: user.id,
    );
    final cachedMeasurements = await BatteryLocalStore.getMeasurements(
      userId: user.id,
    );

    return _applyChargeState(
      batteries: cachedBatteries,
      measurements: cachedMeasurements,
    );
  }

  static Future<void> _refreshBatteriesSilently(String userId) async {
    try {
      await _refreshBatteriesFromCloud(userId);
    } catch (_) {
      // Le cache local reste la source d'affichage lorsque le réseau
      // est indisponible. La prochaine ouverture tentera à nouveau.
    }
  }

  static Future<List<Battery>> _refreshBatteriesFromCloud(String userId) async {
    final batteryResponse = await _client
        .from('batteries')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    final measurementResponse = await _client
        .from('battery_measurements')
        .select()
        .eq('user_id', userId)
        .order('measured_at', ascending: false);

    final batteryRows = batteryResponse
        .map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);

    final measurementRows = measurementResponse
        .map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);

    await BatteryLocalStore.replaceBatteries(userId: userId, rows: batteryRows);
    await BatteryLocalStore.replaceMeasurements(
      userId: userId,
      rows: measurementRows,
    );

    return _buildBatteries(
      batteryRows: batteryRows,
      measurementRows: measurementRows,
    );
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

    try {
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
            (json) => Battery.fromJson(Map<String, dynamic>.from(json)),
          )
          .toList(growable: false);
    } catch (_) {
      final cached = await BatteryLocalStore.getBatteries(userId: user.id);

      return cached
          .where(
            (battery) =>
                battery.technology == technology &&
                battery.capacity == capacity &&
                battery.cells == cells &&
                battery.cRate == cRate &&
                !battery.isPaired &&
                battery.id != excludedBatteryCode,
          )
          .toList(growable: false);
    }
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

    await _client
        .from('batteries')
        .insert(
          batteries
              .map((battery) => {'user_id': user.id, ...battery.toJson()})
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
    final pairId = buildPairId(date: now, number: pairNumber);

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
    final pairId = buildPairId(date: now, number: pairNumber);

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

    final cached = await BatteryLocalStore.getMeasurements(
      userId: user.id,
      batteryCode: batteryCode,
    );
    final hasBatteryCache = await BatteryLocalStore.hasBatteryCache(
      userId: user.id,
    );

    if (hasBatteryCache) {
      unawaited(
        _refreshBatteryMeasurementsSilently(
          userId: user.id,
          batteryCode: batteryCode,
        ),
      );
      return cached;
    }

    return _refreshBatteryMeasurementsFromCloud(
      userId: user.id,
      batteryCode: batteryCode,
    );
  }

  static Future<void> _refreshBatteryMeasurementsSilently({
    required String userId,
    required String batteryCode,
  }) async {
    try {
      await _refreshBatteryMeasurementsFromCloud(
        userId: userId,
        batteryCode: batteryCode,
      );
    } catch (_) {
      // Le relevé local, même vide, reste valable hors ligne.
    }
  }

  static Future<List<BatteryMeasurement>> _refreshBatteryMeasurementsFromCloud({
    required String userId,
    required String batteryCode,
  }) async {
    final response = await _client
        .from('battery_measurements')
        .select()
        .eq('user_id', userId)
        .eq('battery_code', batteryCode)
        .order('measured_at', ascending: false);

    final rows = response
        .map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);

    await BatteryLocalStore.replaceMeasurementsForBattery(
      userId: userId,
      batteryCode: batteryCode,
      rows: rows,
    );

    return rows
        .map<BatteryMeasurement>(BatteryMeasurement.fromJson)
        .toList(growable: false);
  }

  static Future<BatteryMeasurement?> getReferenceMeasurement(
    String batteryCode,
  ) async {
    final measurements = await getBatteryMeasurements(batteryCode);

    for (final measurement in measurements) {
      if (measurement.isReference) {
        return measurement;
      }
    }

    return null;
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
        .inFilter('measurement_type', const [
          BatteryMeasurement.referenceType,
          'Mesure de référence',
        ])
        .order('measured_at');

    final data = {'user_id': user.id, ...referenceMeasurement.toJson()};

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

    return BatteryMeasurement.fromJson(Map<String, dynamic>.from(updatedRow));
  }

  static Future<BatteryMeasurement?> getLatestBatteryMeasurement(
    String batteryCode,
  ) async {
    final measurements = await getBatteryMeasurements(batteryCode);
    return measurements.isEmpty ? null : measurements.first;
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
        .insert({'user_id': user.id, ...measurement.toJson()})
        .select()
        .single();

    return BatteryMeasurement.fromJson(Map<String, dynamic>.from(insertedRow));
  }

  static Future<BatteryMeasurement> updateBatteryMeasurement(
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

    final updatedRow = await _client
        .from('battery_measurements')
        .update(measurement.toJson())
        .eq('user_id', user.id)
        .eq('id', measurement.id!)
        .select()
        .single();

    final savedMeasurement = BatteryMeasurement.fromJson(
      Map<String, dynamic>.from(updatedRow),
    );

    if (savedMeasurement.isEndOfRun) {
      await _synchronizeSessionRunMeasurement(
        userId: user.id,
        measurement: savedMeasurement,
      );
    }

    return savedMeasurement;
  }

  static Future<void> _synchronizeSessionRunMeasurement({
    required String userId,
    required BatteryMeasurement measurement,
  }) async {
    final notes = measurement.notes;

    if (notes == null || notes.trim().isEmpty) {
      return;
    }

    String? sessionId;
    String? runStartedAt;
    String? batteryCode;

    for (final part in notes.split('|')) {
      if (part.startsWith('session:')) {
        sessionId = part.substring('session:'.length).trim();
      } else if (part.startsWith('run:')) {
        runStartedAt = part.substring('run:'.length).trim();
      } else if (part.startsWith('battery:')) {
        batteryCode = part.substring('battery:'.length).trim();
      }
    }

    if (sessionId == null ||
        sessionId.isEmpty ||
        runStartedAt == null ||
        runStartedAt.isEmpty ||
        batteryCode == null ||
        batteryCode.isEmpty) {
      return;
    }

    final runRow = await _client
        .from('session_runs')
        .select('id')
        .eq('session_id', sessionId)
        .eq('started_at', runStartedAt)
        .maybeSingle();

    if (runRow == null) {
      return;
    }

    final runId = runRow['id'] as String?;

    if (runId == null || runId.isEmpty) {
      return;
    }

    await _client
        .from('session_run_measurements')
        .update({
          'measured_at': measurement.measuredAt.toUtc().toIso8601String(),
          'remaining_capacity_percent': measurement.chargePercent,
          'temperature_celsius': measurement.batteryTemperature,
          'cell_voltages': measurement.cellVoltages,
          'cell_resistances': const <double>[],
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('user_id', userId)
        .eq('run_id', runId)
        .eq('battery_code', batteryCode);
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

  static void _validateMeasurement(BatteryMeasurement measurement) {
    if (!BatteryMeasurement.measurementTypes.contains(
      measurement.measurementType,
    )) {
      throw StateError('Type de relevé invalide');
    }

    if (measurement.chargePercent < 0 || measurement.chargePercent > 100) {
      throw StateError('Le pourcentage doit être compris entre 0 et 100');
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
      throw StateError('Aucune résistance interne de cellule renseignée');
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
      throw StateError('Les résistances internes doivent être positives');
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

  static String buildPairId({required DateTime date, required int number}) {
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

    return Battery.fromJson(Map<String, dynamic>.from(response));
  }

  static String withAfterChargeStateNote(
    String? existingNotes,
    BatteryChargeState state,
  ) {
    final parts = (existingNotes ?? '')
        .split('|')
        .where(
          (part) =>
              part.trim().isNotEmpty &&
              !part.trim().startsWith('charge_state:'),
        )
        .toList();

    parts.add(
      'charge_state:${state == BatteryChargeState.storage ? 'storage' : 'charged'}',
    );

    return parts.join('|');
  }

  static BatteryChargeState _chargeStateFor({
    required Battery battery,
    required BatteryMeasurement? measurement,
  }) {
    if (measurement == null) {
      return BatteryChargeState.discharged;
    }

    if (measurement.isAfterCharge) {
      final note = measurement.notes ?? '';

      final isStorage = note
          .split('|')
          .any((part) => part.trim() == 'charge_state:storage');

      if (isStorage) {
        return BatteryChargeState.storage;
      }

      if (measurement.chargePercent <= 20) {
        return BatteryChargeState.discharged;
      }

      if (measurement.chargePercent >= 95) {
        return BatteryChargeState.charged;
      }

      return BatteryChargeState.partial;
    }

    if (measurement.isEndOfRun) {
      return measurement.chargePercent <= 20
          ? BatteryChargeState.discharged
          : BatteryChargeState.partial;
    }

    return BatteryChargeState.discharged;
  }

  static BatteryHealthAnalysis calculateBatteryHealth(
    List<BatteryMeasurement> measurements,
  ) {
    BatteryMeasurement? reference;

    for (final measurement in measurements) {
      if (measurement.isReference && measurement.hasInternalResistance) {
        reference = measurement;
        break;
      }
    }

    final afterChargeMeasurements =
        measurements
            .where(
              (measurement) =>
                  measurement.isAfterCharge &&
                  measurement.hasInternalResistance,
            )
            .toList()
          ..sort(
            (first, second) => first.measuredAt.compareTo(second.measuredAt),
          );

    if (reference == null || afterChargeMeasurements.isEmpty) {
      return const BatteryHealthAnalysis.notEvaluated();
    }

    final latest = afterChargeMeasurements.last;
    final referenceAverage = reference.averageInternalResistance;
    final latestAverage = latest.averageInternalResistance;

    final evolutionPercent = referenceAverage <= 0
        ? 0.0
        : ((latestAverage - referenceAverage) / referenceAverage) * 100;

    bool isSevere(BatteryMeasurement measurement) {
      final average = measurement.averageInternalResistance;

      final evolution = referenceAverage <= 0
          ? 0.0
          : ((average - referenceAverage) / referenceAverage) * 100;

      return measurement.maximumVoltageDifference > 0.100 ||
          measurement.maximumInternalResistanceDifference > 10.0 ||
          evolution > 100.0;
    }

    final recent = afterChargeMeasurements.length <= 3
        ? afterChargeMeasurements
        : afterChargeMeasurements.sublist(afterChargeMeasurements.length - 3);

    final severeRecentCount = recent.where(isSevere).length;

    var risingTrend = false;

    if (recent.length >= 3) {
      final firstAverage = recent.first.averageInternalResistance;
      final middleAverage = recent[1].averageInternalResistance;
      final lastAverage = recent.last.averageInternalResistance;

      final increase = firstAverage <= 0
          ? 0.0
          : ((lastAverage - firstAverage) / firstAverage) * 100;

      risingTrend =
          middleAverage >= firstAverage &&
          lastAverage >= middleAverage &&
          increase > 15.0;
    }

    final latestIsSevere = isSevere(latest);

    final latestHasWarning =
        latest.maximumVoltageDifference > 0.050 ||
        latest.maximumInternalResistanceDifference > 5.0 ||
        evolutionPercent > 25.0;

    final reasons = <String>[
      'Écart de tension actuel : '
          '${latest.maximumVoltageDifference.toStringAsFixed(3)} V.',
      'Écart de résistance interne actuel : '
          '${latest.maximumInternalResistanceDifference.toStringAsFixed(2)} mΩ.',
      'Évolution de la résistance interne moyenne depuis la référence : '
          '${evolutionPercent >= 0 ? '+' : ''}'
          '${evolutionPercent.toStringAsFixed(1)} %.',
      risingTrend
          ? 'Tendance : hausse régulière sur les trois derniers relevés après charge.'
          : 'Tendance : aucune hausse régulière critique sur les trois derniers relevés après charge.',
    ];

    if (latestIsSevere || severeRecentCount >= 2) {
      return BatteryHealthAnalysis(
        level: BatteryHealthLevel.hs,
        label: 'HS*',
        reference: reference,
        latestAfterCharge: latest,
        afterChargeCount: afterChargeMeasurements.length,
        resistanceEvolutionPercent: evolutionPercent,
        risingTrend: risingTrend,
        reasons: reasons,
      );
    }

    if (latestHasWarning || risingTrend) {
      return BatteryHealthAnalysis(
        level: BatteryHealthLevel.warning,
        label: 'À surveiller*',
        reference: reference,
        latestAfterCharge: latest,
        afterChargeCount: afterChargeMeasurements.length,
        resistanceEvolutionPercent: evolutionPercent,
        risingTrend: risingTrend,
        reasons: reasons,
      );
    }

    return BatteryHealthAnalysis(
      level: BatteryHealthLevel.good,
      label: 'Bonne*',
      reference: reference,
      latestAfterCharge: latest,
      afterChargeCount: afterChargeMeasurements.length,
      resistanceEvolutionPercent: evolutionPercent,
      risingTrend: risingTrend,
      reasons: reasons,
    );
  }

  static List<Battery> _buildBatteries({
    required List<Map<String, dynamic>> batteryRows,
    required List<Map<String, dynamic>> measurementRows,
  }) {
    final batteries = batteryRows
        .map<Battery>(Battery.fromJson)
        .toList(growable: false);
    final measurements = measurementRows
        .map<BatteryMeasurement>(BatteryMeasurement.fromJson)
        .toList(growable: false);

    return _applyChargeState(batteries: batteries, measurements: measurements);
  }

  static List<Battery> _applyChargeState({
    required List<Battery> batteries,
    required List<BatteryMeasurement> measurements,
  }) {
    final sortedMeasurements = List<BatteryMeasurement>.from(measurements)
      ..sort((first, second) => second.measuredAt.compareTo(first.measuredAt));

    final latestUsefulMeasurementByBattery = <String, BatteryMeasurement>{};

    for (final measurement in sortedMeasurements) {
      if (measurement.isReference) {
        continue;
      }

      if (!measurement.isAfterCharge && !measurement.isEndOfRun) {
        continue;
      }

      latestUsefulMeasurementByBattery.putIfAbsent(
        measurement.batteryCode,
        () => measurement,
      );
    }

    return batteries
        .map((battery) {
          final latest = latestUsefulMeasurementByBattery[battery.id];

          return battery.copyWith(
            chargeState: _chargeStateFor(battery: battery, measurement: latest),
            chargePercent: latest?.chargePercent,
          );
        })
        .toList(growable: false);
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

enum BatteryHealthLevel { notEvaluated, good, warning, hs }

class BatteryHealthAnalysis {
  const BatteryHealthAnalysis({
    required this.level,
    required this.label,
    required this.reference,
    required this.latestAfterCharge,
    required this.afterChargeCount,
    required this.resistanceEvolutionPercent,
    required this.risingTrend,
    required this.reasons,
  });

  const BatteryHealthAnalysis.notEvaluated()
    : level = BatteryHealthLevel.notEvaluated,
      label = 'Non évaluée',
      reference = null,
      latestAfterCharge = null,
      afterChargeCount = 0,
      resistanceEvolutionPercent = null,
      risingTrend = false,
      reasons = const [
        'Une mesure de référence et au moins un relevé après charge sont nécessaires.',
      ];

  final BatteryHealthLevel level;
  final String label;
  final BatteryMeasurement? reference;
  final BatteryMeasurement? latestAfterCharge;
  final int afterChargeCount;
  final double? resistanceEvolutionPercent;
  final bool risingTrend;
  final List<String> reasons;

  bool get isEvaluated => level != BatteryHealthLevel.notEvaluated;

  bool get isWarning => level == BatteryHealthLevel.warning;

  bool get isHs => level == BatteryHealthLevel.hs;
}
