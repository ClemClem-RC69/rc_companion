class ModelRadioSetup {
  const ModelRadioSetup({
    required this.modelId,
    required this.radioId,

    this.enabledFields = const [],

    this.values = const {},

    this.updatedAt,
  });

  /// Modèle RC concerné.
  final String modelId;

  /// Radio utilisée sur ce modèle.
  final String radioId;

  /// Champs que l'utilisateur souhaite utiliser.
  ///
  /// Exemple :
  /// steering_trim
  /// steering_dual_rate
  /// throttle_epa
  final List<String> enabledFields;

  /// Valeurs enregistrées.
  ///
  /// Exemple :
  ///
  /// {
  ///   "steering_trim":"2",
  ///   "steering_dual_rate":"90 %",
  /// }
  final Map<String, String> values;

  final DateTime? updatedAt;

  factory ModelRadioSetup.fromMap(
    Map<String, dynamic> map,
  ) {
    return ModelRadioSetup(
      modelId: map['model_id'] as String,
      radioId: map['radio_id'] as String,

      enabledFields:
          (map['enabled_fields'] as List<dynamic>? ?? [])
              .cast<String>(),

      values: Map<String, String>.from(
        map['values'] as Map? ?? {},
      ),

      updatedAt: map['updated_at'] == null
          ? null
          : DateTime.parse(
              map['updated_at'] as String,
            ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'model_id': modelId,
      'radio_id': radioId,
      'enabled_fields': enabledFields,
      'values': values,
    };
  }

  ModelRadioSetup copyWith({
    List<String>? enabledFields,
    Map<String, String>? values,
    String? radioId,
  }) {
    return ModelRadioSetup(
      modelId: modelId,
      radioId: radioId ?? this.radioId,
      enabledFields:
          enabledFields ?? this.enabledFields,
      values: values ?? this.values,
      updatedAt: updatedAt,
    );
  }

  bool isEnabled(
    String key,
  ) {
    return enabledFields.contains(key);
  }

  String value(
    String key,
  ) {
    return values[key] ?? '';
  }
}