import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'offline_storage_service.dart';

Future<String?> savePhoto({
  required String userId,
  required String modelId,
  required Uint8List bytes,
  required String originalFilename,
}) async {
  if (bytes.isEmpty) return null;

  final directory = await _modelDirectory(userId: userId, modelId: modelId);
  await directory.create(recursive: true);

  // Réutilise une copie strictement identique déjà présente.
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is! File) continue;

    final filename = entity.uri.pathSegments.isEmpty
        ? ''
        : entity.uri.pathSegments.last;
    if (!filename.startsWith('photo_')) continue;

    try {
      if (await entity.length() != bytes.length) continue;

      final existingBytes = await entity.readAsBytes();
      if (_sameBytes(existingBytes, bytes)) {
        return entity.path;
      }
    } catch (_) {
      // Un fichier local momentanément illisible ne doit pas empêcher
      // l'enregistrement de la photo.
    }
  }

  final extension = _extension(originalFilename);
  final timestamp = DateTime.now().microsecondsSinceEpoch;
  final file = File('${directory.path}/photo_$timestamp.$extension');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

/// Retrouve une photo déjà présente dans le dossier local du modèle.
///
/// Cette méthode sert notamment à réparer une référence `photo_local_path`
/// perdue dans Drift sans retélécharger ni recréer le fichier. Si plusieurs
/// fichiers existent, le plus récemment modifié est retenu.
Future<String?> findExistingPhotoPath({
  required String userId,
  required String modelId,
}) async {
  final directory = await _modelDirectory(userId: userId, modelId: modelId);

  if (!await directory.exists()) return null;

  File? bestFile;
  DateTime? bestModified;

  try {
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;

      final filename = entity.uri.pathSegments.isEmpty
          ? ''
          : entity.uri.pathSegments.last;
      if (!filename.startsWith('photo_')) continue;

      try {
        if (await entity.length() <= 0) continue;

        final modified = await entity.lastModified();
        if (bestFile == null ||
            bestModified == null ||
            modified.isAfter(bestModified)) {
          bestFile = entity;
          bestModified = modified;
        }
      } catch (_) {
        // Ignore uniquement ce fichier.
      }
    }
  } catch (_) {
    return null;
  }

  return bestFile?.path;
}

Future<Uint8List?> readBytes(String? path) async {
  if (path == null || path.trim().isEmpty) return null;
  final file = File(path);
  if (!await file.exists()) return null;
  return file.readAsBytes();
}

Future<void> deletePhoto(String? path) async {
  if (path == null || path.trim().isEmpty) return;
  final file = File(path);
  if (await file.exists()) await file.delete();
}

Future<Directory> _modelDirectory({
  required String userId,
  required String modelId,
}) async {
  final root = await _rootDirectory();
  return Directory(
    '${root.path}/Photos/'
    '${_safeSegment(userId)}/${_safeSegment(modelId)}',
  );
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
  final value = dot == -1 ? '' : clean.substring(dot + 1);
  switch (value) {
    case 'png':
      return 'png';
    case 'webp':
      return 'webp';
    case 'jpeg':
    case 'jpg':
    default:
      return 'jpg';
  }
}

String _safeSegment(String value) {
  final safe = value.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_');
  return safe.isEmpty ? 'item' : safe;
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;

  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }

  return true;
}
