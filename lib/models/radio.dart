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
    this.manualName,
    this.manualStoragePath,
    this.manualLocalPath,
    this.manualPendingUpload = false,
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

  /// Nom du manuel (PDF/JPG/JPEG/PNG/WEBP), synchronisé avec Supabase.
  final String? manualName;

  /// Chemin du manuel stocké sur Google Drive, synchronisé.
  final String? manualStoragePath;

  /// Copie locale du manuel pour consultation hors ligne.
  final String? manualLocalPath;

  /// Vrai quand une nouvelle copie locale doit encore être envoyée au cloud.
  final bool manualPendingUpload;

  String get fullName => '$brand $model';

  bool get hasManual {
    final name = manualName?.trim() ?? '';
    final localPath = manualLocalPath?.trim() ?? '';
    final storagePath = manualStoragePath?.trim() ?? '';
    return name.isNotEmpty && (localPath.isNotEmpty || storagePath.isNotEmpty);
  }

  RcRadio copyWith({
    String? id,
    String? userId,
    String? brand,
    String? model,
    String? level,
    String? type,
    int? channels,
    List<String>? protocols,
    bool? programmable,
    DateTime? createdAt,
    String? manualName,
    bool clearManualName = false,
    String? manualStoragePath,
    bool clearManualStoragePath = false,
    String? manualLocalPath,
    bool clearManualLocalPath = false,
    bool? manualPendingUpload,
  }) {
    return RcRadio(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      level: level ?? this.level,
      type: type ?? this.type,
      channels: channels ?? this.channels,
      protocols: protocols ?? this.protocols,
      programmable: programmable ?? this.programmable,
      createdAt: createdAt ?? this.createdAt,
      manualName: clearManualName ? null : manualName ?? this.manualName,
      manualStoragePath: clearManualStoragePath
          ? null
          : manualStoragePath ?? this.manualStoragePath,
      manualLocalPath: clearManualLocalPath
          ? null
          : manualLocalPath ?? this.manualLocalPath,
      manualPendingUpload: manualPendingUpload ?? this.manualPendingUpload,
    );
  }

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
      createdAt: DateTime.parse(map['created_at'] as String),
      manualName: _nullableText(map['manual_name']),
      manualStoragePath: _nullableText(map['manual_storage_path']),
      manualLocalPath: _nullableText(map['manual_local_path']),
      manualPendingUpload: map['manual_pending_upload'] == true,
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
      'manual_name': manualName,
      'manual_storage_path': manualStoragePath,
    };
  }

  static String? _nullableText(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
