import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StorageService {
  StorageService._();

  static final SupabaseClient _supabase = Supabase.instance.client;
  static final ImagePicker _picker = ImagePicker();

  static const String _bucketName = 'model-photos';

  static Future<XFile?> pickModelPhoto() async {
    return _picker.pickImage(
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
    final user = _supabase.auth.currentUser;

    if (user == null) {
      throw Exception('Aucun utilisateur connecté.');
    }

    final bytes = await photo.readAsBytes();

    if (bytes.isEmpty) {
      throw Exception('Le fichier sélectionné est vide.');
    }

    final extension = _fileExtension(photo.name);
    final contentType = _contentTypeForExtension(extension);

    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final storagePath =
        '${user.id}/$modelId/model_$timestamp.$extension';

    await _supabase.storage.from(_bucketName).uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            cacheControl: '3600',
            upsert: false,
            contentType: contentType,
          ),
        );

    return _supabase.storage
        .from(_bucketName)
        .getPublicUrl(storagePath);
  }

  static Future<void> deleteModelPhoto(String? photoUrl) async {
    if (photoUrl == null || photoUrl.trim().isEmpty) {
      return;
    }

    final storagePath = _storagePathFromPublicUrl(photoUrl);

    if (storagePath == null || storagePath.isEmpty) {
      return;
    }

    await _supabase.storage.from(_bucketName).remove([
      storagePath,
    ]);
  }

  static String _fileExtension(String filename) {
    final cleanName = filename.toLowerCase().trim();
    final dotIndex = cleanName.lastIndexOf('.');

    if (dotIndex == -1 || dotIndex == cleanName.length - 1) {
      return 'jpg';
    }

    final extension = cleanName.substring(dotIndex + 1);

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

  static String _contentTypeForExtension(String extension) {
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

  static String? _storagePathFromPublicUrl(String photoUrl) {
    final marker = '/storage/v1/object/public/$_bucketName/';

    final markerIndex = photoUrl.indexOf(marker);

    if (markerIndex == -1) {
      return null;
    }

    final path = photoUrl.substring(
      markerIndex + marker.length,
    );

    if (path.isEmpty) {
      return null;
    }

    return Uri.decodeFull(path);
  }
}