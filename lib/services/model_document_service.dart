import '../models/model_document.dart';
import 'storage_service.dart';
import 'supabase_service.dart';

class ModelDocumentService {
  ModelDocumentService._();

  static final _client = SupabaseService.client;

  static Future<List<ModelDocument>> getDocuments(
    String modelId,
  ) async {
    final response = await _client
        .from('model_documents')
        .select()
        .eq('model_id', modelId)
        .order('created_at');

    return response
        .map<ModelDocument>(
          (item) => ModelDocument.fromMap(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList();
  }

  static Future<ModelDocument> addDocument({
    required String modelId,
    required String documentType,
  }) async {
    final picked = await StorageService.pickModelDocument();

    if (picked == null) {
      throw Exception('Aucun document sélectionné.');
    }

    final storagePath =
        await StorageService.uploadModelDocument(
      document: picked,
      modelId: modelId,
    );

    final user = _client.auth.currentUser;

    if (user == null) {
      try {
        await StorageService.deleteModelDocument(
          storagePath,
        );
      } catch (_) {
        // On conserve l’erreur principale.
      }

      throw Exception('Aucun utilisateur connecté.');
    }

    try {
      final response = await _client
          .from('model_documents')
          .insert({
            'user_id': user.id,
            'model_id': modelId,
            'document_name': picked.name,
            'document_type': documentType,
            'storage_path': storagePath,
          })
          .select()
          .single();

      return ModelDocument.fromMap(
        Map<String, dynamic>.from(response),
      );
    } catch (error) {
      try {
        await StorageService.deleteModelDocument(
          storagePath,
        );
      } catch (_) {
        // Le fichier orphelin éventuel ne masque pas l’erreur principale.
      }

      rethrow;
    }
  }

  static Future<ModelDocument> renameDocument({
    required ModelDocument document,
    required String newName,
  }) async {
    final cleanName = newName.trim();

    if (cleanName.isEmpty) {
      throw Exception(
        'Le nom du document ne peut pas être vide.',
      );
    }

    final response = await _client
        .from('model_documents')
        .update({
          'document_name': cleanName,
        })
        .eq('id', document.id)
        .select()
        .single();

    return ModelDocument.fromMap(
      Map<String, dynamic>.from(response),
    );
  }

  static Future<void> deleteDocument(
    ModelDocument document,
  ) async {
    await StorageService.deleteModelDocument(
      document.storagePath,
    );

    await _client
        .from('model_documents')
        .delete()
        .eq('id', document.id);
  }

  static Future<String> openDocument(
    ModelDocument document,
  ) {
    return StorageService.createModelDocumentSignedUrl(
      document.storagePath,
    );
  }
}