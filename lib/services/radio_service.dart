import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import '../models/radio.dart';
import 'battery_sync_service.dart';
import 'radio_local_store.dart';
import 'radio_manual_file_store.dart';
import 'storage_service.dart';

class RadioService {
  RadioService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static final AppDatabase _database = AppDatabase.instance;

  Future<List<RcRadio>> fetchRadios() async {
    final user = _requireUser();

    final localRadios = await RadioLocalStore.getRadios(userId: user.id);

    if (localRadios.isNotEmpty) {
      unawaited(_refreshFromRemoteSilently(user.id));
      return localRadios;
    }

    try {
      return await _refreshFromRemote(user.id);
    } catch (_) {
      return localRadios;
    }
  }

  Stream<List<RcRadio>> watchRadios() {
    final user = _requireUser();

    unawaited(_refreshFromRemoteSilently(user.id));

    return RadioLocalStore.watchRadios(userId: user.id);
  }

  Future<RcRadio> addRadio({
    required String brand,
    required String model,
    required String level,
    required String type,
    required int channels,
    required List<String> protocols,
    required bool programmable,
  }) async {
    final user = _requireUser();
    final now = DateTime.now().toUtc();

    final radio = RcRadio(
      id: _newUuid(),
      userId: user.id,
      brand: brand.trim(),
      model: model.trim(),
      level: level,
      type: type,
      channels: channels,
      protocols: List<String>.from(protocols),
      programmable: programmable,
      createdAt: now,
    );

    final row = RadioLocalStore.radioToRow(
      userId: user.id,
      radio: radio,
      updatedAt: now,
    );

    await _database.transaction(() async {
      await RadioLocalStore.upsertRow(userId: user.id, row: row);

      await _database.replacePendingSyncOperation(
        userId: user.id,
        entityType: 'radio',
        entityId: radio.id,
        operation: 'upsert',
        payloadJson: jsonEncode(row),
      );
    });

    unawaited(BatterySyncService.syncNow());
    return radio;
  }

  Future<void> deleteRadio(String radioId) async {
    final user = _requireUser();

    final radio = await RadioLocalStore.getRadio(
      userId: user.id,
      radioId: radioId,
    );

    if (radio == null) {
      return;
    }

    final row = RadioLocalStore.radioToRow(userId: user.id, radio: radio);

    await RadioManualFileStore.delete(radio.manualLocalPath);

    await _database.transaction(() async {
      await RadioLocalStore.markDeleted(userId: user.id, radio: radio);

      await _database.replacePendingSyncOperation(
        userId: user.id,
        entityType: 'radio',
        entityId: radio.id,
        operation: 'delete',
        payloadJson: jsonEncode(row),
      );
    });

    unawaited(BatterySyncService.syncNow());
  }

  Future<bool> addOrReplaceManual(RcRadio radio) async {
    final picked = await StorageService.pickModelDocument();
    if (picked == null) {
      return false;
    }

    final user = _requireUser();
    final previousLocalPath = radio.manualLocalPath;
    final previousStoragePath = radio.manualStoragePath?.trim();

    late final String localPath;
    final sourcePath = picked.path?.trim();
    if (sourcePath != null && sourcePath.isNotEmpty) {
      localPath = await RadioManualFileStore.saveFile(
        userId: user.id,
        radioId: radio.id,
        originalFilename: picked.name,
        sourcePath: sourcePath,
      );
    } else {
      final bytes = picked.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw StateError('Impossible de lire le manuel sélectionné.');
      }
      localPath = await RadioManualFileStore.saveBytes(
        userId: user.id,
        radioId: radio.id,
        originalFilename: picked.name,
        bytes: bytes,
      );
    }

    if (previousLocalPath != null && previousLocalPath != localPath) {
      await RadioManualFileStore.delete(previousLocalPath);
    }

    final updated = radio.copyWith(
      manualName: picked.name,
      manualLocalPath: localPath,
      manualPendingUpload: true,
    );
    final row = RadioLocalStore.radioToRow(
      userId: user.id,
      radio: updated,
      updatedAt: DateTime.now().toUtc(),
    );

    final syncPayload = Map<String, dynamic>.from(row);
    if (previousStoragePath != null && previousStoragePath.isNotEmpty) {
      syncPayload['manual_previous_storage_path'] = previousStoragePath;
    }

    await _database.transaction(() async {
      await RadioLocalStore.upsertRow(userId: user.id, row: row);
      await _database.replacePendingSyncOperation(
        userId: user.id,
        entityType: 'radio',
        entityId: radio.id,
        operation: 'upsert',
        payloadJson: jsonEncode(syncPayload),
      );
    });

    unawaited(BatterySyncService.syncNow());
    return true;
  }

  Future<void> deleteManual(RcRadio radio) async {
    final user = _requireUser();
    final previousStoragePath = radio.manualStoragePath?.trim();

    await RadioManualFileStore.delete(radio.manualLocalPath);

    final updated = radio.copyWith(
      clearManualName: true,
      clearManualStoragePath: true,
      clearManualLocalPath: true,
      manualPendingUpload: false,
    );
    final row = RadioLocalStore.radioToRow(
      userId: user.id,
      radio: updated,
      updatedAt: DateTime.now().toUtc(),
    );
    final syncPayload = Map<String, dynamic>.from(row);
    if (previousStoragePath != null && previousStoragePath.isNotEmpty) {
      syncPayload['manual_previous_storage_path'] = previousStoragePath;
    }

    await _database.transaction(() async {
      await RadioLocalStore.upsertRow(userId: user.id, row: row);
      await _database.replacePendingSyncOperation(
        userId: user.id,
        entityType: 'radio',
        entityId: radio.id,
        operation: 'upsert',
        payloadJson: jsonEncode(syncPayload),
      );
    });

    unawaited(BatterySyncService.syncNow());
  }

  Future<String> getManualLocalPath(RcRadio radio) async {
    final user = _requireUser();

    if (await RadioManualFileStore.exists(radio.manualLocalPath)) {
      return radio.manualLocalPath!;
    }

    final storagePath = radio.manualStoragePath?.trim() ?? '';
    final manualName = radio.manualName?.trim() ?? '';
    if (storagePath.isEmpty || manualName.isEmpty) {
      throw StateError('Aucun manuel n’est enregistré pour cette radio.');
    }

    late final Uint8List bytes;
    try {
      bytes = await StorageService.downloadModelDocumentBytes(storagePath);
    } catch (_) {
      throw StateError(
        'Le manuel n’est pas encore disponible hors ligne sur cet appareil. '
        'Reconnecte l’appareil une fois pour le télécharger.',
      );
    }

    final localPath = await RadioManualFileStore.saveBytes(
      userId: user.id,
      radioId: radio.id,
      originalFilename: manualName,
      bytes: bytes,
    );

    final updated = radio.copyWith(
      manualLocalPath: localPath,
      manualPendingUpload: false,
    );
    await RadioLocalStore.upsertRadio(userId: user.id, radio: updated);
    return localPath;
  }

  Future<bool> radioAlreadyExists({
    required String brand,
    required String model,
  }) async {
    final user = _requireUser();
    final cleanBrand = brand.trim().toLowerCase();
    final cleanModel = model.trim().toLowerCase();

    final radios = await RadioLocalStore.getRadios(userId: user.id);

    return radios.any(
      (radio) =>
          radio.brand.trim().toLowerCase() == cleanBrand &&
          radio.model.trim().toLowerCase() == cleanModel,
    );
  }

  Future<void> _refreshFromRemoteSilently(String userId) async {
    try {
      await _refreshFromRemote(userId);
    } catch (_) {
      // Hors ligne ou réseau indisponible : le cache Drift reste la source
      // d’affichage et les opérations locales restent dans la file de sync.
    }
  }

  Future<List<RcRadio>> _refreshFromRemote(String userId) async {
    final response = await _client
        .from('radios')
        .select()
        .eq('user_id', userId)
        .order('brand')
        .order('model')
        .timeout(const Duration(seconds: 8));

    final rows = (response as List<dynamic>)
        .map((item) => Map<String, dynamic>.from(item as Map<String, dynamic>))
        .toList(growable: false);

    await RadioLocalStore.replaceRadios(userId: userId, rows: rows);

    final radios = await RadioLocalStore.getRadios(userId: userId);
    for (final radio in radios) {
      unawaited(_cacheManualIfNeeded(userId: userId, radio: radio));
    }
    return radios;
  }

  Future<void> _cacheManualIfNeeded({
    required String userId,
    required RcRadio radio,
  }) async {
    if (await RadioManualFileStore.exists(radio.manualLocalPath)) {
      return;
    }
    if (radio.manualPendingUpload) {
      return;
    }

    final storagePath = radio.manualStoragePath?.trim() ?? '';
    final manualName = radio.manualName?.trim() ?? '';
    if (storagePath.isEmpty || manualName.isEmpty) {
      return;
    }

    try {
      final bytes = await StorageService.downloadModelDocumentBytes(
        storagePath,
      );
      final localPath = await RadioManualFileStore.saveBytes(
        userId: userId,
        radioId: radio.id,
        originalFilename: manualName,
        bytes: bytes,
      );
      await RadioLocalStore.upsertRadio(
        userId: userId,
        radio: radio.copyWith(manualLocalPath: localPath),
      );
    } catch (_) {
      // Le manuel restera téléchargeable lorsque le réseau sera disponible.
    }
  }

  User _requireUser() {
    final user = _client.auth.currentUser;

    if (user == null) {
      throw StateError('Aucun utilisateur connecté.');
    }

    return user;
  }

  static String _newUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));

    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;

    String hex(int value) => value.toRadixString(16).padLeft(2, '0');

    final values = bytes.map(hex).toList(growable: false);

    return '${values.sublist(0, 4).join()}-'
        '${values.sublist(4, 6).join()}-'
        '${values.sublist(6, 8).join()}-'
        '${values.sublist(8, 10).join()}-'
        '${values.sublist(10, 16).join()}';
  }
}
