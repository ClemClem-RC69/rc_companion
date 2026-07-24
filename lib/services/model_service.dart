import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../database/app_database.dart';
import '../models/rc_model.dart';
import 'battery_sync_service.dart';
import 'model_local_store.dart';
import 'supabase_service.dart';

class ModelService {
  ModelService._();

  static final _client = SupabaseService.client;
  static final _database = AppDatabase.instance;

  static Future<RcModel> saveModel(RcModel model) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Aucun utilisateur connecté.');
    }

    final modelId = model.id == null || model.id!.trim().isEmpty
        ? _newUuid()
        : model.id!;
    final saved = model.copyWith(id: modelId);
    final row = ModelLocalStore.modelToRow(userId: user.id, model: saved);

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

    final rows = response
        .map<Map<String, dynamic>>(
          (row) => Map<String, dynamic>.from(row as Map),
        )
        .toList(growable: false);

    await ModelLocalStore.replaceModels(userId: user.id, rows: rows);
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
