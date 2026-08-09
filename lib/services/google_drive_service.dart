import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:url_launcher/url_launcher.dart';

class GoogleDriveConnectionState {
  const GoogleDriveConnectionState({
    required this.supported,
    required this.configured,
    required this.connected,
    this.message,
  });

  final bool supported;
  final bool configured;
  final bool connected;
  final String? message;
}

class GoogleDriveService {
  GoogleDriveService._();

  static const String _desktopClientId = String.fromEnvironment(
    'GOOGLE_DRIVE_DESKTOP_CLIENT_ID',
  );
  static const String _desktopClientSecret = String.fromEnvironment(
    'GOOGLE_DRIVE_DESKTOP_CLIENT_SECRET',
  );

  static const List<String> _scopes = <String>[
    'https://www.googleapis.com/auth/drive.file',
  ];

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _refreshTokenKey =
      'rc_companion_google_drive_refresh_token';

  static auth.AutoRefreshingAuthClient? _client;

  static bool get isDesktopSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows;
  }

  static bool get isDesktopConfigured =>
      _desktopClientId.trim().isNotEmpty &&
      _desktopClientSecret.trim().isNotEmpty;

  static Future<GoogleDriveConnectionState> connectionState() async {
    if (!isDesktopSupported) {
      return const GoogleDriveConnectionState(
        supported: false,
        configured: false,
        connected: false,
        message:
            'La connexion Google Drive mobile sera activée dans une étape '
            'dédiée pour Android, iPhone et iPad.',
      );
    }

    if (!isDesktopConfigured) {
      return const GoogleDriveConnectionState(
        supported: true,
        configured: false,
        connected: false,
        message:
            'Le client OAuth Desktop n’est pas encore fourni à cette '
            'exécution de RC Companion.',
      );
    }

    if (_client != null) {
      debugPrint('[GoogleDrive] Client OAuth actif en mémoire : connecté.');
      return const GoogleDriveConnectionState(
        supported: true,
        configured: true,
        connected: true,
      );
    }

    final refreshToken = await _secureStorage.read(key: _refreshTokenKey);
    if (refreshToken == null || refreshToken.trim().isEmpty) {
      debugPrint('[GoogleDrive] Aucun refresh token enregistré localement.');
      return const GoogleDriveConnectionState(
        supported: true,
        configured: true,
        connected: false,
      );
    }

    debugPrint('[GoogleDrive] Refresh token trouvé, restauration OAuth...');

    try {
      await _ensureRestoredClient(refreshToken.trim());
      await _verifyDriveAccess();
      return const GoogleDriveConnectionState(
        supported: true,
        configured: true,
        connected: true,
      );
    } catch (_) {
      _client?.close();
      _client = null;
      return const GoogleDriveConnectionState(
        supported: true,
        configured: true,
        connected: false,
        message: 'La connexion Google Drive enregistrée doit être renouvelée.',
      );
    }
  }

  static Future<void> connectDesktop() async {
    if (!isDesktopSupported) {
      throw Exception(
        'Cette étape de connexion Google Drive concerne uniquement macOS '
        'et Windows.',
      );
    }

    if (!isDesktopConfigured) {
      throw Exception(
        'Configuration OAuth Desktop absente. Lance RC Companion avec les '
        'identifiants Google Drive Desktop prévus pour cette installation.',
      );
    }

    _client?.close();
    _client = null;

    final clientId = auth.ClientId(
      _desktopClientId.trim(),
      _desktopClientSecret.trim(),
    );

    debugPrint('[GoogleDrive] Démarrage du consentement OAuth Desktop...');

    final client = await auth.clientViaUserConsent(
      clientId,
      _scopes,
      (authorizationUrl) {
        debugPrint(
          '[GoogleDrive] URL de consentement reçue, ouverture du navigateur.',
        );
        unawaited(_openAuthorizationUrl(authorizationUrl));
      },
      customPostAuthPage:
          '<!doctype html><html><head><meta charset="utf-8">'
          '<title>RC Companion</title></head><body>'
          '<h2>RC Companion</h2>'
          '<p>Autorisation Google Drive terminée. '
          'Tu peux fermer cette fenêtre et revenir dans RC Companion.</p>'
          '</body></html>',
    );

    _client = client;
    debugPrint('[GoogleDrive] Retour OAuth reçu : client authentifié actif.');

    try {
      await _verifyDriveAccess();
      debugPrint('[GoogleDrive] Accès Google Drive vérifié.');

      final refreshToken = client.credentials.refreshToken?.trim();

      if (refreshToken == null || refreshToken.isEmpty) {
        debugPrint(
          '[GoogleDrive] Aucun refresh token renvoyé par Google. '
          'La connexion reste active pour cette exécution.',
        );
        return;
      }

      await _secureStorage.write(key: _refreshTokenKey, value: refreshToken);

      debugPrint(
        '[GoogleDrive] Refresh token enregistré dans le stockage sécurisé.',
      );
    } catch (error) {
      debugPrint('[GoogleDrive] Échec après retour OAuth : $error');
      client.close();
      if (identical(_client, client)) _client = null;
      rethrow;
    }
  }

  static Future<void> disconnect() async {
    await _secureStorage.delete(key: _refreshTokenKey);
    _client?.close();
    _client = null;
    debugPrint('[GoogleDrive] Connexion locale supprimée.');
  }

  static Future<void> _ensureRestoredClient(String refreshToken) async {
    if (_client != null) return;

    final clientId = auth.ClientId(
      _desktopClientId.trim(),
      _desktopClientSecret.trim(),
    );

    _client = await auth.clientViaRefreshToken(clientId, refreshToken, _scopes);

    debugPrint('[GoogleDrive] Client OAuth restauré via refresh token.');
  }

  static Future<void> _verifyDriveAccess() async {
    final client = _client;
    if (client == null) {
      throw Exception('Google Drive n’est pas connecté.');
    }

    final api = drive.DriveApi(client);
    await api.files.list(pageSize: 1, $fields: 'files(id)');
  }

  static Future<void> _openAuthorizationUrl(String authorizationUrl) async {
    final opened = await launchUrl(
      Uri.parse(authorizationUrl),
      mode: LaunchMode.externalApplication,
    );

    if (!opened) {
      throw Exception(
        'Impossible d’ouvrir la page d’autorisation Google dans le navigateur.',
      );
    }
  }
}
