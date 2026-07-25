import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<String> saveBytes({
  required String userId,
  required String modelId,
  required String documentId,
  required String originalFilename,
  required Uint8List bytes,
}) async {
  if (bytes.isEmpty) {
    throw StateError('Le document sélectionné est vide.');
  }

  final supportDirectory = await getApplicationSupportDirectory();
  final directory = Directory(
    '${supportDirectory.path}/model_documents/'
    '${_safeSegment(userId)}/${_safeSegment(modelId)}',
  );
  await directory.create(recursive: true);

  final extension = _extension(originalFilename);
  final suffix = extension.isEmpty ? '' : '.$extension';
  final file = File('${directory.path}/${_safeSegment(documentId)}$suffix');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Future<Uint8List> readBytes(String path) {
  return File(path).readAsBytes();
}

Future<bool> exists(String? path) async {
  if (path == null || path.trim().isEmpty) {
    return false;
  }
  return File(path).exists();
}

Future<void> delete(String? path) async {
  if (path == null || path.trim().isEmpty) {
    return;
  }

  final file = File(path);
  if (await file.exists()) {
    await file.delete();
  }
}

String _extension(String filename) {
  final clean = filename.toLowerCase().trim();
  final dot = clean.lastIndexOf('.');
  if (dot == -1 || dot == clean.length - 1) {
    return '';
  }
  return clean.substring(dot + 1).replaceAll(RegExp(r'[^a-z0-9]'), '');
}

String _safeSegment(String value) {
  final safe = value.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
  return safe.isEmpty ? 'item' : safe;
}
