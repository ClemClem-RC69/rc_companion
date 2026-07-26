import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/radio_control_catalog.dart';
import '../../../models/model_radio_setup.dart';
import '../../../models/radio.dart';
import '../../../models/rc_model.dart';
import '../../../services/model_radio_setup_service.dart';
import '../../../services/radio_service.dart';

class ModelRadioControlsTab extends StatefulWidget {
  const ModelRadioControlsTab({
    super.key,
    required this.modelId,
    required this.model,
  });

  final String modelId;
  final RcModel model;

  @override
  State<ModelRadioControlsTab> createState() => _ModelRadioControlsTabState();
}

class _ModelRadioControlsTabState extends State<ModelRadioControlsTab> {
  final ModelRadioSetupService _setupService = ModelRadioSetupService();
  final RadioService _radioService = RadioService();

  final Map<String, TextEditingController> _controllers = {};

  RcRadio? _selectedRadio;
  RadioControlLayout? _layout;
  ModelRadioSetup? _loadedSetup;
  Set<String> _enabledFields = {};

  StreamSubscription<ModelRadioSetup?>? _setupSubscription;
  StreamSubscription<List<RcRadio>>? _radioSubscription;

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  List<RadioControlDefinition> get _controls {
    return _layout?.controls ?? const [];
  }

  Set<String> get _controlKeys {
    return _controls.map(_fieldKey).toSet();
  }

  @override
  void initState() {
    super.initState();

    _setupSubscription = _setupService
        .watchSetup(modelId: widget.modelId)
        .listen((setup) {
          if (!mounted || _isSaving) {
            return;
          }

          _applyLiveSetup(setup);
        });

    _radioSubscription = _radioService.watchRadios().listen((radios) {
      if (!mounted) {
        return;
      }

      _applyLiveRadios(radios);
    });

    _loadData();
  }

  @override
  void dispose() {
    _setupSubscription?.cancel();
    _radioSubscription?.cancel();

    for (final controller in _controllers.values) {
      controller.dispose();
    }

    super.dispose();
  }

  String _fieldKey(RadioControlDefinition control) {
    return 'control_assignment_${control.key}';
  }

  void _applyLiveRadios(List<RcRadio> radios) {
    final radioId = widget.model.radioId?.trim();

    RcRadio? radio;
    if (radioId != null && radioId.isNotEmpty) {
      for (final item in radios) {
        if (item.id == radioId) {
          radio = item;
          break;
        }
      }
    }

    final layout = radio == null
        ? null
        : radioControlLayoutFor(brand: radio.brand, model: radio.model);

    final previousValues = <String, String>{
      for (final entry in _controllers.entries) entry.key: entry.value.text,
    };

    final currentKeys = <String>{};
    for (final control in layout?.controls ?? const []) {
      final key = _fieldKey(control);
      currentKeys.add(key);

      final controller = _controllers.putIfAbsent(
        key,
        TextEditingController.new,
      );

      if (!_isSaving && previousValues.containsKey(key)) {
        controller.text = previousValues[key] ?? '';
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _selectedRadio = radio;
      _layout = layout;
      _enabledFields = _enabledFields.where(currentKeys.contains).toSet();
      _isLoading = false;
      _errorMessage = null;
    });

    _applyLiveSetup(_loadedSetup);
  }

  void _applyLiveSetup(ModelRadioSetup? setup) {
    final controlKeys = _controlKeys;

    for (final control in _controls) {
      final key = _fieldKey(control);
      final controller = _controllers.putIfAbsent(
        key,
        TextEditingController.new,
      );

      final remoteValue = setup?.value(key) ?? '';
      if (controller.text != remoteValue) {
        controller.value = TextEditingValue(
          text: remoteValue,
          selection: TextSelection.collapsed(offset: remoteValue.length),
        );
      }
    }

    final enabled = {
      ...?setup?.enabledFields,
    }.where(controlKeys.contains).toSet();

    if (!mounted) {
      return;
    }

    setState(() {
      _loadedSetup = setup;
      _enabledFields = enabled;
      _isLoading = false;
      _errorMessage = null;
    });
  }

  Future<void> _loadData() async {
    final radioId = widget.model.radioId;

    if (radioId == null || radioId.trim().isEmpty) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await Future.wait([
        _radioService.fetchRadios(),
        _setupService.getSetup(modelId: widget.modelId),
      ]);

      final radios = results[0] as List<RcRadio>;
      final setup = results[1] as ModelRadioSetup?;

      RcRadio? radio;
      for (final item in radios) {
        if (item.id == radioId) {
          radio = item;
          break;
        }
      }

      final layout = radio == null
          ? null
          : radioControlLayoutFor(brand: radio.brand, model: radio.model);

      for (final control in layout?.controls ?? const []) {
        final key = _fieldKey(control);
        final value = setup?.value(key) ?? '';
        final controller = _controllers.putIfAbsent(
          key,
          TextEditingController.new,
        );
        controller.text = value;
      }

      final controlKeys = {...(layout?.controls ?? const []).map(_fieldKey)};

      final enabled = {
        ...?setup?.enabledFields,
      }.where(controlKeys.contains).toSet();

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedRadio = radio;
        _layout = layout;
        _loadedSetup = setup;
        _enabledFields = enabled;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage = 'Impossible de charger les commandes radio.\n$error';
      });
    }
  }

  Future<void> _openAddDialog() async {
    final draft = Set<String>.from(_enabledFields);

    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Ajouter des commandes'),
              content: SizedBox(
                width: 520,
                child: _controls.isEmpty
                    ? const Text(
                        'Aucune commande disponible '
                        'pour cette radio.',
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final control in _controls)
                            CheckboxListTile(
                              value: draft.contains(_fieldKey(control)),
                              title: Text(control.label),
                              subtitle: Text(_typeLabel(control.type)),
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                              onChanged: (value) {
                                setDialogState(() {
                                  final key = _fieldKey(control);

                                  if (value ?? false) {
                                    draft.add(key);
                                  } else {
                                    draft.remove(key);
                                  }
                                });
                              },
                            ),
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
                  onPressed: () {
                    Navigator.pop(dialogContext, draft);
                  },
                  child: const Text('Valider'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) {
      return;
    }

    setState(() {
      _enabledFields = result;
    });
  }

  void _removeControl(String key) {
    setState(() {
      _enabledFields.remove(key);
    });
  }

  Future<void> _save() async {
    final radioId = widget.model.radioId;

    if (radioId == null || radioId.trim().isEmpty) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final previousFields = _loadedSetup?.enabledFields ?? const <String>[];
      final previousValues = _loadedSetup?.values ?? const <String, String>{};

      final otherFields = previousFields
          .where((key) => !_controlKeys.contains(key))
          .toList();

      final mergedFields = <String>[...otherFields, ..._enabledFields];

      final mergedValues = <String, String>{
        for (final key in otherFields) key: previousValues[key] ?? '',
        for (final key in _enabledFields)
          key: _controllers[key]?.text.trim() ?? '',
      };

      final saved = await _setupService.saveSetup(
        ModelRadioSetup(
          modelId: widget.modelId,
          radioId: radioId,
          enabledFields: mergedFields,
          values: mergedValues,
        ),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _loadedSetup = saved;
        _isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Commandes radio enregistrées')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Impossible d’enregistrer les commandes radio : '
            '$error',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return _ControlsErrorState(message: _errorMessage!, onRetry: _loadData);
    }

    if (widget.model.radioId == null || widget.model.radioId!.trim().isEmpty) {
      return const _ControlsNoRadioState();
    }

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          children: [
            _ControlsRadioCard(radio: _selectedRadio),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.tonalIcon(
                onPressed: _controls.isEmpty ? null : _openAddDialog,
                icon: const Icon(Icons.add),
                label: const Text('Ajouter'),
              ),
            ),
            const SizedBox(height: 18),
            if (_controls.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Aucune commande référencée '
                    'pour cette radio.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else if (_enabledFields.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'Aucune commande ajoutée.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              ..._buildControlFields(),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            heroTag: 'save-model-radio-controls',
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_isSaving ? 'Enregistrement...' : 'Enregistrer'),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildControlFields() {
    final widgets = <Widget>[];

    for (final control in _controls) {
      final key = _fieldKey(control);

      if (!_enabledFields.contains(key)) {
        continue;
      }

      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: _controllers[key],
            maxLength: 80,
            decoration: InputDecoration(
              labelText: control.label,
              hintText: 'Fonction affectée à ${control.label}',
              helperText: _typeLabel(control.type),
              border: const OutlineInputBorder(),
              counterText: '',
              suffixIcon: IconButton(
                tooltip: 'Retirer',
                onPressed: () {
                  _removeControl(key);
                },
                icon: const Icon(Icons.close),
              ),
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  String _typeLabel(RadioControlType type) {
    switch (type) {
      case RadioControlType.button:
        return 'Bouton';
      case RadioControlType.trim:
        return 'Trim digital';
      case RadioControlType.dial:
        return 'Molette';
      case RadioControlType.switchControl:
        return 'Interrupteur';
      case RadioControlType.lever:
        return 'Levier';
      case RadioControlType.auxiliary:
        return 'Commande auxiliaire';
    }
  }
}

class _ControlsRadioCard extends StatelessWidget {
  const _ControlsRadioCard({required this.radio});

  final RcRadio? radio;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.gamepad_outlined)),
        title: Text(
          radio?.fullName ?? 'Radio associée',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          radio == null || radio!.protocols.isEmpty
              ? 'Protocole non renseigné'
              : 'Protocole : ${radio!.protocols.join(' • ')}',
        ),
      ),
    );
  }
}

class _ControlsNoRadioState extends StatelessWidget {
  const _ControlsNoRadioState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: const [
        SizedBox(height: 100),
        Icon(Icons.gamepad_outlined, size: 72),
        SizedBox(height: 16),
        Text(
          'Aucune radio associée',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 8),
        Text(
          'Modifie la fiche du modèle et sélectionne '
          'une radio.',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _ControlsErrorState extends StatelessWidget {
  const _ControlsErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 56),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}
