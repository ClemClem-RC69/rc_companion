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
                (status) => RadioListTile<String>(
                  value: status,
                  groupValue: battery.status,
                  title: Text(status),
                  onChanged: (value) => Navigator.pop(context, value),
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

    if (_batteries.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadBatteries,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 180),
            Icon(Icons.battery_0_bar, size: 64),
            SizedBox(height: 16),
            Center(
              child: Text(
                'Aucune batterie pour le moment',
                style: TextStyle(fontSize: 20),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadBatteries,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _batteries.length,
        itemBuilder: (context, index) {
          final battery = _batteries[index];

          return Card(
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
                      backgroundColor: _statusColor(context, battery.status),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addBattery,
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
      ),
    );
  }
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
  bool _createPair = false;
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _isSaving) {
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

      if (_createPair) {
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

      if (!_createPair) {
        await BatteryService.createBattery(firstBattery);
      } else {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle batterie')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
              validator: (value) => _positiveIntegerValidator(
                value,
                'taux C',
              ),
            ),
            const SizedBox(height: 14),
            SwitchListTile(
              value: _createPair,
              contentPadding: EdgeInsets.zero,
              title: const Text('Créer une paire'),
              subtitle: const Text(
                'Crée deux batteries strictement identiques',
              ),
              onChanged: _isSaving
                  ? null
                  : (value) {
                      setState(() {
                        _createPair = value;
                      });
                    },
            ),
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
                _isSaving ? 'Enregistrement...' : 'Enregistrer',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
