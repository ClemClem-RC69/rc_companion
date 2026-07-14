import 'package:flutter/material.dart';

import '../../models/battery.dart';
import '../../services/battery_service.dart';
import 'battery_detail_page.dart';

class BatteriesPage extends StatefulWidget {
  const BatteriesPage({super.key});

  @override
  State<BatteriesPage> createState() => _BatteriesPageState();
}

class _BatteriesPageState extends State<BatteriesPage> {
  List<Battery> _batteries = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadBatteries();
  }

  Future<void> _loadBatteries() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final batteries = await BatteryService.getBatteries();

      if (!mounted) {
        return;
      }

      setState(() {
        _batteries = batteries;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'Impossible de charger les batteries.\n$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _addBattery() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddBatteryPage()),
    );

    if (created == true) {
      await _loadBatteries();
    }
  }

  Future<void> _createPairFromExisting() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const CreateExistingPairPage(),
      ),
    );

    if (created == true) {
      await _loadBatteries();
    }
  }

  Future<void> _openBattery(Battery battery) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => BatteryDetailPage(battery: battery),
      ),
    );

    await _loadBatteries();
  }

  Future<void> _changeStatus(Battery battery) async {
    final selectedStatus = await showDialog<String>(
      context: context,
      builder: (context) {
        const statuses = [
          'Active',
          'Stockage',
          'À surveiller',
          'HS',
          'Retirée',
        ];

        return SimpleDialog(
          title: const Text('Changer le statut'),
          children: statuses
              .map(
                (status) => ListTile(
                  leading: Icon(
                    status == battery.status
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(status),
                  onTap: () => Navigator.pop(context, status),
                ),
              )
              .toList(),
        );
      },
    );

    if (selectedStatus == null || selectedStatus == battery.status) {
      return;
    }

    try {
      await BatteryService.updateBattery(
        battery.copyWith(status: selectedStatus),
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Statut modifié : $selectedStatus')),
      );

      await _loadBatteries();
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Modification impossible : $error')),
      );
    }
  }

  Future<void> _dissolvePair(Battery battery) async {
    final pairId = battery.pairId;

    if (pairId == null || pairId.isEmpty) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dissoudre la paire ?'),
        content: Text(
          'Les batteries de la paire $pairId redeviendront des batteries seules.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Dissoudre'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await BatteryService.dissolvePair(pairId);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Paire $pairId dissoute')),
      );

      await _loadBatteries();
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Dissolution impossible : $error')),
      );
    }
  }

  Future<void> _deleteBattery(Battery battery) async {
    final pairMessage = battery.isPaired
        ? '\n\nLa batterie restante sera automatiquement retirée de la paire ${battery.pairId}.'
        : '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer la batterie ?'),
        content: Text(
          'La batterie ${battery.id} sera supprimée définitivement.'
          '$pairMessage\n\nCette action est irréversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await BatteryService.deleteBattery(battery);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${battery.id} supprimée')),
      );

      await _loadBatteries();
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Suppression impossible : $error')),
      );
    }
  }

  Color _statusColor(BuildContext context, String status) {
    final colors = Theme.of(context).colorScheme;

    return switch (status) {
      'Active' => colors.primaryContainer,
      'Stockage' => colors.secondaryContainer,
      'À surveiller' => colors.tertiaryContainer,
      'HS' => colors.errorContainer,
      'Retirée' => colors.surfaceContainerHighest,
      _ => colors.surfaceContainerHighest,
    };
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          FilledButton.icon(
            onPressed: _addBattery,
            icon: const Icon(Icons.add),
            label: const Text('Créer une batterie'),
          ),
          OutlinedButton.icon(
            onPressed: _batteries.length < 2 ? null : _createPairFromExisting,
            icon: const Icon(Icons.link),
            label: const Text('Créer une paire'),
          ),
        ],
      ),
    );
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
              const Icon(Icons.cloud_off, size: 48),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadBatteries,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadBatteries,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: _batteries.isEmpty ? 2 : _batteries.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildActions();
          }

          if (_batteries.isEmpty) {
  return const Padding(
    padding: EdgeInsets.only(top: 140),
    child: Column(
      children: [
        Icon(Icons.battery_0_bar, size: 64),
        SizedBox(height: 16),
        Text(
          'Aucune batterie pour le moment',
          style: TextStyle(fontSize: 20),
        ),
      ],
    ),
  );
}

          final battery = _batteries[index - 1];

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: const Icon(
                  Icons.battery_charging_full,
                  size: 36,
                ),
                title: Text(
                  battery.id,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${battery.technology} • ${battery.brand} • '
                        '${battery.cells} • ${battery.capacity} mAh • '
                        '${battery.cRate}C',
                      ),
                      if (battery.isPaired)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text('Paire ${battery.pairId}'),
                        ),
                      Chip(
                        visualDensity: VisualDensity.compact,
                        backgroundColor:
                            _statusColor(context, battery.status),
                        label: Text(battery.status),
                      ),
                    ],
                  ),
                ),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'status':
                        _changeStatus(battery);
                      case 'dissolve':
                        _dissolvePair(battery);
                      case 'delete':
                        _deleteBattery(battery);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'status',
                      child: ListTile(
                        leading: Icon(Icons.sync_alt),
                        title: Text('Changer le statut'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    if (battery.isPaired)
                      const PopupMenuItem(
                        value: 'dissolve',
                        child: ListTile(
                          leading: Icon(Icons.link_off),
                          title: Text('Dissoudre la paire'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: Icon(Icons.delete_forever),
                        title: Text('Supprimer définitivement'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
                onTap: () => _openBattery(battery),
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
      appBar: AppBar(
        title: const Text('Mes batteries'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadBatteries,
            tooltip: 'Actualiser',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }
}

enum BatteryCreationMode {
  single,
  newPair,
  existingPair,
}

class AddBatteryPage extends StatefulWidget {
  const AddBatteryPage({super.key});

  @override
  State<AddBatteryPage> createState() => _AddBatteryPageState();
}

class _AddBatteryPageState extends State<AddBatteryPage> {
  final _formKey = GlobalKey<FormState>();
  final _brandController = TextEditingController();
  final _capacityController = TextEditingController();
  final _cRateController = TextEditingController();
  final _notesController = TextEditingController();

  String _technology = 'LiPo';
  String _cells = '4S';
  BatteryCreationMode _creationMode = BatteryCreationMode.single;
  List<Battery> _candidates = [];
  Battery? _selectedExistingBattery;
  bool _isSearchingCandidates = false;
  bool _isSaving = false;

  static const _technologies = [
    'LiPo',
    'LiHV',
    'Li-Ion',
    'LiFe',
    'NiMH',
    'NiCd',
  ];

  static const _cellOptions = [
    '1S',
    '2S',
    '3S',
    '4S',
    '5S',
    '6S',
  ];

  @override
  void dispose() {
    _brandController.dispose();
    _capacityController.dispose();
    _cRateController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _clearCandidateSelection() {
    _candidates = [];
    _selectedExistingBattery = null;
  }

  Future<void> _searchCandidates() async {
    if (_creationMode != BatteryCreationMode.existingPair ||
        _isSearchingCandidates) {
      return;
    }

    final capacity = int.tryParse(_capacityController.text.trim());
    final cRate = int.tryParse(_cRateController.text.trim());

    if (capacity == null || capacity <= 0 || cRate == null || cRate <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Renseigne d’abord la capacité et le taux de décharge.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _isSearchingCandidates = true;
      _selectedExistingBattery = null;
    });

    try {
      final candidates = await BatteryService.getAvailablePairCandidates(
        technology: _technology,
        capacity: capacity,
        cells: _cells,
        cRate: cRate,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _candidates = candidates;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Recherche impossible : $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSearchingCandidates = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _isSaving) {
      return;
    }

    if (_creationMode == BatteryCreationMode.existingPair &&
        _selectedExistingBattery == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sélectionne une batterie existante compatible.'),
        ),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final now = DateTime.now();
      final capacity = int.parse(_capacityController.text.trim());
      final cRate = int.parse(_cRateController.text.trim());

      final firstNumber = await BatteryService.getNextBatteryNumber(
        technology: _technology,
        date: now,
      );

      String? pairId;

      if (_creationMode == BatteryCreationMode.newPair) {
        final pairNumber = await BatteryService.getNextPairNumber(now);
        pairId = BatteryService.buildPairId(
          date: now,
          number: pairNumber,
        );
      }

      final firstBattery = Battery(
        id: BatteryService.buildBatteryCode(
          technology: _technology,
          date: now,
          number: firstNumber,
        ),
        technology: _technology,
        brand: _brandController.text.trim(),
        capacity: capacity,
        cells: _cells,
        cRate: cRate,
        status: 'Active',
        pairId: pairId,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      switch (_creationMode) {
        case BatteryCreationMode.single:
          await BatteryService.createBattery(firstBattery);

        case BatteryCreationMode.newPair:
          final secondBattery = Battery(
            id: BatteryService.buildBatteryCode(
              technology: _technology,
              date: now,
              number: firstNumber + 1,
            ),
            technology: _technology,
            brand: _brandController.text.trim(),
            capacity: capacity,
            cells: _cells,
            cRate: cRate,
            status: 'Active',
            pairId: pairId,
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );

          await BatteryService.createBatteries([
            firstBattery,
            secondBattery,
          ]);

        case BatteryCreationMode.existingPair:
          await BatteryService.createBatteryPairedWithExisting(
            newBattery: firstBattery,
            existingBatteryCode: _selectedExistingBattery!.id,
          );
      }

      if (!mounted) {
        return;
      }

      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Enregistrement impossible : $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  String? _requiredTextValidator(String? value, String message) {
    if (value == null || value.trim().isEmpty) {
      return message;
    }

    return null;
  }

  String? _positiveIntegerValidator(String? value, String fieldName) {
    final number = int.tryParse(value?.trim() ?? '');

    if (number == null || number <= 0) {
      return 'Renseigne un $fieldName valide';
    }

    return null;
  }

  Widget _modeTile({
    required BatteryCreationMode mode,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final selected = _creationMode == mode;
    final colors = Theme.of(context).colorScheme;

    return Card(
      color: selected ? colors.primaryContainer : null,
      child: ListTile(
        enabled: !_isSaving,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Icon(
          selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        ),
        onTap: _isSaving
            ? null
            : () {
                setState(() {
                  _creationMode = mode;
                  _clearCandidateSelection();
                });
              },
      ),
    );
  }

  Widget _batteryChoiceCard(Battery battery) {
    final selected = _selectedExistingBattery?.id == battery.id;
    final colors = Theme.of(context).colorScheme;

    return Card(
      color: selected ? colors.primaryContainer : null,
      child: ListTile(
        enabled: !_isSaving,
        leading: const Icon(Icons.battery_charging_full),
        title: Text(
          battery.id,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${battery.brand} • ${battery.technology} • ${battery.cells} • '
          '${battery.capacity} mAh • ${battery.cRate}C\n'
          'Statut : ${battery.status}',
        ),
        isThreeLine: true,
        trailing: Icon(
          selected ? Icons.check_circle : Icons.circle_outlined,
        ),
        onTap: _isSaving
            ? null
            : () {
                setState(() {
                  _selectedExistingBattery = battery;
                });
              },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedExistingBattery = _selectedExistingBattery;
    final differentBrand = selectedExistingBattery != null &&
        _brandController.text.trim().isNotEmpty &&
        selectedExistingBattery.brand.toLowerCase() !=
            _brandController.text.trim().toLowerCase();

    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle batterie')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Type de création',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _modeTile(
              mode: BatteryCreationMode.single,
              title: 'Batterie seule',
              subtitle: 'Crée une seule batterie sans paire.',
              icon: Icons.battery_full,
            ),
            _modeTile(
              mode: BatteryCreationMode.newPair,
              title: 'Paire avec une nouvelle batterie',
              subtitle: 'Crée deux batteries strictement identiques.',
              icon: Icons.battery_charging_full,
            ),
            _modeTile(
              mode: BatteryCreationMode.existingPair,
              title: 'Paire avec une batterie existante',
              subtitle:
                  'Crée une batterie et l’associe à une batterie compatible libre.',
              icon: Icons.link,
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<String>(
              initialValue: _technology,
              decoration: const InputDecoration(
                labelText: 'Technologie',
                border: OutlineInputBorder(),
              ),
              items: _technologies
                  .map(
                    (item) => DropdownMenuItem(
                      value: item,
                      child: Text(item),
                    ),
                  )
                  .toList(),
              onChanged: _isSaving
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() {
                          _technology = value;
                          _clearCandidateSelection();
                        });
                      }
                    },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _brandController,
              enabled: !_isSaving,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Marque',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
              validator: (value) => _requiredTextValidator(
                value,
                'Renseigne la marque',
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _capacityController,
              enabled: !_isSaving,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Capacité (mAh)',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) {
                setState(_clearCandidateSelection);
              },
              validator: (value) => _positiveIntegerValidator(
                value,
                'nombre de mAh',
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _cells,
              decoration: const InputDecoration(
                labelText: 'Nombre de cellules',
                border: OutlineInputBorder(),
              ),
              items: _cellOptions
                  .map(
                    (item) => DropdownMenuItem(
                      value: item,
                      child: Text(item),
                    ),
                  )
                  .toList(),
              onChanged: _isSaving
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() {
                          _cells = value;
                          _clearCandidateSelection();
                        });
                      }
                    },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _cRateController,
              enabled: !_isSaving,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Taux de décharge (C)',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) {
                setState(_clearCandidateSelection);
              },
              validator: (value) => _positiveIntegerValidator(
                value,
                'taux C',
              ),
            ),
            if (_creationMode == BatteryCreationMode.existingPair) ...[
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed:
                    _isSaving || _isSearchingCandidates ? null : _searchCandidates,
                icon: _isSearchingCandidates
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: Text(
                  _isSearchingCandidates
                      ? 'Recherche...'
                      : 'Rechercher les batteries compatibles',
                ),
              ),
              const SizedBox(height: 10),
              if (!_isSearchingCandidates && _candidates.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Renseigne les caractéristiques puis lance la recherche.\n\n'
                      'Les batteries déjà associées à une paire sont automatiquement exclues.',
                    ),
                  ),
                ),
              if (_candidates.isNotEmpty) ...[
                Text(
                  'Sélectionner une batterie existante',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ..._candidates.map(_batteryChoiceCard),
              ],
              if (differentBrand)
                Card(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  child: const ListTile(
                    leading: Icon(Icons.warning_amber),
                    title: Text('Marques différentes'),
                    subtitle: Text(
                      'La paire est compatible, mais il est préférable '
                      'd’utiliser deux batteries de même marque et de même modèle.',
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 14),
            TextFormField(
              controller: _notesController,
              enabled: !_isSaving,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Notes facultatives',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(
                _isSaving
                    ? 'Enregistrement...'
                    : switch (_creationMode) {
                        BatteryCreationMode.single =>
                          'Créer la batterie',
                        BatteryCreationMode.newPair =>
                          'Créer les deux batteries',
                        BatteryCreationMode.existingPair =>
                          'Créer la batterie et la paire',
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CreateExistingPairPage extends StatefulWidget {
  const CreateExistingPairPage({super.key});

  @override
  State<CreateExistingPairPage> createState() => _CreateExistingPairPageState();
}

class _CreateExistingPairPageState extends State<CreateExistingPairPage> {
  List<Battery> _availableBatteries = [];
  Battery? _firstBattery;
  Battery? _secondBattery;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAvailableBatteries();
  }

  Future<void> _loadAvailableBatteries() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final batteries = await BatteryService.getBatteries();

      if (!mounted) {
        return;
      }

      setState(() {
        _availableBatteries =
            batteries.where((battery) => !battery.isPaired).toList();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'Impossible de charger les batteries.\n$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  List<Battery> get _compatibleSecondBatteries {
    final firstBattery = _firstBattery;

    if (firstBattery == null) {
      return [];
    }

    return _availableBatteries
        .where(
          (battery) =>
              battery.id != firstBattery.id &&
              BatteryService.arePairCompatible(firstBattery, battery),
        )
        .toList();
  }

  Future<void> _savePair() async {
    final firstBattery = _firstBattery;
    final secondBattery = _secondBattery;

    if (firstBattery == null || secondBattery == null || _isSaving) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final pairId = await BatteryService.createPairFromExistingBatteries(
        firstBattery: firstBattery,
        secondBattery: secondBattery,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Paire $pairId créée')),
      );

      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Création impossible : $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Widget _selectionCard({
    required Battery battery,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      color: selected ? colors.primaryContainer : null,
      child: ListTile(
        enabled: onTap != null,
        leading: const Icon(Icons.battery_charging_full),
        title: Text(
          battery.id,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${battery.brand} • ${battery.technology} • ${battery.cells} • '
          '${battery.capacity} mAh • ${battery.cRate}C\n'
          'Statut : ${battery.status}',
        ),
        isThreeLine: true,
        trailing: Icon(
          selected ? Icons.check_circle : Icons.circle_outlined,
        ),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final compatibleBatteries = _compatibleSecondBatteries;
    final differentBrand = _firstBattery != null &&
        _secondBattery != null &&
        _firstBattery!.brand.toLowerCase() !=
            _secondBattery!.brand.toLowerCase();

    return Scaffold(
      appBar: AppBar(title: const Text('Créer une paire')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _loadAvailableBatteries,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text(
                      'Seules les batteries qui ne font encore partie '
                      'd’aucune paire sont proposées.',
                    ),
                    const SizedBox(height: 18),
                    Text(
                      '1. Première batterie',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (_availableBatteries.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Aucune batterie libre disponible.',
                          ),
                        ),
                      )
                    else
                      ..._availableBatteries.map(
                        (battery) => _selectionCard(
                          battery: battery,
                          selected: _firstBattery?.id == battery.id,
                          onTap: _isSaving
                              ? null
                              : () {
                                  setState(() {
                                    _firstBattery = battery;
                                    _secondBattery = null;
                                  });
                                },
                        ),
                      ),
                    if (_firstBattery != null) ...[
                      const SizedBox(height: 22),
                      Text(
                        '2. Deuxième batterie compatible',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (compatibleBatteries.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'Aucune autre batterie compatible et libre '
                              'n’est disponible.',
                            ),
                          ),
                        )
                      else
                        ...compatibleBatteries.map(
                          (battery) => _selectionCard(
                            battery: battery,
                            selected: _secondBattery?.id == battery.id,
                            onTap: _isSaving
                                ? null
                                : () {
                                    setState(() {
                                      _secondBattery = battery;
                                    });
                                  },
                          ),
                        ),
                    ],
                    if (differentBrand) ...[
                      const SizedBox(height: 12),
                      Card(
                        color:
                            Theme.of(context).colorScheme.tertiaryContainer,
                        child: const ListTile(
                          leading: Icon(Icons.warning_amber),
                          title: Text('Marques différentes'),
                          subtitle: Text(
                            'La paire est compatible, mais deux batteries '
                            'identiques restent préférables.',
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: _firstBattery == null ||
                              _secondBattery == null ||
                              _isSaving
                          ? null
                          : _savePair,
                      icon: _isSaving
                          ? const SizedBox.square(
                              dimension: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.link),
                      label: Text(
                        _isSaving ? 'Création...' : 'Créer la paire',
                      ),
                    ),
                  ],
                ),
    );
  }
}
