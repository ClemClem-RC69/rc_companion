import 'dart:typed_data';

import 'model_photo_file_store_stub.dart'
    if (dart.library.io) 'model_photo_file_store_io.dart'
    as implementation;

class ModelPhotoFileStore {
  ModelPhotoFileStore._();

  static Future<String?> savePhoto({
    required String userId,
    required String modelId,
    required Uint8List bytes,
    required String originalFilename,
  }) => implementation.savePhoto(
    userId: userId,
    modelId: modelId,
    bytes: bytes,
    originalFilename: originalFilename,
  );

  static Future<String?> findExistingPhotoPath({
    required String userId,
    required String modelId,
  }) => implementation.findExistingPhotoPath(userId: userId, modelId: modelId);

  static Future<Uint8List?> readBytes(String? path) =>
      implementation.readBytes(path);

  static Future<void> deletePhoto(String? path) =>
      implementation.deletePhoto(path);
}
