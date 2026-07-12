class RadioProfile {
  const RadioProfile({
    required this.id,
    required this.userId,
    required this.radioId,
    required this.name,
    required this.createdAt,
    this.updatedAt,
    this.enabledFields = const [],
    this.values = const {},
  });

  final String id;
  final String userId;
  final String radioId;
  final String name;

  /// Réglages que l’utilisateur a choisi d’afficher.
  ///
  /// Exemples :
  /// steering_rate
  /// steering_expo
  /// throttle_limit
  /// brake_rate
  /// abs
  /// gyro_gain
  /// notes
  final List<String> enabledFields;

  /// Valeurs enregistrées pour les réglages activés.
  ///
  /// Exemple :
  /// {
  ///   'steering_rate': '80 %',
  ///   'steering_expo': '-20 %',
  /// }
  final Map<String, String> values;

  final DateTime createdAt;
  final DateTime? updatedAt;

  factory RadioProfile.fromMap(
    Map<String, dynamic> map,
  ) {
    return RadioProfile(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      radioId: map['radio_id'] as String,
      name: map['name'] as String? ?? '',
      enabledFields: _stringListFromJson(
        map['enabled_fields'],
      ),
      values: _stringMapFromJson(
        map['values'],
      ),
      createdAt: DateTime.parse(
        map['created_at'] as String,
      ),
      updatedAt: map['updated_at'] == null
          ? null
          : DateTime.parse(
              map['updated_at'] as String,
            ),
    );
  }

  Map<String, dynamic> toInsertMap({
    required String userId,
  }) {
    return {
      'user_id': userId,
      'radio_id': radioId,
      'name': name.trim(),
      'enabled_fields': List<String>.from(
        enabledFields,
      ),
      'values': Map<String, String>.from(
        values,
      ),
    };
  }

  Map<String, dynamic> toUpdateMap() {
    return {
      'name': name.trim(),
      'enabled_fields': List<String>.from(
        enabledFields,
      ),
      'values': Map<String, String>.from(
        values,
      ),
      'updated_at': DateTime.now().toIso8601String(),
    };
  }

  RadioProfile copyWith({
    String? name,
    List<String>? enabledFields,
    Map<String, String>? values,
  }) {
    return RadioProfile(
      id: id,
      userId: userId,
      radioId: radioId,
      name: name ?? this.name,
      enabledFields: enabledFields ??
          List<String>.from(this.enabledFields),
      values: values ??
          Map<String, String>.from(this.values),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  String value(String fieldKey) {
    return values[fieldKey] ?? '';
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
      if (entry.value != null) {
        result[entry.key.toString()] =
            entry.value.toString();
      }
    }

    return result;
  }
}