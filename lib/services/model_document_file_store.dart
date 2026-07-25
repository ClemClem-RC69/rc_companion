import 'dart:typed_data';

import 'model_document_file_store_stub.dart'
    if (dart.library.io) 'model_document_file_store_io.dart'
    as implementation;

class ModelDocumentFileStore {
  ModelDocumentFileStore._();

  static Future<String> saveFile({
    required String userId,
    required String modelId,
    required String documentId,
    required String originalFilename,
    required String sourcePath,
  }) {
    return implementation.saveFile(
      userId: userId,
      modelId: modelId,
      documentId: documentId,
      originalFilename: originalFilename,
      sourcePath: sourcePath,
    );
  }

  static Future<String> saveBytes({
    required String userId,
    required String modelId,
    required String documentId,
    required String originalFilename,
    required Uint8List bytes,
  }) {
    return implementation.saveBytes(
      userId: userId,
      modelId: modelId,
      documentId: documentId,
      originalFilename: originalFilename,
      bytes: bytes,
    );
  }

  static Future<Uint8List> readBytes(String path) {
    return implementation.readBytes(path);
  }

  static Future<bool> exists(String? path) {
    return implementation.exists(path);
  }

  static Future<void> delete(String? path) {
    return implementation.delete(path);
  }
}
