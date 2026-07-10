import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/rc_model.dart';
import '../../services/storage_service.dart';

class ModelFormResult {
  const ModelFormResult({
    required this.id,
    required this.model,
  });

  final String id;
  final RcModel model;
}

class ModelFormPage extends StatefulWidget {
  const ModelFormPage({
    super.key,
    this.modelId,
    this.existingModel,
  });

  final String? modelId;
  final RcModel? existingModel;

  bool get isEditing => modelId != null && existingModel != null;

  @override
  State<ModelFormPage> createState() => _ModelFormPageState();
}

class _ModelFormPageState extends State<ModelFormPage> {
  final SupabaseClient supabase = Supabase.instance.client;

  late final TextEditingController nameController;
  late final TextEditingController brandController;

  String category = 'Voiture';
  String discipline = 'Monster Truck';
  String motorization = 'Électrique';
  String scale = '1/10';
  int batteryCount = 1;
  String maxCells = '4S';

  XFile? selectedPhoto;
  Uint8List? selectedPhotoBytes;
  String? existingPhotoUrl;
  bool removeExistingPhoto = false;

  bool isPickingPhoto = false;
  bool isSaving = false;

  final categories = const [
    'Voiture',
    'Bateau',
    'Avion',
    'Hélicoptère',
    'Drone',
  ];

  final disciplines = const [
    'Monster Truck',
    'Buggy',
    'Truggy',
    'Short Course',
    'Crawler',
    'Scale / Trial',
    'Rock Racer',
    'Drift',
    'Piste',
    'Rally',
    'Basher',
    'Formule',
    'Autre',
  ];

  final motorisations = const [
    'Électrique',
    'Thermique',
  ];

  final scales = const [
    '1/24',
    '1/18',
    '1/16',
    '1/14',
    '1/12',
    '1/10',
    '1/8',
    '1/7',
    '1/6',
    '1/5',
    'Autre',
  ];

  final cellOptions = const [
    '1S',
    '2S',
    '3S',
    '4S',
    '5S',
    '6S',
    '8S',
    '10S',
    '12S',
  ];

  @override
  void initState() {
    super.initState();

    final model = widget.existingModel;

    nameController = TextEditingController(
      text: model?.name ?? '',
    );

    brandController = TextEditingController(
      text: model?.brand == 'Marque non renseignée'
          ? ''
          : model?.brand ?? '',
    );

    if (model != null) {
      category = model.category;

      discipline = model.discipline.isEmpty
          ? 'Monster Truck'
          : model.discipline;

      motorization = model.motorization;
      scale = model.scale;
      batteryCount = model.batteryCount == 2 ? 2 : 1;

      if (cellOptions.contains(model.maxCells)) {
        maxCells = model.maxCells;
      }

      existingPhotoUrl = model.photoUrl;
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    brandController.dispose();
    super.dispose();
  }

  Future<void> pickPhoto() async {
    setState(() {
      isPickingPhoto = true;
    });

    try {
      final photo = await StorageService.pickModelPhoto();

      if (photo == null) {
        return;
      }

      final bytes = await photo.readAsBytes();

      if (!mounted) {
        return;
      }

      setState(() {
        selectedPhoto = photo;
        selectedPhotoBytes = bytes;
        removeExistingPhoto = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Impossible de sélectionner la photo : $error',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isPickingPhoto = false;
        });
      }
    }
  }

  void removePhoto() {
    setState(() {
      selectedPhoto = null;
      selectedPhotoBytes = null;

      if (existingPhotoUrl != null &&
          existingPhotoUrl!.trim().isNotEmpty) {
        removeExistingPhoto = true;
      }
    });
  }

  Future<void> save() async {
    final name = nameController.text.trim();
    final brand = brandController.text.trim();
    final user = supabase.auth.currentUser;

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Indique un nom de modèle'),
        ),
      );
      return;
    }

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aucun utilisateur connecté'),
        ),
      );
      return;
    }

    setState(() {
      isSaving = true;
    });

    final savedBrand =
        brand.isEmpty ? 'Marque non renseignée' : brand;

    final savedDiscipline =
        category == 'Voiture' ? discipline : '';

    final savedBatteryCount =
        motorization == 'Électrique' ? batteryCount : 0;

    final savedMaxCells = motorization == 'Électrique'
        ? int.parse(maxCells.replaceAll('S', ''))
        : 0;

    String? modelId = widget.modelId;
    String? finalPhotoUrl = existingPhotoUrl;
    bool createdNewModel = false;

    final data = <String, dynamic>{
      'user_id': user.id,
      'name': name,
      'brand': savedBrand,
      'category': category,
      'discipline': savedDiscipline,
      'motorization': motorization,
      'scale': scale,
      'battery_count': savedBatteryCount,
      'max_cells': savedMaxCells,
    };

    try {
      if (widget.isEditing) {
        await supabase
            .from('rc_models')
            .update(data)
            .eq('id', modelId!);
      } else {
        final response = await supabase
            .from('rc_models')
            .insert(data)
            .select('id')
            .single();

        modelId = response['id'] as String;
        createdNewModel = true;
      }

      if (selectedPhoto != null) {
        final newPhotoUrl =
            await StorageService.uploadModelPhoto(
          photo: selectedPhoto!,
          modelId: modelId!,
        );

        await supabase
            .from('rc_models')
            .update({'photo_url': newPhotoUrl})
            .eq('id', modelId);

        final oldPhotoUrl = existingPhotoUrl;
        finalPhotoUrl = newPhotoUrl;

        if (oldPhotoUrl != null &&
            oldPhotoUrl.trim().isNotEmpty &&
            oldPhotoUrl != newPhotoUrl) {
          try {
            await StorageService.deleteModelPhoto(oldPhotoUrl);
          } catch (_) {
            // La nouvelle photo est bien enregistrée.
            // Une éventuelle ancienne photo non supprimée ne bloque pas.
          }
        }
      } else if (removeExistingPhoto) {
        await supabase
            .from('rc_models')
            .update({'photo_url': null})
            .eq('id', modelId!);

        final oldPhotoUrl = existingPhotoUrl;
        finalPhotoUrl = null;

        if (oldPhotoUrl != null &&
            oldPhotoUrl.trim().isNotEmpty) {
          try {
            await StorageService.deleteModelPhoto(oldPhotoUrl);
          } catch (_) {
            // La référence en base est supprimée même si le fichier
            // n’a pas pu être effacé du Storage.
          }
        }
      }

      final model = RcModel(
        name: name,
        brand: savedBrand,
        category: category,
        discipline: savedDiscipline,
        motorization: motorization,
        scale: scale,
        batteryCount: savedBatteryCount,
        maxCells: motorization == 'Électrique'
            ? '${savedMaxCells}S'
            : 'Aucune',
        photoUrl: finalPhotoUrl,
      );

      if (!mounted) {
        return;
      }

      Navigator.pop(
        context,
        ModelFormResult(
          id: modelId!,
          model: model,
        ),
      );
    } catch (error) {
      if (createdNewModel && modelId != null) {
        try {
          await supabase
              .from('rc_models')
              .delete()
              .eq('id', modelId);
        } catch (_) {
          // On conserve l’erreur principale affichée à l’utilisateur.
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isEditing
                ? 'Impossible de modifier le modèle : $error'
                : 'Impossible d’enregistrer le modèle : $error',
          ),
        ),
      );
    }
  }

  Widget buildPhotoPreview() {
    if (selectedPhotoBytes != null) {
      return Image.memory(
        selectedPhotoBytes!,
        width: double.infinity,
        height: 220,
        fit: BoxFit.cover,
      );
    }

    if (!removeExistingPhoto &&
        existingPhotoUrl != null &&
        existingPhotoUrl!.trim().isNotEmpty) {
      return Image.network(
        existingPhotoUrl!,
        width: double.infinity,
        height: 220,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          return const _EmptyPhotoPreview();
        },
      );
    }

    return const _EmptyPhotoPreview();
  }

  bool get hasDisplayedPhoto {
    return selectedPhotoBytes != null ||
        (!removeExistingPhoto &&
            existingPhotoUrl != null &&
            existingPhotoUrl!.trim().isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final isCar = category == 'Voiture';
    final isElectric = motorization == 'Électrique';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.isEditing
              ? 'Modifier le modèle'
              : 'Nouveau modèle',
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: buildPhotoPreview(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed:
                      isSaving || isPickingPhoto ? null : pickPhoto,
                  icon: isPickingPhoto
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(
                    hasDisplayedPhoto
                        ? 'Remplacer la photo'
                        : 'Ajouter une photo',
                  ),
                ),
              ),
              if (hasDisplayedPhoto) ...[
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  tooltip: 'Supprimer la photo',
                  onPressed: isSaving ? null : removePhoto,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          TextField(
            controller: nameController,
            enabled: !isSaving,
            decoration: const InputDecoration(
              labelText: 'Nom du modèle',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: brandController,
            enabled: !isSaving,
            decoration: const InputDecoration(
              labelText: 'Marque',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: category,
            decoration: const InputDecoration(
              labelText: 'Catégorie',
              border: OutlineInputBorder(),
            ),
            items: categories
                .map(
                  (item) => DropdownMenuItem(
                    value: item,
                    child: Text(item),
                  ),
                )
                .toList(),
            onChanged: isSaving
                ? null
                : (value) {
                    if (value == null) {
                      return;
                    }

                    setState(() {
                      category = value;
                    });
                  },
          ),
          if (isCar) ...[
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: discipline,
              decoration: const InputDecoration(
                labelText: 'Discipline',
                border: OutlineInputBorder(),
              ),
              items: disciplines
                  .map(
                    (item) => DropdownMenuItem(
                      value: item,
                      child: Text(item),
                    ),
                  )
                  .toList(),
              onChanged: isSaving
                  ? null
                  : (value) {
                      if (value == null) {
                        return;
                      }

                      setState(() {
                        discipline = value;
                      });
                    },
            ),
          ],
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: motorization,
            decoration: const InputDecoration(
              labelText: 'Motorisation',
              border: OutlineInputBorder(),
            ),
            items: motorisations
                .map(
                  (item) => DropdownMenuItem(
                    value: item,
                    child: Text(item),
                  ),
                )
                .toList(),
            onChanged: isSaving
                ? null
                : (value) {
                    if (value == null) {
                      return;
                    }

                    setState(() {
                      motorization = value;
                    });
                  },
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: scale,
            decoration: const InputDecoration(
              labelText: 'Échelle',
              border: OutlineInputBorder(),
            ),
            items: scales
                .map(
                  (item) => DropdownMenuItem(
                    value: item,
                    child: Text(item),
                  ),
                )
                .toList(),
            onChanged: isSaving
                ? null
                : (value) {
                    if (value == null) {
                      return;
                    }

                    setState(() {
                      scale = value;
                    });
                  },
          ),
          if (isElectric) ...[
            const SizedBox(height: 14),
            DropdownButtonFormField<int>(
              value: batteryCount,
              decoration: const InputDecoration(
                labelText: 'Nombre de batteries',
                border: OutlineInputBorder(),
              ),
              items: [1, 2]
                  .map(
                    (item) => DropdownMenuItem(
                      value: item,
                      child: Text('$item batterie(s)'),
                    ),
                  )
                  .toList(),
              onChanged: isSaving
                  ? null
                  : (value) {
                      if (value == null) {
                        return;
                      }

                      setState(() {
                        batteryCount = value;
                      });
                    },
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: maxCells,
              decoration: const InputDecoration(
                labelText:
                    'Configuration maximale par batterie',
                border: OutlineInputBorder(),
              ),
              items: cellOptions
                  .map(
                    (item) => DropdownMenuItem(
                      value: item,
                      child: Text(item),
                    ),
                  )
                  .toList(),
              onChanged: isSaving
                  ? null
                  : (value) {
                      if (value == null) {
                        return;
                      }

                      setState(() {
                        maxCells = value;
                      });
                    },
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: isSaving ? null : save,
            icon: isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.save),
            label: Text(
              isSaving
                  ? 'Enregistrement...'
                  : widget.isEditing
                      ? 'Enregistrer les modifications'
                      : 'Enregistrer',
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPhotoPreview extends StatelessWidget {
  const _EmptyPhotoPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 220,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.photo_camera_back_outlined,
            size: 56,
          ),
          SizedBox(height: 10),
          Text('Aucune photo'),
        ],
      ),
    );
  }
}