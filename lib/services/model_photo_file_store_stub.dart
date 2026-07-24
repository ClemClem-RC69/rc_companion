import 'dart:typed_data';

Future<String?> savePhoto({
  required String userId,
  required String modelId,
  required Uint8List bytes,
  required String originalFilename,
}) async => null;

Future<Uint8List?> readBytes(String? path) async => null;

Future<void> deletePhoto(String? path) async {}
