class BatteryMeasurement {
  const BatteryMeasurement({
    this.id,
    required this.batteryCode,
    required this.measuredAt,
    required this.measurementType,
    required this.chargePercent,
    required this.cellVoltages,
    this.cellInternalResistances = const [],
    // Champs conservés uniquement pour relire les anciennes données.
    // Les nouveaux écrans ne les utiliseront plus.
    this.batteryTemperature,
    this.notes,
  });

  static const String referenceType = 'Relevé de référence';
  static const String afterChargeType = 'Relevé après charge';
  static const String endOfRunType = 'Relevé fin de roulage';

  // Alias temporaire pour éviter de casser les fichiers qui seront remplacés
  // aux étapes suivantes.
  static const String endOfSessionType = endOfRunType;

  static const List<String> measurementTypes = [
    referenceType,
    afterChargeType,
    endOfRunType,
  ];

  static const List<String> manualMeasurementTypes = [
    referenceType,
    afterChargeType,
  ];

  final int? id;
  final String batteryCode;
  final DateTime measuredAt;
  final String measurementType;
  final int chargePercent;
  final List<double> cellVoltages;

  /// Renseignées uniquement pour un relevé de référence ou après charge.
  final List<double> cellInternalResistances;

  /// Anciens champs conservés pour la compatibilité avec les données déjà
  /// enregistrées. Ils seront ignorés par les nouveaux formulaires.
  final double? batteryTemperature;
  final String? notes;

  int get cellCount => cellVoltages.length;

  bool get isReference => measurementType == referenceType;

  bool get isAfterCharge => measurementType == afterChargeType;

  bool get isEndOfRun => measurementType == endOfRunType;

  // Alias temporaire pour les écrans actuels.
  bool get isEndOfSession => isEndOfRun;

  // Le type « Contrôle » est supprimé. Ce getter reste uniquement pour que
  // les anciens fichiers compilent jusqu'à leur remplacement.
  bool get isControl => false;

  bool get usesInternalResistance => isReference || isAfterCharge;

  bool get hasInternalResistance =>
      usesInternalResistance && cellInternalResistances.isNotEmpty;

  double get totalVoltage {
    return cellVoltages.fold<double>(0, (total, voltage) => total + voltage);
  }

  double get minimumCellVoltage {
    if (cellVoltages.isEmpty) {
      return 0;
    }

    return cellVoltages.reduce(
      (current, next) => current < next ? current : next,
    );
  }

  double get maximumCellVoltage {
    if (cellVoltages.isEmpty) {
      return 0;
    }

    return cellVoltages.reduce(
      (current, next) => current > next ? current : next,
    );
  }

  double get maximumVoltageDifference {
    if (cellVoltages.isEmpty) {
      return 0;
    }

    return maximumCellVoltage - minimumCellVoltage;
  }

  double get averageInternalResistance {
    if (!hasInternalResistance) {
      return 0;
    }

    final total = cellInternalResistances.fold<double>(
      0,
      (sum, resistance) => sum + resistance,
    );

    return total / cellInternalResistances.length;
  }

  /// Conservé temporairement pour la compatibilité du code existant.
  /// Cette valeur ne devra plus être affichée ni utilisée pour évaluer la
  /// santé de la batterie.
  double get totalInternalResistance {
    if (!hasInternalResistance) {
      return 0;
    }

    return cellInternalResistances.fold<double>(
      0,
      (total, resistance) => total + resistance,
    );
  }

  double get minimumInternalResistance {
    if (!hasInternalResistance) {
      return 0;
    }

    return cellInternalResistances.reduce(
      (current, next) => current < next ? current : next,
    );
  }

  double get maximumInternalResistance {
    if (!hasInternalResistance) {
      return 0;
    }

    return cellInternalResistances.reduce(
      (current, next) => current > next ? current : next,
    );
  }

  double get maximumInternalResistanceDifference {
    if (!hasInternalResistance) {
      return 0;
    }

    return maximumInternalResistance - minimumInternalResistance;
  }

  factory BatteryMeasurement.fromJson(Map<String, dynamic> json) {
    final measurementType = _normalizeMeasurementType(
      json['measurement_type'] as String?,
    );

    final voltages = _toDoubleList(json['cell_voltages']);
    final storedResistances = _toDoubleList(json['cell_internal_resistances']);

    final keepsResistance =
        measurementType == referenceType || measurementType == afterChargeType;

    return BatteryMeasurement(
      id: (json['id'] as num?)?.toInt(),
      batteryCode: json['battery_code'] as String,
      measuredAt: DateTime.parse(json['measured_at'] as String),
      measurementType: measurementType,
      chargePercent: (json['charge_percent'] as num?)?.toInt() ?? 0,
      cellVoltages: voltages,
      cellInternalResistances: keepsResistance ? storedResistances : const [],
      batteryTemperature: (json['battery_temperature_c'] as num?)?.toDouble(),
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'battery_code': batteryCode,
      'measured_at': measuredAt.toIso8601String(),
      // La base conserve encore ses anciens libellés dans la contrainte SQL.
      // L'application affiche les nouveaux noms, mais enregistre les valeurs
      // historiques acceptées par Supabase.
      'measurement_type': _databaseMeasurementType(measurementType),
      'charge_percent': chargePercent,
      'cell_voltages': cellVoltages,
      'cell_internal_resistances': usesInternalResistance
          ? cellInternalResistances
          : const <double>[],
      // Température facultative uniquement pour les relevés de fin de roulage.
      'battery_temperature_c': isEndOfRun ? batteryTemperature : null,
      // Les notes ne sont plus saisies manuellement. Le service Session peut
      // encore utiliser ce champ comme marqueur technique jusqu'à sa refonte.
      'notes': notes,
    };
  }

  BatteryMeasurement copyWith({
    int? id,
    String? batteryCode,
    DateTime? measuredAt,
    String? measurementType,
    int? chargePercent,
    List<double>? cellVoltages,
    List<double>? cellInternalResistances,
    double? batteryTemperature,
    String? notes,
    bool removeBatteryTemperature = false,
    bool removeNotes = false,
  }) {
    final nextType = measurementType ?? this.measurementType;
    final keepsResistance =
        nextType == referenceType || nextType == afterChargeType;

    return BatteryMeasurement(
      id: id ?? this.id,
      batteryCode: batteryCode ?? this.batteryCode,
      measuredAt: measuredAt ?? this.measuredAt,
      measurementType: nextType,
      chargePercent: chargePercent ?? this.chargePercent,
      cellVoltages: cellVoltages ?? this.cellVoltages,
      cellInternalResistances: keepsResistance
          ? cellInternalResistances ?? this.cellInternalResistances
          : const [],
      batteryTemperature: removeBatteryTemperature
          ? null
          : batteryTemperature ?? this.batteryTemperature,
      notes: removeNotes ? null : notes ?? this.notes,
    );
  }

  static String _databaseMeasurementType(String value) {
    switch (_normalizeMeasurementType(value)) {
      case referenceType:
        return 'Mesure de référence';
      case afterChargeType:
        return 'Après charge';
      case endOfRunType:
        return 'Fin de session';
      default:
        return 'Après charge';
    }
  }

  static String _normalizeMeasurementType(String? value) {
    switch (value?.trim()) {
      case referenceType:
      case 'Mesure de référence':
        return referenceType;
      case afterChargeType:
      case 'Après charge':
        return afterChargeType;
      case endOfRunType:
      case 'Fin de session':
        return endOfRunType;
      case 'Contrôle':
        // Les anciens contrôles contiennent des résistances et sont donc
        // assimilés à des relevés après charge dans l'historique.
        return afterChargeType;
      default:
        return afterChargeType;
    }
  }

  static List<double> _toDoubleList(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<num>()
        .map((item) => item.toDouble())
        .toList(growable: false);
  }
}
