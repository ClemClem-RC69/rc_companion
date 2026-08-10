import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'google_drive_service.dart';

class PickedModelDocument {
  const PickedModelDocument({
    required this.name,
    required this.size,
    required this.contentType,
    this.path,
    this.bytes,
  });

  final String name;
  final int size;
  final String contentType;
  final String? path;
  final Uint8List? bytes;

  bool get isPdf => contentType == 'application/pdf';

  bool get isImage => contentType.startsWith('image/');
}

class StorageService {
  StorageService._();

  static final SupabaseClient _supabase = Supabase.instance.client;
  static final ImagePicker _imagePicker = ImagePicker();

  static const int _maximumPdfSize = 200 * 1024 * 1024;
  static const int _maximumImageSize = 50 * 1024 * 1024;

  // ---------------------------------------------------------------------------
  // PHOTOS DES MODÈLES
  // ---------------------------------------------------------------------------

  static Future<XFile?> pickModelPhoto() async {
    return _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 82,
      requestFullMetadata: false,
    );
  }

  static Future<String> uploadModelPhoto({
    required XFile photo,
    required String modelId,
  }) async {
    return uploadModelPhotoBytes(
      bytes: await photo.readAsBytes(),
      originalFilename: photo.name,
      modelId: modelId,
    );
  }

  static Future<String> uploadModelPhotoBytes({
    required Uint8List bytes,
    required String originalFilename,
    required String modelId,
  }) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('Aucun utilisateur connecté.');
    }

    if (bytes.isEmpty) {
      throw Exception('Le fichier sélectionné est vide.');
    }

    final extension = _imageFileExtension(originalFilename);
    final contentType = _imageContentType(extension);

    final driveState = await GoogleDriveService.connectionState();
    if (!driveState.connected) {
      throw StateError(
        driveState.message ??
            'Google Drive n’est pas connecté. '
                'La photo reste stockée localement et sera synchronisée '
                'automatiquement lorsque Google Drive sera disponible.',
      );
    }

    return GoogleDriveService.uploadFileBytes(
      bytes: bytes,
      filename: 'photo_modele.$extension',
      contentType: contentType,
      relativeFolder: modelId,
      objectKey: 'model_photo:$modelId',
    );
  }

  static Future<Uint8List?> downloadModelPhotoBytes(String? photoUrl) async {
    if (photoUrl == null || photoUrl.trim().isEmpty) {
      return null;
    }

    if (!GoogleDriveService.isDriveStoragePath(photoUrl)) {
      return null;
    }

    return GoogleDriveService.downloadFileBytes(photoUrl);
  }

  static Future<void> deleteModelPhoto(String? photoUrl) async {
    if (photoUrl == null || photoUrl.trim().isEmpty) {
      return;
    }

    if (!GoogleDriveService.isDriveStoragePath(photoUrl)) {
      return;
    }

    await GoogleDriveService.deleteFile(photoUrl);
  }

  // ---------------------------------------------------------------------------
  // DOCUMENTS DES MODÈLES ET NOTICES RADIO : PDF ET IMAGES
  //
  // ARCHITECTURE FINALE :
  // - tous les fichiers lourds sont stockés uniquement sur Google Drive ;
  // - si Drive ou le réseau n'est pas disponible, l'opération de
  //   synchronisation reste en attente et le fichier reste local ;
  // - Google Drive est l'unique stockage distant des fichiers lourds.
  // ---------------------------------------------------------------------------

  static Future<PickedModelDocument?> pickModelDocument() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Choisir un document',
      type: FileType.any,
      allowMultiple: false,
      withData: kIsWeb,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final file = result.files.single;

    final contentType = _documentContentType(file.name);

    if (contentType == null) {
      throw Exception('Formats autorisés : PDF, JPG, JPEG, PNG et WEBP.');
    }

    final maximumSize = contentType == 'application/pdf'
        ? _maximumPdfSize
        : _maximumImageSize;

    if (file.size > maximumSize) {
      throw Exception(
        contentType == 'application/pdf'
            ? 'Le PDF dépasse la taille maximale autorisée de 200 Mo.'
            : 'Les images sont limitées à 50 Mo.',
      );
    }

    final path = file.path?.trim();
    final bytes = file.bytes;

    if ((path == null || path.isEmpty) && (bytes == null || bytes.isEmpty)) {
      throw Exception('Impossible de lire le document sélectionné.');
    }

    return PickedModelDocument(
      name: file.name,
      size: file.size,
      contentType: contentType,
      path: path,
      bytes: bytes,
    );
  }

  static Future<String> uploadModelDocument({
    required PickedModelDocument document,
    required String modelId,
  }) async {
    Uint8List? bytes = document.bytes;

    final path = document.path?.trim();
    if ((bytes == null || bytes.isEmpty) && path != null && path.isNotEmpty) {
      bytes = await XFile(path).readAsBytes();
    }

    if (bytes == null || bytes.isEmpty) {
      throw Exception('Impossible de lire le document sélectionné.');
    }

    return uploadModelDocumentBytes(
      bytes: bytes,
      originalFilename: document.name,
      contentType: document.contentType,
      modelId: modelId,
    );
  }

  static Future<String> uploadModelDocumentBytes({
    required Uint8List bytes,
    required String originalFilename,
    required String contentType,
    required String modelId,
    String? driveObjectKey,
  }) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('Aucun utilisateur connecté.');
    }

    if (bytes.isEmpty) {
      throw Exception('Le document sélectionné est vide.');
    }

    final maximumSize = contentType == 'application/pdf'
        ? _maximumPdfSize
        : _maximumImageSize;

    if (bytes.length > maximumSize) {
      throw Exception(
        contentType == 'application/pdf'
            ? 'Le PDF dépasse la taille maximale autorisée de 200 Mo.'
            : 'Les images sont limitées à 50 Mo.',
      );
    }

    final safeFilename = _safeDocumentFilename(originalFilename);

    final driveState = await GoogleDriveService.connectionState();
    if (!driveState.connected) {
      throw StateError(
        driveState.message ??
            'Google Drive n’est pas connecté. '
                'Le document reste stocké localement et sera synchronisé '
                'automatiquement lorsque Google Drive sera disponible.',
      );
    }

    return GoogleDriveService.uploadFileBytes(
      bytes: bytes,
      filename: safeFilename,
      contentType: contentType,
      relativeFolder: modelId,
      objectKey: driveObjectKey,
    );
  }

  static Future<Uint8List> downloadModelDocumentBytes(
    String storagePath,
  ) async {
    final cleanPath = storagePath.trim();

    if (cleanPath.isEmpty) {
      throw Exception('Chemin du document invalide.');
    }

    if (!GoogleDriveService.isDriveStoragePath(cleanPath)) {
      throw UnsupportedError('Ce document n’est pas stocké sur Google Drive.');
    }

    return GoogleDriveService.downloadFileBytes(cleanPath);
  }

  static Future<String> createModelDocumentSignedUrl(
    String storagePath, {
    int expiresInSeconds = 3600,
  }) async {
    final cleanPath = storagePath.trim();

    if (cleanPath.isEmpty) {
      throw Exception('Chemin du document invalide.');
    }

    throw UnsupportedError(
      'RC Companion ouvre les documents Google Drive depuis le cache local. '
      'Les documents Google Drive sont ouverts depuis le cache local.',
    );
  }

  static Future<void> deleteModelDocument(String storagePath) async {
    final cleanPath = storagePath.trim();

    if (cleanPath.isEmpty) {
      return;
    }

    if (!GoogleDriveService.isDriveStoragePath(cleanPath)) {
      return;
    }

    await GoogleDriveService.deleteFile(cleanPath);
  }

  static Future<void> renameModelDocument(
    String storagePath,
    String newFilename,
  ) async {
    final cleanPath = storagePath.trim();
    final cleanFilename = _safeDocumentFilename(newFilename);

    if (cleanPath.isEmpty || cleanFilename.isEmpty) {
      return;
    }

    // Le renommage demandé ici concerne le fichier visible dans Google Drive.
    if (GoogleDriveService.isDriveStoragePath(cleanPath)) {
      await GoogleDriveService.renameFile(cleanPath, cleanFilename);
    }
  }

  // ---------------------------------------------------------------------------
  // OUTILS INTERNES
  // ---------------------------------------------------------------------------

  static String? _documentContentType(String filename) {
    final extension = _extensionFromFilename(filename);

    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      default:
        return null;
    }
  }

  static String _safeDocumentFilename(String filename) {
    var safeName = filename.trim();

    if (safeName.isEmpty) {
      safeName = 'document.pdf';
    }

    safeName = _removeDocumentFilenameAccents(safeName)
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    return safeName.isEmpty ? 'document.pdf' : safeName;
  }

  static String _removeDocumentFilenameAccents(String value) {
    const replacements = <String, String>{
      'à': 'a',
      'á': 'a',
      'â': 'a',
      'ä': 'a',
      'ã': 'a',
      'å': 'a',
      'À': 'A',
      'Á': 'A',
      'Â': 'A',
      'Ä': 'A',
      'Ã': 'A',
      'Å': 'A',
      'ç': 'c',
      'Ç': 'C',
      'è': 'e',
      'é': 'e',
      'ê': 'e',
      'ë': 'e',
      'È': 'E',
      'É': 'E',
      'Ê': 'E',
      'Ë': 'E',
      'ì': 'i',
      'í': 'i',
      'î': 'i',
      'ï': 'i',
      'Ì': 'I',
      'Í': 'I',
      'Î': 'I',
      'Ï': 'I',
      'ñ': 'n',
      'Ñ': 'N',
      'ò': 'o',
      'ó': 'o',
      'ô': 'o',
      'ö': 'o',
      'õ': 'o',
      'Ò': 'O',
      'Ó': 'O',
      'Ô': 'O',
      'Ö': 'O',
      'Õ': 'O',
      'ù': 'u',
      'ú': 'u',
      'û': 'u',
      'ü': 'u',
      'Ù': 'U',
      'Ú': 'U',
      'Û': 'U',
      'Ü': 'U',
      'ý': 'y',
      'ÿ': 'y',
      'Ý': 'Y',
      'œ': 'oe',
      'Œ': 'OE',
      'æ': 'ae',
      'Æ': 'AE',
    };

    final buffer = StringBuffer();

    for (final rune in value.runes) {
      final character = String.fromCharCode(rune);
      buffer.write(replacements[character] ?? character);
    }

    return buffer.toString();
  }

  static String _extensionFromFilename(String filename) {
    final cleanName = filename.toLowerCase().trim();
    final dotIndex = cleanName.lastIndexOf('.');

    if (dotIndex == -1 || dotIndex == cleanName.length - 1) {
      return '';
    }

    return cleanName.substring(dotIndex + 1);
  }

  static String _imageFileExtension(String filename) {
    final extension = _extensionFromFilename(filename);

    switch (extension) {
      case 'jpeg':
      case 'jpg':
        return 'jpg';
      case 'png':
        return 'png';
      case 'webp':
        return 'webp';
      default:
        return 'jpg';
    }
  }

  static String _imageContentType(String extension) {
    switch (extension) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'jpg':
      default:
        return 'image/jpeg';
    }
  }
}
