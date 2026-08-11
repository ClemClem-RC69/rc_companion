import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/model_document.dart';
import '../models/radio.dart';
import 'model_document_file_store.dart';
import 'model_document_local_store.dart';
import 'model_local_store.dart';
import 'model_photo_file_store.dart';
import 'offline_storage_service.dart';
import 'radio_local_store.dart';
import 'radio_manual_file_store.dart';
import 'storage_service.dart';

class OfflineStorageUpdateProgress {
  const OfflineStorageUpdateProgress({
    required this.current,
    required this.total,
    required this.label,
  });

  final int current;
  final int total;
  final String label;
}

class OfflineStorageUpdateResult {
  const OfflineStorageUpdateResult({
    required this.totalExpected,
    required this.available,
    required this.copiedFromLocal,
    required this.downloaded,
    required this.failed,
    required this.fileCountOnTarget,
    required this.bytesOnTarget,
  });

  final int totalExpected;
  final int available;
  final int copiedFromLocal;
  final int downloaded;
  final int failed;
  final int fileCountOnTarget;
  final int bytesOnTarget;
}

class OfflineStorageStats {
  const OfflineStorageStats({required this.fileCount, required this.bytes});

  final int fileCount;
  final int bytes;
}

class OfflineStorageRebuildService {
  OfflineStorageRebuildService._();

  static Future<OfflineStorageUpdateResult> updateAll({
    void Function(OfflineStorageUpdateProgress progress)? onProgress,
  }) async {
    if (!Platform.isAndroid) {
      throw StateError(
        'La mise à jour du stockage hors ligne est disponible uniquement sur Android.',
      );
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      throw StateError('Aucun utilisateur connecté.');
    }

    final targetRoot = await OfflineStorageService.getSelectedDirectoryPath();
    final models = await ModelLocalStore.getModels(userId: user.id);
    final radios = await RadioLocalStore.getRadios(userId: user.id);

    final documents = <ModelDocument>[];
    for (final model in models) {
      final modelId = model.id?.trim();
      if (modelId == null || modelId.isEmpty) {
        continue;
      }

      documents.addAll(
        await ModelDocumentLocalStore.getDocuments(
          userId: user.id,
          modelId: modelId,
        ),
      );
    }

    final modelsWithPhoto = models
        .where((model) {
          final remote = model.photoUrl?.trim() ?? '';
          final local = model.photoLocalPath?.trim() ?? '';
          return remote.isNotEmpty || local.isNotEmpty;
        })
        .toList(growable: false);

    final radiosWithManual = radios
        .where((radio) {
          final remote = radio.manualStoragePath?.trim() ?? '';
          final local = radio.manualLocalPath?.trim() ?? '';
          final name = radio.manualName?.trim() ?? '';
          return name.isNotEmpty && (remote.isNotEmpty || local.isNotEmpty);
        })
        .toList(growable: false);

    final total =
        modelsWithPhoto.length + documents.length + radiosWithManual.length;

    var current = 0;
    var available = 0;
    var copiedFromLocal = 0;
    var downloaded = 0;
    var failed = 0;

    void progress(String label) {
      current += 1;
      onProgress?.call(
        OfflineStorageUpdateProgress(
          current: current,
          total: total,
          label: label,
        ),
      );
    }

    for (final model in modelsWithPhoto) {
      final modelId = model.id?.trim();
      if (modelId == null || modelId.isEmpty) {
        failed += 1;
        progress('Photo modèle');
        continue;
      }

      try {
        final result = await _ensureModelPhoto(
          userId: user.id,
          modelId: modelId,
          targetRoot: targetRoot,
          photoUrl: model.photoUrl,
          localPath: model.photoLocalPath,
        );

        if (result.path != null) {
          final updated = model.copyWith(
            photoLocalPath: result.path,
            photoPendingUpload: model.photoPendingUpload,
          );
          await ModelLocalStore.upsertModel(userId: user.id, model: updated);

          available += 1;
          if (result.source == _FileSource.local) {
            copiedFromLocal += 1;
          } else if (result.source == _FileSource.remote) {
            downloaded += 1;
          }
        } else {
          failed += 1;
        }
      } catch (_) {
        failed += 1;
      }

      progress('Photo — ${model.name}');
    }

    for (final document in documents) {
      try {
        final result = await _ensureDocument(
          userId: user.id,
          targetRoot: targetRoot,
          document: document,
        );

        if (result.path != null) {
          final updated = document.copyWith(
            localPath: result.path,
            pendingUpload: document.pendingUpload,
          );
          await ModelDocumentLocalStore.upsertDocument(
            userId: user.id,
            document: updated,
          );

          available += 1;
          if (result.source == _FileSource.local) {
            copiedFromLocal += 1;
          } else if (result.source == _FileSource.remote) {
            downloaded += 1;
          }
        } else {
          failed += 1;
        }
      } catch (_) {
        failed += 1;
      }

      progress('Document — ${document.documentName}');
    }

    for (final radio in radiosWithManual) {
      try {
        final result = await _ensureManual(
          userId: user.id,
          targetRoot: targetRoot,
          radio: radio,
        );

        if (result.path != null) {
          final updated = radio.copyWith(
            manualLocalPath: result.path,
            manualPendingUpload: radio.manualPendingUpload,
          );
          await RadioLocalStore.upsertRadio(userId: user.id, radio: updated);

          available += 1;
          if (result.source == _FileSource.local) {
            copiedFromLocal += 1;
          } else if (result.source == _FileSource.remote) {
            downloaded += 1;
          }
        } else {
          failed += 1;
        }
      } catch (_) {
        failed += 1;
      }

      progress('Notice — ${radio.fullName}');
    }

    final stats = await readStats();

    return OfflineStorageUpdateResult(
      totalExpected: total,
      available: available,
      copiedFromLocal: copiedFromLocal,
      downloaded: downloaded,
      failed: failed,
      fileCountOnTarget: stats.fileCount,
      bytesOnTarget: stats.bytes,
    );
  }

  static Future<OfflineStorageStats> readStats() async {
    if (!Platform.isAndroid) {
      return const OfflineStorageStats(fileCount: 0, bytes: 0);
    }

    try {
      final rootPath = await OfflineStorageService.getSelectedDirectoryPath();
      final root = Directory(rootPath);

      if (!await root.exists()) {
        return const OfflineStorageStats(fileCount: 0, bytes: 0);
      }

      var count = 0;
      var bytes = 0;

      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          count += 1;
          try {
            bytes += await entity.length();
          } catch (_) {
            // Un fichier temporairement inaccessible n'empêche pas le bilan.
          }
        }
      }

      return OfflineStorageStats(fileCount: count, bytes: bytes);
    } catch (_) {
      return const OfflineStorageStats(fileCount: 0, bytes: 0);
    }
  }

  static Future<_EnsureResult> _ensureModelPhoto({
    required String userId,
    required String modelId,
    required String targetRoot,
    required String? photoUrl,
    required String? localPath,
  }) async {
    final cleanLocal = localPath?.trim() ?? '';

    if (_isOnTarget(cleanLocal, targetRoot) &&
        await _fileExistsAndNotEmpty(cleanLocal)) {
      return _EnsureResult(path: cleanLocal, source: _FileSource.existing);
    }

    Uint8List? bytes;
    var source = _FileSource.none;

    if (await _fileExistsAndNotEmpty(cleanLocal)) {
      bytes = await ModelPhotoFileStore.readBytes(cleanLocal);
      if (bytes != null && bytes.isNotEmpty) {
        source = _FileSource.local;
      }
    }

    final cleanRemote = photoUrl?.trim() ?? '';
    if ((bytes == null || bytes.isEmpty) && _isGoogleDrivePath(cleanRemote)) {
      bytes = await StorageService.downloadModelPhotoBytes(cleanRemote);
      if (bytes != null && bytes.isNotEmpty) {
        source = _FileSource.remote;
      }
    }

    if (bytes == null || bytes.isEmpty) {
      return const _EnsureResult(path: null, source: _FileSource.none);
    }

    final saved = await ModelPhotoFileStore.savePhoto(
      userId: userId,
      modelId: modelId,
      bytes: bytes,
      originalFilename: _filenameFromRemote(cleanRemote, fallback: 'model.jpg'),
    );

    return _EnsureResult(path: saved, source: source);
  }

  static Future<_EnsureResult> _ensureDocument({
    required String userId,
    required String targetRoot,
    required ModelDocument document,
  }) async {
    final cleanLocal = document.localPath?.trim() ?? '';

    if (_isOnTarget(cleanLocal, targetRoot) &&
        await _fileExistsAndNotEmpty(cleanLocal)) {
      return _EnsureResult(path: cleanLocal, source: _FileSource.existing);
    }

    Uint8List? bytes;
    var source = _FileSource.none;

    if (await _fileExistsAndNotEmpty(cleanLocal)) {
      bytes = await ModelDocumentFileStore.readBytes(cleanLocal);
      if (bytes.isNotEmpty) {
        source = _FileSource.local;
      }
    }

    final cleanRemote = document.storagePath.trim();
    if ((bytes == null || bytes.isEmpty) && _isGoogleDrivePath(cleanRemote)) {
      bytes = await StorageService.downloadModelDocumentBytes(cleanRemote);
      if (bytes.isNotEmpty) {
        source = _FileSource.remote;
      }
    }

    if (bytes == null || bytes.isEmpty) {
      return const _EnsureResult(path: null, source: _FileSource.none);
    }

    final saved = await ModelDocumentFileStore.saveBytes(
      userId: userId,
      modelId: document.modelId,
      documentId: document.id,
      originalFilename: document.documentName,
      bytes: bytes,
    );

    return _EnsureResult(path: saved, source: source);
  }

  static Future<_EnsureResult> _ensureManual({
    required String userId,
    required String targetRoot,
    required RcRadio radio,
  }) async {
    final cleanLocal = radio.manualLocalPath?.trim() ?? '';

    if (_isOnTarget(cleanLocal, targetRoot) &&
        await _fileExistsAndNotEmpty(cleanLocal)) {
      return _EnsureResult(path: cleanLocal, source: _FileSource.existing);
    }

    Uint8List? bytes;
    var source = _FileSource.none;

    if (await _fileExistsAndNotEmpty(cleanLocal)) {
      bytes = await RadioManualFileStore.readBytes(cleanLocal);
      if (bytes.isNotEmpty) {
        source = _FileSource.local;
      }
    }

    final cleanRemote = radio.manualStoragePath?.trim() ?? '';
    if ((bytes == null || bytes.isEmpty) && _isGoogleDrivePath(cleanRemote)) {
      bytes = await StorageService.downloadModelDocumentBytes(cleanRemote);
      if (bytes.isNotEmpty) {
        source = _FileSource.remote;
      }
    }

    if (bytes == null || bytes.isEmpty) {
      return const _EnsureResult(path: null, source: _FileSource.none);
    }

    final saved = await RadioManualFileStore.saveBytes(
      userId: userId,
      radioId: radio.id,
      originalFilename: radio.manualName ?? 'manuel.pdf',
      bytes: bytes,
    );

    return _EnsureResult(path: saved, source: source);
  }

  static bool _isOnTarget(String path, String root) {
    if (path.isEmpty) {
      return false;
    }

    final cleanRoot = root.endsWith(Platform.pathSeparator)
        ? root
        : '$root${Platform.pathSeparator}';

    return path == root || path.startsWith(cleanRoot);
  }

  static Future<bool> _fileExistsAndNotEmpty(String path) async {
    if (path.isEmpty) {
      return false;
    }

    final file = File(path);
    if (!await file.exists()) {
      return false;
    }

    try {
      return await file.length() > 0;
    } catch (_) {
      return false;
    }
  }

  static bool _isGoogleDrivePath(String path) {
    return path.trim().startsWith('gdrive:');
  }

  static String _filenameFromRemote(String remote, {required String fallback}) {
    if (remote.isEmpty || remote.startsWith('gdrive:')) {
      return fallback;
    }

    final uri = Uri.tryParse(remote);
    final name = uri?.pathSegments.isNotEmpty == true
        ? uri!.pathSegments.last
        : fallback;

    return name.isEmpty ? fallback : name;
  }
}

enum _FileSource { none, existing, local, remote }

class _EnsureResult {
  const _EnsureResult({required this.path, required this.source});

  final String? path;
  final _FileSource source;
}
