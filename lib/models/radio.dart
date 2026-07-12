class RcRadio {
  const RcRadio({
    required this.id,
    required this.userId,
    required this.brand,
    required this.model,
    required this.level,
    required this.type,
    required this.channels,
    required this.protocols,
    required this.programmable,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String brand;
  final String model;
  final String level;
  final String type;
  final int channels;
  final List<String> protocols;
  final bool programmable;
  final DateTime createdAt;

  String get fullName => '$brand $model';

  factory RcRadio.fromMap(Map<String, dynamic> map) {
    return RcRadio(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      brand: map['brand'] as String,
      model: map['model'] as String,
      level: map['level'] as String,
      type: map['type'] as String,
      channels: map['channels'] as int,
      protocols: List<String>.from(
        map['protocols'] as List<dynamic>? ?? const [],
      ),
      programmable: map['programmable'] as bool,
      createdAt: DateTime.parse(
        map['created_at'] as String,
      ),
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'brand': brand,
      'model': model,
      'level': level,
      'type': type,
      'channels': channels,
      'protocols': protocols,
      'programmable': programmable,
    };
  }
}