class ModelDocument {
  const ModelDocument({
    required this.id,
    required this.userId,
    required this.modelId,
    required this.documentName,
    required this.documentType,
    required this.storagePath,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String modelId;

  /// Exemples :
  /// Notice
  /// Vue éclatée
  /// Manuel ESC
  /// Manuel radio
  /// Autre
  final String documentType;

  final String documentName;

  /// Chemin relatif dans le bucket privé model-documents.
  final String storagePath;

  final DateTime createdAt;

  factory ModelDocument.fromMap(
    Map<String, dynamic> map,
  ) {
    return ModelDocument(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      modelId: map['model_id'] as String,
      documentName: map['document_name'] as String,
      documentType:
          map['document_type'] as String? ?? 'Autre',
      storagePath: map['storage_path'] as String,
      createdAt: DateTime.parse(
        map['created_at'] as String,
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'model_id': modelId,
      'document_name': documentName,
      'document_type': documentType,
      'storage_path': storagePath,
      'created_at': createdAt.toIso8601String(),
    };
  }
}