import 'package:flutter/material.dart';

import '../../models/radio_profile.dart';
import '../../services/radio_profile_service.dart';

class RadioProfilesPage extends StatefulWidget {
  const RadioProfilesPage({
    super.key,
    required this.radioId,
    required this.radioName,
  });

  final String radioId;
  final String radioName;

  @override
  State<RadioProfilesPage> createState() =>
      _RadioProfilesPageState();
}

class _RadioProfilesPageState extends State<RadioProfilesPage> {
  final RadioProfileService _profileService =
      RadioProfileService();

  List<RadioProfile> _profiles = [];

  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final profiles = await _profileService.fetchProfiles(
        radioId: widget.radioId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _profiles = profiles;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
        _errorMessage =
            'Impossible de charger les profils radio.\n$error';
      });
    }
  }

  Future<void> _openProfileEditor({
    RadioProfile? profile,
  }) async {
    final result = await Navigator.push<_ProfileFormResult>(
      context,
      MaterialPageRoute(
        builder: (_) => _RadioProfileEditorPage(
          profile: profile,
          radioName: widget.radioName,
        ),
      ),
    );

    if (result == null) {
      return;
    }

    await _saveProfile(
      profile: profile,
      result: result,
    );
  }

  Future<void> _saveProfile({
    required RadioProfile? profile,
    required _ProfileFormResult result,
  }) async {
    setState(() {
      _isSaving = true;
    });

    try {
      final nameExists =
          await _profileService.profileNameAlreadyExists(
        radioId: widget.radioId,
        name: result.name,
        ignoredProfileId: profile?.id,
      );

      if (!mounted) {
        return;
      }

      if (nameExists) {
        setState(() {
          _isSaving = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Un profil portant ce nom existe déjà.',
            ),
          ),
        );

        return;
      }

      if (profile == null) {
        await _profileService.addProfile(
          radioId: widget.radioId,
          name: result.name,
          enabledFields: result.enabledFields,
          values: result.values,
        );
      } else {
        await _profileService.updateProfile(
          profile.copyWith(
            name: result.name,
            enabledFields: result.enabledFields,
            values: result.values,
          ),
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _isSaving = false;
      });

      await _loadProfiles();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            profile == null
                ? 'Profil radio créé'
                : 'Profil radio modifié',
          ),
        ),
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
            'Impossible d’enregistrer le profil : $error',
          ),
        ),
      );
    }
  }

  Future<void> _confirmDeleteProfile(
    RadioProfile profile,
  ) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Supprimer le profil'),
          content: Text(
            'Veux-tu vraiment supprimer le profil '
            '"${profile.name}" ?',
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

    try {
      await _profileService.deleteProfile(profile.id);

      if (!mounted) {
        return;
      }

      setState(() {
        _profiles.removeWhere(
          (item) => item.id == profile.id,
        );
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profil radio supprimé'),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Impossible de supprimer le profil : $error',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profils radio'),
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'add-radio-profile',
        onPressed: _isSaving
            ? null
            : () {
                _openProfileEditor();
              },
        icon: _isSaving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.add),
        label: Text(
          _isSaving
              ? 'Enregistrement...'
              : 'Nouveau profil',
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _loadProfiles,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadProfiles,
      child: _profiles.isEmpty
          ? ListView(
              physics:
                  const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 100),
                const Icon(
                  Icons.tune,
                  size: 72,
                ),
                const SizedBox(height: 18),
                const Text(
                  'Aucun profil radio',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Crée le premier profil de réglages pour '
                  '${widget.radioName}.',
                  textAlign: TextAlign.center,
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                16,
                16,
                16,
                100,
              ),
              itemCount: _profiles.length,
              itemBuilder: (context, index) {
                final profile = _profiles[index];

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.tune),
                    ),
                    title: Text(
                      profile.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      _profileSummary(profile),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () {
                      _openProfileEditor(profile: profile);
                    },
                    trailing: PopupMenuButton<String>(
                      tooltip: 'Options',
                      onSelected: (value) {
                        if (value == 'edit') {
                          _openProfileEditor(
                            profile: profile,
                          );
                        } else if (value == 'delete') {
                          _confirmDeleteProfile(profile);
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
                  ),
                );
              },
            ),
    );
  }

  String _profileSummary(RadioProfile profile) {
    if (profile.enabledFields.isEmpty) {
      return 'Aucun réglage sélectionné';
    }

    final labels = profile.enabledFields
        .take(3)
        .map(_labelForField)
        .toList();

    final remaining = profile.enabledFields.length - labels.length;

    if (remaining > 0) {
      labels.add('+$remaining');
    }

    return labels.join(' • ');
  }
}

class _RadioProfileEditorPage extends StatefulWidget {
  const _RadioProfileEditorPage({
    required this.radioName,
    this.profile,
  });

  final String radioName;
  final RadioProfile? profile;

  @override
  State<_RadioProfileEditorPage> createState() =>
      _RadioProfileEditorPageState();
}

class _RadioProfileEditorPageState
    extends State<_RadioProfileEditorPage> {
  final GlobalKey<FormState> _formKey =
      GlobalKey<FormState>();

  late final TextEditingController _nameController;
  late final Set<String> _enabledFields;
  late final Map<String, TextEditingController>
      _valueControllers;

  bool _showFieldSelection = true;

  @override
  void initState() {
    super.initState();

    final profile = widget.profile;

    _nameController = TextEditingController(
      text: profile?.name ?? '',
    );

    _enabledFields = {
      ...?profile?.enabledFields,
    };

    _valueControllers = {
      for (final field in _allRadioFields)
        field.key: TextEditingController(
          text: profile?.value(field.key) ?? '',
        ),
    };

    _showFieldSelection = profile == null;
  }

  @override
  void dispose() {
    _nameController.dispose();

    for (final controller in _valueControllers.values) {
      controller.dispose();
    }

    super.dispose();
  }

  void _toggleField(
    String fieldKey,
    bool enabled,
  ) {
    setState(() {
      if (enabled) {
        _enabledFields.add(fieldKey);
      } else {
        _enabledFields.remove(fieldKey);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _enabledFields
        ..clear()
        ..addAll(
          _allRadioFields.map((field) => field.key),
        );
    });
  }

  void _clearAll() {
    setState(() {
      _enabledFields.clear();
    });
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) {
      return;
    }

    final values = <String, String>{};

    for (final fieldKey in _enabledFields) {
      values[fieldKey] =
          _valueControllers[fieldKey]?.text.trim() ?? '';
    }

    Navigator.pop(
      context,
      _ProfileFormResult(
        name: _nameController.text.trim(),
        enabledFields: _enabledFields.toList(),
        values: values,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.profile != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isEditing
              ? 'Modifier le profil'
              : 'Nouveau profil',
        ),
        actions: [
          TextButton(
            onPressed: _submit,
            child: const Text('Enregistrer'),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            16,
            16,
            16,
            32,
          ),
          children: [
            TextFormField(
              controller: _nameController,
              autofocus: !isEditing,
              maxLength: 60,
              decoration: InputDecoration(
                labelText: 'Nom du profil',
                hintText: 'Exemple : Setup principal',
                helperText: widget.radioName,
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null ||
                    value.trim().isEmpty) {
                  return 'Le nom est obligatoire.';
                }

                return null;
              },
            ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.checklist),
                    title: const Text(
                      'Réglages à renseigner',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      '${_enabledFields.length} élément'
                      '${_enabledFields.length > 1 ? 's' : ''} '
                      'sélectionné'
                      '${_enabledFields.length > 1 ? 's' : ''}',
                    ),
                    trailing: Icon(
                      _showFieldSelection
                          ? Icons.expand_less
                          : Icons.expand_more,
                    ),
                    onTap: () {
                      setState(() {
                        _showFieldSelection =
                            !_showFieldSelection;
                      });
                    },
                  ),
                  if (_showFieldSelection) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          OutlinedButton(
                            onPressed: _selectAll,
                            child: const Text(
                              'Tout sélectionner',
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: _clearAll,
                            child: const Text(
                              'Tout désélectionner',
                            ),
                          ),
                        ],
                      ),
                    ),
                    ..._buildFieldSelection(),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_enabledFields.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 42,
                      ),
                      SizedBox(height: 10),
                      Text(
                        'Sélectionne les éléments que tu '
                        'souhaites renseigner dans ce profil.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              ..._buildEnabledFields(),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Enregistrer le profil'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFieldSelection() {
    final widgets = <Widget>[];

    for (final section in _radioSections) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(
            16,
            16,
            16,
            6,
          ),
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
      );

      for (final field in section.fields) {
        widgets.add(
          CheckboxListTile(
            value: _enabledFields.contains(field.key),
            title: Text(field.label),
            subtitle: null,
            controlAffinity:
                ListTileControlAffinity.leading,
            onChanged: (value) {
              _toggleField(
                field.key,
                value ?? false,
              );
            },
          ),
        );
      }
    }

    widgets.add(const SizedBox(height: 8));

    return widgets;
  }

  List<Widget> _buildEnabledFields() {
    final widgets = <Widget>[];

    for (final section in _radioSections) {
      final enabledSectionFields = section.fields
          .where(
            (field) =>
                _enabledFields.contains(field.key),
          )
          .toList();

      if (enabledSectionFields.isEmpty) {
        continue;
      }

      widgets.add(
        Padding(
          padding: const EdgeInsets.only(
            top: 8,
            bottom: 10,
          ),
          child: Row(
            children: [
              Icon(section.icon),
              const SizedBox(width: 8),
              Text(
                section.title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );

      for (final field in enabledSectionFields) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextFormField(
              controller: _valueControllers[field.key],
              minLines: field.multiline ? 3 : 1,
              maxLines: field.multiline ? 6 : 1,
              maxLength: field.multiline ? 500 : 60,
              decoration: InputDecoration(
                labelText: field.label,
                hintText: field.hint,
                helperText: null,
                border: const OutlineInputBorder(),
                alignLabelWithHint: field.multiline,
                counterText: field.multiline ? null : '',
              ),
            ),
          ),
        );
      }
    }

    return widgets;
  }
}

class _ProfileFormResult {
  const _ProfileFormResult({
    required this.name,
    required this.enabledFields,
    required this.values,
  });

  final String name;
  final List<String> enabledFields;
  final Map<String, String> values;
}

class _RadioField {
  const _RadioField({
    required this.key,
    required this.label,
    required this.hint,
    this.multiline = false,
  });

  final String key;
  final String label;
  final String hint;
  final bool multiline;
}

class _RadioSection {
  const _RadioSection({
    required this.title,
    required this.icon,
    required this.fields,
  });

  final String title;
  final IconData icon;
  final List<_RadioField> fields;
}

const List<_RadioSection> _radioSections = [
  _RadioSection(
    title: 'Direction',
    icon: Icons.swap_horiz,
    fields: [
      _RadioField(
        key: 'steering_trim',
        label: 'Trim direction',
        hint: 'Exemple : +2',
      ),
      _RadioField(
        key: 'steering_subtrim',
        label: 'Sub-trim direction',
        hint: 'Exemple : -3',
      ),
      _RadioField(
        key: 'steering_dual_rate',
        label: 'Dual Rate direction',
        hint: 'Exemple : 90 %',
      ),
      _RadioField(
        key: 'steering_expo',
        label: 'Expo direction',
        hint: 'Exemple : -20 %',
      ),
      _RadioField(
        key: 'steering_speed',
        label: 'Vitesse direction',
        hint: 'Exemple : 80 %',
      ),
      _RadioField(
        key: 'steering_left_epa',
        label: 'EPA direction gauche',
        hint: 'Exemple : 95 %',
      ),
      _RadioField(
        key: 'steering_right_epa',
        label: 'EPA direction droite',
        hint: 'Exemple : 92 %',
      ),
      _RadioField(
        key: 'steering_reverse',
        label: 'Inversion direction',
        hint: 'Normal ou inversé',
      ),
    ],
  ),
  _RadioSection(
    title: 'Gaz et frein',
    icon: Icons.speed,
    fields: [
      _RadioField(
        key: 'throttle_trim',
        label: 'Trim gaz',
        hint: 'Exemple : 0',
      ),
      _RadioField(
        key: 'throttle_subtrim',
        label: 'Sub-trim gaz',
        hint: 'Exemple : +1',
      ),
      _RadioField(
        key: 'throttle_expo',
        label: 'Expo gaz',
        hint: 'Exemple : -10 %',
      ),
      _RadioField(
        key: 'throttle_limit',
        label: 'Limite gaz',
        hint: 'Exemple : 75 %',
      ),
      _RadioField(
        key: 'throttle_epa',
        label: 'EPA gaz',
        hint: 'Exemple : 100 %',
      ),
      _RadioField(
        key: 'brake_epa',
        label: 'EPA frein',
        hint: 'Exemple : 80 %',
      ),
      _RadioField(
        key: 'brake_rate',
        label: 'Puissance de frein',
        hint: 'Exemple : 70 %',
      ),
      _RadioField(
        key: 'throttle_reverse',
        label: 'Inversion gaz',
        hint: 'Normal ou inversé',
      ),
      _RadioField(
        key: 'abs',
        label: 'ABS',
        hint: 'Exemple : Off ou 20 %',
      ),
    ],
  ),
  _RadioSection(
    title: 'Gyro et assistances',
    icon: Icons.assistant_outlined,
    fields: [
      _RadioField(
        key: 'gyro_gain',
        label: 'Gain gyro',
        hint: 'Exemple : 30 %',
      ),
      _RadioField(
        key: 'tsm_avc',
        label: 'TSM / AVC',
        hint: 'Exemple : Off ou 25 %',
      ),
      _RadioField(
        key: 'traction_control',
        label: 'Contrôle de traction',
        hint: 'Exemple : Off',
      ),
    ],
  ),
  _RadioSection(
    title: 'Voies auxiliaires',
    icon: Icons.tune,
    fields: [
      _RadioField(
        key: 'channel_3',
        label: 'Voie 3',
        hint: 'Fonction ou valeur',
      ),
      _RadioField(
        key: 'channel_4',
        label: 'Voie 4',
        hint: 'Fonction ou valeur',
      ),
      _RadioField(
        key: 'channel_5',
        label: 'Voie 5',
        hint: 'Fonction ou valeur',
      ),
      _RadioField(
        key: 'channel_6',
        label: 'Voie 6',
        hint: 'Fonction ou valeur',
      ),
    ],
  ),
  _RadioSection(
    title: 'Mixages',
    icon: Icons.merge_type,
    fields: [
      _RadioField(
        key: 'mix_1',
        label: 'Mixage 1',
        hint: 'Fonction et valeur',
      ),
      _RadioField(
        key: 'mix_2',
        label: 'Mixage 2',
        hint: 'Fonction et valeur',
      ),
    ],
  ),
  _RadioSection(
    title: 'Divers',
    icon: Icons.more_horiz,
    fields: [
      _RadioField(
        key: 'timer',
        label: 'Timer',
        hint: 'Exemple : 8 min',
      ),
      _RadioField(
        key: 'voltage_alarm',
        label: 'Alarme tension',
        hint: 'Exemple : 7,0 V',
      ),
      _RadioField(
        key: 'model_memory',
        label: 'Mémoire modèle',
        hint: 'Exemple : Mémoire 3',
      ),
      _RadioField(
        key: 'notes',
        label: 'Notes',
        hint:
            'Comportement du modèle, conditions, remarques...',
        multiline: true,
      ),
    ],
  ),
];

List<_RadioField> get _allRadioFields {
  return _radioSections
      .expand((section) => section.fields)
      .toList();
}

String _labelForField(String fieldKey) {
  for (final field in _allRadioFields) {
    if (field.key == fieldKey) {
      return field.label;
    }
  }

  return fieldKey;
}
