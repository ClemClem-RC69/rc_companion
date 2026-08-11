import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'offline_storage_service.dart';

Future<String> saveFile({
  required String userId,
  required String modelId,
  required String documentId,
  required String originalFilename,
  required String sourcePath,
}) async {
  final cleanSourcePath = sourcePath.trim();
  if (cleanSourcePath.isEmpty) {
    throw StateError('Le chemin du document sélectionné est invalide.');
  }

  final sourceFile = File(cleanSourcePath);
  if (!await sourceFile.exists()) {
    throw StateError('Le document sélectionné est introuvable.');
  }

  if (await sourceFile.length() == 0) {
    throw StateError('Le document sélectionné est vide.');
  }

  final destination = await _destinationFile(
    userId: userId,
    modelId: modelId,
    documentId: documentId,
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
  required String modelId,
  required String documentId,
  required String originalFilename,
  required Uint8List bytes,
}) async {
  if (bytes.isEmpty) {
    throw StateError('Le document sélectionné est vide.');
  }

  final file = await _destinationFile(
    userId: userId,
    modelId: modelId,
    documentId: documentId,
    originalFilename: originalFilename,
  );
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

Future<File> _destinationFile({
  required String userId,
  required String modelId,
  required String documentId,
  required String originalFilename,
}) async {
  final root = await _rootDirectory();
  final directory = Directory(
    '${root.path}/Documents/'
    '${_safeSegment(userId)}/${_safeSegment(modelId)}',
  );
  await directory.create(recursive: true);

  final extension = _extension(originalFilename);
  final suffix = extension.isEmpty ? '' : '.$extension';
  return File('${directory.path}/${_safeSegment(documentId)}$suffix');
}

Future<Directory> _rootDirectory() async {
  if (Platform.isAndroid) {
    final selectedPath = await OfflineStorageService.getSelectedDirectoryPath();
    final directory = Directory(selectedPath);
    await directory.create(recursive: true);
    return directory;
  }

  return getApplicationSupportDirectory();
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
