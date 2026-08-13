import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis_auth/auth_io.dart' as auth;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class GoogleDriveConnectionState {
  const GoogleDriveConnectionState({
    required this.supported,
    required this.configured,
    required this.connected,
    this.message,
    this.accountEmail,
    this.accountName,
  });

  final bool supported;
  final bool configured;
  final bool connected;
  final String? message;
  final String? accountEmail;
  final String? accountName;
}

class GoogleDriveService {
  GoogleDriveService._();

  static const String _desktopClientId = String.fromEnvironment(
    'GOOGLE_DRIVE_DESKTOP_CLIENT_ID',
  );
  static const String _desktopClientSecret = String.fromEnvironment(
    'GOOGLE_DRIVE_DESKTOP_CLIENT_SECRET',
  );
  static const String _androidServerClientId = String.fromEnvironment(
    'GOOGLE_DRIVE_ANDROID_SERVER_CLIENT_ID',
  );

  static const List<String> _scopes = <String>[
    'https://www.googleapis.com/auth/drive.file',
  ];

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();
  static const String _legacyRefreshTokenKey =
      'rc_companion_google_drive_refresh_token';
  static const String _refreshTokenKeyPrefix =
      'rc_companion_google_drive_refresh_token_';
  static const String _mobileGoogleAccountKeyPrefix =
      'rc_companion_google_drive_mobile_account_';

  static const String storagePrefix = 'gdrive:';
  static const String _rootFolderName = 'RC Companion';
  static const String _modelsFolderName = 'Modèles';
  static const String _radiosFolderName = 'Radios';

  static auth.AutoRefreshingAuthClient? _desktopClient;
  static GoogleSignInAccount? _mobileAccount;
  static _GoogleAuthorizationClient? _mobileClient;
  static bool _mobileSignInInitialized = false;
  static String? _rootFolderId;
  static String? _driveOwnerUserId;

  static bool get isDesktopSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows;
  }

  static bool get isDesktopConfigured =>
      _desktopClientId.trim().isNotEmpty &&
      _desktopClientSecret.trim().isNotEmpty;

  static bool isDriveStoragePath(String value) {
    return value.trim().startsWith(storagePrefix);
  }

  static String fileIdFromStoragePath(String value) {
    final clean = value.trim();
    if (!isDriveStoragePath(clean)) {
      throw ArgumentError('Ce chemin ne correspond pas à Google Drive.');
    }

    final fileId = clean.substring(storagePrefix.length).trim();
    if (fileId.isEmpty) {
      throw ArgumentError('Identifiant Google Drive invalide.');
    }
    return fileId;
  }

  static bool get isIosSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.iOS;
  }

  static bool get isAndroidSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android;
  }

  static bool get isMobileSupported => isIosSupported || isAndroidSupported;

  static bool get isAndroidConfigured =>
      _androidServerClientId.trim().isNotEmpty;

  static Future<GoogleDriveConnectionState> connectionState() async {
    final rcUserId = _requireRcUserId();
    await _ensureDriveOwner(rcUserId);

    if (isMobileSupported) {
      if (isAndroidSupported && !isAndroidConfigured) {
        return const GoogleDriveConnectionState(
          supported: true,
          configured: false,
          connected: false,
          message:
              'Le client OAuth Web requis par Google Drive Android n’est pas '
              'fourni à cette exécution de RC Companion.',
        );
      }
      return _mobileConnectionState();
    }

    if (!isDesktopSupported) {
      return const GoogleDriveConnectionState(
        supported: false,
        configured: false,
        connected: false,
        message:
            'Google Drive est pris en charge sur macOS, Windows, Android, '
            'iPhone et iPad.',
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

    if (_desktopClient != null) {
      debugPrint('[GoogleDrive] Client OAuth Desktop actif en mémoire.');
      final identity = await _desktopGoogleIdentity();
      return GoogleDriveConnectionState(
        supported: true,
        configured: true,
        connected: true,
        accountEmail: identity.email,
        accountName: identity.name,
      );
    }

    final refreshToken = await _secureStorage.read(
      key: _refreshTokenKeyForUser(rcUserId),
    );
    if (refreshToken == null || refreshToken.trim().isEmpty) {
      debugPrint('[GoogleDrive] Aucun refresh token Desktop enregistré.');
      return const GoogleDriveConnectionState(
        supported: true,
        configured: true,
        connected: false,
      );
    }

    debugPrint('[GoogleDrive] Refresh token Desktop trouvé, restauration...');

    try {
      await _ensureRestoredClient(refreshToken.trim());
      await _verifyDriveAccess();
      final identity = await _desktopGoogleIdentity();
      return GoogleDriveConnectionState(
        supported: true,
        configured: true,
        connected: true,
        accountEmail: identity.email,
        accountName: identity.name,
      );
    } catch (_) {
      _desktopClient?.close();
      _desktopClient = null;
      _rootFolderId = null;
      return const GoogleDriveConnectionState(
        supported: true,
        configured: true,
        connected: false,
        message: 'La connexion Google Drive enregistrée doit être renouvelée.',
      );
    }
  }

  static Future<void> connectDesktop() async {
    final rcUserId = _requireRcUserId();
    await _ensureDriveOwner(rcUserId);

    if (isMobileSupported) {
      await _connectMobile();
      return;
    }

    if (!isDesktopSupported) {
      throw Exception(
        'La connexion Google Drive n’est pas encore disponible sur cette '
        'plateforme.',
      );
    }

    if (!isDesktopConfigured) {
      throw Exception(
        'Configuration OAuth Desktop absente. Lance RC Companion avec les '
        'identifiants Google Drive Desktop prévus pour cette installation.',
      );
    }

    _desktopClient?.close();
    _desktopClient = null;
    _rootFolderId = null;

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

    _desktopClient = client;
    debugPrint('[GoogleDrive] Retour OAuth reçu : client Desktop actif.');

    try {
      await _verifyDriveAccess();
      debugPrint('[GoogleDrive] Accès Google Drive Desktop vérifié.');

      final refreshToken = client.credentials.refreshToken?.trim();

      if (refreshToken == null || refreshToken.isEmpty) {
        debugPrint(
          '[GoogleDrive] Aucun refresh token renvoyé par Google. '
          'La connexion reste active pour cette exécution.',
        );
        return;
      }

      await _secureStorage.write(
        key: _refreshTokenKeyForUser(rcUserId),
        value: refreshToken,
      );

      debugPrint(
        '[GoogleDrive] Refresh token Desktop enregistré dans le stockage sécurisé.',
      );
    } catch (error) {
      debugPrint('[GoogleDrive] Échec après retour OAuth Desktop : $error');
      client.close();
      if (identical(_desktopClient, client)) _desktopClient = null;
      _rootFolderId = null;
      rethrow;
    }
  }

  static Future<void> disconnect() async {
    final rcUserId = _requireRcUserId();

    if (isMobileSupported) {
      await _ensureMobileSignInInitialized();
      await GoogleSignIn.instance.disconnect();
      await _secureStorage.delete(
        key: _mobileGoogleAccountKeyForUser(rcUserId),
      );
      _mobileAccount = null;
      _mobileClient?.close();
      _mobileClient = null;
      _rootFolderId = null;
      _driveOwnerUserId = null;
      debugPrint('[GoogleDrive] Connexion Google mobile supprimée.');
      return;
    }

    await _secureStorage.delete(key: _refreshTokenKeyForUser(rcUserId));
    _desktopClient?.close();
    _desktopClient = null;
    _rootFolderId = null;
    _driveOwnerUserId = null;
    debugPrint('[GoogleDrive] Connexion locale Desktop supprimée.');
  }

  static Future<GoogleDriveConnectionState> _mobileConnectionState() async {
    try {
      await _ensureMobileSignInInitialized();

      var account = _mobileAccount;
      if (account == null) {
        final expectedGoogleAccount = await _secureStorage.read(
          key: _mobileGoogleAccountKeyForUser(_requireRcUserId()),
        );

        if (expectedGoogleAccount == null ||
            expectedGoogleAccount.trim().isEmpty) {
          return const GoogleDriveConnectionState(
            supported: true,
            configured: true,
            connected: false,
            message:
                'Google Drive n’est pas encore associé à ce compte '
                'RC Companion.',
          );
        }

        final restoredAccount = await GoogleSignIn.instance
            .attemptLightweightAuthentication();

        if (restoredAccount == null) {
          return const GoogleDriveConnectionState(
            supported: true,
            configured: true,
            connected: false,
            message:
                'Le compte Google Drive associé n’a pas pu être reconnecté '
                'automatiquement. Reconnecte Google Drive.',
          );
        }

        if (restoredAccount.email.trim().toLowerCase() !=
            expectedGoogleAccount.trim().toLowerCase()) {
          await GoogleSignIn.instance.signOut();
          return const GoogleDriveConnectionState(
            supported: true,
            configured: true,
            connected: false,
            message:
                'Le compte Google disponible sur cet appareil ne correspond '
                'pas au Google Drive associé à ce compte RC Companion.',
          );
        }

        _mobileAccount = restoredAccount;
        account = restoredAccount;
      }

      final authorization = await account.authorizationClient
          .authorizationForScopes(_scopes);
      if (authorization == null) {
        return const GoogleDriveConnectionState(
          supported: true,
          configured: true,
          connected: false,
          message:
              'Google est connecté, mais RC Companion doit encore être '
              'autorisé à utiliser Google Drive.',
        );
      }

      return GoogleDriveConnectionState(
        supported: true,
        configured: true,
        connected: true,
        accountEmail: account.email.trim(),
        accountName: account.displayName?.trim(),
      );
    } catch (error) {
      debugPrint(
        '[GoogleDrive] Vérification Google mobile impossible : $error',
      );
      _mobileAccount = null;
      return const GoogleDriveConnectionState(
        supported: true,
        configured: true,
        connected: false,
        message: 'La connexion Google Drive doit être renouvelée.',
      );
    }
  }

  static Future<void> _connectMobile() async {
    final rcUserId = _requireRcUserId();

    if (isAndroidSupported && !isAndroidConfigured) {
      throw StateError(
        'Le client OAuth Web requis par Google Drive Android est absent.',
      );
    }

    await _ensureMobileSignInInitialized();
    _rootFolderId = null;

    debugPrint('[GoogleDrive] Démarrage de la connexion Google mobile...');

    final account = await GoogleSignIn.instance.authenticate(
      scopeHint: _scopes,
    );
    _mobileAccount = account;
    _driveOwnerUserId = rcUserId;

    await _secureStorage.write(
      key: _mobileGoogleAccountKeyForUser(rcUserId),
      value: account.email.trim().toLowerCase(),
    );

    var authorization = await account.authorizationClient
        .authorizationForScopes(_scopes);
    authorization ??= await account.authorizationClient.authorizeScopes(
      _scopes,
    );

    _mobileClient ??= _GoogleAuthorizationClient(authorization.accessToken);
    _mobileClient!.accessToken = authorization.accessToken;
    final api = drive.DriveApi(_mobileClient!);
    await api.files.list(pageSize: 1, $fields: 'files(id)');
    debugPrint('[GoogleDrive] Accès Google Drive mobile vérifié.');
  }

  static Future<void> _ensureMobileSignInInitialized() async {
    if (_mobileSignInInitialized) return;

    await GoogleSignIn.instance.initialize(
      serverClientId: isAndroidSupported ? _androidServerClientId.trim() : null,
    );

    _mobileSignInInitialized = true;
    debugPrint('[GoogleDrive] Google Sign-In mobile initialisé.');
  }

  static String _requireRcUserId() {
    final userId = Supabase.instance.client.auth.currentUser?.id.trim();
    if (userId == null || userId.isEmpty) {
      throw StateError(
        'Aucun compte RC Companion n’est connecté. '
        'Google Drive ne peut pas être utilisé.',
      );
    }
    return userId;
  }

  static String _refreshTokenKeyForUser(String userId) {
    return '$_refreshTokenKeyPrefix$userId';
  }

  static String _mobileGoogleAccountKeyForUser(String userId) {
    return '$_mobileGoogleAccountKeyPrefix$userId';
  }

  static Future<void> _ensureDriveOwner(String rcUserId) async {
    final currentOwner = _driveOwnerUserId;

    if (currentOwner == rcUserId) {
      return;
    }

    // Un changement de compte RC Companion ne doit jamais réutiliser
    // silencieusement la session Google Drive du compte précédent.
    _desktopClient?.close();
    _desktopClient = null;
    _mobileClient?.close();
    _mobileClient = null;
    _mobileAccount = null;
    _rootFolderId = null;
    _driveOwnerUserId = rcUserId;

    // L'ancienne clé Desktop globale n'est plus utilisée. On la supprime
    // localement pour éviter qu'un ancien compte RC puisse en hériter.
    await _secureStorage.delete(key: _legacyRefreshTokenKey);

    debugPrint(
      '[GoogleDrive] Contexte Drive associé au compte RC Companion $rcUserId.',
    );
  }

  static Future<void> resetRcCompanionFiles() async {
    final api = await _driveApi();

    final result = await api.files.list(
      q: "appProperties has { key='rcCompanion' and value='true' } and trashed = false",
      spaces: 'drive',
      pageSize: 1000,
      $fields: 'files(id,name,mimeType,parents,appProperties)',
    );

    final files = result.files ?? const <drive.File>[];

    for (final file in files) {
      final id = file.id?.trim();
      if (id == null || id.isEmpty) {
        continue;
      }

      try {
        await api.files.delete(id);
        debugPrint(
          '[GoogleDrive] RESET : élément RC Companion supprimé '
          '${file.name} ($id)',
        );
      } catch (_) {
        // Un élément enfant peut déjà avoir disparu avec son dossier parent.
      }
    }

    final escapedName = _rootFolderName.replaceAll("'", r"\'");
    final roots = await api.files.list(
      q:
          "name = '$escapedName' and "
          "mimeType = 'application/vnd.google-apps.folder' and "
          "'root' in parents and trashed = false",
      spaces: 'drive',
      pageSize: 10,
      $fields: 'files(id,name)',
    );

    for (final folder in roots.files ?? const <drive.File>[]) {
      final id = folder.id?.trim();
      if (id == null || id.isEmpty) {
        continue;
      }

      await api.files.delete(id);
      debugPrint('[GoogleDrive] RESET : dossier racine supprimé ($id)');
    }

    _rootFolderId = null;
  }

  static Future<String> ensureModelFolder({
    required String modelId,
    required String brand,
    required String name,
  }) async {
    final api = await _driveApi();
    final categoryId = await _ensureRelativeFolder(api, _modelsFolderName);
    final entityFolderId = await _ensureEntityFolder(
      api,
      parentId: categoryId,
      objectKey: 'model:$modelId',
      displayName: _entityDisplayName(brand: brand, name: name),
    );
    await _findOrCreateFolder(
      api,
      folderName: 'Documents',
      parentId: entityFolderId,
    );
    await _findOrCreateFolder(
      api,
      folderName: 'Photos',
      parentId: entityFolderId,
    );
    return entityFolderId;
  }

  static Future<String> ensureRadioFolder({
    required String radioId,
    required String brand,
    required String name,
  }) async {
    final api = await _driveApi();
    final categoryId = await _ensureRelativeFolder(api, _radiosFolderName);
    final entityFolderId = await _ensureEntityFolder(
      api,
      parentId: categoryId,
      objectKey: 'radio:$radioId',
      displayName: _entityDisplayName(brand: brand, name: name),
    );
    await _findOrCreateFolder(
      api,
      folderName: 'Notice',
      parentId: entityFolderId,
    );
    return entityFolderId;
  }

  static Future<void> deleteModelFolder(String modelId) async {
    await _deleteEntityFolder('model:$modelId');
  }

  static Future<void> deleteRadioFolder(String radioId) async {
    await _deleteEntityFolder('radio:$radioId');
  }

  static Future<String> uploadFileBytes({
    required Uint8List bytes,
    required String filename,
    required String contentType,
    required String relativeFolder,
    String? objectKey,
  }) async {
    if (bytes.isEmpty) {
      throw Exception('Le fichier à envoyer sur Google Drive est vide.');
    }

    final api = await _driveApi();
    final cleanObjectKey = objectKey?.trim();
    final parentId = await _resolveUploadParent(
      api,
      relativeFolder: relativeFolder,
      objectKey: cleanObjectKey,
    );

    final appProperties = <String, String>{
      'rcCompanion': 'true',
      'storageVersion': '1',
      if (cleanObjectKey != null && cleanObjectKey.isNotEmpty)
        'rcCompanionObjectKey': cleanObjectKey,
    };

    final metadata = drive.File()
      ..name = filename
      ..parents = <String>[parentId]
      ..appProperties = appProperties;

    final media = drive.Media(
      Stream<List<int>>.value(bytes),
      bytes.length,
      contentType: contentType,
    );

    if (cleanObjectKey != null && cleanObjectKey.isNotEmpty) {
      final existingFile = await _findFileByObjectKey(
        api,
        objectKey: cleanObjectKey,
      );

      final existingId = existingFile?.id?.trim();
      if (existingId != null && existingId.isNotEmpty) {
        // Pour les fichiers gérés par RC Companion (photo de modèle,
        // document de modèle et notice radio), on recrée volontairement le
        // fichier lors d'un remplacement. Google Drive régénère ainsi aussi
        // son aperçu et aucun ancien aperçu ne reste attaché à l'ancien ID.
        final recreateOnReplacement =
            cleanObjectKey.startsWith('model_photo:') ||
            cleanObjectKey.startsWith('model_document:') ||
            cleanObjectKey.startsWith('radio_manual:');

        if (recreateOnReplacement) {
          await api.files.delete(existingId);
          debugPrint(
            '[GoogleDrive] Ancien fichier supprimé avant remplacement : '
            '$existingId — clé $cleanObjectKey',
          );

          final recreated = await api.files.create(
            metadata,
            uploadMedia: media,
            $fields: 'id,name',
          );

          final recreatedId = recreated.id?.trim();
          if (recreatedId == null || recreatedId.isEmpty) {
            throw StateError(
              'Google Drive n’a pas renvoyé l’identifiant du fichier recréé.',
            );
          }

          debugPrint(
            '[GoogleDrive] Fichier recréé : ${recreated.name} ($recreatedId) '
            '— clé $cleanObjectKey',
          );
          return '$storagePrefix$recreatedId';
        }

        // Pour d'éventuels autres fichiers, on conserve la mise à jour en place.
        final updateMetadata = drive.File()
          ..name = filename
          ..appProperties = appProperties;

        final updated = await api.files.update(
          updateMetadata,
          existingId,
          uploadMedia: media,
          $fields: 'id,name',
        );

        debugPrint(
          '[GoogleDrive] Fichier réutilisé/mis à jour : '
          '${updated.name} ($existingId) — clé $cleanObjectKey',
        );
        return '$storagePrefix$existingId';
      }
    }

    final created = await api.files.create(
      metadata,
      uploadMedia: media,
      $fields: 'id,name',
    );

    final fileId = created.id?.trim();
    if (fileId == null || fileId.isEmpty) {
      throw StateError(
        'Google Drive n’a pas renvoyé l’identifiant du fichier envoyé.',
      );
    }

    debugPrint(
      '[GoogleDrive] Fichier créé : ${created.name} ($fileId)'
      '${cleanObjectKey == null || cleanObjectKey.isEmpty ? '' : ' — clé $cleanObjectKey'}',
    );
    return '$storagePrefix$fileId';
  }

  static Future<Uint8List> downloadFileBytes(String storagePath) async {
    final api = await _driveApi();
    final fileId = fileIdFromStoragePath(storagePath);

    final response = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    );

    if (response is! drive.Media) {
      throw StateError(
        'Réponse Google Drive inattendue lors du téléchargement.',
      );
    }

    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      builder.add(chunk);
    }

    final bytes = builder.takeBytes();
    debugPrint(
      '[GoogleDrive] Fichier téléchargé : $fileId (${bytes.length} octets)',
    );
    return bytes;
  }

  static Future<void> deleteFile(String storagePath) async {
    final api = await _driveApi();
    final fileId = fileIdFromStoragePath(storagePath);
    await api.files.delete(fileId);
    debugPrint('[GoogleDrive] Fichier supprimé : $fileId');
  }

  static Future<void> renameFile(String storagePath, String newFilename) async {
    final cleanFilename = newFilename.trim();
    if (cleanFilename.isEmpty) {
      throw ArgumentError('Le nouveau nom du fichier Google Drive est vide.');
    }

    final api = await _driveApi();
    final fileId = fileIdFromStoragePath(storagePath);

    final updated = await api.files.update(
      drive.File()..name = cleanFilename,
      fileId,
      $fields: 'id,name',
    );

    debugPrint('[GoogleDrive] Fichier renommé : ${updated.name} ($fileId)');
  }

  static Future<drive.DriveApi> _driveApi() async {
    final state = await connectionState();
    if (!state.connected) {
      throw StateError(
        state.message ?? 'Google Drive n’est pas connecté à RC Companion.',
      );
    }

    if (isMobileSupported) {
      final account = _mobileAccount;
      if (account == null) {
        throw StateError('Google Drive n’est pas connecté à RC Companion.');
      }

      final authorization = await account.authorizationClient
          .authorizationForScopes(_scopes);
      if (authorization == null) {
        throw StateError(
          'L’autorisation Google Drive doit être renouvelée dans RC Companion.',
        );
      }
      _mobileClient ??= _GoogleAuthorizationClient(authorization.accessToken);
      _mobileClient!.accessToken = authorization.accessToken;
      return drive.DriveApi(_mobileClient!);
    }

    final client = _desktopClient;
    if (client == null) {
      throw StateError('Google Drive n’est pas connecté à RC Companion.');
    }
    return drive.DriveApi(client);
  }

  static Future<String> _resolveUploadParent(
    drive.DriveApi api, {
    required String relativeFolder,
    required String? objectKey,
  }) async {
    final cleanKey = objectKey?.trim() ?? '';

    if (cleanKey.startsWith('model_document:')) {
      final modelId = relativeFolder.trim();
      await _ensureRelativeFolder(api, _modelsFolderName);
      final entityFolder = await _findEntityFolder(
        api,
        objectKey: 'model:$modelId',
      );
      if (entityFolder != null) {
        return _findOrCreateFolder(
          api,
          folderName: 'Documents',
          parentId: entityFolder.id!,
        );
      }
      return _ensureRelativeFolder(api, relativeFolder);
    }

    if (cleanKey.startsWith('model_photo:')) {
      final modelId = cleanKey.substring('model_photo:'.length).trim();
      await _ensureRelativeFolder(api, _modelsFolderName);
      final entityFolder = await _findEntityFolder(
        api,
        objectKey: 'model:$modelId',
      );
      if (entityFolder != null) {
        return _findOrCreateFolder(
          api,
          folderName: 'Photos',
          parentId: entityFolder.id!,
        );
      }
      return _ensureRelativeFolder(api, relativeFolder);
    }

    if (cleanKey.startsWith('radio_manual:')) {
      final radioId = cleanKey.substring('radio_manual:'.length).trim();
      await _ensureRelativeFolder(api, _radiosFolderName);
      final entityFolder = await _findEntityFolder(
        api,
        objectKey: 'radio:$radioId',
      );
      if (entityFolder != null) {
        return _findOrCreateFolder(
          api,
          folderName: 'Notice',
          parentId: entityFolder.id!,
        );
      }
      return _ensureRelativeFolder(api, relativeFolder);
    }

    return _ensureRelativeFolder(api, relativeFolder);
  }

  static Future<String> _ensureEntityFolder(
    drive.DriveApi api, {
    required String parentId,
    required String objectKey,
    required String displayName,
  }) async {
    final existing = await _findEntityFolder(api, objectKey: objectKey);
    final existingId = existing?.id?.trim();

    if (existingId != null && existingId.isNotEmpty) {
      if ((existing?.name ?? '') != displayName) {
        await api.files.update(
          drive.File()..name = displayName,
          existingId,
          $fields: 'id,name',
        );
        debugPrint(
          '[GoogleDrive] Dossier renommé : $displayName ($existingId)',
        );
      }
      return existingId;
    }

    final folder = drive.File()
      ..name = displayName
      ..mimeType = 'application/vnd.google-apps.folder'
      ..parents = <String>[parentId]
      ..appProperties = <String, String>{
        'rcCompanion': 'true',
        'rcCompanionFolderKey': objectKey,
      };

    final created = await api.files.create(folder, $fields: 'id,name');
    final id = created.id?.trim();
    if (id == null || id.isEmpty) {
      throw StateError(
        'Google Drive n’a pas renvoyé l’identifiant du dossier créé.',
      );
    }

    debugPrint('[GoogleDrive] Dossier créé : $displayName ($id)');
    return id;
  }

  static Future<drive.File?> _findEntityFolder(
    drive.DriveApi api, {
    required String objectKey,
  }) async {
    final escapedKey = objectKey.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    final result = await api.files.list(
      q:
          "appProperties has { key='rcCompanionFolderKey' "
          "and value='$escapedKey' } and "
          "mimeType = 'application/vnd.google-apps.folder' and "
          "trashed = false",
      spaces: 'drive',
      pageSize: 10,
      $fields: 'files(id,name,parents,appProperties)',
    );
    final files = result.files;
    if (files == null || files.isEmpty) return null;
    return files.first;
  }

  static Future<void> _deleteEntityFolder(String objectKey) async {
    final api = await _driveApi();
    final folder = await _findEntityFolder(api, objectKey: objectKey);
    final id = folder?.id?.trim();
    if (id == null || id.isEmpty) return;
    await api.files.delete(id);
    debugPrint('[GoogleDrive] Dossier supprimé : ${folder?.name} ($id)');
  }

  static String _entityDisplayName({
    required String brand,
    required String name,
  }) {
    final cleanBrand = _safeFolderPart(brand);
    final cleanName = _safeFolderPart(name);

    if (cleanBrand.isEmpty && cleanName.isEmpty) return 'Sans nom';
    if (cleanBrand.isEmpty) return cleanName;
    if (cleanName.isEmpty) return cleanBrand;
    return '$cleanBrand - $cleanName';
  }

  static String _safeFolderPart(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'[/\\:\n\r\t]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static Future<String> _ensureRelativeFolder(
    drive.DriveApi api,
    String relativeFolder,
  ) async {
    var parentId = await _ensureRootFolder(api);

    final parts = relativeFolder
        .split('/')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);

    for (final part in parts) {
      parentId = await _findOrCreateFolder(
        api,
        folderName: part,
        parentId: parentId,
      );
    }

    return parentId;
  }

  static Future<String> _ensureRootFolder(drive.DriveApi api) async {
    final cached = _rootFolderId;
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    final rootId = await _findOrCreateFolder(
      api,
      folderName: _rootFolderName,
      parentId: 'root',
    );
    _rootFolderId = rootId;
    return rootId;
  }

  static Future<String> _findOrCreateFolder(
    drive.DriveApi api, {
    required String folderName,
    required String parentId,
  }) async {
    final escapedName = folderName.replaceAll("'", r"\'");
    final result = await api.files.list(
      q:
          "name = '$escapedName' and "
          "mimeType = 'application/vnd.google-apps.folder' and "
          "'$parentId' in parents and trashed = false",
      spaces: 'drive',
      pageSize: 10,
      $fields: 'files(id,name)',
    );

    final existing = result.files;
    if (existing != null && existing.isNotEmpty) {
      final id = existing.first.id?.trim();
      if (id != null && id.isNotEmpty) {
        return id;
      }
    }

    final folder = drive.File()
      ..name = folderName
      ..mimeType = 'application/vnd.google-apps.folder'
      ..parents = <String>[parentId]
      ..appProperties = <String, String>{'rcCompanion': 'true'};

    final created = await api.files.create(folder, $fields: 'id,name');
    final id = created.id?.trim();
    if (id == null || id.isEmpty) {
      throw StateError(
        'Google Drive n’a pas renvoyé l’identifiant du dossier créé.',
      );
    }

    debugPrint('[GoogleDrive] Dossier créé : $folderName ($id)');
    return id;
  }

  static Future<drive.File?> _findFileByObjectKey(
    drive.DriveApi api, {
    required String objectKey,
  }) async {
    final escapedKey = objectKey.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

    final result = await api.files.list(
      q:
          "appProperties has { key='rcCompanionObjectKey' "
          "and value='$escapedKey' } and trashed = false",
      spaces: 'drive',
      pageSize: 10,
      $fields: 'files(id,name,parents,appProperties)',
    );

    final files = result.files;
    if (files == null || files.isEmpty) {
      return null;
    }

    if (files.length > 1) {
      debugPrint(
        '[GoogleDrive] Attention : ${files.length} fichiers portent la même '
        'clé RC Companion $objectKey. Le premier sera réutilisé.',
      );
    }

    return files.first;
  }

  static Future<void> _ensureRestoredClient(String refreshToken) async {
    if (_desktopClient != null) return;

    final clientId = auth.ClientId(
      _desktopClientId.trim(),
      _desktopClientSecret.trim(),
    );

    _desktopClient = await auth.clientViaRefreshToken(
      clientId,
      refreshToken,
      _scopes,
    );

    debugPrint(
      '[GoogleDrive] Client OAuth Desktop restauré via refresh token.',
    );
  }

  static Future<_GoogleDriveIdentity> _desktopGoogleIdentity() async {
    final client = _desktopClient;
    if (client == null) {
      return const _GoogleDriveIdentity();
    }

    try {
      final api = drive.DriveApi(client);
      final about = await api.about.get(
        $fields: 'user(displayName,emailAddress)',
      );
      final user = about.user;

      return _GoogleDriveIdentity(
        email: user?.emailAddress?.trim(),
        name: user?.displayName?.trim(),
      );
    } catch (error) {
      debugPrint(
        '[GoogleDrive] Lecture de l’identité du compte Google impossible : '
        '$error',
      );
      return const _GoogleDriveIdentity();
    }
  }

  static Future<void> _verifyDriveAccess() async {
    final client = _desktopClient;
    if (client == null) {
      throw Exception('Google Drive Desktop n’est pas connecté.');
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

class _GoogleDriveIdentity {
  const _GoogleDriveIdentity({this.email, this.name});

  final String? email;
  final String? name;
}

class _GoogleAuthorizationClient extends http.BaseClient {
  _GoogleAuthorizationClient(this.accessToken);

  String accessToken;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $accessToken';
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
