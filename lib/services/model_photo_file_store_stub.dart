import 'dart:typed_data';

Future<String?> savePhoto({
  required String userId,
  required String modelId,
  required Uint8List bytes,
  required String originalFilename,
}) async {
  return null;
}

Future<String?> findExistingPhotoPath({
  required String userId,
  required String modelId,
}) async {
  return null;
}

Future<Uint8List?> readBytes(String? path) async {
  return null;
}

Future<void> deletePhoto(String? path) async {}
