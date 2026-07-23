import 'dart:async';
import 'dart:convert';

import '../models/battery.dart';
import '../models/battery_measurement.dart';
import '../database/app_database.dart';
import 'battery_local_store.dart';
import 'battery_sync_service.dart';
import 'supabase_service.dart';

class BatteryService {
  static final _client = SupabaseService.client;
  static final _database = AppDatabase.instance;

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
        .order('created_at', ascending: false)
        .timeout(const Duration(seconds: 8));

    final measurementResponse = await _client
        .from('battery_measurements')
        .select()
        .eq('user_id', userId)
        .order('measured_at', ascending: false)
        .timeout(const Duration(seconds: 8));

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

    await BatteryLocalStore.upsertBattery(userId: user.id, battery: battery);

    await _database.replacePendingSyncOperation(
      userId: user.id,
      entityType: 'battery',
      entityId: battery.id,
      operation: 'upsert',
      payloadJson: jsonEncode({
        'user_id': user.id,
        ...battery.toJson(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }),
    );

    unawaited(BatterySyncService.syncNow());
  }

  static Future<void> createBatteries(List<Battery> batteries) async {
    for (final battery in batteries) {
      await createBattery(battery);
    }
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
    final pairedExistingBattery = existingBattery.copyWith(pairId: pairId);

    await BatteryLocalStore.upsertBatteries(
      userId: user.id,
      batteries: [pairedNewBattery, pairedExistingBattery],
    );

    await _queueBatteryUpsert(userId: user.id, battery: pairedNewBattery);
    await _queueBatteryUpsert(userId: user.id, battery: pairedExistingBattery);

    unawaited(BatterySyncService.syncNow());
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

    final pairedFirstBattery = currentFirstBattery.copyWith(pairId: pairId);
    final pairedSecondBattery = currentSecondBattery.copyWith(pairId: pairId);

    await BatteryLocalStore.upsertBatteries(
      userId: user.id,
      batteries: [pairedFirstBattery, pairedSecondBattery],
    );

    await _queueBatteryUpsert(userId: user.id, battery: pairedFirstBattery);
    await _queueBatteryUpsert(userId: user.id, battery: pairedSecondBattery);

    unawaited(BatterySyncService.syncNow());
    return pairId;
  }

  static Future<void> updateBattery(Battery battery) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError('Utilisateur non connecté');
    }

    await BatteryLocalStore.upsertBattery(userId: user.id, battery: battery);
    await _queueBatteryUpsert(userId: user.id, battery: battery);

    unawaited(BatterySyncService.syncNow());
  }

  static Future<void> dissolvePair(String pairId) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError('Utilisateur non connecté');
    }

    final cachedBatteries = await BatteryLocalStore.getBatteries(
      userId: user.id,
    );
    final pairedBatteries = cachedBatteries
        .where((battery) => battery.pairId == pairId)
        .toList(growable: false);

    if (pairedBatteries.isEmpty) {
      throw StateError('La paire $pairId est introuvable');
    }

    for (final battery in pairedBatteries) {
      await updateBattery(battery.copyWith(removePair: true));
    }
  }

  static Future<void> deleteBattery(Battery battery) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError('Utilisateur non connecté');
    }

    final pairId = battery.pairId;
    if (pairId != null && pairId.isNotEmpty) {
      final cached = await BatteryLocalStore.getBatteries(userId: user.id);

      for (final other in cached.where(
        (item) => item.id != battery.id && item.pairId == pairId,
      )) {
        await updateBattery(other.copyWith(removePair: true));
      }
    }

    await BatteryLocalStore.markBatteryDeleted(
      userId: user.id,
      battery: battery,
    );

    await _database.replacePendingSyncOperation(
      userId: user.id,
      entityType: 'battery',
      entityId: battery.id,
      operation: 'delete',
    );

    unawaited(BatterySyncService.syncNow());
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
        .order('measured_at', ascending: false)
        .timeout(const Duration(seconds: 8));

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

    final cachedMeasurements = await BatteryLocalStore.getMeasurements(
      userId: user.id,
      batteryCode: referenceMeasurement.batteryCode,
    );

    final existingReferences = cachedMeasurements
        .where((item) => item.isReference)
        .toList(growable: false);

    final existingReference = existingReferences.isEmpty
        ? null
        : existingReferences.first;

    final savedReference = existingReference == null
        ? referenceMeasurement
        : referenceMeasurement.copyWith(id: existingReference.id);

    final entityId = existingReference == null
        ? BatteryLocalStore.measurementEntityId(
            userId: user.id,
            measurement: savedReference,
          )
        : BatteryLocalStore.measurementEntityId(
            userId: user.id,
            measurement: existingReference,
          );

    await BatteryLocalStore.upsertMeasurement(
      userId: user.id,
      measurement: savedReference,
      forcedLocalKey: entityId,
    );

    await _database.replacePendingSyncOperation(
      userId: user.id,
      entityType: 'battery_measurement',
      entityId: entityId,
      operation: 'upsert',
      payloadJson: jsonEncode({
        'user_id': user.id,
        if (savedReference.id != null) 'id': savedReference.id,
        ...savedReference.toJson(),
      }),
    );

    for (final duplicate in existingReferences.skip(1)) {
      final duplicateEntityId = BatteryLocalStore.measurementEntityId(
        userId: user.id,
        measurement: duplicate,
      );

      await BatteryLocalStore.markMeasurementDeleted(
        userId: user.id,
        measurement: duplicate,
      );

      await _database.replacePendingSyncOperation(
        userId: user.id,
        entityType: 'battery_measurement',
        entityId: duplicateEntityId,
        operation: 'delete',
        payloadJson: jsonEncode({if (duplicate.id != null) 'id': duplicate.id}),
      );
    }

    unawaited(BatterySyncService.syncNow());
    return savedReference;
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

    final entityId = BatteryLocalStore.measurementEntityId(
      userId: user.id,
      measurement: measurement,
    );

    await BatteryLocalStore.upsertMeasurement(
      userId: user.id,
      measurement: measurement,
      forcedLocalKey: entityId,
    );

    await _database.replacePendingSyncOperation(
      userId: user.id,
      entityType: 'battery_measurement',
      entityId: entityId,
      operation: 'upsert',
      payloadJson: jsonEncode({'user_id': user.id, ...measurement.toJson()}),
    );

    unawaited(BatterySyncService.syncNow());
    return measurement;
  }

  static Future<BatteryMeasurement> updateBatteryMeasurement(
    BatteryMeasurement measurement,
  ) async {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError('Utilisateur non connecté');
    }

    _validateMeasurement(measurement);

    final entityId = BatteryLocalStore.measurementEntityId(
      userId: user.id,
      measurement: measurement,
    );

    await BatteryLocalStore.upsertMeasurement(
      userId: user.id,
      measurement: measurement,
      forcedLocalKey: entityId,
    );

    await _database.replacePendingSyncOperation(
      userId: user.id,
      entityType: 'battery_measurement',
      entityId: entityId,
      operation: 'upsert',
      payloadJson: jsonEncode({
        'user_id': user.id,
        if (measurement.id != null) 'id': measurement.id,
        ...measurement.toJson(),
      }),
    );

    unawaited(BatterySyncService.syncNow());
    return measurement;
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

    final entityId = BatteryLocalStore.measurementEntityId(
      userId: user.id,
      measurement: measurement,
    );

    await BatteryLocalStore.markMeasurementDeleted(
      userId: user.id,
      measurement: measurement,
    );

    await _database.replacePendingSyncOperation(
      userId: user.id,
      entityType: 'battery_measurement',
      entityId: entityId,
      operation: 'delete',
      payloadJson: jsonEncode({
        if (measurement.id != null) 'id': measurement.id,
      }),
    );

    unawaited(BatterySyncService.syncNow());
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
    final batteries = await BatteryLocalStore.getBatteries(userId: user.id);

    var highestNumber = 0;

    for (final battery in batteries) {
      final code = battery.id;

      if (!code.startsWith(prefix)) {
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

    final batteries = await BatteryLocalStore.getBatteries(userId: user.id);

    var highestNumber = 0;

    for (final battery in batteries) {
      final pairId = battery.pairId;

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

    final cachedBatteries = await BatteryLocalStore.getBatteries(
      userId: user.id,
    );

    for (final battery in cachedBatteries) {
      if (battery.id == batteryCode) {
        return battery;
      }
    }

    try {
      final response = await _client
          .from('batteries')
          .select()
          .eq('user_id', user.id)
          .eq('battery_code', batteryCode)
          .maybeSingle()
          .timeout(const Duration(seconds: 8));

      if (response == null) {
        return null;
      }

      final battery = Battery.fromJson(Map<String, dynamic>.from(response));
      await BatteryLocalStore.upsertBattery(userId: user.id, battery: battery);
      return battery;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _queueBatteryUpsert({
    required String userId,
    required Battery battery,
  }) {
    return _database.replacePendingSyncOperation(
      userId: userId,
      entityType: 'battery',
      entityId: battery.id,
      operation: 'upsert',
      payloadJson: jsonEncode({
        'user_id': userId,
        ...battery.toJson(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }),
    );
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

    if (measurement.isReference) {
      if (measurement.chargePercent <= 20) {
        return BatteryChargeState.discharged;
      }

      if (measurement.chargePercent >= 95) {
        return BatteryChargeState.charged;
      }

      return BatteryChargeState.partial;
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

    if (reference == null) {
      return const BatteryHealthAnalysis.notEvaluated();
    }

    if (afterChargeMeasurements.isEmpty) {
      final referenceHasSevereIssue =
          reference.maximumVoltageDifference > 0.100 ||
          reference.maximumInternalResistanceDifference > 10.0;

      final referenceHasWarning =
          reference.maximumVoltageDifference > 0.050 ||
          reference.maximumInternalResistanceDifference > 5.0;

      final reasons = <String>[
        'Écart de tension de référence : '
            '${reference.maximumVoltageDifference.toStringAsFixed(3)} V.',
        'Écart de résistance interne de référence : '
            '${reference.maximumInternalResistanceDifference.toStringAsFixed(2)} mΩ.',
        'Santé initiale calculée à partir de la mesure de référence. '
            'Les relevés après charge permettront ensuite de suivre son évolution.',
      ];

      return BatteryHealthAnalysis(
        level: referenceHasSevereIssue
            ? BatteryHealthLevel.hs
            : referenceHasWarning
            ? BatteryHealthLevel.warning
            : BatteryHealthLevel.good,
        label: referenceHasSevereIssue
            ? 'HS*'
            : referenceHasWarning
            ? 'À surveiller*'
            : 'Bonne*',
        reference: reference,
        latestAfterCharge: null,
        afterChargeCount: 0,
        resistanceEvolutionPercent: 0.0,
        risingTrend: false,
        reasons: reasons,
      );
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
      if (!measurement.isReference &&
          !measurement.isAfterCharge &&
          !measurement.isEndOfRun) {
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
