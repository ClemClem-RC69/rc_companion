import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'supabase_service.dart';

class DeviceAccessResult {
  const DeviceAccessResult({
    required this.allowed,
    required this.reason,
    required this.payload,
  });

  final bool allowed;
  final String reason;
  final Map<String, dynamic> payload;

  bool get localDataPreserved => payload['local_data_preserved'] == true;

  String? get message {
    final value = payload['message']?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  int? get maxActive {
    final value = payload['max_active'];
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '');
  }

  int get replacedDevices {
    final value = payload['replaced_devices'];
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  bool get wasRemovedByAdmin => reason == 'device_removed';

  bool get wasDisabledByAdmin => reason == 'device_disabled_by_admin';

  bool get wasReplacedByQuota => reason == 'device_replaced';

  bool get userIsNotAuthorized => reason == 'user_not_authorized';
}

class UserAccessService {
  UserAccessService._();

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  static const String _installationIdKey =
      'rc_companion_user_access_installation_id_v1';

  static Future<String> installationId() async {
    final existing = (await _secureStorage.read(
      key: _installationIdKey,
    ))?.trim();

    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final generated = _generateInstallationId();

    await _secureStorage.write(key: _installationIdKey, value: generated);

    return generated;
  }

  static String get platform {
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isIOS) return 'ios';

    throw UnsupportedError(
      'Cette plateforme n’est pas prise en charge par '
      'le contrôle d’accès RC Companion.',
    );
  }

  static Future<String> deviceName() async {
    final deviceInfo = DeviceInfoPlugin();

    try {
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        final manufacturer = _cleanDevicePart(info.manufacturer);
        final model = _cleanDevicePart(info.model);

        if (manufacturer.isNotEmpty && model.isNotEmpty) {
          if (model.toLowerCase().startsWith(manufacturer.toLowerCase())) {
            return model;
          }
          return '${_capitalizeManufacturer(manufacturer)} $model';
        }

        if (model.isNotEmpty) {
          return model;
        }

        final name = _cleanDevicePart(info.name);
        if (name.isNotEmpty) {
          return name;
        }
      }

      if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        final modelName = _cleanDevicePart(info.modelName);
        if (modelName.isNotEmpty) {
          return modelName;
        }

        final model = _cleanDevicePart(info.model);
        if (model.isNotEmpty) {
          return model;
        }
      }

      if (Platform.isMacOS) {
        final info = await deviceInfo.macOsInfo;
        final modelName = _cleanDevicePart(info.modelName);
        final computerName = _cleanDevicePart(info.computerName);

        if (modelName.isNotEmpty && computerName.isNotEmpty) {
          return '$modelName — $computerName';
        }

        if (modelName.isNotEmpty) {
          return modelName;
        }

        if (computerName.isNotEmpty) {
          return computerName;
        }
      }

      if (Platform.isWindows) {
        final info = await deviceInfo.windowsInfo;
        final computerName = _cleanDevicePart(info.computerName);
        if (computerName.isNotEmpty) {
          return computerName;
        }
      }
    } catch (_) {
      // En cas d'échec du plugin, RC Companion conserve un nom de secours.
    }

    final hostname = Platform.localHostname.trim();
    if (hostname.isNotEmpty && hostname.toLowerCase() != 'localhost') {
      return hostname;
    }

    switch (platform) {
      case 'android':
        return 'Appareil Android';
      case 'windows':
        return 'PC Windows';
      case 'macos':
        return 'Mac';
      case 'ios':
        return 'Appareil Apple';
    }

    return 'Appareil RC Companion';
  }

  static String _cleanDevicePart(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty ||
        cleaned.toLowerCase() == 'unknown' ||
        cleaned.toLowerCase() == 'generic') {
      return '';
    }
    return cleaned;
  }

  static String _capitalizeManufacturer(String value) {
    if (value.isEmpty) {
      return value;
    }

    if (value.toLowerCase() == value) {
      return '${value[0].toUpperCase()}${value.substring(1)}';
    }

    return value;
  }

  /// À appeler uniquement après une connexion volontaire de l’utilisateur.
  ///
  /// Cette fonction peut prendre la place d’un autre appareil actif
  /// de la même plateforme lorsque le quota est atteint.
  static Future<DeviceAccessResult> activateCurrentDevice() async {
    final id = await installationId();
    final resolvedDeviceName = await deviceName();

    final response = await SupabaseService.client.rpc(
      'rc_activate_device',
      params: <String, dynamic>{
        'p_platform': platform,
        'p_device_id': id,
        'p_device_name': resolvedDeviceName,
      },
    );

    return _parseAccessResult(response);
  }

  /// Vérifie si CET appareil possède toujours une place active.
  ///
  /// Cette fonction ne réactive jamais automatiquement un appareil remplacé.
  /// Elle doit être utilisée lors d’un retour réseau, d’une reprise de
  /// l’application ou avant une synchronisation.
  static Future<DeviceAccessResult> checkCurrentDevice() async {
    final id = await installationId();

    final response = await SupabaseService.client.rpc(
      'rc_check_device',
      params: <String, dynamic>{'p_platform': platform, 'p_device_id': id},
    );

    return _parseAccessResult(response);
  }

  /// Libère volontairement la place de cet appareil sur sa plateforme.
  static Future<bool> releaseCurrentDevice() async {
    final id = await installationId();

    final response = await SupabaseService.client.rpc(
      'rc_release_device',
      params: <String, dynamic>{'p_platform': platform, 'p_device_id': id},
    );

    final payload = _asMap(response);
    return payload['released'] == true;
  }

  /// Retourne les droits et quotas du compte actuellement authentifié.
  static Future<Map<String, dynamic>> myAccess() async {
    final response = await SupabaseService.client.rpc('rc_my_access');
    return _asMap(response);
  }

  static Future<bool> isCurrentUserAdmin() async {
    final access = await myAccess();
    return access['is_admin'] == true;
  }

  static DeviceAccessResult _parseAccessResult(dynamic response) {
    final payload = _asMap(response);

    return DeviceAccessResult(
      allowed: payload['allowed'] == true,
      reason: payload['reason']?.toString() ?? 'unknown',
      payload: payload,
    );
  }

  static Map<String, dynamic> _asMap(dynamic response) {
    if (response is Map<String, dynamic>) {
      return Map<String, dynamic>.from(response);
    }

    if (response is Map) {
      return response.map((key, value) => MapEntry(key.toString(), value));
    }

    return <String, dynamic>{};
  }

  static String _generateInstallationId() {
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));

    final buffer = StringBuffer('rc-');
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }

    return buffer.toString();
  }
}
