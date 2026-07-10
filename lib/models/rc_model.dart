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
  /// Null = aucune photo.
  final String? photoUrl;

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
    bool clearPhoto = false,
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
    );
  }

  bool get hasPhoto =>
      photoUrl != null && photoUrl!.trim().isNotEmpty;
}