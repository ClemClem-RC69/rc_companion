import 'dart:typed_data';

Future<String> saveFile({
  required String userId,
  required String radioId,
  required String originalFilename,
  required String sourcePath,
}) {
  throw UnsupportedError('Stockage local du manuel non disponible.');
}

Future<String> saveBytes({
  required String userId,
  required String radioId,
  required String originalFilename,
  required Uint8List bytes,
}) {
  throw UnsupportedError('Stockage local du manuel non disponible.');
}

Future<Uint8List> readBytes(String path) {
  throw UnsupportedError('Lecture locale du manuel non disponible.');
}

Future<bool> exists(String? path) async => false;

Future<void> delete(String? path) async {}
