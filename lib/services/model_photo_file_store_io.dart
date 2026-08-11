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

  final root = await _rootDirectory();
  final directory = Directory(
    '${root.path}/Photos/'
    '${_safeSegment(userId)}/${_safeSegment(modelId)}',
  );
  await directory.create(recursive: true);

  final extension = _extension(originalFilename);
  final timestamp = DateTime.now().microsecondsSinceEpoch;
  final file = File('${directory.path}/photo_$timestamp.$extension');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
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
