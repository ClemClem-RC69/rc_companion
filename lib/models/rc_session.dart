import 'battery.dart';
import 'rc_model.dart';

/// Relevés facultatifs effectués après un roulage.
///
/// Ils peuvent être saisis immédiatement sur le terrain ou complétés plus tard
/// depuis l'historique de la batterie.
class BatteryRunReading {
  const BatteryRunReading({
    required this.batteryId,
    this.measuredAt,
    this.remainingCapacityPercent,
    this.cellVoltages = const [],
    // Anciens champs conservés temporairement pour que les écrans et les
    // données existantes continuent de fonctionner pendant la refonte.
    // Les nouveaux relevés de fin de roulage ne les renseignent plus.
    this.cellResistances = const [],
    this.temperatureCelsius,
  });

  final String batteryId;
  final DateTime? measuredAt;

  /// Capacité restante du pack en pourcentage.
  final double? remainingCapacityPercent;

  /// Tension de chaque cellule en volts.
  final List<double> cellVoltages;

  /// Compatibilité avec les anciennes données uniquement.
  final List<double> cellResistances;

  /// Compatibilité avec les anciennes données uniquement.
  final double? temperatureCelsius;

  double get totalVoltage {
    return cellVoltages.fold<double>(0, (total, voltage) => total + voltage);
  }

  /// Un relevé de fin de roulage est considéré comme renseigné dès qu'il
  /// contient un pourcentage ou au moins une tension de cellule.
  bool get hasMeasurements {
    return remainingCapacityPercent != null || cellVoltages.isNotEmpty;
  }

  /// Relevé complet pouvant être ajouté à l'historique batterie.
  bool get isCompleteEndOfRunReading {
    return remainingCapacityPercent != null && cellVoltages.isNotEmpty;
  }

  BatteryRunReading copyWith({
    String? batteryId,
    DateTime? measuredAt,
    double? remainingCapacityPercent,
    List<double>? cellVoltages,
    List<double>? cellResistances,
    double? temperatureCelsius,
    bool clearMeasuredAt = false,
    bool clearCapacity = false,
    bool clearTemperature = false,
    bool clearResistances = false,
  }) {
    return BatteryRunReading(
      batteryId: batteryId ?? this.batteryId,
      measuredAt: clearMeasuredAt ? null : measuredAt ?? this.measuredAt,
      remainingCapacityPercent: clearCapacity
          ? null
          : remainingCapacityPercent ?? this.remainingCapacityPercent,
      cellVoltages: cellVoltages ?? this.cellVoltages,
      cellResistances: clearResistances
          ? const []
          : cellResistances ?? this.cellResistances,
      temperatureCelsius: clearTemperature
          ? null
          : temperatureCelsius ?? this.temperatureCelsius,
    );
  }
}

class HistoricalBattery {
  const HistoricalBattery({
    this.name = '',
    this.brand = '',
    this.capacityMah,
    this.cells,
    this.cRate,
  });

  final String name;
  final String brand;
  final int? capacityMah;
  final int? cells;
  final int? cRate;

  bool get isEmpty =>
      name.trim().isEmpty &&
      brand.trim().isEmpty &&
      capacityMah == null &&
      cells == null &&
      cRate == null;

  String get displayLabel {
    final values = <String>[
      if (brand.trim().isNotEmpty) brand.trim(),
      if (capacityMah != null) '$capacityMah mAh',
      if (cells != null) '${cells}S',
      if (cRate != null) '${cRate}C',
    ];
    return values.isEmpty ? 'Ancienne batterie' : values.join(' — ');
  }

  factory HistoricalBattery.fromJson(Map<String, dynamic> json) {
    return HistoricalBattery(
      name: json['name']?.toString() ?? '',
      brand: json['brand']?.toString() ?? '',
      capacityMah: (json['capacity_mah'] as num?)?.toInt(),
      cells: (json['cells'] as num?)?.toInt(),
      cRate: (json['c_rate'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'name': name.trim(),
      'brand': brand.trim(),
      'capacity_mah': capacityMah,
      'cells': cells,
      'c_rate': cRate,
    };
  }
}

/// Un roulage correspond à l'utilisation d'un jeu de batteries pendant une
/// durée donnée au sein d'une session pouvant durer toute la journée.
class RcRun {
  const RcRun({
    required this.startedAt,
    required this.batteries,
    this.endedAt,
    this.durationMinutes,
    this.readings = const [],
    this.historicalBatteries = const [],
    this.notes = '',
  });

  final DateTime startedAt;
  final DateTime? endedAt;
  final List<Battery> batteries;

  /// Batteries anciennes renseignées uniquement à titre historique.
  final List<HistoricalBattery> historicalBatteries;

  /// Durée saisie manuellement ou calculée à partir des heures de début/fin.
  final int? durationMinutes;

  /// Un relevé distinct par batterie utilisée.
  final List<BatteryRunReading> readings;

  final String notes;

  bool get isActive => endedAt == null && durationMinutes == null;

  int get effectiveDurationMinutes {
    if (durationMinutes != null) {
      return durationMinutes!;
    }

    if (endedAt == null) {
      return 0;
    }

    return endedAt!.difference(startedAt).inMinutes;
  }

  bool get hasMeasurements =>
      readings.any((reading) => reading.hasMeasurements);

  bool hasReadingFor(String batteryId) {
    return readings.any((reading) => reading.batteryId == batteryId);
  }

  RcRun copyWith({
    DateTime? startedAt,
    DateTime? endedAt,
    List<Battery>? batteries,
    int? durationMinutes,
    List<BatteryRunReading>? readings,
    List<HistoricalBattery>? historicalBatteries,
    String? notes,
    bool clearEndedAt = false,
    bool clearDuration = false,
  }) {
    return RcRun(
      startedAt: startedAt ?? this.startedAt,
      endedAt: clearEndedAt ? null : endedAt ?? this.endedAt,
      batteries: batteries ?? this.batteries,
      durationMinutes: clearDuration
          ? null
          : durationMinutes ?? this.durationMinutes,
      readings: readings ?? this.readings,
      historicalBatteries: historicalBatteries ?? this.historicalBatteries,
      notes: notes ?? this.notes,
    );
  }
}

/// Session complète d'un modèle.
///
/// Une session peut rester ouverte toute la journée et contenir plusieurs
/// roulages avec différents jeux de batteries.
class RcSession {
  RcSession({
    required this.model,
    DateTime? startedAt,
    this.endedAt,
    List<RcRun>? runs,
    this.drivingNotes = '',
    this.breakages = '',
    this.partsReplacedOnSite = '',
    this.maintenanceToDo = '',
    this.partsToOrder = '',
    this.changesBeforeNextSession = '',
    String generalNotes = '',
    this.location = '',
    this.id,
    this.isHistorical = false,
    // Compatibilité temporaire avec l'ancien écran Sessions.
    DateTime? date,
    List<Battery>? batteries,
    int? durationMinutes,
    String? notes,
  }) : startedAt = startedAt ?? date ?? DateTime.now(),
       runs =
           runs ??
           _legacyRuns(
             date: startedAt ?? date ?? DateTime.now(),
             batteries: batteries,
             durationMinutes: durationMinutes,
             notes: notes,
           ),
       generalNotes = generalNotes.isNotEmpty ? generalNotes : notes ?? '';

  final String? id;
  final RcModel model;
  final DateTime startedAt;
  final DateTime? endedAt;
  final List<RcRun> runs;

  final String location;
  final String drivingNotes;
  final String breakages;
  final String partsReplacedOnSite;
  final String maintenanceToDo;
  final String partsToOrder;
  final String changesBeforeNextSession;
  final String generalNotes;

  /// V2 : session créée explicitement via le parcours « Session antérieure ».
  ///
  /// Ce marqueur est conservé localement pendant la phase de test V2 afin
  /// qu'une saisie rétroactive n'influence ni l'état opérationnel du modèle,
  /// ni l'état / la santé actuelle des batteries.
  final bool isHistorical;

  bool get isClosed => endedAt != null;

  bool get hasActiveRun => runs.any((run) => run.isActive);

  RcRun? get activeRun {
    for (final run in runs.reversed) {
      if (run.isActive) {
        return run;
      }
    }
    return null;
  }

  int get totalDurationMinutes {
    return runs.fold(0, (total, run) => total + run.effectiveDurationMinutes);
  }

  List<Battery> get usedBatteries {
    final uniqueBatteries = <String, Battery>{};

    for (final run in runs) {
      for (final battery in run.batteries) {
        uniqueBatteries[battery.id] = battery;
      }
    }

    return uniqueBatteries.values.toList(growable: false);
  }

  // Propriétés conservées temporairement pour l'ancien écran.
  DateTime get date => startedAt;
  List<Battery> get batteries => usedBatteries;
  int get durationMinutes => totalDurationMinutes;
  String get notes => generalNotes;

  RcSession copyWith({
    String? id,
    RcModel? model,
    DateTime? startedAt,
    DateTime? endedAt,
    List<RcRun>? runs,
    String? location,
    String? drivingNotes,
    String? breakages,
    String? partsReplacedOnSite,
    String? maintenanceToDo,
    String? partsToOrder,
    String? changesBeforeNextSession,
    String? generalNotes,
    bool? isHistorical,
    bool clearEndedAt = false,
  }) {
    return RcSession(
      id: id ?? this.id,
      model: model ?? this.model,
      startedAt: startedAt ?? this.startedAt,
      endedAt: clearEndedAt ? null : endedAt ?? this.endedAt,
      runs: runs ?? this.runs,
      location: location ?? this.location,
      drivingNotes: drivingNotes ?? this.drivingNotes,
      breakages: breakages ?? this.breakages,
      partsReplacedOnSite: partsReplacedOnSite ?? this.partsReplacedOnSite,
      maintenanceToDo: maintenanceToDo ?? this.maintenanceToDo,
      partsToOrder: partsToOrder ?? this.partsToOrder,
      changesBeforeNextSession:
          changesBeforeNextSession ?? this.changesBeforeNextSession,
      generalNotes: generalNotes ?? this.generalNotes,
      isHistorical: isHistorical ?? this.isHistorical,
    );
  }

  static List<RcRun> _legacyRuns({
    required DateTime date,
    List<Battery>? batteries,
    int? durationMinutes,
    String? notes,
  }) {
    if (batteries == null || batteries.isEmpty) {
      return const [];
    }

    return [
      RcRun(
        startedAt: date,
        endedAt: date.add(Duration(minutes: durationMinutes ?? 0)),
        durationMinutes: durationMinutes,
        batteries: List<Battery>.unmodifiable(batteries),
        notes: notes ?? '',
      ),
    ];
  }
}
