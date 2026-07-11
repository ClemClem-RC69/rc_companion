class ModelSetup {
  const ModelSetup({
    required this.modelId,
    this.enabledFields = const [],
    this.originalValues = const {},
    this.currentValues = const {},
  });

  final String modelId;

  /// Liste des réglages affichés pour ce modèle.
  final List<String> enabledFields;

  /// Valeurs du setup constructeur.
  final Map<String, String> originalValues;

  /// Valeurs actuellement montées sur le modèle.
  final Map<String, String> currentValues;

  factory ModelSetup.empty(String modelId) {
    return ModelSetup(modelId: modelId);
  }

  factory ModelSetup.fromMap(
    Map<String, dynamic> map,
  ) {
    final enabledFields = _stringListFromJson(
      map['enabled_fields'],
    );

    final originalValues = _stringMapFromJson(
      map['original_values'],
    );

    final currentValues = _stringMapFromJson(
      map['current_values'],
    );

    // -------------------------------------------------------------------------
    // COMPATIBILITÉ AVEC LES ANCIENNES COLONNES
    // -------------------------------------------------------------------------

    if (originalValues.isEmpty) {
      _addLegacyValue(
        originalValues,
        'front_shock_oil',
        map['original_shock_oil_front'],
      );

      _addLegacyValue(
        originalValues,
        'rear_shock_oil',
        map['original_shock_oil_rear'],
      );

      _addLegacyValue(
        originalValues,
        'front_diff_oil',
        map['original_diff_oil_front'],
      );

      _addLegacyValue(
        originalValues,
        'center_diff_oil',
        map['original_diff_oil_center'],
      );

      _addLegacyValue(
        originalValues,
        'rear_diff_oil',
        map['original_diff_oil_rear'],
      );

      _addLegacyValue(
        originalValues,
        'spur',
        map['original_spur_gear_teeth'],
      );

      _addLegacyValue(
        originalValues,
        'pinion',
        map['original_pinion_gear_teeth'],
      );

      _addLegacyValue(
        originalValues,
        'notes',
        map['original_notes'],
      );
    }

    if (currentValues.isEmpty) {
      _addLegacyValue(
        currentValues,
        'front_shock_oil',
        map['current_shock_oil_front'],
      );

      _addLegacyValue(
        currentValues,
        'rear_shock_oil',
        map['current_shock_oil_rear'],
      );

      _addLegacyValue(
        currentValues,
        'front_diff_oil',
        map['current_diff_oil_front'],
      );

      _addLegacyValue(
        currentValues,
        'center_diff_oil',
        map['current_diff_oil_center'],
      );

      _addLegacyValue(
        currentValues,
        'rear_diff_oil',
        map['current_diff_oil_rear'],
      );

      _addLegacyValue(
        currentValues,
        'spur',
        map['current_spur_gear_teeth'],
      );

      _addLegacyValue(
        currentValues,
        'pinion',
        map['current_pinion_gear_teeth'],
      );

      _addLegacyValue(
        currentValues,
        'notes',
        map['current_notes'],
      );
    }

    // -------------------------------------------------------------------------
    // INITIALISATION AUTOMATIQUE DU SETUP ACTUEL
    // -------------------------------------------------------------------------
    //
    // Si une valeur actuelle est absente ou vide, on reprend automatiquement
    // la valeur d'origine. Cela corrige notamment les éléments ajoutés après
    // la création initiale du setup, comme les pneus.
    // -------------------------------------------------------------------------

    for (final entry in originalValues.entries) {
      final fieldKey = entry.key;
      final originalValue = entry.value.trim();
      final currentValue =
          currentValues[fieldKey]?.trim() ?? '';

      if (currentValue.isEmpty && originalValue.isNotEmpty) {
        currentValues[fieldKey] = originalValue;
      }
    }

    // Si aucun choix n’existait encore, on active automatiquement les champs
    // qui possèdent une valeur.
    if (enabledFields.isEmpty) {
      final detectedFields = <String>{
        ...originalValues.keys,
        ...currentValues.keys,
      };

      enabledFields.addAll(detectedFields);
    }

    return ModelSetup(
      modelId: map['model_id'] as String,
      enabledFields: enabledFields,
      originalValues: originalValues,
      currentValues: currentValues,
    );
  }

  Map<String, dynamic> toDatabaseMap({
    required String userId,
  }) {
    final normalizedCurrentValues =
        Map<String, String>.from(currentValues);

    // Sécurité supplémentaire avant l’envoi à Supabase :
    // toute valeur actuelle vide reçoit la valeur d’origine.
    for (final fieldKey in enabledFields) {
      final originalValue =
          originalValues[fieldKey]?.trim() ?? '';

      final currentValue =
          normalizedCurrentValues[fieldKey]?.trim() ?? '';

      if (currentValue.isEmpty && originalValue.isNotEmpty) {
        normalizedCurrentValues[fieldKey] = originalValue;
      }
    }

    return {
      'user_id': userId,
      'model_id': modelId,
      'enabled_fields': List<String>.from(enabledFields),
      'original_values':
          Map<String, String>.from(originalValues),
      'current_values': normalizedCurrentValues,
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  ModelSetup copyWith({
    List<String>? enabledFields,
    Map<String, String>? originalValues,
    Map<String, String>? currentValues,
  }) {
    return ModelSetup(
      modelId: modelId,
      enabledFields: enabledFields ??
          List<String>.from(this.enabledFields),
      originalValues: originalValues ??
          Map<String, String>.from(this.originalValues),
      currentValues: currentValues ??
          Map<String, String>.from(this.currentValues),
    );
  }

  ModelSetup copyOriginalToCurrent() {
    return copyWith(
      currentValues: Map<String, String>.from(
        originalValues,
      ),
    );
  }

  String originalValue(String fieldKey) {
    return originalValues[fieldKey] ?? '';
  }

  String currentValue(String fieldKey) {
    final currentValue =
        currentValues[fieldKey]?.trim() ?? '';

    if (currentValue.isNotEmpty) {
      return currentValue;
    }

    return originalValues[fieldKey] ?? '';
  }

  bool isFieldEnabled(String fieldKey) {
    return enabledFields.contains(fieldKey);
  }

  static List<String> _stringListFromJson(
    dynamic value,
  ) {
    if (value is! List) {
      return <String>[];
    }

    return value
        .whereType<Object>()
        .map((item) => item.toString())
        .toList();
  }

  static Map<String, String> _stringMapFromJson(
    dynamic value,
  ) {
    if (value is! Map) {
      return <String, String>{};
    }

    final result = <String, String>{};

    for (final entry in value.entries) {
      final key = entry.key.toString();
      final itemValue = entry.value;

      if (itemValue != null) {
        result[key] = itemValue.toString();
      }
    }

    return result;
  }

  static void _addLegacyValue(
    Map<String, String> target,
    String fieldKey,
    dynamic value,
  ) {
    if (value == null) {
      return;
    }

    final text = value.toString().trim();

    if (text.isNotEmpty) {
      target[fieldKey] = text;
    }
  }
}