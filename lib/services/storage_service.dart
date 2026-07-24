import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PickedModelDocument {
  const PickedModelDocument({
    required this.name,
    required this.bytes,
    required this.size,
    required this.contentType,
  });

  final String name;
  final Uint8List bytes;
  final int size;
  final String contentType;

  bool get isPdf => contentType == 'application/pdf';

  bool get isImage => contentType.startsWith('image/');
}

class StorageService {
  StorageService._();

  static final SupabaseClient _supabase = Supabase.instance.client;
  static final ImagePicker _imagePicker = ImagePicker();

  static const String _photoBucketName = 'model-photos';
  static const String _documentBucketName = 'model-documents';

  static const int _maximumDocumentSize = 20 * 1024 * 1024;

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
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final storagePath = '${user.id}/$modelId/model_$timestamp.$extension';

    await _supabase.storage
        .from(_photoBucketName)
        .uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            cacheControl: '3600',
            upsert: false,
            contentType: contentType,
          ),
        );

    return _supabase.storage.from(_photoBucketName).getPublicUrl(storagePath);
  }

  static Future<Uint8List?> downloadModelPhotoBytes(String? photoUrl) async {
    if (photoUrl == null || photoUrl.trim().isEmpty) {
      return null;
    }

    final storagePath = _storagePathFromPublicPhotoUrl(photoUrl);
    if (storagePath == null || storagePath.isEmpty) {
      return null;
    }

    return _supabase.storage.from(_photoBucketName).download(storagePath);
  }

  static Future<void> deleteModelPhoto(String? photoUrl) async {
    if (photoUrl == null || photoUrl.trim().isEmpty) {
      return;
    }

    final storagePath = _storagePathFromPublicPhotoUrl(photoUrl);

    if (storagePath == null || storagePath.isEmpty) {
      return;
    }

    await _supabase.storage.from(_photoBucketName).remove([storagePath]);
  }

  // ---------------------------------------------------------------------------
  // DOCUMENTS DES MODÈLES : PDF ET IMAGES
  // ---------------------------------------------------------------------------

  static Future<PickedModelDocument?> pickModelDocument() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Choisir un document',
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      allowMultiple: false,
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final file = result.files.single;
    final bytes = file.bytes;

    if (bytes == null || bytes.isEmpty) {
      throw Exception('Impossible de lire le document sélectionné.');
    }

    if (file.size > _maximumDocumentSize) {
      throw Exception(
        'Le document dépasse la taille maximale autorisée de 20 Mo.',
      );
    }

    final contentType = _documentContentType(file.name);

    if (contentType == null) {
      throw Exception('Le fichier doit être un PDF, JPG, JPEG, PNG ou WEBP.');
    }

    return PickedModelDocument(
      name: file.name,
      bytes: bytes,
      size: file.size,
      contentType: contentType,
    );
  }

  static Future<String> uploadModelDocument({
    required PickedModelDocument document,
    required String modelId,
  }) async {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('Aucun utilisateur connecté.');
    }

    if (document.bytes.isEmpty) {
      throw Exception('Le document sélectionné est vide.');
    }

    if (document.size > _maximumDocumentSize) {
      throw Exception(
        'Le document dépasse la taille maximale autorisée de 20 Mo.',
      );
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final safeFilename = _safeDocumentFilename(document.name);

    final storagePath = '${user.id}/$modelId/${timestamp}_$safeFilename';

    await _supabase.storage
        .from(_documentBucketName)
        .uploadBinary(
          storagePath,
          document.bytes,
          fileOptions: FileOptions(
            cacheControl: '3600',
            upsert: false,
            contentType: document.contentType,
          ),
        );

    return storagePath;
  }

  static Future<String> createModelDocumentSignedUrl(
    String storagePath, {
    int expiresInSeconds = 3600,
  }) async {
    final cleanPath = storagePath.trim();

    if (cleanPath.isEmpty) {
      throw Exception('Chemin du document invalide.');
    }

    return _supabase.storage
        .from(_documentBucketName)
        .createSignedUrl(cleanPath, expiresInSeconds);
  }

  static Future<void> deleteModelDocument(String storagePath) async {
    final cleanPath = storagePath.trim();

    if (cleanPath.isEmpty) {
      return;
    }

    await _supabase.storage.from(_documentBucketName).remove([cleanPath]);
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

    safeName = safeName
        .replaceAll(RegExp(r'[^\wÀ-ÿ.\-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');

    return safeName;
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

  static String? _storagePathFromPublicPhotoUrl(String photoUrl) {
    final marker = '/storage/v1/object/public/$_photoBucketName/';

    final markerIndex = photoUrl.indexOf(marker);

    if (markerIndex == -1) {
      return null;
    }

    final path = photoUrl.substring(markerIndex + marker.length);

    if (path.isEmpty) {
      return null;
    }

    return Uri.decodeFull(path);
  }
}
