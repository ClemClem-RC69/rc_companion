import 'dart:async';
import 'package:flutter/material.dart';

import '../../../models/model_radio_setup.dart';
import '../../../models/radio.dart';
import '../../../models/radio_field_catalog.dart';
import '../../../models/rc_model.dart';
import '../../../services/model_radio_setup_service.dart';
import '../../../services/radio_service.dart';

class ModelRadioSetupTab extends StatefulWidget {
  const ModelRadioSetupTab({
    super.key,
    required this.modelId,
    required this.model,
  });

  final String modelId;
  final RcModel model;

  @override
  State<ModelRadioSetupTab> createState() => _ModelRadioSetupTabState();
}

class _ModelRadioSetupTabState extends State<ModelRadioSetupTab> {
  final ModelRadioSetupService _setupService = ModelRadioSetupService();
  final RadioService _radioService = RadioService();

  final Map<String, TextEditingController> _controllers = {};

  RcRadio? _selectedRadio;
  ModelRadioSetup? _loadedSetup;
  StreamSubscription<ModelRadioSetup?>? _setupSubscription;
  StreamSubscription<List<RcRadio>>? _radioSubscription;
  Set<String> _enabledFields = {};

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEditing = false;
  String? _errorMessage;

  List<RadioFieldSection> get _sections {
    return radioFieldCatalog
        .where(
          (section) => section.title != 'Boutons, molettes et interrupteurs',
        )
        .toList();
  }

  List<RadioFieldDefinition> get _allFields {
    return _sections.expand((section) => section.fields).toList();
  }

  Set<String> get _availableKeys {
    return _allFields.map((field) => field.key).toSet();
  }

  @override
  void initState() {
    super.initState();

    for (final field in _allFields) {
      _controllers[field.key] = TextEditingController();
    }

    _setupSubscription = _setupService
        .watchSetup(modelId: widget.modelId)
        .listen((setup) {
          if (!mounted || _isSaving) return;

          final enabled = {
            ...?setup?.enabledFields,
          }.where(_availableKeys.contains).toSet();

          for (final field in _allFields) {
            _controllers[field.key]?.text = setup?.value(field.key) ?? '';
          }

          setState(() {
            _loadedSetup = setup;
            _enabledFields = enabled;
            _isLoading = false;
            _errorMessage = null;
          });
        });

    _radioSubscription = _radioService.watchRadios().listen((radios) {
      if (!mounted) return;
      final radioId = widget.model.radioId?.trim();
      RcRadio? selected;
      if (radioId != null && radioId.isNotEmpty) {
        for (final radio in radios) {
          if (radio.id == radioId) {
            selected = radio;
            break;
          }
        }
      }
      setState(() {
        _selectedRadio = selected;
      });
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

      final enabled = {
        ...?setup?.enabledFields,
      }.where(_availableKeys.contains).toSet();

      for (final field in _allFields) {
        _controllers[field.key]?.text = setup?.value(field.key) ?? '';
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _selectedRadio = radio;
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
        _errorMessage = 'Impossible de charger les réglages radio.\n$error';
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
              title: const Text('Ajouter des réglages'),
              content: SizedBox(
                width: 520,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final section in _sections) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 14, 4, 4),
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
                          value: draft.contains(field.key),
                          title: Text(field.label),
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          onChanged: (value) {
                            setDialogState(() {
                              if (value ?? false) {
                                draft.add(field.key);
                              } else {
                                draft.remove(field.key);
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

  void _removeField(String key) {
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
          .where((key) => !_availableKeys.contains(key))
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
        _isEditing = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Réglages radio enregistrés')),
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
            'Impossible d’enregistrer les réglages radio : '
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
      return _ErrorState(message: _errorMessage!, onRetry: _loadData);
    }

    if (widget.model.radioId == null || widget.model.radioId!.trim().isEmpty) {
      return const _NoRadioState();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _RadioCard(radio: _selectedRadio),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.tonalIcon(
              onPressed: _openAddDialog,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter'),
            ),
            OutlinedButton.icon(
              onPressed: _enabledFields.isEmpty
                  ? null
                  : () {
                      setState(() {
                        _isEditing = !_isEditing;
                      });
                    },
              icon: Icon(
                _isEditing ? Icons.close_rounded : Icons.edit_outlined,
              ),
              label: Text(_isEditing ? 'Annuler' : 'Modifier'),
            ),
            if (_isEditing)
              FilledButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_isSaving ? 'Enregistrement...' : 'Enregistrer'),
              ),
          ],
        ),
        const SizedBox(height: 18),
        if (_enabledFields.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('Aucun réglage ajouté.', textAlign: TextAlign.center),
            ),
          )
        else
          _buildResponsiveFields(),
      ],
    );
  }

  Widget _buildResponsiveFields() {
    final visible = <(RadioFieldSection, RadioFieldDefinition)>[];

    for (final section in _sections) {
      for (final field in section.fields) {
        if (_enabledFields.contains(field.key)) {
          visible.add((section, field));
        }
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumns = constraints.maxWidth >= 300;
        final spacing = 10.0;
        final itemWidth = twoColumns
            ? (constraints.maxWidth - spacing) / 2
            : constraints.maxWidth;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final entry in visible)
              SizedBox(
                width: itemWidth,
                child: _buildFieldCard(entry.$1, entry.$2),
              ),
          ],
        );
      },
    );
  }

  Widget _buildFieldCard(
    RadioFieldSection section,
    RadioFieldDefinition field,
  ) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: TextField(
          controller: _controllers[field.key],
          readOnly: !_isEditing,
          minLines: field.multiline ? 3 : 1,
          maxLines: field.multiline ? 6 : 1,
          maxLength: field.multiline ? 500 : 60,
          decoration: InputDecoration(
            labelText: field.label,
            hintText: field.hint,
            border: const OutlineInputBorder(),
            alignLabelWithHint: field.multiline,
            counterText: field.multiline ? null : '',
            suffixIcon: _isEditing
                ? IconButton(
                    tooltip: 'Retirer',
                    onPressed: () {
                      _removeField(field.key);
                    },
                    icon: const Icon(Icons.close),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

class _RadioCard extends StatelessWidget {
  const _RadioCard({required this.radio});

  final RcRadio? radio;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const CircleAvatar(
          child: Icon(Icons.settings_remote_outlined),
        ),
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

class _NoRadioState extends StatelessWidget {
  const _NoRadioState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: const [
        SizedBox(height: 100),
        Icon(Icons.settings_remote_outlined, size: 72),
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

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

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
