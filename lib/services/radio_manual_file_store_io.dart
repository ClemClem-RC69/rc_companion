import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<String> saveFile({
  required String userId,
  required String radioId,
  required String originalFilename,
  required String sourcePath,
}) async {
  final cleanSourcePath = sourcePath.trim();
  if (cleanSourcePath.isEmpty) {
    throw StateError('Le chemin du manuel sélectionné est invalide.');
  }

  final sourceFile = File(cleanSourcePath);
  if (!await sourceFile.exists()) {
    throw StateError('Le manuel sélectionné est introuvable.');
  }
  if (await sourceFile.length() == 0) {
    throw StateError('Le manuel sélectionné est vide.');
  }

  final destination = await _destinationFile(
    userId: userId,
    radioId: radioId,
    originalFilename: originalFilename,
  );

  if (await destination.exists()) {
    await destination.delete();
  }

  await sourceFile.copy(destination.path);
  return destination.path;
}

Future<String> saveBytes({
  required String userId,
  required String radioId,
  required String originalFilename,
  required Uint8List bytes,
}) async {
  if (bytes.isEmpty) {
    throw StateError('Le manuel sélectionné est vide.');
  }

  final file = await _destinationFile(
    userId: userId,
    radioId: radioId,
    originalFilename: originalFilename,
  );
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Future<Uint8List> readBytes(String path) => File(path).readAsBytes();

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

Future<File> _destinationFile({
  required String userId,
  required String radioId,
  required String originalFilename,
}) async {
  final supportDirectory = await getApplicationSupportDirectory();
  final directory = Directory(
    '${supportDirectory.path}/radio_manuals/'
    '${_safeSegment(userId)}/${_safeSegment(radioId)}',
  );
  await directory.create(recursive: true);

  final extension = _extension(originalFilename);
  final suffix = extension.isEmpty ? '' : '.$extension';
  return File('${directory.path}/manual$suffix');
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
