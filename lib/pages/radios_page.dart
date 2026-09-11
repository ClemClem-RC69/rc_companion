import 'dart:async';

import 'package:flutter/material.dart';

import '../data/radio_catalog.dart';
import '../models/radio.dart';
import '../models/radio_catalog_item.dart';
import 'radio_manual_viewer_page.dart';
import '../services/radio_service.dart';

class RadiosPage extends StatefulWidget {
  const RadiosPage({super.key});

  @override
  State<RadiosPage> createState() => _RadiosPageState();
}

class _RadiosPageState extends State<RadiosPage> {
  final RadioService _radioService = RadioService();

  List<RcRadio> _radios = [];
  StreamSubscription<List<RcRadio>>? _radioSubscription;

  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _radioSubscription = _radioService.watchRadios().listen(
      (radios) {
        if (!mounted) return;
        setState(() {
          _radios = radios;
          _isLoading = false;
          _errorMessage = null;
        });
      },
      onError: (_) {
        // Le cache local reste utilisable hors ligne.
      },
    );
    _loadRadios();
  }

  @override
  void dispose() {
    _radioSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadRadios() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final radios = await _radioService.fetchRadios();

      if (!mounted) return;

      setState(() {
        _radios = radios;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = 'Impossible de charger les radios.\n$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openCatalog() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return const _RadioCatalogSheet();
      },
    );

    if (added == true) {
      await _loadRadios();
    }
  }

  Future<void> _deleteRadio(RcRadio radio) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Supprimer la radio'),
          content: Text('Supprimer ${radio.fullName} de vos radios ?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: const Text('Supprimer'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await _radioService.deleteRadio(radio.id);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${radio.fullName} a été supprimée.')),
      );

      await _loadRadios();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible de supprimer la radio : $error')),
      );
    }
  }

  Future<void> _addOrReplaceManual(RcRadio radio) async {
    try {
      final changed = await _radioService.addOrReplaceManual(radio);
      if (!mounted || !changed) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            radio.hasManual
                ? 'Le manuel de ${radio.fullName} a été remplacé.'
                : 'Le manuel de ${radio.fullName} a été ajouté.',
          ),
        ),
      );
      await _loadRadios();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible d’enregistrer le manuel : $error')),
      );
    }
  }

  Future<void> _openManual(RcRadio radio) async {
    try {
      final path = await _radioService.getManualLocalPath(radio);
      if (!mounted) return;

      final action = await Navigator.of(context).push<RadioManualViewerAction>(
        MaterialPageRoute<RadioManualViewerAction>(
          builder: (_) => RadioManualViewerPage(
            path: path,
            filename: radio.manualName ?? 'Manuel',
          ),
        ),
      );

      if (!mounted) return;

      switch (action) {
        case RadioManualViewerAction.replace:
          await _addOrReplaceManual(radio);
          break;
        case RadioManualViewerAction.delete:
          await _deleteManual(radio);
          break;
        case null:
          await _loadRadios();
          break;
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible d’ouvrir le manuel : $error')),
      );
    }
  }

  Future<void> _deleteManual(RcRadio radio) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer le manuel'),
        content: Text(
          'Supprimer le manuel enregistré pour ${radio.fullName} ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _radioService.deleteManual(radio);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Le manuel de ${radio.fullName} a été supprimé.'),
        ),
      );
      await _loadRadios();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible de supprimer le manuel : $error')),
      );
    }
  }

  void _handleRadioMenu(String value, RcRadio radio) {
    switch (value) {
      case 'manual_add':
        _addOrReplaceManual(radio);
        return;
      case 'manual_open':
        _openManual(radio);
        return;
      case 'delete':
        _deleteRadio(radio);
        return;
    }
  }

  Color _radioAccentColor(String radioName) {
    const colors = <Color>[
      Color(0xFF2F80ED),
      Color(0xFF16C6D4),
      Color(0xFFFF7A1A),
      Color(0xFFFF4D5A),
      Color(0xFFA855F7),
      Color(0xFF34C98F),
      Color(0xFFFFD84D),
      Color(0xFF5B8CFF),
    ];

    final normalized = radioName.trim().toLowerCase();
    var hash = 0;
    for (final codeUnit in normalized.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }

    return colors[hash % colors.length];
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 56),
              const SizedBox(height: 16),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _loadRadios,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    if (_radios.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.settings_remote,
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(
                'Aucune radio enregistrée',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Sélectionne une radio dans le catalogue.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _openCatalog,
                icon: const Icon(Icons.add),
                label: const Text('Ajouter une radio'),
              ),
            ],
          ),
        ),
      );
    }

    final isPhonePortrait =
        MediaQuery.sizeOf(context).width < 600 &&
        MediaQuery.orientationOf(context) == Orientation.portrait;

    return RefreshIndicator(
      onRefresh: _loadRadios,
      child: ListView.separated(
        padding: EdgeInsets.fromLTRB(
          isPhonePortrait ? 10 : 16,
          isPhonePortrait ? 10 : 16,
          isPhonePortrait ? 10 : 16,
          96,
        ),
        itemCount: _radios.length,
        separatorBuilder: (context, index) {
          return SizedBox(height: isPhonePortrait ? 5 : 8);
        },
        itemBuilder: (context, index) {
          final radio = _radios[index];

          return Card(
            child: ListTile(
              dense: isPhonePortrait,
              visualDensity: isPhonePortrait
                  ? const VisualDensity(horizontal: -2, vertical: -3)
                  : null,
              contentPadding: EdgeInsets.symmetric(
                horizontal: isPhonePortrait ? 8 : 16,
                vertical: isPhonePortrait ? 2 : 8,
              ),
              leading: _RadioThumbnail(
                brand: radio.brand,
                model: radio.model,
                type: radio.type,
                compact: isPhonePortrait,
              ),
              title: Text(
                radio.fullName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isPhonePortrait
                      ? _radioAccentColor(radio.fullName)
                      : null,
                  fontSize: isPhonePortrait ? 14 : null,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Padding(
                padding: EdgeInsets.only(top: isPhonePortrait ? 2 : 6),
                child: Text(
                  radio.protocols.isEmpty
                      ? 'Protocole non renseigné'
                      : 'Protocole : ${radio.protocols.join(' • ')}',
                  maxLines: isPhonePortrait ? 1 : null,
                  overflow: isPhonePortrait ? TextOverflow.ellipsis : null,
                  style: TextStyle(fontSize: isPhonePortrait ? 10.5 : null),
                ),
              ),
              trailing: PopupMenuButton<String>(
                padding: isPhonePortrait
                    ? EdgeInsets.zero
                    : const EdgeInsets.all(8),
                iconSize: isPhonePortrait ? 18 : 24,
                constraints: isPhonePortrait
                    ? const BoxConstraints.tightFor(width: 28, height: 28)
                    : null,
                onSelected: (value) => _handleRadioMenu(value, radio),
                itemBuilder: (context) {
                  final items = <PopupMenuEntry<String>>[];

                  if (radio.hasManual) {
                    items.addAll(const [
                      PopupMenuItem<String>(
                        value: 'manual_open',
                        child: Row(
                          children: [
                            Icon(Icons.menu_book_outlined),
                            SizedBox(width: 12),
                            Text('Ouvrir le manuel'),
                          ],
                        ),
                      ),
                      PopupMenuDivider(),
                    ]);
                  } else {
                    items.add(
                      const PopupMenuItem<String>(
                        value: 'manual_add',
                        child: Row(
                          children: [
                            Icon(Icons.note_add_outlined),
                            SizedBox(width: 12),
                            Text('Ajouter le manuel'),
                          ],
                        ),
                      ),
                    );
                    items.add(const PopupMenuDivider());
                  }

                  items.add(
                    const PopupMenuItem<String>(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline),
                          SizedBox(width: 12),
                          Text('Supprimer'),
                        ],
                      ),
                    ),
                  );
                  return items;
                },
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Radios')),
      floatingActionButton: _radios.isEmpty || _isLoading
          ? null
          : FloatingActionButton.extended(
              onPressed: _openCatalog,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter'),
            ),
      body: _buildBody(),
    );
  }
}

class _RadioThumbnail extends StatelessWidget {
  const _RadioThumbnail({
    required this.brand,
    required this.model,
    required this.type,
    this.compact = false,
  });

  final String brand;
  final String model;
  final String type;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final normalizedType = type.toLowerCase();

    final icon = normalizedType == 'sticks'
        ? Icons.sports_esports_outlined
        : Icons.settings_remote_outlined;

    return Container(
      width: compact ? 38 : 52,
      height: compact ? 38 : 52,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(compact ? 9 : 12),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: compact ? 22 : 30),
    );
  }
}

class _RadioCatalogSheet extends StatefulWidget {
  const _RadioCatalogSheet();

  @override
  State<_RadioCatalogSheet> createState() => _RadioCatalogSheetState();
}

class _RadioCatalogSheetState extends State<_RadioCatalogSheet> {
  final RadioService _radioService = RadioService();
  final TextEditingController _searchController = TextEditingController();

  String? _selectedBrand;
  RadioLevel? _selectedLevel;
  RadioType? _selectedType;

  String? _addingRadioId;

  List<String> get _brands {
    final brands = radioCatalog.map((radio) => radio.brand).toSet().toList();

    brands.sort();

    return brands;
  }

  List<RadioCatalogItem> get _filteredRadios {
    final query = _searchController.text.trim().toLowerCase();

    final radios = radioCatalog.where((radio) {
      final matchesSearch =
          query.isEmpty ||
          radio.brand.toLowerCase().contains(query) ||
          radio.model.toLowerCase().contains(query) ||
          radio.fullName.toLowerCase().contains(query) ||
          radio.protocols.any(
            (protocol) => protocol.toLowerCase().contains(query),
          );

      final matchesBrand =
          _selectedBrand == null || radio.brand == _selectedBrand;

      final matchesLevel =
          _selectedLevel == null || radio.level == _selectedLevel;

      final matchesType = _selectedType == null || radio.type == _selectedType;

      return matchesSearch && matchesBrand && matchesLevel && matchesType;
    }).toList();

    radios.sort((a, b) {
      final brandComparison = a.brand.compareTo(b.brand);

      if (brandComparison != 0) {
        return brandComparison;
      }

      return a.model.compareTo(b.model);
    });

    return radios;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _resetFilters() {
    setState(() {
      _searchController.clear();
      _selectedBrand = null;
      _selectedLevel = null;
      _selectedType = null;
    });
  }

  Future<void> _addRadio(RadioCatalogItem radio) async {
    if (_addingRadioId != null) return;

    setState(() {
      _addingRadioId = radio.id;
    });

    try {
      final alreadyExists = await _radioService.radioAlreadyExists(
        brand: radio.brand,
        model: radio.model,
      );

      if (!mounted) return;

      if (alreadyExists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${radio.fullName} est déjà dans vos radios.'),
          ),
        );

        return;
      }

      await _radioService.addRadio(
        brand: radio.brand,
        model: radio.model,
        level: radio.levelValue,
        type: radio.typeValue,
        channels: radio.channels,
        protocols: radio.protocols,
        programmable: radio.programmable,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${radio.fullName} a été ajoutée.')),
      );

      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible d’ajouter la radio : $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _addingRadioId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredRadios = _filteredRadios;

    return FractionallySizedBox(
      heightFactor: 0.95,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Ajouter une radio',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'Fermer',
                  onPressed: () {
                    Navigator.of(context).pop(false);
                  },
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchController,
              onChanged: (value) {
                setState(() {});
              },
              decoration: InputDecoration(
                hintText: 'Rechercher une marque ou un modèle',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Effacer',
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                          });
                        },
                        icon: const Icon(Icons.clear),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedBrand,
                    decoration: const InputDecoration(
                      labelText: 'Marque',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Toutes'),
                      ),
                      ..._brands.map(
                        (brand) => DropdownMenuItem<String>(
                          value: brand,
                          child: Text(brand),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedBrand = value;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<RadioLevel>(
                    initialValue: _selectedLevel,
                    decoration: const InputDecoration(
                      labelText: 'Niveau',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem<RadioLevel>(
                        value: null,
                        child: Text('Tous'),
                      ),
                      DropdownMenuItem<RadioLevel>(
                        value: RadioLevel.basic,
                        child: Text('Basique'),
                      ),
                      DropdownMenuItem<RadioLevel>(
                        value: RadioLevel.intermediate,
                        child: Text('Intermédiaire'),
                      ),
                      DropdownMenuItem<RadioLevel>(
                        value: RadioLevel.advanced,
                        child: Text('Avancée'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedLevel = value;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 160,
                  child: DropdownButtonFormField<RadioType>(
                    initialValue: _selectedType,
                    decoration: const InputDecoration(
                      labelText: 'Type',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem<RadioType>(
                        value: null,
                        child: Text('Tous'),
                      ),
                      DropdownMenuItem<RadioType>(
                        value: RadioType.wheel,
                        child: Text('Volant'),
                      ),
                      DropdownMenuItem<RadioType>(
                        value: RadioType.sticks,
                        child: Text('Manches'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedType = value;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _resetFilters,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réinitialiser'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${filteredRadios.length} radio'
                '${filteredRadios.length > 1 ? 's' : ''}',
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: filteredRadios.isEmpty
                ? const Center(
                    child: Text('Aucune radio ne correspond à la recherche.'),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: filteredRadios.length,
                    separatorBuilder: (context, index) {
                      return const SizedBox(height: 8);
                    },
                    itemBuilder: (context, index) {
                      final radio = filteredRadios[index];
                      final isAdding = _addingRadioId == radio.id;

                      return Card(
                        child: ListTile(
                          leading: _RadioThumbnail(
                            brand: radio.brand,
                            model: radio.model,
                            type: radio.typeValue,
                          ),
                          title: Text(
                            radio.fullName,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              radio.protocols.isEmpty
                                  ? 'Protocole non renseigné'
                                  : 'Protocole : '
                                        '${radio.protocols.join(' • ')}',
                            ),
                          ),
                          trailing: isAdding
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.add_circle_outline),
                          onTap: isAdding
                              ? null
                              : () {
                                  _addRadio(radio);
                                },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
