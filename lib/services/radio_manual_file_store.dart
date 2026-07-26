import 'dart:typed_data';

import 'radio_manual_file_store_stub.dart'
    if (dart.library.io) 'radio_manual_file_store_io.dart'
    as impl;

class RadioManualFileStore {
  RadioManualFileStore._();

  static Future<String> saveFile({
    required String userId,
    required String radioId,
    required String originalFilename,
    required String sourcePath,
  }) {
    return impl.saveFile(
      userId: userId,
      radioId: radioId,
      originalFilename: originalFilename,
      sourcePath: sourcePath,
    );
  }

  static Future<String> saveBytes({
    required String userId,
    required String radioId,
    required String originalFilename,
    required Uint8List bytes,
  }) {
    return impl.saveBytes(
      userId: userId,
      radioId: radioId,
      originalFilename: originalFilename,
      bytes: bytes,
    );
  }

  static Future<Uint8List> readBytes(String path) => impl.readBytes(path);

  static Future<bool> exists(String? path) => impl.exists(path);

  static Future<void> delete(String? path) => impl.delete(path);
}
