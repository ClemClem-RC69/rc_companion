class BatteryMeasurement {
  const BatteryMeasurement({
    this.id,
    required this.batteryCode,
    required this.measuredAt,
    required this.measurementType,
    required this.chargePercent,
    required this.cellVoltages,
    required this.cellInternalResistances,
    this.batteryTemperature,
    this.notes,
  });

  static const String afterChargeType = 'Après charge';
  static const String controlType = 'Contrôle';

  static const List<String> measurementTypes = [
    afterChargeType,
    controlType,
  ];

  final int? id;
  final String batteryCode;
  final DateTime measuredAt;
  final String measurementType;
  final int chargePercent;
  final List<double> cellVoltages;
  final List<double> cellInternalResistances;
  final double? batteryTemperature;
  final String? notes;

  int get cellCount => cellVoltages.length;

  bool get isAfterCharge => measurementType == afterChargeType;

  bool get isControl => measurementType == controlType;

  double get totalVoltage {
    return cellVoltages.fold<double>(
      0,
      (total, voltage) => total + voltage,
    );
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
    if (cellInternalResistances.isEmpty) {
      return 0;
    }

    final total = cellInternalResistances.fold<double>(
      0,
      (sum, resistance) => sum + resistance,
    );

    return total / cellInternalResistances.length;
  }

  double get minimumInternalResistance {
    if (cellInternalResistances.isEmpty) {
      return 0;
    }

    return cellInternalResistances.reduce(
      (current, next) => current < next ? current : next,
    );
  }

  double get maximumInternalResistance {
    if (cellInternalResistances.isEmpty) {
      return 0;
    }

    return cellInternalResistances.reduce(
      (current, next) => current > next ? current : next,
    );
  }

  double get maximumInternalResistanceDifference {
    if (cellInternalResistances.isEmpty) {
      return 0;
    }

    return maximumInternalResistance - minimumInternalResistance;
  }

  factory BatteryMeasurement.fromJson(Map<String, dynamic> json) {
    final voltages = _toDoubleList(json['cell_voltages']);
    final resistances = _toDoubleList(
      json['cell_internal_resistances'],
    );

    final rawMeasurementType =
        json['measurement_type'] as String? ?? afterChargeType;

    return BatteryMeasurement(
      id: (json['id'] as num?)?.toInt(),
      batteryCode: json['battery_code'] as String,
      measuredAt: DateTime.parse(json['measured_at'] as String),
      measurementType: measurementTypes.contains(rawMeasurementType)
          ? rawMeasurementType
          : afterChargeType,
      chargePercent: (json['charge_percent'] as num).toInt(),
      cellVoltages: voltages,
      cellInternalResistances: resistances,
      batteryTemperature:
          (json['battery_temperature_c'] as num?)?.toDouble(),
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'battery_code': batteryCode,
      'measured_at': measuredAt.toIso8601String(),
      'measurement_type': measurementType,
      'charge_percent': chargePercent,
      'cell_voltages': cellVoltages,
      'cell_internal_resistances': cellInternalResistances,
      'battery_temperature_c': batteryTemperature,
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
    return BatteryMeasurement(
      id: id ?? this.id,
      batteryCode: batteryCode ?? this.batteryCode,
      measuredAt: measuredAt ?? this.measuredAt,
      measurementType: measurementType ?? this.measurementType,
      chargePercent: chargePercent ?? this.chargePercent,
      cellVoltages: cellVoltages ?? this.cellVoltages,
      cellInternalResistances:
          cellInternalResistances ?? this.cellInternalResistances,
      batteryTemperature: removeBatteryTemperature
          ? null
          : batteryTemperature ?? this.batteryTemperature,
      notes: removeNotes ? null : notes ?? this.notes,
    );
  }

  static List<double> _toDoubleList(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .map((item) => (item as num).toDouble())
        .toList(growable: false);
  }
}
