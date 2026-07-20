class ModelHistoryEvent {
  const ModelHistoryEvent({
    required this.id,
    required this.modelId,
    required this.eventType,
    required this.eventDate,
    required this.title,
    this.description = '',
    this.location = '',
    this.cost,
    this.durationMinutes,
  });

  static const eventTypes = <String>[
    'Session',
    'Entretien',
    'Réparation',
    'Modification',
    'Autre',
  ];

  final String id;
  final String modelId;
  final String eventType;
  final DateTime eventDate;
  final String title;
  final String description;
  final String location;
  final double? cost;
  final int? durationMinutes;

  factory ModelHistoryEvent.fromJson(Map<String, dynamic> json) {
    return ModelHistoryEvent(
      id: json['id'] as String,
      modelId: json['model_id'] as String,
      eventType: json['event_type'] as String? ?? 'Autre',
      eventDate: DateTime.parse(json['event_date'] as String).toLocal(),
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      location: json['location'] as String? ?? '',
      cost: (json['cost'] as num?)?.toDouble(),
      durationMinutes: (json['duration_minutes'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'model_id': modelId,
      'event_type': eventType,
      'event_date': eventDate.toUtc().toIso8601String(),
      'title': title.trim(),
      'description': _nullableText(description),
      'location': _nullableText(location),
      'cost': cost,
      'duration_minutes': durationMinutes,
    };
  }

  ModelHistoryEvent copyWith({
    String? id,
    String? modelId,
    String? eventType,
    DateTime? eventDate,
    String? title,
    String? description,
    String? location,
    double? cost,
    int? durationMinutes,
    bool clearCost = false,
    bool clearDuration = false,
  }) {
    return ModelHistoryEvent(
      id: id ?? this.id,
      modelId: modelId ?? this.modelId,
      eventType: eventType ?? this.eventType,
      eventDate: eventDate ?? this.eventDate,
      title: title ?? this.title,
      description: description ?? this.description,
      location: location ?? this.location,
      cost: clearCost ? null : cost ?? this.cost,
      durationMinutes: clearDuration
          ? null
          : durationMinutes ?? this.durationMinutes,
    );
  }

  static String? _nullableText(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
