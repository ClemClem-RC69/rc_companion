enum BatteryChargeState {
  charged,
  storage,
  partial,
  discharged,
}

extension BatteryChargeStateLabel on BatteryChargeState {
  String get label {
    return switch (this) {
      BatteryChargeState.charged => 'Chargée',
      BatteryChargeState.storage => 'Storage',
      BatteryChargeState.partial => 'Partiellement chargée',
      BatteryChargeState.discharged => 'Déchargée',
    };
  }

  bool get isSelectableForRun {
    return this == BatteryChargeState.charged ||
        this == BatteryChargeState.partial;
  }
}

class Battery {
  const Battery({
    required this.id,
    required this.technology,
    required this.brand,
    required this.capacity,
    required this.cells,
    required this.cRate,
    required this.status,
    this.chargeState = BatteryChargeState.discharged,
    this.pairId,
    this.notes,
  });

  final String id;
  final String technology;
  final String brand;
  final int capacity;
  final String cells;
  final int cRate;

  /// Statut administratif conservé pour la compatibilité des données.
  final String status;

  /// État énergétique calculé à partir du dernier relevé utile.
  final BatteryChargeState chargeState;

  final String? pairId;
  final String? notes;

  bool get isUsable =>
      status == 'Active' && chargeState.isSelectableForRun;

  bool get isPaired => pairId != null && pairId!.isNotEmpty;

  factory Battery.fromJson(Map<String, dynamic> json) {
    return Battery(
      id: json['battery_code'] as String,
      technology: json['technology'] as String,
      brand: json['brand'] as String,
      capacity: (json['capacity_mah'] as num).toInt(),
      cells: '${json['cells']}S',
      cRate: (json['c_rate'] as num).toInt(),
      pairId: json['pair_id'] as String?,
      status: json['status'] as String? ?? 'Active',
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'battery_code': id,
      'technology': technology,
      'brand': brand,
      'capacity_mah': capacity,
      'cells': int.parse(cells.replaceAll('S', '')),
      'c_rate': cRate,
      'pair_id': pairId,
      'status': status,
      'notes': notes,
    };
  }

  Battery copyWith({
    String? id,
    String? technology,
    String? brand,
    int? capacity,
    String? cells,
    int? cRate,
    String? status,
    BatteryChargeState? chargeState,
    String? pairId,
    String? notes,
    bool removePair = false,
  }) {
    return Battery(
      id: id ?? this.id,
      technology: technology ?? this.technology,
      brand: brand ?? this.brand,
      capacity: capacity ?? this.capacity,
      cells: cells ?? this.cells,
      cRate: cRate ?? this.cRate,
      pairId: removePair ? null : pairId ?? this.pairId,
      status: status ?? this.status,
      chargeState: chargeState ?? this.chargeState,
      notes: notes ?? this.notes,
    );
  }
}
