import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

Future<String?> savePhoto({
  required String userId,
  required String modelId,
  required Uint8List bytes,
  required String originalFilename,
}) async {
  if (bytes.isEmpty) return null;
  final support = await getApplicationSupportDirectory();
  final directory = Directory('${support.path}/model_photos/$userId/$modelId');
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
