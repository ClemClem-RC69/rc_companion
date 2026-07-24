import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/radio.dart';
import '../../models/rc_model.dart';
import '../../services/model_photo_file_store.dart';
import '../../services/model_service.dart';
import '../../services/radio_service.dart';
import '../../services/storage_service.dart';

class ModelFormResult {
  const ModelFormResult({required this.id, required this.model});

  final String id;
  final RcModel model;
}

class ModelFormPage extends StatefulWidget {
  const ModelFormPage({super.key, this.modelId, this.existingModel});

  final String? modelId;
  final RcModel? existingModel;

  bool get isEditing => modelId != null && existingModel != null;

  @override
  State<ModelFormPage> createState() => _ModelFormPageState();
}

class _ModelFormPageState extends State<ModelFormPage> {
  final SupabaseClient supabase = Supabase.instance.client;
  final RadioService radioService = RadioService();

  late final TextEditingController nameController;
  late final TextEditingController brandController;
  late final TextEditingController weightController;
  late final TextEditingController purchaseLocationController;

  String category = 'Voiture';
  String discipline = 'Monster Truck';
  String motorization = 'Électrique';
  String scale = '1/10';
  int batteryCount = 1;
  String maxCells = '4S';
  DateTime? acquisitionDate;
  String? purchaseType;

  List<RcRadio> radios = [];
  String? selectedRadioId;
  bool isLoadingRadios = true;
  String? radiosError;

  XFile? selectedPhoto;
  Uint8List? selectedPhotoBytes;
  String? existingPhotoUrl;
  String? existingPhotoLocalPath;
  bool removeExistingPhoto = false;

  bool isPickingPhoto = false;
  bool isSaving = false;

  final categories = const ['Voiture', 'Moto', 'Bateau'];

  final carDisciplines = const [
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

  final motorcycleDisciplines = const [
    'Moto',
    'Piste',
    'Motocross',
    'Supermotard',
    'Trail',
    'Scale',
    'Basher',
    'Autre',
  ];

  final boatDisciplines = const [
    'Offshore',
    'Catamaran',
    'Monocoque',
    'Hydroplane',
    'Airboat',
    'Remorqueur',
    'Voilier',
    'Yacht',
    'Scale',
    'Autre',
  ];

  final motorisations = const ['Électrique', 'Thermique'];

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
    '1/4',
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

    nameController = TextEditingController(text: model?.name ?? '');

    brandController = TextEditingController(
      text: model?.brand == 'Marque non renseignée' ? '' : model?.brand ?? '',
    );

    purchaseLocationController = TextEditingController(
      text: model?.purchaseLocation ?? '',
    );

    weightController = TextEditingController(
      text: model?.weightKg == null
          ? ''
          : model!.weightKg!
                .toStringAsFixed(3)
                .replaceFirst(RegExp(r'0+$'), '')
                .replaceFirst(RegExp(r'\.$'), '')
                .replaceAll('.', ','),
    );

    selectedRadioId = model?.radioId;
    acquisitionDate = model?.acquisitionDate;

    if (model != null) {
      category = categories.contains(model.category)
          ? model.category
          : 'Voiture';

      final availableDisciplines = switch (category) {
        'Bateau' => boatDisciplines,
        'Moto' => motorcycleDisciplines,
        _ => carDisciplines,
      };

      discipline = availableDisciplines.contains(model.discipline)
          ? model.discipline
          : availableDisciplines.first;

      motorization = model.motorization;
      scale = model.scale;
      batteryCount = model.batteryCount == 2 ? 2 : 1;

      if (cellOptions.contains(model.maxCells)) {
        maxCells = model.maxCells;
      }

      existingPhotoUrl = model.photoUrl;
      existingPhotoLocalPath = model.photoLocalPath;
    }

    loadRadios();
  }

  @override
  void dispose() {
    nameController.dispose();
    brandController.dispose();
    weightController.dispose();
    purchaseLocationController.dispose();
    super.dispose();
  }

  Future<void> loadRadios() async {
    setState(() {
      isLoadingRadios = true;
      radiosError = null;
    });

    try {
      final result = await radioService.fetchRadios();

      if (!mounted) {
        return;
      }

      setState(() {
        radios = result;
        isLoadingRadios = false;

        if (selectedRadioId != null &&
            !radios.any((radio) => radio.id == selectedRadioId)) {
          selectedRadioId = null;
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        isLoadingRadios = false;
        radiosError = 'Impossible de charger les radios : $error';
      });
    }
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
        SnackBar(content: Text('Impossible de sélectionner la photo : $error')),
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

      if (existingPhotoUrl != null && existingPhotoUrl!.trim().isNotEmpty) {
        removeExistingPhoto = true;
      }
    });
  }

  String _formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  Future<void> selectPurchaseDate() async {
    final now = DateTime.now();
    final initialDate = acquisitionDate ?? now;

    final selectedDate = await showDatePicker(
      context: context,
      initialDate: initialDate.isAfter(now) ? now : initialDate,
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Date d’achat',
      cancelText: 'Annuler',
      confirmText: 'Valider',
    );

    if (selectedDate == null || !mounted) {
      return;
    }

    setState(() {
      acquisitionDate = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
      );
    });
  }

  void clearPurchaseDate() {
    setState(() {
      acquisitionDate = null;
    });
  }

  Future<void> save() async {
    final name = nameController.text.trim();
    final brand = brandController.text.trim();
    final weightText = weightController.text.trim();
    final purchaseLocation = purchaseLocationController.text.trim();
    final user = supabase.auth.currentUser;

    double? weightKg;

    if (weightText.isNotEmpty) {
      weightKg = double.tryParse(weightText.replaceAll(',', '.'));

      if (weightKg == null || weightKg <= 0 || weightKg > 999.999) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Indique un poids valide en kg (par exemple 8,7).'),
          ),
        );
        return;
      }
    }

    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Indique un nom de modèle')));
      return;
    }

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun utilisateur connecté')),
      );
      return;
    }

    setState(() => isSaving = true);

    final savedBrand = brand.isEmpty ? 'Marque non renseignée' : brand;
    final savedBatteryCount = motorization == 'Électrique' ? batteryCount : 0;
    final savedMaxCells = motorization == 'Électrique'
        ? int.parse(maxCells.replaceAll('S', ''))
        : 0;
    final modelId =
        widget.modelId ?? widget.existingModel?.id ?? ModelService.newModelId();

    String? finalPhotoUrl = removeExistingPhoto ? null : existingPhotoUrl;
    String? finalPhotoLocalPath = removeExistingPhoto
        ? null
        : existingPhotoLocalPath;
    var photoPendingUpload = widget.existingModel?.photoPendingUpload ?? false;
    String? previousPhotoUrl;

    try {
      if (selectedPhotoBytes != null && selectedPhoto != null) {
        finalPhotoLocalPath = await ModelPhotoFileStore.savePhoto(
          userId: user.id,
          modelId: modelId,
          bytes: selectedPhotoBytes!,
          originalFilename: selectedPhoto!.name,
        );
        if (finalPhotoLocalPath == null) {
          throw StateError('Impossible de conserver la photo localement.');
        }
        previousPhotoUrl = existingPhotoUrl;
        photoPendingUpload = true;
      } else if (removeExistingPhoto) {
        previousPhotoUrl = existingPhotoUrl;
        await ModelPhotoFileStore.deletePhoto(existingPhotoLocalPath);
        photoPendingUpload = true;
      }

      final model = RcModel(
        id: modelId,
        name: name,
        brand: savedBrand,
        category: category,
        discipline: discipline,
        motorization: motorization,
        scale: scale,
        weightKg: weightKg,
        acquisitionDate: acquisitionDate,
        purchaseType: purchaseType,
        purchaseLocation: purchaseLocation.isEmpty ? null : purchaseLocation,
        batteryCount: savedBatteryCount,
        maxCells: motorization == 'Électrique' ? '${savedMaxCells}S' : 'Aucune',
        photoUrl: finalPhotoUrl,
        photoLocalPath: finalPhotoLocalPath,
        photoPendingUpload: photoPendingUpload,
        radioId: selectedRadioId,
      );

      final savedModel = await ModelService.saveModel(
        model,
        previousPhotoUrl: previousPhotoUrl,
      );

      if (!mounted) {
        return;
      }

      Navigator.pop(
        context,
        ModelFormResult(id: savedModel.id!, model: savedModel),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() => isSaving = false);
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
        existingPhotoLocalPath != null &&
        existingPhotoLocalPath!.trim().isNotEmpty) {
      return FutureBuilder<Uint8List?>(
        future: ModelPhotoFileStore.readBytes(existingPhotoLocalPath),
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes != null && bytes.isNotEmpty) {
            return Image.memory(
              bytes,
              width: double.infinity,
              height: 220,
              fit: BoxFit.cover,
            );
          }
          return const _EmptyPhotoPreview();
        },
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
        errorBuilder: (_, __, ___) => const _EmptyPhotoPreview(),
      );
    }

    return const _EmptyPhotoPreview();
  }

  bool get hasDisplayedPhoto {
    return selectedPhotoBytes != null ||
        (!removeExistingPhoto &&
            ((existingPhotoLocalPath != null &&
                    existingPhotoLocalPath!.trim().isNotEmpty) ||
                (existingPhotoUrl != null &&
                    existingPhotoUrl!.trim().isNotEmpty)));
  }

  RcRadio? get selectedRadio {
    final id = selectedRadioId;

    if (id == null) {
      return null;
    }

    for (final radio in radios) {
      if (radio.id == id) {
        return radio;
      }
    }

    return null;
  }

  Widget buildRadioField() {
    if (isLoadingRadios) {
      return const InputDecorator(
        decoration: InputDecoration(
          labelText: 'Radio utilisée',
          border: OutlineInputBorder(),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Chargement des radios...'),
          ],
        ),
      );
    }

    if (radiosError != null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.error_outline),
          title: const Text('Impossible de charger les radios'),
          subtitle: Text(radiosError!),
          trailing: IconButton(
            tooltip: 'Réessayer',
            onPressed: loadRadios,
            icon: const Icon(Icons.refresh),
          ),
        ),
      );
    }

    return DropdownButtonFormField<String>(
      value: selectedRadioId ?? '',
      decoration: InputDecoration(
        labelText: 'Radio utilisée',
        border: const OutlineInputBorder(),
        helperText: selectedRadio == null
            ? radios.isEmpty
                  ? 'Ajoute d’abord une radio dans l’onglet Radios.'
                  : 'Aucune radio associée à ce modèle.'
            : selectedRadio!.protocols.isEmpty
            ? 'Aucun protocole renseigné'
            : 'Protocole : ${selectedRadio!.protocols.join(' • ')}',
      ),
      items: [
        const DropdownMenuItem<String>(value: '', child: Text('Aucune radio')),
        ...radios.map(
          (radio) => DropdownMenuItem<String>(
            value: radio.id,
            child: Text(radio.fullName),
          ),
        ),
      ],
      onChanged: isSaving
          ? null
          : (value) {
              setState(() {
                selectedRadioId = value == null || value.isEmpty ? null : value;
              });
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    final availableDisciplines = switch (category) {
      'Bateau' => boatDisciplines,
      'Moto' => motorcycleDisciplines,
      _ => carDisciplines,
    };
    final isElectric = motorization == 'Électrique';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Modifier le modèle' : 'Nouveau modèle'),
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
                  onPressed: isSaving || isPickingPhoto ? null : pickPhoto,
                  icon: isPickingPhoto
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
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
                .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                .toList(),
            onChanged: isSaving
                ? null
                : (value) {
                    if (value == null) {
                      return;
                    }

                    setState(() {
                      category = value;

                      final newDisciplines = switch (category) {
                        'Bateau' => boatDisciplines,
                        'Moto' => motorcycleDisciplines,
                        _ => carDisciplines,
                      };

                      if (!newDisciplines.contains(discipline)) {
                        discipline = newDisciplines.first;
                      }
                    });
                  },
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: discipline,
            decoration: const InputDecoration(
              labelText: 'Discipline',
              border: OutlineInputBorder(),
            ),
            items: availableDisciplines
                .map((item) => DropdownMenuItem(value: item, child: Text(item)))
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
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: motorization,
            decoration: const InputDecoration(
              labelText: 'Motorisation',
              border: OutlineInputBorder(),
            ),
            items: motorisations
                .map((item) => DropdownMenuItem(value: item, child: Text(item)))
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
                .map((item) => DropdownMenuItem(value: item, child: Text(item)))
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
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final acquisitionFields = <Widget>[
                SizedBox(
                  width: 230,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Date d’achat',
                      helperText: 'Facultative',
                      border: OutlineInputBorder(),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_month_outlined),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            acquisitionDate == null
                                ? 'Non renseignée'
                                : _formatDate(acquisitionDate!),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (acquisitionDate != null)
                          IconButton(
                            tooltip: 'Effacer la date',
                            onPressed: isSaving ? null : clearPurchaseDate,
                            icon: const Icon(Icons.clear),
                          ),
                        IconButton(
                          tooltip: 'Choisir une date',
                          onPressed: isSaving ? null : selectPurchaseDate,
                          icon: const Icon(Icons.edit_calendar_outlined),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<String>(
                    initialValue: purchaseType ?? '',
                    decoration: const InputDecoration(
                      labelText: 'Type d’achat',
                      helperText: 'Facultatif',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: '', child: Text('Non renseigné')),
                      DropdownMenuItem(value: 'Neuf', child: Text('Neuf')),
                      DropdownMenuItem(
                        value: 'Occasion',
                        child: Text('Occasion'),
                      ),
                    ],
                    onChanged: isSaving
                        ? null
                        : (value) {
                            setState(() {
                              purchaseType = value == null || value.isEmpty
                                  ? null
                                  : value;
                            });
                          },
                  ),
                ),
                SizedBox(
                  width: 310,
                  child: TextField(
                    controller: purchaseLocationController,
                    enabled: !isSaving,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Lieu d’achat',
                      hintText: 'Magasin, site, particulier…',
                      helperText: 'Facultatif',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ];

              if (constraints.maxWidth >= 770) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 23, child: acquisitionFields[0]),
                    const SizedBox(width: 12),
                    Expanded(flex: 19, child: acquisitionFields[1]),
                    const SizedBox(width: 12),
                    Expanded(flex: 31, child: acquisitionFields[2]),
                  ],
                );
              }

              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    acquisitionFields[0],
                    const SizedBox(width: 12),
                    acquisitionFields[1],
                    const SizedBox(width: 12),
                    acquisitionFields[2],
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 14),
          TextField(
            controller: weightController,
            enabled: !isSaving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Poids',
              hintText: 'Ex. 8,7',
              suffixText: 'kg',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          buildRadioField(),
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
                labelText: 'Configuration maximale par batterie',
                border: OutlineInputBorder(),
              ),
              items: cellOptions
                  .map(
                    (item) => DropdownMenuItem(value: item, child: Text(item)),
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
                    child: CircularProgressIndicator(strokeWidth: 2),
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
          Icon(Icons.photo_camera_back_outlined, size: 56),
          SizedBox(height: 10),
          Text('Aucune photo'),
        ],
      ),
    );
  }
}
