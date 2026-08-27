import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../database/app_database.dart';
import '../models/rc_model.dart';
import 'battery_sync_service.dart';
import 'model_local_store.dart';
import 'model_photo_file_store.dart';
import 'storage_service.dart';
import 'supabase_service.dart';

class ModelService {
  ModelService._();

  static final _client = SupabaseService.client;
  static final _database = AppDatabase.instance;

  static String newModelId() => _newUuid();

  static Future<RcModel> saveModel(
    RcModel model, {
    String? previousPhotoUrl,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Aucun utilisateur connecté.');
    }

    final modelId = model.id == null || model.id!.trim().isEmpty
        ? _newUuid()
        : model.id!;
    final saved = model.copyWith(id: modelId);
    final row = ModelLocalStore.modelToRow(userId: user.id, model: saved);

    if (previousPhotoUrl != null && previousPhotoUrl.trim().isNotEmpty) {
      row['_previous_photo_url'] = previousPhotoUrl;
    }

    await ModelLocalStore.upsertModel(userId: user.id, model: saved);
    await _database.replacePendingSyncOperation(
      userId: user.id,
      entityType: 'model',
      entityId: modelId,
      operation: 'upsert',
      payloadJson: jsonEncode(row),
    );

    unawaited(BatterySyncService.syncNow());
    return saved;
  }

  static Future<void> deleteModel(RcModel model) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Aucun utilisateur connecté.');
    }

    final modelId = model.id;
    if (modelId == null || modelId.trim().isEmpty) {
      throw StateError('Modèle sans identifiant.');
    }

    await ModelLocalStore.markModelDeleted(userId: user.id, model: model);
    await _database.replacePendingSyncOperation(
      userId: user.id,
      entityType: 'model',
      entityId: modelId,
      operation: 'delete',
      payloadJson: jsonEncode({
        'id': modelId,
        'user_id': user.id,
        'photo_url': model.photoUrl,
        'photo_local_path': model.photoLocalPath,
      }),
    );

    unawaited(BatterySyncService.syncNow());
  }

  static Future<void> refreshModels() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      return;
    }

    final response = await _client
        .from('rc_models')
        .select()
        .eq('user_id', user.id)
        .order('created_at', ascending: false)
        .timeout(const Duration(seconds: 8));

    final rows = <Map<String, dynamic>>[];

    for (final raw in response) {
      final row = Map<String, dynamic>.from(raw as Map);
      final modelId = row['id']?.toString();
      final photoUrl = row['photo_url']?.toString();

      if (modelId != null && modelId.isNotEmpty) {
        final existing = await ModelLocalStore.getModel(
          userId: user.id,
          modelId: modelId,
        );

        final existingLocalPath = existing?.photoLocalPath?.trim() ?? '';
        String? localPath;

        // 1. Le chemin connu par Drift reste prioritaire s'il pointe vers
        //    un fichier réellement lisible et que la photo distante n'a
        //    pas changé.
        final existingBytes = await ModelPhotoFileStore.readBytes(
          existingLocalPath,
        );

        if (existingBytes != null &&
            existingBytes.isNotEmpty &&
            existing?.photoUrl == photoUrl) {
          localPath = existingLocalPath;
        }

        // 2. Si Drift a perdu photo_local_path, tente d'abord de rattacher
        //    le fichier déjà présent dans le dossier local du modèle.
        if ((localPath == null || localPath.isEmpty) &&
            existingLocalPath.isEmpty &&
            _isGoogleDrivePath(photoUrl)) {
          localPath = await ModelPhotoFileStore.findExistingPhotoPath(
            userId: user.id,
            modelId: modelId,
          );
        }

        // 3. Seulement si aucune copie locale exploitable n'a été retrouvée,
        //    tente le téléchargement Drive.
        if ((localPath == null || localPath.isEmpty) &&
            _isGoogleDrivePath(photoUrl)) {
          try {
            final bytes = await StorageService.downloadModelPhotoBytes(
              photoUrl!,
            );

            if (bytes != null && bytes.isNotEmpty) {
              localPath = await ModelPhotoFileStore.savePhoto(
                userId: user.id,
                modelId: modelId,
                bytes: bytes,
                originalFilename: _filenameFromUrl(photoUrl),
              );
            }
          } catch (_) {
            // Un échec distant ne doit jamais effacer une référence locale
            // encore potentiellement utile.
          }
        }

        // 4. Si le téléchargement n'a rien fourni, conserve toujours
        //    l'ancien chemin au lieu d'écrire null dans Drift.
        if ((localPath == null || localPath.isEmpty) &&
            existingLocalPath.isNotEmpty) {
          localPath = existingLocalPath;
        }

        // 5. Une absence réelle de photo distante reste une suppression
        //    explicite de la copie locale.
        if (!_isGoogleDrivePath(photoUrl)) {
          await ModelPhotoFileStore.deletePhoto(existing?.photoLocalPath);
          localPath = null;
        }

        row['photo_local_path'] = localPath;
        row['photo_pending_upload'] = false;
      }

      rows.add(row);
    }

    await ModelLocalStore.replaceModels(userId: user.id, rows: rows);
  }

  static bool _isGoogleDrivePath(String? path) {
    if (path == null) {
      return false;
    }
    return path.trim().startsWith('gdrive:');
  }

  static String _filenameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    final last = uri?.pathSegments.isNotEmpty == true
        ? uri!.pathSegments.last
        : 'model.jpg';
    return last.isEmpty ? 'model.jpg' : last;
  }

  static String _newUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    String hex(int value) => value.toRadixString(16).padLeft(2, '0');

    final value = bytes.map(hex).join();
    return '${value.substring(0, 8)}-'
        '${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-'
        '${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }
}
