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
    this.id,
    this.photoUrl,
    this.photoLocalPath,
    this.photoPendingUpload = false,
    this.weightKg,
    this.acquisitionDate,
    this.purchaseType,
    this.purchaseLocation,

    // Radio associée au modèle
    this.radioId,
  });

  /// Identifiant unique du modèle dans Supabase.
  ///
  /// Il peut rester null pour les objets créés localement avant leur
  /// enregistrement en base.
  final String? id;

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

  /// Chemin persistant de la copie locale utilisée hors ligne.
  final String? photoLocalPath;

  /// Indique que la copie locale doit encore être envoyée vers Supabase.
  final bool photoPendingUpload;

  /// Poids du modèle en kilogrammes.
  final double? weightKg;

  /// Date d’achat ou d’acquisition du modèle.
  final DateTime? acquisitionDate;

  /// Type d’achat : « Neuf » ou « Occasion ».
  final String? purchaseType;

  /// Magasin, site, particulier ou autre lieu d’achat.
  final String? purchaseLocation;

  /// Radio associée au modèle.
  /// Null = aucune radio affectée.
  final String? radioId;

  RcModel copyWith({
    String? id,
    String? name,
    String? brand,
    String? category,
    String? discipline,
    String? motorization,
    String? scale,
    int? batteryCount,
    String? maxCells,
    String? photoUrl,
    String? photoLocalPath,
    bool? photoPendingUpload,
    double? weightKg,
    DateTime? acquisitionDate,
    String? purchaseType,
    String? purchaseLocation,
    String? radioId,
    bool clearId = false,
    bool clearPhoto = false,
    bool clearPhotoLocalPath = false,
    bool clearAcquisitionDate = false,
    bool clearPurchaseType = false,
    bool clearPurchaseLocation = false,
    bool clearRadio = false,
  }) {
    return RcModel(
      id: clearId ? null : (id ?? this.id),
      name: name ?? this.name,
      brand: brand ?? this.brand,
      category: category ?? this.category,
      discipline: discipline ?? this.discipline,
      motorization: motorization ?? this.motorization,
      scale: scale ?? this.scale,
      batteryCount: batteryCount ?? this.batteryCount,
      maxCells: maxCells ?? this.maxCells,
      photoUrl: clearPhoto ? null : (photoUrl ?? this.photoUrl),
      photoLocalPath: clearPhotoLocalPath
          ? null
          : (photoLocalPath ?? this.photoLocalPath),
      photoPendingUpload: photoPendingUpload ?? this.photoPendingUpload,
      weightKg: weightKg ?? this.weightKg,
      acquisitionDate: clearAcquisitionDate
          ? null
          : (acquisitionDate ?? this.acquisitionDate),
      purchaseType: clearPurchaseType
          ? null
          : (purchaseType ?? this.purchaseType),
      purchaseLocation: clearPurchaseLocation
          ? null
          : (purchaseLocation ?? this.purchaseLocation),
      radioId: clearRadio ? null : (radioId ?? this.radioId),
    );
  }

  bool get hasId => id != null && id!.trim().isNotEmpty;

  bool get hasPhoto =>
      (photoLocalPath != null && photoLocalPath!.trim().isNotEmpty) ||
      (photoUrl != null && photoUrl!.trim().isNotEmpty);

  bool get hasRadio => radioId != null && radioId!.trim().isNotEmpty;

  bool get hasAcquisitionDate => acquisitionDate != null;

  String get formattedAcquisitionDate {
    final date = acquisitionDate;
    if (date == null) {
      return 'Non renseignée';
    }

    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  String get formattedAcquisition {
    final values = <String>[
      if (acquisitionDate != null) formattedAcquisitionDate,
      if (purchaseType != null && purchaseType!.trim().isNotEmpty)
        purchaseType!.trim(),
      if (purchaseLocation != null && purchaseLocation!.trim().isNotEmpty)
        purchaseLocation!.trim(),
    ];

    return values.isEmpty ? 'Non renseignée' : values.join(' • ');
  }

  String get formattedWeight {
    if (weightKg == null) {
      return '-';
    }

    return '${weightKg!.toStringAsFixed(2).replaceAll('.', ',')} kg';
  }
}
