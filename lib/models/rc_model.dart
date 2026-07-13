class RcModel {
  const RcModel({
    required this.name,
    required this.brand,
    required this.category,
    required this.discipline,
    required this.motorization,
    required this.scale,
    required this.batteryCount,
    required this.maxCells,
    this.photoUrl,
    this.weightKg,

    // Radio associée au modèle
    this.radioId,
  });

  final String name;
  final String brand;
  final String category;
  final String discipline;
  final String motorization;
  final String scale;
  final int batteryCount;
  final String maxCells;

  /// URL de la photo stockée dans Supabase Storage.
  final String? photoUrl;

  /// Poids du modèle en kilogrammes.
  final double? weightKg;

  /// Radio associée au modèle.
  /// Null = aucune radio affectée.
  final String? radioId;

  RcModel copyWith({
    String? name,
    String? brand,
    String? category,
    String? discipline,
    String? motorization,
    String? scale,
    int? batteryCount,
    String? maxCells,
    String? photoUrl,
    double? weightKg,
    String? radioId,
    bool clearPhoto = false,
    bool clearRadio = false,
  }) {
    return RcModel(
      name: name ?? this.name,
      brand: brand ?? this.brand,
      category: category ?? this.category,
      discipline: discipline ?? this.discipline,
      motorization: motorization ?? this.motorization,
      scale: scale ?? this.scale,
      batteryCount: batteryCount ?? this.batteryCount,
      maxCells: maxCells ?? this.maxCells,
      photoUrl: clearPhoto ? null : (photoUrl ?? this.photoUrl),
      weightKg: weightKg ?? this.weightKg,
      radioId: clearRadio ? null : (radioId ?? this.radioId),
    );
  }

  bool get hasPhoto =>
      photoUrl != null && photoUrl!.trim().isNotEmpty;

  bool get hasRadio =>
      radioId != null && radioId!.trim().isNotEmpty;

  String get formattedWeight {
    if (weightKg == null) {
      return '-';
    }

    return '${weightKg!.toStringAsFixed(2).replaceAll('.', ',')} kg';
  }
}