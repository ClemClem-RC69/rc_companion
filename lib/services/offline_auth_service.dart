import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'supabase_service.dart';
import 'user_access_service.dart';

class OfflineAuthService {
  OfflineAuthService._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  static const String _emailKey = 'rc_offline_auth_email_v1';
  static const String _userIdKey = 'rc_offline_auth_user_id_v1';
  static const String _installationIdKey = 'rc_offline_auth_installation_id_v1';
  static const String _saltKey = 'rc_offline_auth_salt_v1';
  static const String _passwordHashKey = 'rc_offline_auth_password_hash_v1';
  static const String _allowedKey = 'rc_offline_auth_allowed_v1';

  static String? _stagedEmail;
  static String? _stagedPassword;

  static const int _iterations = 60000;
  static const int _derivedKeyLength = 32;

  static void stageCredentials({
    required String email,
    required String password,
  }) {
    _stagedEmail = email.trim().toLowerCase();
    _stagedPassword = password;
  }

  static void clearStagedCredentials() {
    _stagedEmail = null;
    _stagedPassword = null;
  }

  static Future<bool> commitCurrentAuthorization() async {
    final user = SupabaseService.client.auth.currentUser;
    final email = user?.email?.trim().toLowerCase();
    final password = _stagedPassword;
    final stagedEmail = _stagedEmail;

    if (user == null ||
        email == null ||
        email.isEmpty ||
        password == null ||
        stagedEmail != email) {
      clearStagedCredentials();
      return false;
    }

    final installationId = await UserAccessService.installationId();
    final salt = _randomBytes(24);
    final hash = _derivePasswordHash(
      password: password,
      salt: salt,
      installationId: installationId,
      userId: user.id,
      email: email,
    );

    await _storage.write(key: _emailKey, value: email);
    await _storage.write(key: _userIdKey, value: user.id);
    await _storage.write(key: _installationIdKey, value: installationId);
    await _storage.write(key: _saltKey, value: base64UrlEncode(salt));
    await _storage.write(key: _passwordHashKey, value: base64UrlEncode(hash));
    await _storage.write(key: _allowedKey, value: 'true');

    clearStagedCredentials();
    return true;
  }

  static Future<bool> finalizeAfterOnlineLogin() async {
    final user = SupabaseService.client.auth.currentUser;
    final stagedEmail = _stagedEmail;
    final stagedPassword = _stagedPassword;
    final email = user?.email?.trim().toLowerCase();

    if (user == null ||
        email == null ||
        email.isEmpty ||
        stagedEmail != email ||
        stagedPassword == null) {
      return false;
    }

    // L'admin conserve son parcours spécifique en ligne.
    try {
      if (await UserAccessService.isCurrentUserAdmin()) {
        clearStagedCredentials();
        return false;
      }
    } catch (_) {
      // Si le contrôle Admin ne répond pas, aucune autorisation hors ligne
      // nouvelle n'est créée.
      return false;
    }

    // signInWithPassword() et l'activation d'appareil sont asynchrones l'un
    // par rapport à l'autre. On attend que le serveur confirme que CET appareil
    // est bien autorisé avant d'enregistrer le vérificateur hors ligne.
    for (var attempt = 0; attempt < 12; attempt++) {
      try {
        final result = await UserAccessService.checkCurrentDevice();
        if (result.allowed) {
          return commitCurrentAuthorization();
        }

        // Un refus explicite ne doit jamais être transformé en droit hors ligne.
        if (result.userIsNotAuthorized ||
            result.wasRemovedByAdmin ||
            result.wasDisabledByAdmin ||
            result.wasReplacedByQuota) {
          clearStagedCredentials();
          return false;
        }
      } catch (_) {
        // On laisse quelques instants à l'activation volontaire déclenchée par
        // AuthGate. Si le serveur reste indisponible, aucun nouveau droit local
        // n'est créé.
      }

      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    return false;
  }

  static Future<bool> hasAuthorizedCurrentSession() async {
    final user = SupabaseService.client.auth.currentUser;
    final email = user?.email?.trim().toLowerCase();

    if (user == null || email == null || email.isEmpty) {
      return false;
    }

    final allowed = await _storage.read(key: _allowedKey);
    if (allowed != 'true') {
      return false;
    }

    final storedEmail = (await _storage.read(
      key: _emailKey,
    ))?.trim().toLowerCase();
    final storedUserId = (await _storage.read(key: _userIdKey))?.trim();
    final storedInstallationId = (await _storage.read(
      key: _installationIdKey,
    ))?.trim();
    final installationId = await UserAccessService.installationId();

    return storedEmail == email &&
        storedUserId == user.id &&
        storedInstallationId == installationId;
  }

  static Future<bool> verifyOfflineCredentials({
    required String email,
    required String password,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final user = SupabaseService.client.auth.currentUser;
    final sessionEmail = user?.email?.trim().toLowerCase();

    if (user == null ||
        sessionEmail == null ||
        sessionEmail != normalizedEmail ||
        !await hasAuthorizedCurrentSession()) {
      return false;
    }

    final saltEncoded = await _storage.read(key: _saltKey);
    final expectedEncoded = await _storage.read(key: _passwordHashKey);
    final storedInstallationId = (await _storage.read(
      key: _installationIdKey,
    ))?.trim();

    if (saltEncoded == null ||
        expectedEncoded == null ||
        storedInstallationId == null ||
        storedInstallationId.isEmpty) {
      return false;
    }

    try {
      final salt = base64Url.decode(saltEncoded);
      final expected = base64Url.decode(expectedEncoded);
      final calculated = _derivePasswordHash(
        password: password,
        salt: salt,
        installationId: storedInstallationId,
        userId: user.id,
        email: normalizedEmail,
      );

      return _constantTimeEquals(expected, calculated);
    } catch (_) {
      return false;
    }
  }

  static Future<void> markCurrentAuthorizationAllowed() async {
    if (_stagedPassword != null) {
      await commitCurrentAuthorization();
      return;
    }

    final user = SupabaseService.client.auth.currentUser;
    final email = user?.email?.trim().toLowerCase();
    if (user == null || email == null || email.isEmpty) {
      return;
    }

    final storedEmail = (await _storage.read(
      key: _emailKey,
    ))?.trim().toLowerCase();
    final storedUserId = (await _storage.read(key: _userIdKey))?.trim();
    final storedInstallationId = (await _storage.read(
      key: _installationIdKey,
    ))?.trim();
    final installationId = await UserAccessService.installationId();
    final hash = await _storage.read(key: _passwordHashKey);

    if (storedEmail == email &&
        storedUserId == user.id &&
        storedInstallationId == installationId &&
        hash != null &&
        hash.isNotEmpty) {
      await _storage.write(key: _allowedKey, value: 'true');
    }
  }

  static Future<void> revokeCurrentAuthorization() async {
    await _storage.write(key: _allowedKey, value: 'false');
    clearStagedCredentials();
  }

  static Future<void> updateCurrentPassword(String password) async {
    final user = SupabaseService.client.auth.currentUser;
    final email = user?.email?.trim().toLowerCase();

    if (user == null || email == null || email.isEmpty) {
      return;
    }

    final installationId = await UserAccessService.installationId();
    final storedEmail = (await _storage.read(
      key: _emailKey,
    ))?.trim().toLowerCase();
    final storedUserId = (await _storage.read(key: _userIdKey))?.trim();
    final storedInstallationId = (await _storage.read(
      key: _installationIdKey,
    ))?.trim();

    if (storedEmail != email ||
        storedUserId != user.id ||
        storedInstallationId != installationId) {
      return;
    }

    final salt = _randomBytes(24);
    final hash = _derivePasswordHash(
      password: password,
      salt: salt,
      installationId: installationId,
      userId: user.id,
      email: email,
    );

    await _storage.write(key: _saltKey, value: base64UrlEncode(salt));
    await _storage.write(key: _passwordHashKey, value: base64UrlEncode(hash));
  }

  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }

  static Uint8List _derivePasswordHash({
    required String password,
    required List<int> salt,
    required String installationId,
    required String userId,
    required String email,
  }) {
    final material = utf8.encode(
      '$password\u0000$installationId\u0000$userId\u0000$email',
    );
    return _pbkdf2HmacSha256(
      password: material,
      salt: salt,
      iterations: _iterations,
      length: _derivedKeyLength,
    );
  }

  static Uint8List _pbkdf2HmacSha256({
    required List<int> password,
    required List<int> salt,
    required int iterations,
    required int length,
  }) {
    final hmac = Hmac(sha256, password);
    const blockLength = 32;
    final blocks = (length + blockLength - 1) ~/ blockLength;
    final output = <int>[];

    for (var block = 1; block <= blocks; block++) {
      final blockIndex = <int>[
        (block >> 24) & 0xff,
        (block >> 16) & 0xff,
        (block >> 8) & 0xff,
        block & 0xff,
      ];

      var u = hmac.convert(<int>[...salt, ...blockIndex]).bytes;
      final t = List<int>.from(u);

      for (var iteration = 1; iteration < iterations; iteration++) {
        u = hmac.convert(u).bytes;
        for (var index = 0; index < t.length; index++) {
          t[index] ^= u[index];
        }
      }

      output.addAll(t);
    }

    return Uint8List.fromList(output.take(length).toList(growable: false));
  }

  static bool _constantTimeEquals(List<int> left, List<int> right) {
    if (left.length != right.length) {
      return false;
    }

    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }
}
