import 'package:flutter/material.dart';

import '../../models/battery.dart';
import '../../models/battery_measurement.dart';
import '../../services/battery_service.dart';
import 'battery_detail_page.dart';
import 'battery_scanner_page.dart';

class BatteriesPage extends StatefulWidget {
  const BatteriesPage({super.key});

  @override
  State<BatteriesPage> createState() => _BatteriesPageState();
}

class _BatteriesPageState extends State<BatteriesPage> {
  List<Battery> _batteries = [];
  final Map<String, _BatteryHealthStatus> _healthByBatteryCode = {};
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

      final healthEntries = await Future.wait(
        batteries.map(
          (battery) async {
            final latest =
                await BatteryService.getLatestBatteryMeasurement(
              battery.id,
            );

            return MapEntry(
              battery.id,
              _healthStatusFor(
                battery: battery,
                measurement: latest,
              ),
            );
          },
        ),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _batteries = batteries;
        _healthByBatteryCode
          ..clear()
          ..addEntries(healthEntries);
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

  Future<void> _createPair() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const CreatePairPage(),
      ),
    );

    if (created == true) {
      await _loadBatteries();
    }
  }

  Future<void> _scanBattery() async {
    final scannedCode = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const BatteryScannerPage(),
      ),
    );

    if (!mounted || scannedCode == null) {
      return;
    }

    final normalizedCode = scannedCode.trim();

    Battery? matchingBattery;

    for (final battery in _batteries) {
      if (battery.id.trim().toLowerCase() ==
          normalizedCode.toLowerCase()) {
        matchingBattery = battery;
        break;
      }
    }

    if (matchingBattery == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Aucune batterie trouvée pour le QR Code : $normalizedCode',
          ),
        ),
      );
      return;
    }

    await _openBattery(matchingBattery);
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

  _BatteryHealthStatus _healthStatusFor({
    required Battery battery,
    required BatteryMeasurement? measurement,
  }) {
    if (measurement == null) {
      return const _BatteryHealthStatus(
        label: 'Non évaluée',
        level: _BatteryHealthLevel.notEvaluated,
      );
    }

    final technology = battery.technology
        .toLowerCase()
        .replaceAll('-', '')
        .replaceAll(' ', '');

    final capacityAh = battery.capacity <= 0
        ? 1.0
        : battery.capacity / 1000;

    late final double warningFactor;
    late final double criticalFactor;

    switch (technology) {
      case 'lipo':
      case 'lihv':
        warningFactor = 30;
        criticalFactor = 50;
      case 'liion':
        warningFactor = 60;
        criticalFactor = 100;
      case 'life':
        warningFactor = 40;
        criticalFactor = 65;
      case 'nimh':
        warningFactor = 90;
        criticalFactor = 150;
      case 'nicd':
        warningFactor = 80;
        criticalFactor = 130;
      default:
        warningFactor = 50;
        criticalFactor = 90;
    }

    final warningResistance = warningFactor / capacityAh;
    final criticalResistance = criticalFactor / capacityAh;

    final isLithiumTechnology = {
      'lipo',
      'lihv',
      'liion',
      'life',
    }.contains(technology);

    final warningVoltageSpread =
        isLithiumTechnology ? 0.030 : 0.050;
    final criticalVoltageSpread =
        isLithiumTechnology ? 0.050 : 0.100;

    var hasWarning = false;
    var hasCritical = false;

    if (measurement.averageInternalResistance >=
        criticalResistance) {
      hasCritical = true;
    } else if (measurement.averageInternalResistance >=
        warningResistance) {
      hasWarning = true;
    }

    if (measurement.maximumVoltageDifference >=
        criticalVoltageSpread) {
      hasCritical = true;
    } else if (measurement.maximumVoltageDifference >=
        warningVoltageSpread) {
      hasWarning = true;
    }

    for (var index = 0;
        index < measurement.cellInternalResistances.length;
        index++) {
      final resistance =
          measurement.cellInternalResistances[index];

      if (resistance >= criticalResistance) {
        hasCritical = true;
      } else if (resistance >= warningResistance) {
        hasWarning = true;
      }

      final voltage = measurement.cellVoltages[index];
      final minimum = measurement.minimumCellVoltage;
      final maximum = measurement.maximumCellVoltage;

      if ((maximum - voltage) >= criticalVoltageSpread ||
          (voltage - minimum) >= criticalVoltageSpread) {
        hasCritical = true;
      } else if ((maximum - voltage) >= warningVoltageSpread ||
          (voltage - minimum) >= warningVoltageSpread) {
        hasWarning = true;
      }
    }

    final temperature = measurement.batteryTemperature;

    if (temperature != null) {
      if (temperature >= 55) {
        hasCritical = true;
      } else if (temperature >= 45) {
        hasWarning = true;
      }
    }

    if (hasCritical) {
      return const _BatteryHealthStatus(
        label: 'État critique*',
        level: _BatteryHealthLevel.critical,
      );
    }

    if (hasWarning) {
      return const _BatteryHealthStatus(
        label: 'À surveiller*',
        level: _BatteryHealthLevel.warning,
      );
    }

    return const _BatteryHealthStatus(
      label: 'Bon état*',
      level: _BatteryHealthLevel.good,
    );
  }

  Color _healthColor(
    BuildContext context,
    _BatteryHealthLevel level,
  ) {
    final colors = Theme.of(context).colorScheme;

    return switch (level) {
      _BatteryHealthLevel.notEvaluated =>
        colors.surfaceContainerHighest,
      _BatteryHealthLevel.good => Colors.green.shade700,
      _BatteryHealthLevel.warning => Colors.orange.shade700,
      _BatteryHealthLevel.critical => Colors.red,
    };
  }

  Color _healthForegroundColor(
    BuildContext context,
    _BatteryHealthLevel level,
  ) {
    return switch (level) {
      _BatteryHealthLevel.notEvaluated =>
        Theme.of(context).colorScheme.onSurfaceVariant,
      _BatteryHealthLevel.good ||
      _BatteryHealthLevel.warning ||
      _BatteryHealthLevel.critical => Colors.white,
    };
  }

  Color _technologyColor(String technology) {
    return switch (technology) {
      'LiPo' => Colors.red,
      'LiHV' => Colors.purple,
      'Li-Ion' => Colors.blue,
      'LiFe' => Colors.green,
      'NiMH' => Colors.orange,
      'NiCd' => Colors.grey,
      _ => Theme.of(context).colorScheme.primary,
    };
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scannerButton = FilledButton.tonalIcon(
            onPressed: _isLoading ? null : _scanBattery,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scanner'),
          );

          if (constraints.maxWidth < 720) {
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _addBattery,
                  icon: const Icon(Icons.add),
                  label: const Text('Créer une batterie'),
                ),
                OutlinedButton.icon(
                  onPressed: _createPair,
                  icon: const Icon(Icons.link),
                  label: const Text('Créer une paire'),
                ),
                scannerButton,
              ],
            );
          }

          return Row(
            children: [
              FilledButton.icon(
                onPressed: _addBattery,
                icon: const Icon(Icons.add),
                label: const Text('Créer une batterie'),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _createPair,
                icon: const Icon(Icons.link),
                label: const Text('Créer une paire'),
              ),
              const Spacer(),
              scannerButton,
            ],
          );
        },
      ),
    );
  }

  Widget _buildBatteryTile(
    Battery battery, {
    bool insidePair = false,
  }) {
    return Card(
      margin: EdgeInsets.only(
        bottom: insidePair ? 6 : 10,
      ),
      elevation: insidePair ? 0 : null,
      color: insidePair
          ? Theme.of(context).colorScheme.surfaceContainerHighest
          : null,
      child: ListTile(
        leading: Icon(
          Icons.battery_charging_full,
          size: insidePair ? 30 : 36,
          color: _technologyColor(battery.technology),
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
              Builder(
                builder: (context) {
                  final health =
                      _healthByBatteryCode[battery.id] ??
                      const _BatteryHealthStatus(
                        label: 'Non évaluée',
                        level: _BatteryHealthLevel.notEvaluated,
                      );

                  return Chip(
                    visualDensity: VisualDensity.compact,
                    backgroundColor:
                        _healthColor(context, health.level),
                    label: Text(
                      health.label,
                      style: TextStyle(
                        color: _healthForegroundColor(
                          context,
                          health.level,
                        ),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'dissolve':
                _dissolvePair(battery);
              case 'delete':
                _deleteBattery(battery);
            }
          },
          itemBuilder: (context) => [
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
  }

  Widget _buildPairCard(
    String pairId,
    List<Battery> batteries,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.link,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Paire $pairId',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                Text(
                  '${batteries.length} batteries',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...batteries.map(
              (battery) => _buildBatteryTile(
                battery,
                insidePair: true,
              ),
            ),
          ],
        ),
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

    final pairedBatteries = <String, List<Battery>>{};
    final singleBatteries = <Battery>[];

    for (final battery in _batteries) {
      final pairId = battery.pairId;

      if (pairId != null && pairId.isNotEmpty) {
        pairedBatteries.putIfAbsent(pairId, () => []).add(battery);
      } else {
        singleBatteries.add(battery);
      }
    }

    final pairEntries = pairedBatteries.entries.toList()
      ..sort((first, second) => first.key.compareTo(second.key));

    return RefreshIndicator(
      onRefresh: _loadBatteries,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _buildActions(),
          if (_batteries.isEmpty)
            const Padding(
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
            )
          else ...[
            if (pairEntries.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  'Paires',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ...pairEntries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildPairCard(
                    entry.key,
                    entry.value,
                  ),
                ),
              ),
            ],
            if (singleBatteries.isNotEmpty) ...[
              Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  pairEntries.isEmpty ? 8 : 4,
                  16,
                  8,
                ),
                child: Text(
                  'Batteries seules',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ...singleBatteries.map(
                (battery) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildBatteryTile(battery),
                ),
              ),
            ],
          ],
        ],
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
  bool _isSaving = false;

  static const _technologies = [
    'LiPo',
    'LiHV',
    'Li-Ion',
    'LiFe',
    'NiMH',
    'NiCd',
  ];

  static const _cellOptions = ['1S', '2S', '3S', '4S', '5S', '6S'];

  @override
  void dispose() {
    _brandController.dispose();
    _capacityController.dispose();
    _cRateController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String? _required(String? value, String message) {
    if (value == null || value.trim().isEmpty) {
      return message;
    }
    return null;
  }

  String? _positiveInteger(String? value, String fieldName) {
    final number = int.tryParse(value?.trim() ?? '');
    if (number == null || number <= 0) {
      return 'Renseigne un $fieldName valide';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _isSaving) {
      return;
    }

    setState(() => _isSaving = true);

    try {
      final now = DateTime.now();
      final number = await BatteryService.getNextBatteryNumber(
        technology: _technology,
        date: now,
      );

      final battery = Battery(
        id: BatteryService.buildBatteryCode(
          technology: _technology,
          date: now,
          number: number,
        ),
        technology: _technology,
        brand: _brandController.text.trim(),
        capacity: int.parse(_capacityController.text.trim()),
        cells: _cells,
        cRate: int.parse(_cRateController.text.trim()),
        status: 'Active',
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      await BatteryService.createBattery(battery);

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Enregistrement impossible : $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
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
                  .map((value) => DropdownMenuItem(
                        value: value,
                        child: Text(value),
                      ))
                  .toList(),
              onChanged: _isSaving
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _technology = value);
                      }
                    },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _brandController,
              enabled: !_isSaving,
              decoration: const InputDecoration(
                labelText: 'Marque',
                border: OutlineInputBorder(),
              ),
              validator: (value) => _required(value, 'Renseigne la marque'),
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
              validator: (value) => _positiveInteger(value, 'nombre de mAh'),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _cells,
              decoration: const InputDecoration(
                labelText: 'Nombre de cellules',
                border: OutlineInputBorder(),
              ),
              items: _cellOptions
                  .map((value) => DropdownMenuItem(
                        value: value,
                        child: Text(value),
                      ))
                  .toList(),
              onChanged: _isSaving
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _cells = value);
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
              validator: (value) => _positiveInteger(value, 'taux C'),
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
                _isSaving ? 'Enregistrement...' : 'Créer la batterie',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum PairBatterySource { newBattery, existingBattery }

class CreatePairPage extends StatefulWidget {
  const CreatePairPage({super.key});

  @override
  State<CreatePairPage> createState() => _CreatePairPageState();
}

class _CreatePairPageState extends State<CreatePairPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final _formKey1 = GlobalKey<FormState>();
  final _formKey2 = GlobalKey<FormState>();

  final _brand1 = TextEditingController();
  final _capacity1 = TextEditingController();
  final _cRate1 = TextEditingController();
  final _notes1 = TextEditingController();

  final _brand2 = TextEditingController();
  final _capacity2 = TextEditingController();
  final _cRate2 = TextEditingController();
  final _notes2 = TextEditingController();

  PairBatterySource _source1 = PairBatterySource.newBattery;
  PairBatterySource _source2 = PairBatterySource.newBattery;

  String _technology1 = 'LiPo';
  String _technology2 = 'LiPo';
  String _cells1 = '4S';
  String _cells2 = '4S';

  Battery? _existing1;
  Battery? _existing2;

  List<Battery> _available = [];
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  static const _technologies = [
    'LiPo',
    'LiHV',
    'Li-Ion',
    'LiFe',
    'NiMH',
    'NiCd',
  ];

  static const _cellOptions = ['1S', '2S', '3S', '4S', '5S', '6S'];

  Color _technologyColor(String technology) {
    return switch (technology) {
      'LiPo' => Colors.red,
      'LiHV' => Colors.purple,
      'Li-Ion' => Colors.blue,
      'LiFe' => Colors.green,
      'NiMH' => Colors.orange,
      'NiCd' => Colors.grey,
      _ => Theme.of(context).colorScheme.primary,
    };
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAvailable();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _brand1.dispose();
    _capacity1.dispose();
    _cRate1.dispose();
    _notes1.dispose();
    _brand2.dispose();
    _capacity2.dispose();
    _cRate2.dispose();
    _notes2.dispose();
    super.dispose();
  }

  Future<void> _loadAvailable() async {
    try {
      final batteries = await BatteryService.getBatteries();
      if (!mounted) {
        return;
      }

      setState(() {
        _available = batteries.where((battery) => !battery.isPaired).toList();
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Impossible de charger les batteries.\n$error';
        _isLoading = false;
      });
    }
  }

  String? _required(String? value, String message) {
    if (value == null || value.trim().isEmpty) {
      return message;
    }
    return null;
  }

  String? _positiveInteger(String? value, String fieldName) {
    final number = int.tryParse(value?.trim() ?? '');
    if (number == null || number <= 0) {
      return 'Renseigne un $fieldName valide';
    }
    return null;
  }

  Battery? _batteryForSlot(int slot) {
    final source = slot == 1 ? _source1 : _source2;

    if (source == PairBatterySource.existingBattery) {
      return slot == 1 ? _existing1 : _existing2;
    }

    final brand = slot == 1 ? _brand1.text.trim() : _brand2.text.trim();
    final capacity = int.tryParse(
      slot == 1 ? _capacity1.text.trim() : _capacity2.text.trim(),
    );
    final cRate = int.tryParse(
      slot == 1 ? _cRate1.text.trim() : _cRate2.text.trim(),
    );

    if (brand.isEmpty ||
        capacity == null ||
        capacity <= 0 ||
        cRate == null ||
        cRate <= 0) {
      return null;
    }

    return Battery(
      id: 'NOUVELLE-$slot',
      technology: slot == 1 ? _technology1 : _technology2,
      brand: brand,
      capacity: capacity,
      cells: slot == 1 ? _cells1 : _cells2,
      cRate: cRate,
      status: 'Active',
      notes: (slot == 1 ? _notes1.text : _notes2.text).trim().isEmpty
          ? null
          : (slot == 1 ? _notes1.text : _notes2.text).trim(),
    );
  }

  bool get _sameExisting =>
      _source1 == PairBatterySource.existingBattery &&
      _source2 == PairBatterySource.existingBattery &&
      _existing1 != null &&
      _existing2 != null &&
      _existing1!.id == _existing2!.id;

  bool get _complete => _batteryForSlot(1) != null && _batteryForSlot(2) != null;

  bool get _compatible {
    final first = _batteryForSlot(1);
    final second = _batteryForSlot(2);

    return first != null &&
        second != null &&
        !_sameExisting &&
        BatteryService.arePairCompatible(first, second);
  }

  List<Battery> _choices(int slot) {
    final excludedId = slot == 1 ? _existing2?.id : _existing1?.id;
    return _available.where((battery) => battery.id != excludedId).toList();
  }

  Battery? _findBattery(String? id) {
    if (id == null) {
      return null;
    }
    for (final battery in _available) {
      if (battery.id == id) {
        return battery;
      }
    }
    return null;
  }

  Future<Battery> _buildNewBattery(int slot) async {
    final now = DateTime.now();
    final technology = slot == 1 ? _technology1 : _technology2;
    final number = await BatteryService.getNextBatteryNumber(
      technology: technology,
      date: now,
    );

    return Battery(
      id: BatteryService.buildBatteryCode(
        technology: technology,
        date: now,
        number: number,
      ),
      technology: technology,
      brand: slot == 1 ? _brand1.text.trim() : _brand2.text.trim(),
      capacity: int.parse(
        slot == 1 ? _capacity1.text.trim() : _capacity2.text.trim(),
      ),
      cells: slot == 1 ? _cells1 : _cells2,
      cRate: int.parse(
        slot == 1 ? _cRate1.text.trim() : _cRate2.text.trim(),
      ),
      status: 'Active',
      notes: (slot == 1 ? _notes1.text : _notes2.text).trim().isEmpty
          ? null
          : (slot == 1 ? _notes1.text : _notes2.text).trim(),
    );
  }

  Future<void> _savePair() async {
    if (_isSaving) {
      return;
    }

    final valid1 = _source1 == PairBatterySource.existingBattery
        ? _existing1 != null
        : (_formKey1.currentState?.validate() ?? false);

    final valid2 = _source2 == PairBatterySource.existingBattery
        ? _existing2 != null
        : (_formKey2.currentState?.validate() ?? false);

    if (!valid1) {
      _tabController.animateTo(0);
      return;
    }

    if (!valid2) {
      _tabController.animateTo(1);
      return;
    }

    if (!_compatible) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Batterie incompatible pour la paire, '
            'choisir ou renseigner un autre modèle.',
          ),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      if (_source1 == PairBatterySource.existingBattery &&
          _source2 == PairBatterySource.existingBattery) {
        await BatteryService.createPairFromExistingBatteries(
          firstBattery: _existing1!,
          secondBattery: _existing2!,
        );
      } else if (_source1 == PairBatterySource.newBattery &&
          _source2 == PairBatterySource.existingBattery) {
        await BatteryService.createBatteryPairedWithExisting(
          newBattery: await _buildNewBattery(1),
          existingBatteryCode: _existing2!.id,
        );
      } else if (_source1 == PairBatterySource.existingBattery &&
          _source2 == PairBatterySource.newBattery) {
        await BatteryService.createBatteryPairedWithExisting(
          newBattery: await _buildNewBattery(2),
          existingBatteryCode: _existing1!.id,
        );
      } else {
        final now = DateTime.now();
        final pairNumber = await BatteryService.getNextPairNumber(now);
        final pairId = BatteryService.buildPairId(
          date: now,
          number: pairNumber,
        );

        final firstNumber = await BatteryService.getNextBatteryNumber(
          technology: _technology1,
          date: now,
        );

        final first = Battery(
          id: BatteryService.buildBatteryCode(
            technology: _technology1,
            date: now,
            number: firstNumber,
          ),
          technology: _technology1,
          brand: _brand1.text.trim(),
          capacity: int.parse(_capacity1.text.trim()),
          cells: _cells1,
          cRate: int.parse(_cRate1.text.trim()),
          status: 'Active',
          pairId: pairId,
          notes: _notes1.text.trim().isEmpty ? null : _notes1.text.trim(),
        );

        final second = Battery(
          id: BatteryService.buildBatteryCode(
            technology: _technology2,
            date: now,
            number: firstNumber + 1,
          ),
          technology: _technology2,
          brand: _brand2.text.trim(),
          capacity: int.parse(_capacity2.text.trim()),
          cells: _cells2,
          cRate: int.parse(_cRate2.text.trim()),
          status: 'Active',
          pairId: pairId,
          notes: _notes2.text.trim().isEmpty ? null : _notes2.text.trim(),
        );

        await BatteryService.createBatteries([first, second]);
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Création impossible : $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Widget _sourceSelector(int slot) {
    final selected = slot == 1 ? _source1 : _source2;

    return SegmentedButton<PairBatterySource>(
      segments: const [
        ButtonSegment(
          value: PairBatterySource.newBattery,
          label: Text('Nouvelle batterie'),
          icon: Icon(Icons.add),
        ),
        ButtonSegment(
          value: PairBatterySource.existingBattery,
          label: Text('Batterie existante'),
          icon: Icon(Icons.inventory_2_outlined),
        ),
      ],
      selected: {selected},
      onSelectionChanged: _isSaving
          ? null
          : (selection) {
              setState(() {
                if (slot == 1) {
                  _source1 = selection.first;
                  if (_source1 == PairBatterySource.newBattery) {
                    _existing1 = null;
                  }
                } else {
                  _source2 = selection.first;
                  if (_source2 == PairBatterySource.newBattery) {
                    _existing2 = null;
                  }
                }
              });
            },
    );
  }

  Widget _newBatteryForm(int slot) {
    final formKey = slot == 1 ? _formKey1 : _formKey2;
    final brand = slot == 1 ? _brand1 : _brand2;
    final capacity = slot == 1 ? _capacity1 : _capacity2;
    final cRate = slot == 1 ? _cRate1 : _cRate2;
    final notes = slot == 1 ? _notes1 : _notes2;
    final technology = slot == 1 ? _technology1 : _technology2;
    final cells = slot == 1 ? _cells1 : _cells2;

    return Form(
      key: formKey,
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            initialValue: technology,
            decoration: const InputDecoration(
              labelText: 'Technologie',
              border: OutlineInputBorder(),
            ),
            items: _technologies
                .map((value) => DropdownMenuItem(
                      value: value,
                      child: Text(value),
                    ))
                .toList(),
            onChanged: _isSaving
                ? null
                : (value) {
                    if (value != null) {
                      setState(() {
                        if (slot == 1) {
                          _technology1 = value;
                        } else {
                          _technology2 = value;
                        }
                      });
                    }
                  },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: brand,
            enabled: !_isSaving,
            decoration: const InputDecoration(
              labelText: 'Marque',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            validator: (value) => _required(value, 'Renseigne la marque'),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: capacity,
            enabled: !_isSaving,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Capacité (mAh)',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            validator: (value) => _positiveInteger(value, 'nombre de mAh'),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            initialValue: cells,
            decoration: const InputDecoration(
              labelText: 'Nombre de cellules',
              border: OutlineInputBorder(),
            ),
            items: _cellOptions
                .map((value) => DropdownMenuItem(
                      value: value,
                      child: Text(value),
                    ))
                .toList(),
            onChanged: _isSaving
                ? null
                : (value) {
                    if (value != null) {
                      setState(() {
                        if (slot == 1) {
                          _cells1 = value;
                        } else {
                          _cells2 = value;
                        }
                      });
                    }
                  },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: cRate,
            enabled: !_isSaving,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Taux de décharge (C)',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            validator: (value) => _positiveInteger(value, 'taux C'),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: notes,
            enabled: !_isSaving,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Notes facultatives',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _existingSelector(int slot) {
    final choices = _choices(slot);
    final selected = slot == 1 ? _existing1 : _existing2;

    if (choices.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Aucune batterie libre disponible. '
            'Les batteries déjà associées à une paire sont exclues.',
          ),
        ),
      );
    }

    return DropdownButtonFormField<String>(
      initialValue: selected?.id,
      isExpanded: true,
      itemHeight: null,
      decoration: const InputDecoration(
        labelText: 'Batterie existante',
        border: OutlineInputBorder(),
      ),
      hint: const Text('Sélectionner une batterie'),
      items: choices
          .map(
            (battery) => DropdownMenuItem(
              value: battery.id,
              child: Row(
                children: [
                  Icon(
                    Icons.battery_charging_full,
                    color: _technologyColor(battery.technology),
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          battery.id,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${battery.brand} • ${battery.technology} • '
                          '${battery.cells} • ${battery.capacity} mAh • '
                          '${battery.cRate}C',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
      onChanged: _isSaving
          ? null
          : (id) {
              setState(() {
                if (slot == 1) {
                  _existing1 = _findBattery(id);
                } else {
                  _existing2 = _findBattery(id);
                }
              });
            },
    );
  }

  Widget _tab(int slot) {
    final source = slot == 1 ? _source1 : _source2;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _sourceSelector(slot),
        const SizedBox(height: 18),
        if (source == PairBatterySource.newBattery)
          _newBatteryForm(slot)
        else
          _existingSelector(slot),
        if (slot == 1) ...[
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _isSaving
                ? null
                : () {
                    final valid = _source1 ==
                            PairBatterySource.existingBattery
                        ? _existing1 != null
                        : (_formKey1.currentState?.validate() ?? false);

                    if (valid) {
                      _tabController.animateTo(1);
                    }
                  },
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Passer à la batterie 2'),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Créer une paire'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Batterie 1'),
            Tab(text: 'Batterie 2'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, textAlign: TextAlign.center))
              : Column(
                  children: [
                    if (_complete && !_compatible)
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.red.shade700,
                            width: 2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error,
                              color: Colors.red.shade700,
                              size: 34,
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'BATTERIES INCOMPATIBLES\n'
                                'Les deux batteries doivent avoir la même '
                                'technologie, le même nombre de cellules, '
                                'la même capacité et le même taux C.',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => _tabController.animateTo(1),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red.shade700,
                              ),
                              child: const Text('Modifier'),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: TabBarView(
                        controller: _tabController,
                        children: [_tab(1), _tab(2)],
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed:
                                _isSaving || !_compatible ? null : _savePair,
                            icon: _isSaving
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.link),
                            label: Text(
                              _isSaving ? 'Création...' : 'Créer la paire',
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}


enum _BatteryHealthLevel {
  notEvaluated,
  good,
  warning,
  critical,
}

class _BatteryHealthStatus {
  const _BatteryHealthStatus({
    required this.label,
    required this.level,
  });

  final String label;
  final _BatteryHealthLevel level;
}
