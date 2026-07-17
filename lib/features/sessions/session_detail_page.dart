import 'package:flutter/material.dart';

import '../../models/battery.dart';
import '../../models/rc_session.dart';
import '../../services/session_service.dart';
import '../../services/supabase_service.dart';

class SessionDetailPage extends StatefulWidget {
  const SessionDetailPage({
    super.key,
    required this.session,
  });

  final RcSession session;

  @override
  State<SessionDetailPage> createState() => _SessionDetailPageState();
}

class _SessionDetailPageState extends State<SessionDetailPage> {
  late RcSession _session;
  bool _isSavingMeasurement = false;
  bool _isSavingSession = false;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
  }

  String _formatDateTime(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');

    return '$day/$month/$year à $hour:$minute';
  }

  String _durationLabel(int minutes) {
    if (minutes < 60) {
      return '$minutes min';
    }

    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;

    if (remainingMinutes == 0) {
      return '${hours}h';
    }

    return '${hours}h ${remainingMinutes}min';
  }

  String _batterySummary(Battery battery) {
    return '${battery.brand} • ${battery.technology} • ${battery.cells} • '
        '${battery.capacity} mAh • ${battery.cRate}C';
  }

  BatteryRunReading? _readingForBattery(
    RcRun run,
    String batteryId,
  ) {
    for (final reading in run.readings) {
      if (reading.batteryId == batteryId) {
        return reading;
      }
    }

    return null;
  }

  Future<void> _editMeasurements({
    required int runIndex,
    required Battery battery,
  }) async {
    final run = _session.runs[runIndex];
    final currentReading = _readingForBattery(run, battery.id);

    final updatedReading = await showDialog<BatteryRunReading>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _EditBatteryMeasurementDialog(
        battery: battery,
        initialReading: currentReading,
      ),
    );

    if (updatedReading == null || !mounted) {
      return;
    }

    setState(() => _isSavingMeasurement = true);

    try {
      final sessionId = _session.id;

      if (sessionId == null || sessionId.isEmpty) {
        throw StateError('Session introuvable');
      }

      final user = SupabaseService.client.auth.currentUser;

      if (user == null) {
        throw StateError('Utilisateur non connecté');
      }

      final runRow = await SupabaseService.client
          .from('session_runs')
          .select('id')
          .eq('session_id', sessionId)
          .eq(
            'started_at',
            run.startedAt.toUtc().toIso8601String(),
          )
          .maybeSingle();

      if (runRow == null) {
        throw StateError('Roulage introuvable');
      }

      final runId = runRow['id'] as String;

      await SupabaseService.client
          .from('session_run_measurements')
          .upsert(
            {
              'run_id': runId,
              'user_id': user.id,
              'battery_code': battery.id,
              'measured_at': (updatedReading.measuredAt ?? DateTime.now())
                  .toUtc()
                  .toIso8601String(),
              'remaining_capacity_percent':
                  updatedReading.remainingCapacityPercent,
              'temperature_celsius':
                  updatedReading.temperatureCelsius,
              'cell_voltages': updatedReading.cellVoltages,
              'cell_resistances': updatedReading.cellResistances,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
            onConflict: 'run_id,battery_code',
          );

      final updatedRuns = List<RcRun>.from(_session.runs);
      final updatedReadings =
          List<BatteryRunReading>.from(updatedRuns[runIndex].readings);

      final readingIndex = updatedReadings.indexWhere(
        (reading) => reading.batteryId == battery.id,
      );

      if (readingIndex == -1) {
        updatedReadings.add(updatedReading);
      } else {
        updatedReadings[readingIndex] = updatedReading;
      }

      updatedRuns[runIndex] = updatedRuns[runIndex].copyWith(
        readings: List<BatteryRunReading>.unmodifiable(updatedReadings),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _session = _session.copyWith(
          runs: List<RcRun>.unmodifiable(updatedRuns),
        );
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mesures mises à jour.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Modification impossible : $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingMeasurement = false);
      }
    }
  }

  Future<void> _saveSession(RcSession updatedSession) async {
    if (_isSavingSession) {
      return;
    }

    setState(() {
      _isSavingSession = true;
    });

    try {
      final savedSession = await SessionService.saveSession(updatedSession);

      if (!mounted) {
        return;
      }

      setState(() {
        _session = savedSession;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session mise à jour.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Modification impossible : $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSavingSession = false;
        });
      }
    }
  }

  Future<void> _editRun(int runIndex) async {
    final run = _session.runs[runIndex];

    final result = await showDialog<_EditRunResult>(
      context: context,
      builder: (context) => _EditRunDialog(
        durationMinutes: run.effectiveDurationMinutes,
        notes: run.notes,
      ),
    );

    if (result == null) {
      return;
    }

    final updatedRuns = List<RcRun>.from(_session.runs);
    updatedRuns[runIndex] = run.copyWith(
      durationMinutes: result.durationMinutes,
      notes: result.notes,
    );

    await _saveSession(
      _session.copyWith(
        runs: List<RcRun>.unmodifiable(updatedRuns),
      ),
    );
  }

  Future<void> _editTerrainInformation() async {
    final result = await showDialog<_EditTerrainResult>(
      context: context,
      builder: (context) => _EditTerrainDialog(session: _session),
    );

    if (result == null) {
      return;
    }

    await _saveSession(
      _session.copyWith(
        drivingNotes: result.drivingNotes,
        breakages: result.breakages,
        partsReplacedOnSite: result.partsReplacedOnSite,
        maintenanceToDo: result.maintenanceToDo,
        partsToOrder: result.partsToOrder,
        changesBeforeNextSession: result.changesBeforeNextSession,
        generalNotes: result.generalNotes,
      ),
    );
  }

  Widget _sectionTitle(
    BuildContext context,
    String title,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  Widget _infoCard({
    required String label,
    required String value,
    IconData? icon,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: icon == null ? null : Icon(icon),
        title: Text(label),
        subtitle: Text(value),
      ),
    );
  }

  Widget _measurementBlock(
    BuildContext context,
    BatteryRunReading reading,
  ) {
    final hasCapacity = reading.remainingCapacityPercent != null;
    final hasTemperature = reading.temperatureCelsius != null;
    final hasCells = reading.cellVoltages.isNotEmpty ||
        reading.cellResistances.isNotEmpty;

    if (!hasCapacity && !hasTemperature && !hasCells) {
      return const SizedBox.shrink();
    }

    final rowCount = reading.cellVoltages.length >
            reading.cellResistances.length
        ? reading.cellVoltages.length
        : reading.cellResistances.length;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasCapacity || hasTemperature)
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                if (hasCapacity)
                  Text(
                    'Capacité restante : '
                    '${reading.remainingCapacityPercent!.toStringAsFixed(0)} %',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                if (hasTemperature)
                  Text(
                    'Température : '
                    '${reading.temperatureCelsius!.toStringAsFixed(1)} °C',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          if ((hasCapacity || hasTemperature) && hasCells)
            const SizedBox(height: 14),
          if (hasCells) ...[
            const Row(
              children: [
                Expanded(
                  child: Text(
                    'Cellule',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Tension',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Résistance',
                    textAlign: TextAlign.end,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const Divider(),
            for (var index = 0; index < rowCount; index++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(child: Text('${index + 1}')),
                    Expanded(
                      child: Text(
                        index < reading.cellVoltages.length
                            ? '${reading.cellVoltages[index].toStringAsFixed(3)} V'
                            : '—',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        index < reading.cellResistances.length
                            ? '${reading.cellResistances[index].toStringAsFixed(1)} mΩ'
                            : '—',
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _batteryCard(
    BuildContext context, {
    required int runIndex,
    required RcRun run,
    required Battery battery,
  }) {
    final reading = _readingForBattery(run, battery.id);

    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.battery_full),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    battery.id,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _isSavingMeasurement
                      ? null
                      : () => _editMeasurements(
                            runIndex: runIndex,
                            battery: battery,
                          ),
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(
                    reading == null
                        ? 'Ajouter les mesures'
                        : 'Modifier les mesures',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(_batterySummary(battery)),
            if (reading != null) _measurementBlock(context, reading),
          ],
        ),
      ),
    );
  }

  Widget _runCard(
    BuildContext context, {
    required RcRun run,
    required int index,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Roulage ${index + 1}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _isSavingSession
                      ? null
                      : () => _editRun(index),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Modifier'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Début : ${_formatDateTime(run.startedAt)}'),
            Text(
              'Durée : ${_durationLabel(run.effectiveDurationMinutes)}',
            ),
            if (run.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Observations : ${run.notes}',
              ),
            ],
            if (run.batteries.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Batteries utilisées',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              for (final battery in run.batteries)
                _batteryCard(
                  context,
                  runIndex: index,
                  run: run,
                  battery: battery,
                ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasClosingInformation = _session.drivingNotes.isNotEmpty ||
        _session.breakages.isNotEmpty ||
        _session.partsReplacedOnSite.isNotEmpty ||
        _session.maintenanceToDo.isNotEmpty ||
        _session.partsToOrder.isNotEmpty ||
        _session.changesBeforeNextSession.isNotEmpty ||
        _session.generalNotes.isNotEmpty;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          return;
        }
      },
      child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Retour',
          onPressed: () => Navigator.of(context).pop(_session),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Détail de la session'),
        actions: [
          TextButton.icon(
            onPressed: _isSavingSession
                ? null
                : _editTerrainInformation,
            icon: const Icon(Icons.edit_note_outlined),
            label: const Text('Modifier la session'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            _session.model.name,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          _infoCard(
            label: 'Ouverture',
            value: _formatDateTime(_session.startedAt),
            icon: Icons.calendar_month_outlined,
          ),
          if (_session.location.isNotEmpty)
            _infoCard(
              label: 'Lieu',
              value: _session.location,
              icon: Icons.location_on_outlined,
            ),
          _infoCard(
            label: 'Roulages',
            value:
                '${_session.runs.length} roulage(s) • ${_durationLabel(_session.totalDurationMinutes)}',
            icon: Icons.timer_outlined,
          ),
          if (_session.runs.isNotEmpty) ...[
            _sectionTitle(context, 'Roulages'),
            for (var index = 0; index < _session.runs.length; index++)
              _runCard(
                context,
                run: _session.runs[index],
                index: index,
              ),
          ],
          if (hasClosingInformation) ...[
            _sectionTitle(context, 'Bilan de la session'),
            if (_session.drivingNotes.isNotEmpty)
              _infoCard(
                label: 'Comportement et réglages constatés',
                value: _session.drivingNotes,
              ),
            if (_session.breakages.isNotEmpty)
              _infoCard(
                label: 'Casses',
                value: _session.breakages,
              ),
            if (_session.partsReplacedOnSite.isNotEmpty)
              _infoCard(
                label: 'Pièces remplacées sur place',
                value: _session.partsReplacedOnSite,
              ),
            if (_session.maintenanceToDo.isNotEmpty)
              _infoCard(
                label: 'Entretien à effectuer',
                value: _session.maintenanceToDo,
              ),
            if (_session.partsToOrder.isNotEmpty)
              _infoCard(
                label: 'Pièces à commander',
                value: _session.partsToOrder,
              ),
            if (_session.changesBeforeNextSession.isNotEmpty)
              _infoCard(
                label: 'Modifications avant la prochaine session',
                value: _session.changesBeforeNextSession,
              ),
            if (_session.generalNotes.isNotEmpty)
              _infoCard(
                label: 'Notes générales',
                value: _session.generalNotes,
              ),
          ],
        ],
      ),
    ),
    );
  }
}

class _EditRunResult {
  const _EditRunResult({
    required this.durationMinutes,
    required this.notes,
  });

  final int durationMinutes;
  final String notes;
}

class _EditRunDialog extends StatefulWidget {
  const _EditRunDialog({
    required this.durationMinutes,
    required this.notes,
  });

  final int durationMinutes;
  final String notes;

  @override
  State<_EditRunDialog> createState() => _EditRunDialogState();
}

class _EditRunDialogState extends State<_EditRunDialog> {
  late final TextEditingController _durationController;
  late final TextEditingController _notesController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _durationController = TextEditingController(
      text: widget.durationMinutes.toString(),
    );
    _notesController = TextEditingController(text: widget.notes);
  }

  @override
  void dispose() {
    _durationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _save() {
    final duration = int.tryParse(_durationController.text.trim());

    if (duration == null || duration <= 0) {
      setState(() {
        _errorText = 'Indique une durée valide.';
      });
      return;
    }

    Navigator.of(context).pop(
      _EditRunResult(
        durationMinutes: duration,
        notes: _notesController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Modifier le roulage'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _durationController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Temps de roulage (minutes)',
                border: const OutlineInputBorder(),
                errorText: _errorText,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Observations',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _EditTerrainResult {
  const _EditTerrainResult({
    required this.drivingNotes,
    required this.breakages,
    required this.partsReplacedOnSite,
    required this.maintenanceToDo,
    required this.partsToOrder,
    required this.changesBeforeNextSession,
    required this.generalNotes,
  });

  final String drivingNotes;
  final String breakages;
  final String partsReplacedOnSite;
  final String maintenanceToDo;
  final String partsToOrder;
  final String changesBeforeNextSession;
  final String generalNotes;
}

class _EditTerrainDialog extends StatefulWidget {
  const _EditTerrainDialog({
    required this.session,
  });

  final RcSession session;

  @override
  State<_EditTerrainDialog> createState() => _EditTerrainDialogState();
}

class _EditTerrainDialogState extends State<_EditTerrainDialog> {
  late final TextEditingController _drivingNotesController;
  late final TextEditingController _breakagesController;
  late final TextEditingController _partsReplacedController;
  late final TextEditingController _maintenanceController;
  late final TextEditingController _partsToOrderController;
  late final TextEditingController _changesController;
  late final TextEditingController _generalNotesController;

  @override
  void initState() {
    super.initState();
    final session = widget.session;
    _drivingNotesController =
        TextEditingController(text: session.drivingNotes);
    _breakagesController =
        TextEditingController(text: session.breakages);
    _partsReplacedController =
        TextEditingController(text: session.partsReplacedOnSite);
    _maintenanceController =
        TextEditingController(text: session.maintenanceToDo);
    _partsToOrderController =
        TextEditingController(text: session.partsToOrder);
    _changesController =
        TextEditingController(text: session.changesBeforeNextSession);
    _generalNotesController =
        TextEditingController(text: session.generalNotes);
  }

  @override
  void dispose() {
    _drivingNotesController.dispose();
    _breakagesController.dispose();
    _partsReplacedController.dispose();
    _maintenanceController.dispose();
    _partsToOrderController.dispose();
    _changesController.dispose();
    _generalNotesController.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      alignLabelWithHint: true,
    );
  }

  void _save() {
    Navigator.of(context).pop(
      _EditTerrainResult(
        drivingNotes: _drivingNotesController.text.trim(),
        breakages: _breakagesController.text.trim(),
        partsReplacedOnSite: _partsReplacedController.text.trim(),
        maintenanceToDo: _maintenanceController.text.trim(),
        partsToOrder: _partsToOrderController.text.trim(),
        changesBeforeNextSession: _changesController.text.trim(),
        generalNotes: _generalNotesController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Modifier les informations terrain'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: _drivingNotesController,
                maxLines: 3,
                decoration:
                    _decoration('Comportement et réglages constatés'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _breakagesController,
                maxLines: 2,
                decoration: _decoration('Casses'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _partsReplacedController,
                maxLines: 2,
                decoration: _decoration('Pièces remplacées sur place'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _maintenanceController,
                maxLines: 2,
                decoration: _decoration('Entretien à effectuer'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _partsToOrderController,
                maxLines: 2,
                decoration: _decoration('Pièces à commander'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _changesController,
                maxLines: 2,
                decoration: _decoration(
                  'Modifications avant la prochaine session',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _generalNotesController,
                maxLines: 3,
                decoration: _decoration('Notes générales'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _EditBatteryMeasurementDialog extends StatefulWidget {
  const _EditBatteryMeasurementDialog({
    required this.battery,
    required this.initialReading,
  });

  final Battery battery;
  final BatteryRunReading? initialReading;

  @override
  State<_EditBatteryMeasurementDialog> createState() =>
      _EditBatteryMeasurementDialogState();
}

class _EditBatteryMeasurementDialogState
    extends State<_EditBatteryMeasurementDialog> {
  late final TextEditingController _capacityController;
  late final TextEditingController _temperatureController;
  late final List<TextEditingController> _voltageControllers;
  late final List<TextEditingController> _resistanceControllers;

  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    final reading = widget.initialReading;
    final cellCount =
        int.tryParse(widget.battery.cells.replaceAll('S', '')) ?? 0;

    _capacityController = TextEditingController(
      text: reading?.remainingCapacityPercent?.toString() ?? '',
    );
    _temperatureController = TextEditingController(
      text: reading?.temperatureCelsius?.toString() ?? '',
    );

    _voltageControllers = List.generate(
      cellCount,
      (index) => TextEditingController(
        text: reading != null && index < reading.cellVoltages.length
            ? reading.cellVoltages[index].toString()
            : '',
      ),
    );

    _resistanceControllers = List.generate(
      cellCount,
      (index) => TextEditingController(
        text: reading != null && index < reading.cellResistances.length
            ? reading.cellResistances[index].toString()
            : '',
      ),
    );
  }

  @override
  void dispose() {
    _capacityController.dispose();
    _temperatureController.dispose();

    for (final controller in _voltageControllers) {
      controller.dispose();
    }

    for (final controller in _resistanceControllers) {
      controller.dispose();
    }

    super.dispose();
  }

  double? _parseDouble(String value) {
    final normalized = value.trim().replaceAll(',', '.');

    if (normalized.isEmpty) {
      return null;
    }

    return double.tryParse(normalized);
  }

  void _save() {
    final capacity = _parseDouble(_capacityController.text);
    final temperature = _parseDouble(_temperatureController.text);

    if (capacity != null && (capacity < 0 || capacity > 100)) {
      setState(() {
        _errorMessage = 'La capacité restante doit être comprise entre 0 et 100 %.';
      });
      return;
    }

    final voltages = <double>[];
    final resistances = <double>[];

    for (var index = 0; index < _voltageControllers.length; index++) {
      final voltage = _parseDouble(_voltageControllers[index].text);
      final resistance = _parseDouble(_resistanceControllers[index].text);

      if (voltage == null || resistance == null) {
        setState(() {
          _errorMessage =
              'Renseigne la tension et la résistance de chaque cellule.';
        });
        return;
      }

      voltages.add(voltage);
      resistances.add(resistance);
    }

    Navigator.of(context).pop(
      BatteryRunReading(
        batteryId: widget.battery.id,
        measuredAt: DateTime.now(),
        remainingCapacityPercent: capacity,
        temperatureCelsius: temperature,
        cellVoltages: List<double>.unmodifiable(voltages),
        cellResistances: List<double>.unmodifiable(resistances),
      ),
    );
  }

  InputDecoration _decoration(
    String label, {
    String? suffix,
  }) {
    return InputDecoration(
      labelText: label,
      suffixText: suffix,
      border: const OutlineInputBorder(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Mesures — ${widget.battery.id}'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _capacityController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: _decoration(
                        'Capacité restante',
                        suffix: '%',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _temperatureController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: _decoration(
                        'Température',
                        suffix: '°C',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Row(
                children: [
                  Expanded(
                    child: Text(
                      'Cellule',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Tension',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Résistance',
                      textAlign: TextAlign.end,
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              for (var index = 0;
                  index < _voltageControllers.length;
                  index++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _voltageControllers[index],
                          keyboardType:
                              const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            suffixText: 'V',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _resistanceControllers[index],
                          keyboardType:
                              const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            suffixText: 'mΩ',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}
