import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/rc_model.dart';
import '../../services/model_local_store.dart';
import '../../services/model_service.dart';
import 'model_detail_page.dart';
import 'model_form_page.dart';

class ModelsPage extends StatefulWidget {
  const ModelsPage({super.key});

  @override
  State<ModelsPage> createState() => _ModelsPageState();
}

class _ModelsPageState extends State<ModelsPage> {
  final SupabaseClient supabase = Supabase.instance.client;

  List<_StoredModel> models = [];

  StreamSubscription<List<RcModel>>? _modelsSubscription;

  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _startModelLiveUpdates();
    loadModels();
  }

  void _startModelLiveUpdates() {
    final user = supabase.auth.currentUser;
    if (user == null) {
      return;
    }

    _modelsSubscription = ModelLocalStore.watchModels(
      userId: user.id,
    ).listen(_applyCachedModels);
  }

  @override
  void dispose() {
    _modelsSubscription?.cancel();
    super.dispose();
  }

  Future<void> loadModels() async {
    final user = supabase.auth.currentUser;

    if (user == null) {
      if (!mounted) {
        return;
      }

      setState(() {
        isLoading = false;
        errorMessage = 'Aucun utilisateur connecté.';
      });
      return;
    }

    if (mounted) {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });
    }

    try {
      final hasCache = await ModelLocalStore.hasModelCache(userId: user.id);
      final cachedModels = await ModelLocalStore.getModels(userId: user.id);

      if (hasCache) {
        _applyCachedModels(cachedModels);
        unawaited(_refreshModelsFromCloud(user.id));
        return;
      }

      await _refreshModelsFromCloud(user.id, showError: true);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        isLoading = false;
        errorMessage = 'Impossible de charger les modèles.\n$error';
      });
    }
  }

  void _applyCachedModels(List<RcModel> cachedModels) {
    if (!mounted) {
      return;
    }

    final loadedModels = cachedModels
        .where((model) => model.id != null && model.id!.trim().isNotEmpty)
        .map((model) => _StoredModel(id: model.id!, model: model))
        .toList(growable: false)
        .reversed
        .toList(growable: false);

    setState(() {
      models = loadedModels;
      isLoading = false;
      errorMessage = null;
    });
  }

  Future<void> _refreshModelsFromCloud(
    String userId, {
    bool showError = false,
  }) async {
    try {
      await ModelService.refreshModels();

      if (mounted) {
        setState(() {
          isLoading = false;
          errorMessage = null;
        });
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      if (showError && models.isEmpty) {
        setState(() {
          isLoading = false;
          errorMessage = 'Impossible de charger les modèles.\n$error';
        });
        return;
      }

      if (showError) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Actualisation impossible. Les modèles locaux restent disponibles.',
            ),
          ),
        );
      }

      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _refreshModelsManually() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      return;
    }

    await _refreshModelsFromCloud(user.id, showError: true);
  }

  Future<void> addModel() async {
    final result = await Navigator.push<ModelFormResult>(
      context,
      MaterialPageRoute(builder: (_) => const ModelFormPage()),
    );

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      models.insert(0, _StoredModel(id: result.id, model: result.model));
    });

    final user = supabase.auth.currentUser;
    if (user != null) {
      unawaited(_refreshModelsFromCloud(user.id));
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Modèle enregistré')));
  }

  Future<void> editModel(_StoredModel storedModel) async {
    final result = await Navigator.push<ModelFormResult>(
      context,
      MaterialPageRoute(
        builder: (_) => ModelFormPage(
          modelId: storedModel.id,
          existingModel: storedModel.model,
        ),
      ),
    );

    if (result == null || !mounted) {
      return;
    }

    final index = models.indexWhere((item) => item.id == result.id);

    if (index == -1) {
      await loadModels();
      return;
    }

    setState(() {
      models[index] = _StoredModel(id: result.id, model: result.model);
    });

    final user = supabase.auth.currentUser;
    if (user != null) {
      unawaited(_refreshModelsFromCloud(user.id));
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Modèle modifié')));
  }

  Future<void> confirmDelete(_StoredModel storedModel) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Supprimer le modèle'),
          content: Text(
            'Veux-tu vraiment supprimer '
            '"${storedModel.model.name}" ?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) {
      return;
    }

    await deleteModel(storedModel);
  }

  Future<void> deleteModel(_StoredModel storedModel) async {
    try {
      await ModelService.deleteModel(
        storedModel.model.copyWith(id: storedModel.id),
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Modèle supprimé')));
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur pendant la suppression : $error')),
      );
    }
  }

  Future<void> openModelDetail(_StoredModel storedModel) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ModelDetailPage(modelId: storedModel.id, model: storedModel.model),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes modèles'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: isLoading ? null : _refreshModelsManually,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: isLoading ? null : addModel,
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
      ),
    );
  }

  Widget buildBody() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 54),
              const SizedBox(height: 16),
              Text(errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: loadModels,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    if (models.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refreshModelsManually,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: const [
            SizedBox(height: 150),
            Icon(Icons.directions_car_outlined, size: 72),
            SizedBox(height: 18),
            Center(
              child: Text(
                'Aucun modèle pour le moment',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(height: 8),
            Center(
              child: Text(
                'Appuie sur Ajouter pour créer ton '
                'premier modèle.',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshModelsManually,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: models.length,
        itemBuilder: (context, index) {
          final storedModel = models[index];

          return _ModelCard(
            storedModel: storedModel,
            onTap: () => openModelDetail(storedModel),
            onEdit: () => editModel(storedModel),
            onDelete: () => confirmDelete(storedModel),
          );
        },
      ),
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({
    required this.storedModel,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final _StoredModel storedModel;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final model = storedModel.model;

    final disciplineText = model.discipline.isEmpty
        ? model.category
        : model.discipline;

    final batteryText = model.motorization == 'Électrique'
        ? '${model.batteryCount} × ${model.maxCells}'
        : 'Aucune batterie';

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _ModelThumbnail(model: model),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${model.brand} • $disciplineText',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Icon(
                          model.motorization == 'Électrique'
                              ? Icons.bolt
                              : Icons.local_gas_station_outlined,
                          size: 18,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            '${model.motorization} • '
                            '${model.scale} • $batteryText',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Options',
                onSelected: (value) {
                  if (value == 'edit') {
                    onEdit();
                  } else if (value == 'delete') {
                    onDelete();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined),
                        SizedBox(width: 10),
                        Text('Modifier'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline),
                        SizedBox(width: 10),
                        Text('Supprimer'),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModelThumbnail extends StatelessWidget {
  const _ModelThumbnail({required this.model});

  final RcModel model;

  @override
  Widget build(BuildContext context) {
    final photoUrl = model.photoUrl;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 84,
        height: 84,
        child: photoUrl != null && photoUrl.trim().isNotEmpty
            ? Image.network(
                photoUrl,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) {
                    return child;
                  }

                  return Container(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                },
                errorBuilder: (_, __, ___) {
                  return _CategoryIcon(category: model.category);
                },
              )
            : _CategoryIcon(category: model.category),
      ),
    );
  }
}

class _CategoryIcon extends StatelessWidget {
  const _CategoryIcon({required this.category});

  final String category;

  IconData get icon {
    switch (category) {
      case 'Bateau':
        return Icons.sailing;
      case 'Moto':
        return Icons.two_wheeler;
      case 'Voiture':
      default:
        return Icons.directions_car;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(icon, size: 42),
    );
  }
}

class _StoredModel {
  const _StoredModel({required this.id, required this.model});

  final String id;
  final RcModel model;
}
