import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import '../models/radio.dart';
import 'radio_local_store.dart';

class RadioService {
  RadioService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  static final AppDatabase _database = AppDatabase.instance;

  Future<List<RcRadio>> fetchRadios() async {
    final user = _requireUser();

    final localRadios = await RadioLocalStore.getRadios(userId: user.id);

    if (localRadios.isNotEmpty) {
      unawaited(_refreshFromRemote(user.id));
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

    unawaited(_refreshFromRemote(user.id));

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

  Future<List<RcRadio>> _refreshFromRemote(String userId) async {
    final response = await _client
        .from('radios')
        .select()
        .eq('user_id', userId)
        .order('brand')
        .order('model');

    final rows = (response as List<dynamic>)
        .map((item) => Map<String, dynamic>.from(item as Map<String, dynamic>))
        .toList(growable: false);

    await RadioLocalStore.replaceRadios(userId: userId, rows: rows);

    return rows.map(RcRadio.fromMap).toList(growable: false);
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
