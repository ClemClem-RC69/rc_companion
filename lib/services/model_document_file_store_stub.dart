import 'dart:typed_data';

Future<String> saveFile({
  required String userId,
  required String modelId,
  required String documentId,
  required String originalFilename,
  required String sourcePath,
}) {
  throw UnsupportedError(
    'Le stockage local des documents n’est pas disponible sur cette plateforme.',
  );
}

Future<String> saveBytes({
  required String userId,
  required String modelId,
  required String documentId,
  required String originalFilename,
  required Uint8List bytes,
}) {
  throw UnsupportedError(
    'Le stockage local des documents n’est pas disponible sur cette plateforme.',
  );
}

Future<Uint8List> readBytes(String path) {
  throw UnsupportedError(
    'La lecture locale des documents n’est pas disponible sur cette plateforme.',
  );
}

Future<bool> exists(String? path) async => false;

Future<void> delete(String? path) async {}
