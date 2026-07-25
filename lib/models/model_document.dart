class ModelDocument {
  const ModelDocument({
    required this.id,
    required this.userId,
    required this.modelId,
    required this.documentName,
    required this.documentType,
    required this.storagePath,
    required this.createdAt,
    this.localPath,
    this.pendingUpload = false,
  });

  final String id;
  final String userId;
  final String modelId;
  final String documentType;
  final String documentName;
  final String storagePath;
  final DateTime createdAt;
  final String? localPath;
  final bool pendingUpload;

  bool get hasLocalFile => localPath != null && localPath!.trim().isNotEmpty;

  ModelDocument copyWith({
    String? id,
    String? userId,
    String? modelId,
    String? documentName,
    String? documentType,
    String? storagePath,
    DateTime? createdAt,
    String? localPath,
    bool clearLocalPath = false,
    bool? pendingUpload,
  }) {
    return ModelDocument(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      modelId: modelId ?? this.modelId,
      documentName: documentName ?? this.documentName,
      documentType: documentType ?? this.documentType,
      storagePath: storagePath ?? this.storagePath,
      createdAt: createdAt ?? this.createdAt,
      localPath: clearLocalPath ? null : localPath ?? this.localPath,
      pendingUpload: pendingUpload ?? this.pendingUpload,
    );
  }

  factory ModelDocument.fromMap(Map<String, dynamic> map) {
    return ModelDocument(
      id: map['id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      modelId: map['model_id']?.toString() ?? '',
      documentName: map['document_name']?.toString() ?? 'Document',
      documentType: map['document_type']?.toString() ?? 'Autre',
      storagePath: map['storage_path']?.toString() ?? '',
      createdAt:
          DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.now(),
      localPath: map['local_path']?.toString(),
      pendingUpload: map['pending_upload'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'user_id': userId,
      'model_id': modelId,
      'document_name': documentName,
      'document_type': documentType,
      'storage_path': storagePath,
      'created_at': createdAt.toUtc().toIso8601String(),
      'local_path': localPath,
      'pending_upload': pendingUpload,
    };
  }

  Map<String, dynamic> toRemoteMap() {
    return <String, dynamic>{
      'id': id,
      'user_id': userId,
      'model_id': modelId,
      'document_name': documentName,
      'document_type': documentType,
      'storage_path': storagePath,
      'created_at': createdAt.toUtc().toIso8601String(),
    };
  }
}
