import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum OfflineStorageTarget { internal, removable }

class OfflineStorageVolume {
  const OfflineStorageVolume({
    required this.index,
    required this.path,
    required this.rcCompanionPath,
    required this.removable,
    required this.state,
    required this.mounted,
    required this.writable,
    required this.totalBytes,
    required this.freeBytes,
  });

  final int index;
  final String path;
  final String rcCompanionPath;
  final bool removable;
  final String state;
  final bool mounted;
  final bool writable;
  final int totalBytes;
  final int freeBytes;

  factory OfflineStorageVolume.fromMap(Map<Object?, Object?> map) {
    int readInt(String key) {
      final value = map[key];
      return value is num ? value.toInt() : 0;
    }

    bool readBool(String key) => map[key] == true;

    String readString(String key) => map[key]?.toString() ?? '';

    return OfflineStorageVolume(
      index: readInt('index'),
      path: readString('path'),
      rcCompanionPath: readString('rcCompanionPath'),
      removable: readBool('removable'),
      state: readString('state'),
      mounted: readBool('mounted'),
      writable: readBool('writable'),
      totalBytes: readInt('totalBytes'),
      freeBytes: readInt('freeBytes'),
    );
  }
}

class OfflineStorageSelection {
  const OfflineStorageSelection({
    required this.target,
    required this.volume,
    required this.directoryExists,
  });

  final OfflineStorageTarget target;
  final OfflineStorageVolume? volume;
  final bool directoryExists;

  bool get available => volume != null && volume!.mounted && volume!.writable;

  String? get directoryPath => volume?.rcCompanionPath;
}

class OfflineStorageService {
  OfflineStorageService._();

  static const MethodChannel _channel = MethodChannel(
    'com.clementg.rccompanion/offline_storage',
  );

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  static const String _targetKey = 'offline_storage_target_v1';

  static bool get isAndroid => Platform.isAndroid;

  static Future<List<OfflineStorageVolume>> getVolumes() async {
    if (!Platform.isAndroid) {
      return const <OfflineStorageVolume>[];
    }

    final raw = await _channel.invokeMethod<List<Object?>>('getStorageVolumes');

    if (raw == null) {
      return const <OfflineStorageVolume>[];
    }

    return raw
        .whereType<Map<Object?, Object?>>()
        .map(OfflineStorageVolume.fromMap)
        .toList(growable: false);
  }

  static Future<OfflineStorageTarget> getSelectedTarget() async {
    final value = await _secureStorage.read(key: _targetKey);

    if (value == OfflineStorageTarget.removable.name) {
      return OfflineStorageTarget.removable;
    }

    return OfflineStorageTarget.internal;
  }

  static OfflineStorageVolume? findVolumeForTarget(
    List<OfflineStorageVolume> volumes,
    OfflineStorageTarget target,
  ) {
    final wantsRemovable = target == OfflineStorageTarget.removable;

    for (final volume in volumes) {
      if (volume.removable == wantsRemovable) {
        return volume;
      }
    }

    return null;
  }

  static Future<OfflineStorageSelection> getSelection() async {
    final target = await getSelectedTarget();

    if (!Platform.isAndroid) {
      return OfflineStorageSelection(
        target: target,
        volume: null,
        directoryExists: false,
      );
    }

    final volumes = await getVolumes();
    final volume = findVolumeForTarget(volumes, target);

    var directoryExists = false;
    if (volume != null) {
      directoryExists = await Directory(volume.rcCompanionPath).exists();
    }

    return OfflineStorageSelection(
      target: target,
      volume: volume,
      directoryExists: directoryExists,
    );
  }

  static Future<OfflineStorageSelection> selectTarget(
    OfflineStorageTarget target,
  ) async {
    if (!Platform.isAndroid) {
      throw StateError(
        'Le choix mémoire interne / carte SD est disponible uniquement sur Android.',
      );
    }

    final volumes = await getVolumes();
    final volume = findVolumeForTarget(volumes, target);

    if (volume == null) {
      if (target == OfflineStorageTarget.removable) {
        throw StateError(
          'Aucune carte SD / mémoire amovible n’est actuellement détectée.',
        );
      }

      throw StateError('La mémoire interne Android n’est pas disponible.');
    }

    if (!volume.mounted) {
      throw StateError('Ce stockage n’est pas actuellement monté par Android.');
    }

    if (!volume.writable) {
      throw StateError(
        'Android n’autorise pas actuellement l’écriture sur ce stockage.',
      );
    }

    final directory = Directory(volume.rcCompanionPath);
    await directory.create(recursive: true);

    if (!await directory.exists()) {
      throw StateError(
        'RC Companion n’a pas pu créer son dossier sur ce stockage.',
      );
    }

    await _secureStorage.write(key: _targetKey, value: target.name);

    return OfflineStorageSelection(
      target: target,
      volume: volume,
      directoryExists: true,
    );
  }

  static Future<String> getSelectedDirectoryPath() async {
    final selection = await getSelection();

    if (!selection.available || selection.directoryPath == null) {
      if (selection.target == OfflineStorageTarget.removable) {
        throw StateError('La carte SD sélectionnée n’est pas disponible.');
      }

      throw StateError('Le stockage interne sélectionné n’est pas disponible.');
    }

    final directory = Directory(selection.directoryPath!);
    await directory.create(recursive: true);

    return directory.path;
  }
}
