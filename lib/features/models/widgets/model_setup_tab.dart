import 'dart:async';
import 'package:flutter/material.dart';

import '../../../models/model_setup.dart';
import '../../../services/model_setup_service.dart';

class ModelSetupTab extends StatefulWidget {
  const ModelSetupTab({
    super.key,
    required this.modelId,
    required this.category,
  });

  final String modelId;
  final String category;

  @override
  State<ModelSetupTab> createState() => _ModelSetupTabState();
}

class _ModelSetupTabState extends State<ModelSetupTab> {
  ModelSetup? setup;
  StreamSubscription<ModelSetup?>? _setupSubscription;

  bool isLoading = true;
  bool isSaving = false;
  bool isEditingOriginal = false;
  bool isCreatingInitialSetup = false;

  String? errorMessage;

  final Map<String, TextEditingController> originalControllers = {};
  final Map<String, TextEditingController> currentControllers = {};

  // ---------------------------------------------------------------------------
  // BIBLIOTHÈQUE DES CHAMPS DE SETUP PAR CATÉGORIE
  // ---------------------------------------------------------------------------
  //
  // La voiture conserve STRICTEMENT les champs historiques de RC Companion.
  // Bateau et Moto utilisent des champs adaptés aux réglages réellement utiles
  // en RC. Le stockage reste générique (enabledFields/original/current), donc
  // aucune migration de base n'est nécessaire.
  // ---------------------------------------------------------------------------

  static const List<_SetupSection> carSections = [
    _SetupSection(
      title: 'Transmission',
      icon: Icons.settings,
      fields: [
        _SetupField(
          keyName: 'pinion',
          label: 'Pignon moteur',
          hint: 'Ex. 18 dents',
        ),
        _SetupField(keyName: 'spur', label: 'Couronne', hint: 'Ex. 54 dents'),
      ],
    ),
    _SetupSection(
      title: 'Différentiels',
      icon: Icons.oil_barrel_outlined,
      fields: [
        _SetupField(
          keyName: 'front_diff_oil',
          label: 'Huile diff avant',
          hint: 'Ex. 50K',
        ),
        _SetupField(
          keyName: 'center_diff_oil',
          label: 'Huile diff central',
          hint: 'Ex. 500K',
        ),
        _SetupField(
          keyName: 'rear_diff_oil',
          label: 'Huile diff arrière',
          hint: 'Ex. 30K',
        ),
      ],
    ),
    _SetupSection(
      title: 'Amortisseurs',
      icon: Icons.compress,
      fields: [
        _SetupField(
          keyName: 'front_shock_oil',
          label: 'Huile amortisseurs avant',
          hint: 'Ex. 600 cSt',
        ),
        _SetupField(
          keyName: 'rear_shock_oil',
          label: 'Huile amortisseurs arrière',
          hint: 'Ex. 550 cSt',
        ),
      ],
    ),
    _SetupSection(
      title: 'Géométrie',
      icon: Icons.straighten,
      fields: [
        _SetupField(
          keyName: 'front_camber',
          label: 'Carrossage avant',
          hint: 'Ex. -2°',
        ),
        _SetupField(
          keyName: 'rear_camber',
          label: 'Carrossage arrière',
          hint: 'Ex. -2°',
        ),
        _SetupField(
          keyName: 'front_toe',
          label: 'Pincement avant',
          hint: 'Ex. 1° ouvert',
        ),
        _SetupField(
          keyName: 'rear_toe',
          label: 'Pincement arrière',
          hint: 'Ex. 2° fermé',
        ),
        _SetupField(
          keyName: 'front_ride_height',
          label: 'Garde au sol avant',
          hint: 'Ex. 28 mm',
        ),
        _SetupField(
          keyName: 'rear_ride_height',
          label: 'Garde au sol arrière',
          hint: 'Ex. 30 mm',
        ),
      ],
    ),
    _SetupSection(
      title: 'Électronique',
      icon: Icons.electric_bolt_outlined,
      fields: [
        _SetupField(keyName: 'esc', label: 'ESC', hint: 'Ex. Hobbywing MAX6'),
        _SetupField(keyName: 'motor', label: 'Moteur', hint: 'Ex. 4985 1650KV'),
        _SetupField(keyName: 'servo', label: 'Servo', hint: 'Ex. 35 kg'),
      ],
    ),
    _SetupSection(
      title: 'Roues',
      icon: Icons.tire_repair,
      fields: [
        _SetupField(
          keyName: 'tires',
          label: 'Pneus',
          hint: 'Ex. Louise Cyclone',
        ),
      ],
    ),
    _SetupSection(
      title: 'Autres',
      icon: Icons.notes,
      fields: [
        _SetupField(
          keyName: 'notes',
          label: 'Notes',
          hint: 'Informations complémentaires',
          multiline: true,
        ),
      ],
    ),
  ];

  static const List<_SetupSection> boatSections = [
    _SetupSection(
      title: 'Propulsion',
      icon: Icons.settings,
      fields: [
        _SetupField(
          keyName: 'boat_propeller',
          label: 'Hélice',
          hint: 'Ex. 42 x 1,6 / 2 pales',
        ),
        _SetupField(
          keyName: 'boat_strut_height',
          label: 'Strut — hauteur',
          hint: 'Ex. +2 mm',
        ),
        _SetupField(
          keyName: 'boat_strut_angle',
          label: 'Strut — angle',
          hint: 'Ex. 0° / -1°',
        ),
        _SetupField(
          keyName: 'boat_jet_impeller',
          label: 'Turbine / Impeller',
          hint: 'Référence ou configuration',
        ),
        _SetupField(
          keyName: 'boat_jet_nozzle_trim',
          label: 'Buse jet — trim',
          hint: 'Ex. neutre / +1 cran',
        ),
        _SetupField(
          keyName: 'boat_jet_nozzle_travel',
          label: 'Débattement de buse',
          hint: 'Ex. 25° gauche / droite',
        ),
      ],
    ),
    _SetupSection(
      title: 'Comportement coque',
      icon: Icons.directions_boat_outlined,
      fields: [
        _SetupField(
          keyName: 'boat_trim_tab_left',
          label: 'Trim tab gauche',
          hint: 'Ex. neutre / -1 mm',
        ),
        _SetupField(
          keyName: 'boat_trim_tab_right',
          label: 'Trim tab droit',
          hint: 'Ex. neutre / -1 mm',
        ),
        _SetupField(
          keyName: 'boat_turn_fin_left',
          label: 'Turn fin gauche',
          hint: 'Position / réglage',
        ),
        _SetupField(
          keyName: 'boat_turn_fin_right',
          label: 'Turn fin droit',
          hint: 'Position / réglage',
        ),
        _SetupField(
          keyName: 'boat_battery_position',
          label: 'Position batterie',
          hint: 'Ex. 20 mm vers l’avant',
        ),
        _SetupField(
          keyName: 'boat_steering_trim',
          label: 'Trim de direction',
          hint: 'Ex. neutre / +2',
        ),
      ],
    ),
    _SetupSection(
      title: 'Électronique',
      icon: Icons.electric_bolt_outlined,
      fields: [
        _SetupField(keyName: 'motor', label: 'Moteur', hint: 'Ex. 3660 2300KV'),
        _SetupField(
          keyName: 'esc',
          label: 'ESC',
          hint: 'Ex. Spektrum Firma 100A',
        ),
        _SetupField(
          keyName: 'boat_steering_servo',
          label: 'Servo de direction',
          hint: 'Référence / couple',
        ),
      ],
    ),
    _SetupSection(
      title: 'Autres',
      icon: Icons.notes,
      fields: [
        _SetupField(
          keyName: 'notes',
          label: 'Notes',
          hint: 'Informations complémentaires',
          multiline: true,
        ),
      ],
    ),
  ];

  static const List<_SetupSection> motorcycleSections = [
    _SetupSection(
      title: 'Fourche avant',
      icon: Icons.compress,
      fields: [
        _SetupField(
          keyName: 'moto_fork_spring',
          label: 'Ressort de fourche',
          hint: 'Ex. Soft / Medium / Hard',
        ),
        _SetupField(
          keyName: 'moto_fork_oil',
          label: 'Huile de fourche',
          hint: 'Ex. 500 cSt',
        ),
        _SetupField(
          keyName: 'moto_fork_spacers',
          label: 'Entretoises / hauteur',
          hint: 'Ex. 2 mm',
        ),
      ],
    ),
    _SetupSection(
      title: 'Suspension arrière',
      icon: Icons.compress,
      fields: [
        _SetupField(
          keyName: 'moto_rear_shock_spring',
          label: 'Ressort arrière',
          hint: 'Ex. Medium',
        ),
        _SetupField(
          keyName: 'moto_rear_shock_oil',
          label: 'Huile amortisseur arrière',
          hint: 'Ex. 450 cSt',
        ),
        _SetupField(
          keyName: 'moto_rear_preload',
          label: 'Précharge arrière',
          hint: 'Ex. 3 mm',
        ),
      ],
    ),
    _SetupSection(
      title: 'Transmission',
      icon: Icons.settings,
      fields: [
        _SetupField(
          keyName: 'pinion',
          label: 'Pignon moteur',
          hint: 'Ex. 12 dents',
        ),
        _SetupField(keyName: 'spur', label: 'Couronne', hint: 'Ex. 60 dents'),
        _SetupField(
          keyName: 'moto_gear_ratio',
          label: 'Rapport',
          hint: 'Ex. 15,5:1',
        ),
        _SetupField(
          keyName: 'moto_clutch_drive',
          label: 'Clutch drive',
          hint: 'Référence / configuration',
        ),
        _SetupField(
          keyName: 'moto_flywheel',
          label: 'Flywheel',
          hint: 'Référence / configuration',
        ),
        _SetupField(
          keyName: 'moto_chain',
          label: 'Chaîne',
          hint: 'Référence / type',
        ),
        _SetupField(
          keyName: 'moto_chain_tension',
          label: 'Tension chaîne',
          hint: 'Ex. position 2 / jeu 3 mm',
        ),
        _SetupField(
          keyName: 'moto_diff_oil',
          label: 'Huile de diff',
          hint: 'Ex. 50K / 100K',
        ),
      ],
    ),
    _SetupSection(
      title: 'Roues',
      icon: Icons.tire_repair,
      fields: [
        _SetupField(
          keyName: 'moto_front_tire',
          label: 'Pneu avant',
          hint: 'Référence / gomme',
        ),
        _SetupField(
          keyName: 'moto_rear_tire',
          label: 'Pneu arrière',
          hint: 'Référence / gomme',
        ),
      ],
    ),
    _SetupSection(
      title: 'Électronique',
      icon: Icons.electric_bolt_outlined,
      fields: [
        _SetupField(keyName: 'motor', label: 'Moteur', hint: 'Ex. 3800KV'),
        _SetupField(keyName: 'esc', label: 'ESC', hint: 'Référence / réglage'),
        _SetupField(
          keyName: 'moto_steering_servo',
          label: 'Servo de direction',
          hint: 'Référence / couple',
        ),
        _SetupField(
          keyName: 'moto_brake_servo',
          label: 'Servo de frein',
          hint: 'Référence / couple',
        ),
      ],
    ),
    _SetupSection(
      title: 'Autres',
      icon: Icons.notes,
      fields: [
        _SetupField(
          keyName: 'notes',
          label: 'Notes',
          hint: 'Informations complémentaires',
          multiline: true,
        ),
      ],
    ),
  ];

  List<_SetupSection> get sections {
    final category = widget.category.trim().toLowerCase();

    if (category.contains('bateau')) {
      return boatSections;
    }

    if (category.contains('moto')) {
      return motorcycleSections;
    }

    // Voiture + sécurité pour les anciennes catégories inconnues :
    // comportement historique inchangé.
    return carSections;
  }

  List<_SetupField> get allFields {
    return sections.expand((section) => section.fields).toList();
  }

  bool get hasSetup {
    final currentSetup = setup;

    if (currentSetup == null) {
      return false;
    }

    return currentSetup.enabledFields.isNotEmpty ||
        currentSetup.originalValues.isNotEmpty ||
        currentSetup.currentValues.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();

    _setupSubscription = ModelSetupService.watchSetup(widget.modelId).listen((
      updatedSetup,
    ) {
      if (!mounted || isSaving || isEditingOriginal || isCreatingInitialSetup) {
        return;
      }

      final value = updatedSetup ?? ModelSetup.empty(widget.modelId);
      _prepareControllers(value);

      setState(() {
        setup = value;
        isLoading = false;
        errorMessage = null;
      });
    });

    loadSetup();
  }

  @override
  void dispose() {
    _setupSubscription?.cancel();

    for (final controller in originalControllers.values) {
      controller.dispose();
    }

    for (final controller in currentControllers.values) {
      controller.dispose();
    }

    super.dispose();
  }

  Future<void> loadSetup() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final loadedSetup = await ModelSetupService.getSetup(widget.modelId);

      _prepareControllers(loadedSetup);

      if (!mounted) {
        return;
      }

      setState(() {
        setup = loadedSetup;
        isLoading = false;
        isEditingOriginal = false;
        isCreatingInitialSetup = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        isLoading = false;
        errorMessage = 'Impossible de charger le setup.\n$error';
      });
    }
  }

  void _prepareControllers(ModelSetup loadedSetup) {
    for (final field in allFields) {
      originalControllers.putIfAbsent(field.keyName, TextEditingController.new);

      currentControllers.putIfAbsent(field.keyName, TextEditingController.new);

      originalControllers[field.keyName]!.text = loadedSetup.originalValue(
        field.keyName,
      );

      currentControllers[field.keyName]!.text = loadedSetup.currentValue(
        field.keyName,
      );
    }
  }

  Future<List<String>?> _chooseSetupFields({
    required List<String> initialSelection,
  }) async {
    final selectedFields = Set<String>.from(initialSelection);

    return showDialog<List<String>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Choisir les éléments du setup'),
              content: SizedBox(
                width: 520,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final section in sections) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 12, bottom: 4),
                        child: Row(
                          children: [
                            Icon(section.icon, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              section.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      for (final field in section.fields)
                        CheckboxListTile(
                          value: selectedFields.contains(field.keyName),
                          title: Text(field.label),
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (value) {
                            setDialogState(() {
                              if (value == true) {
                                selectedFields.add(field.keyName);
                              } else {
                                selectedFields.remove(field.keyName);
                              }
                            });
                          },
                        ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: selectedFields.isEmpty
                      ? null
                      : () {
                          Navigator.pop(dialogContext, selectedFields.toList());
                        },
                  child: const Text('Continuer'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> createOriginalSetup() async {
    final selectedFields = await _chooseSetupFields(initialSelection: const []);

    if (selectedFields == null || selectedFields.isEmpty) {
      return;
    }

    final newSetup = ModelSetup.empty(
      widget.modelId,
    ).copyWith(enabledFields: selectedFields);

    _prepareControllers(newSetup);

    setState(() {
      setup = newSetup;
      isCreatingInitialSetup = true;
      isEditingOriginal = true;
    });
  }

  Future<void> configureFields() async {
    final currentSetup = setup;

    if (currentSetup == null) {
      return;
    }

    final shouldContinue = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Modifier les éléments du setup'),
          content: const Text(
            'Tu peux ajouter ou retirer des éléments. '
            'Les valeurs des éléments retirés ne seront plus affichées.',
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
              child: const Text('Continuer'),
            ),
          ],
        );
      },
    );

    if (shouldContinue != true) {
      return;
    }

    final selectedFields = await _chooseSetupFields(
      initialSelection: currentSetup.enabledFields,
    );

    if (selectedFields == null || selectedFields.isEmpty) {
      return;
    }

    final updatedSetup = currentSetup.copyWith(enabledFields: selectedFields);

    setState(() {
      setup = updatedSetup;
    });

    await saveSetup();
  }

  Future<void> enableOriginalEditing() async {
    final shouldEdit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Modifier le setup d’origine'),
          content: const Text(
            'Cette fonction sert à corriger une erreur de saisie '
            'ou une valeur constructeur incorrecte. '
            'Le setup actuel ne sera pas modifié automatiquement.',
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
              child: const Text('Modifier'),
            ),
          ],
        );
      },
    );

    if (shouldEdit != true) {
      return;
    }

    setState(() {
      isEditingOriginal = true;
    });
  }

  Future<void> saveSetup() async {
    final currentSetup = setup;

    if (currentSetup == null || currentSetup.enabledFields.isEmpty) {
      return;
    }

    setState(() {
      isSaving = true;
    });

    final originalValues = <String, String>{};
    final currentValues = <String, String>{};

    for (final fieldKey in currentSetup.enabledFields) {
      final originalValue = originalControllers[fieldKey]?.text.trim() ?? '';

      var currentValue = currentControllers[fieldKey]?.text.trim() ?? '';

      originalValues[fieldKey] = originalValue;

      // Lors de la création initiale, ou lorsqu'une valeur actuelle est vide,
      // on initialise automatiquement la colonne Actuel avec la valeur Origine.
      if (isCreatingInitialSetup ||
          (currentValue.isEmpty && originalValue.isNotEmpty)) {
        currentValue = originalValue;
        currentControllers[fieldKey]?.value = TextEditingValue(
          text: originalValue,
          selection: TextSelection.collapsed(offset: originalValue.length),
        );
      }

      currentValues[fieldKey] = currentValue;
    }

    final setupToSave = currentSetup.copyWith(
      originalValues: originalValues,
      currentValues: currentValues,
    );

    try {
      final savedSetup = await ModelSetupService.saveSetup(setupToSave);

      if (!mounted) {
        return;
      }

      _prepareControllers(savedSetup);

      setState(() {
        setup = savedSetup;
        isSaving = false;
        isEditingOriginal = false;
        isCreatingInitialSetup = false;
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Setup enregistré')));
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible d’enregistrer le setup : $error')),
      );
    }
  }

  Future<void> restoreOriginalSetup() async {
    final currentSetup = setup;

    if (currentSetup == null || currentSetup.enabledFields.isEmpty) {
      return;
    }

    final shouldRestore = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Revenir au setup d’origine'),
          content: const Text(
            'Toutes les valeurs actuelles seront remplacées '
            'par les valeurs du setup d’origine.',
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
              child: const Text('Confirmer'),
            ),
          ],
        );
      },
    );

    if (shouldRestore != true) {
      return;
    }

    final originalValues = <String, String>{};
    final currentValues = <String, String>{};

    for (final fieldKey in currentSetup.enabledFields) {
      final originalValue = originalControllers[fieldKey]?.text.trim() ?? '';

      originalValues[fieldKey] = originalValue;
      currentValues[fieldKey] = originalValue;
      currentControllers[fieldKey]?.text = originalValue;
    }

    final restoredSetup = currentSetup.copyWith(
      originalValues: originalValues,
      currentValues: currentValues,
    );

    setState(() {
      isSaving = true;
    });

    try {
      final savedSetup = await ModelSetupService.saveSetup(restoredSetup);

      if (!mounted) {
        return;
      }

      _prepareControllers(savedSetup);

      setState(() {
        setup = savedSetup;
        isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Le setup actuel correspond maintenant au setup d’origine',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible de restaurer le setup : $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: loadSetup,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    if (!hasSetup) {
      return _buildEmptySetup();
    }

    final currentSetup = setup!;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
      children: [
        _buildActionCard(),
        const SizedBox(height: 16),
        if (isCreatingInitialSetup)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Renseigne les valeurs d’origine. '
                      'Lors du premier enregistrement, elles seront '
                      'automatiquement copiées dans la colonne Actuel.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (isCreatingInitialSetup) const SizedBox(height: 16),
        _buildColumnHeader(),
        const SizedBox(height: 10),
        for (final section in sections) _buildSection(section, currentSetup),
        if (isCreatingInitialSetup || isEditingOriginal) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: isSaving ? null : saveSetup,
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
                  : isCreatingInitialSetup
                  ? 'Créer le setup'
                  : 'Enregistrer les modifications',
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildEmptySetup() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 90),
        const Icon(Icons.tune, size: 72),
        const SizedBox(height: 18),
        const Text(
          'Aucun setup enregistré',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        const Text(
          'Choisis les éléments utiles à ce modèle, '
          'puis renseigne son setup d’origine.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Center(
          child: FilledButton.icon(
            onPressed: createOriginalSetup,
            icon: const Icon(Icons.add),
            label: const Text('Créer le setup d’origine'),
          ),
        ),
      ],
    );
  }

  Widget _buildActionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.tonalIcon(
              onPressed: isSaving ? null : configureFields,
              icon: const Icon(Icons.tune),
              label: const Text('Configurer les éléments'),
            ),
            OutlinedButton.icon(
              onPressed: isSaving || isEditingOriginal
                  ? null
                  : enableOriginalEditing,
              icon: const Icon(Icons.edit_outlined),
              label: Text(
                isEditingOriginal
                    ? 'Origine modifiable'
                    : 'Modifier le setup d’origine',
              ),
            ),
            OutlinedButton.icon(
              onPressed: isSaving ? null : restoreOriginalSetup,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Revenir au setup d’origine'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColumnHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return const SizedBox.shrink();
        }

        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  'Réglage',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                flex: 4,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline, size: 16),
                    SizedBox(width: 4),
                    Text(
                      'Origine',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 10),
              Expanded(
                flex: 4,
                child: Text(
                  'Actuel',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSection(_SetupSection section, ModelSetup currentSetup) {
    final visibleFields = section.fields.where((field) {
      return currentSetup.isFieldEnabled(field.keyName);
    }).toList();

    if (visibleFields.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(section.icon, size: 22),
                const SizedBox(width: 8),
                Text(
                  section.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const Divider(height: 18),
            for (final field in visibleFields) _buildSetupRow(field),
          ],
        ),
      ),
    );
  }

  Widget _buildSetupRow(_SetupField field) {
    final canEditOriginal = isCreatingInitialSetup || isEditingOriginal;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 600;

          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  field.label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: canEditOriginal
                          ? _buildValueField(
                              controller: originalControllers[field.keyName]!,
                              label: 'Origine',
                              hint: field.hint,
                              multiline: field.multiline,
                              enabled: true,
                            )
                          : _buildOriginalDisplay(
                              value: originalControllers[field.keyName]?.text,
                              label: 'Origine',
                              multiline: field.multiline,
                            ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildValueField(
                        controller: currentControllers[field.keyName]!,
                        label: 'Actuel',
                        hint: isCreatingInitialSetup
                            ? 'Copié à l’enregistrement'
                            : field.hint,
                        multiline: field.multiline,
                        enabled: !isCreatingInitialSetup,
                      ),
                    ),
                  ],
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  field.label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Expanded(
                flex: 4,
                child: canEditOriginal
                    ? _buildValueField(
                        controller: originalControllers[field.keyName]!,
                        label: null,
                        hint: field.hint,
                        multiline: field.multiline,
                        enabled: true,
                      )
                    : _buildOriginalDisplay(
                        value: originalControllers[field.keyName]?.text,
                        multiline: field.multiline,
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 4,
                child: _buildValueField(
                  controller: currentControllers[field.keyName]!,
                  label: null,
                  hint: isCreatingInitialSetup
                      ? 'Copié à l’enregistrement'
                      : field.hint,
                  multiline: field.multiline,
                  enabled: !isCreatingInitialSetup,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOriginalDisplay({
    required String? value,
    required bool multiline,
    String? label,
  }) {
    final cleanValue = value?.trim() ?? '';
    final displayedValue = cleanValue.isEmpty ? 'Non renseigné' : cleanValue;

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: multiline ? 72 : 42),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (label != null) ...[
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 2),
          ],
          Text(
            displayedValue,
            maxLines: multiline ? 4 : 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              color: cleanValue.isEmpty
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValueField({
    required TextEditingController controller,
    required String? label,
    required String hint,
    required bool multiline,
    required bool enabled,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled && !isSaving,
      minLines: multiline ? 2 : 1,
      maxLines: multiline ? 4 : 1,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
        filled: !enabled,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
    );
  }
}

class _SetupSection {
  const _SetupSection({
    required this.title,
    required this.icon,
    required this.fields,
  });

  final String title;
  final IconData icon;
  final List<_SetupField> fields;
}

class _SetupField {
  const _SetupField({
    required this.keyName,
    required this.label,
    required this.hint,
    this.multiline = false,
  });

  final String keyName;
  final String label;
  final String hint;
  final bool multiline;
}
