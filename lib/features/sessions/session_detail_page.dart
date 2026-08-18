import 'package:flutter/material.dart';

import '../../models/battery.dart';
import '../../models/rc_session.dart';
import '../../services/session_service.dart';

class SessionDetailPage extends StatefulWidget {
  const SessionDetailPage({super.key, required this.session});

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

  BatteryRunReading? _readingForBattery(RcRun run, String batteryId) {
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
      final updatedRuns = List<RcRun>.from(_session.runs);
      final updatedReadings = List<BatteryRunReading>.from(
        updatedRuns[runIndex].readings,
      );

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

      final updatedSession = _session.copyWith(
        runs: List<RcRun>.unmodifiable(updatedRuns),
      );

      final sessionId = updatedSession.id;

      if (sessionId == null || sessionId.trim().isEmpty) {
        throw StateError('Session introuvable');
      }

      await SessionService.updateRunReading(
        sessionId: sessionId,
        modelName: updatedSession.model.name,
        run: updatedRuns[runIndex],
        reading: updatedReading,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _session = updatedSession;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Mesures enregistrées dans la session et l’historique batterie.',
          ),
        ),
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

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Session mise à jour.')));
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
      _session.copyWith(runs: List<RcRun>.unmodifiable(updatedRuns)),
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

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
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

  Widget _measurementBlock(BuildContext context, BatteryRunReading reading) {
    final hasCapacity = reading.remainingCapacityPercent != null;
    final hasCells = reading.cellVoltages.isNotEmpty;

    if (!hasCapacity && !hasCells) {
      return const SizedBox.shrink();
    }

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
          if (hasCapacity)
            Text(
              'Capacité restante : '
              '${reading.remainingCapacityPercent!.toStringAsFixed(0)} %',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          if (reading.temperatureCelsius != null) ...[
            if (hasCapacity) const SizedBox(height: 8),
            Text(
              'Température : ${reading.temperatureCelsius} °C',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
          if ((hasCapacity || reading.temperatureCelsius != null) && hasCells)
            const SizedBox(height: 8),
          if (hasCells)
            Text(
              'Tension totale : '
              '${reading.totalVoltage.toStringAsFixed(3)} V',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          if (hasCells) ...[
            const SizedBox(height: 14),
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
                    textAlign: TextAlign.end,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const Divider(),
            for (var index = 0; index < reading.cellVoltages.length; index++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(child: Text('${index + 1}')),
                    Expanded(
                      child: Text(
                        '${reading.cellVoltages[index].toStringAsFixed(3)} V',
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
                  onPressed: _isSavingSession ? null : () => _editRun(index),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Modifier'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Début : ${_formatDateTime(run.startedAt)}'),
            Text('Durée : ${_durationLabel(run.effectiveDurationMinutes)}'),
            if (run.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Observations : ${run.notes}'),
            ],
            const SizedBox(height: 12),
            Text(
              'Nombre de batteries utilisées : ${run.batteries.length + run.historicalBatteries.length}',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            if (run.batteries.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Batteries utilisées',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              for (final battery in run.batteries)
                _batteryCard(
                  context,
                  runIndex: index,
                  run: run,
                  battery: battery,
                ),
            ],
            if (run.historicalBatteries.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Anciennes batteries',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              for (
                var historicalIndex = 0;
                historicalIndex < run.historicalBatteries.length;
                historicalIndex++
              )
                Card(
                  margin: const EdgeInsets.only(top: 10),
                  child: ListTile(
                    leading: const Icon(Icons.battery_unknown),
                    title: Text(
                      run.historicalBatteries.length == 1
                          ? 'Ancienne batterie'
                          : 'Ancienne batterie ${historicalIndex + 1}',
                    ),
                    subtitle: Text(
                      run.historicalBatteries[historicalIndex].displayLabel,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasClosingInformation =
        _session.drivingNotes.isNotEmpty ||
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
              onPressed: _isSavingSession ? null : _editTerrainInformation,
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
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
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
              for (var index = _session.runs.length - 1; index >= 0; index--)
                _runCard(context, run: _session.runs[index], index: index),
            ],
            if (hasClosingInformation) ...[
              _sectionTitle(context, 'Bilan de la session'),
              if (_session.drivingNotes.isNotEmpty)
                _infoCard(
                  label: 'Comportement pendant la session',
                  value: _session.drivingNotes,
                ),
              if (_session.breakages.isNotEmpty)
                _infoCard(label: 'Casses', value: _session.breakages),
              if (_session.partsReplacedOnSite.isNotEmpty)
                _infoCard(
                  label: 'Maintenance / réglages sur place',
                  value: _session.partsReplacedOnSite,
                ),
              if (_session.maintenanceToDo.isNotEmpty)
                _infoCard(
                  label:
                      'Entretien / réglages / modifications avant prochaine session',
                  value: _session.maintenanceToDo,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EditRunResult {
  const _EditRunResult({required this.durationMinutes, required this.notes});

  final int durationMinutes;
  final String notes;
}

class _EditRunDialog extends StatefulWidget {
  const _EditRunDialog({required this.durationMinutes, required this.notes});

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
        FilledButton(onPressed: _save, child: const Text('Enregistrer')),
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
  const _EditTerrainDialog({required this.session});

  final RcSession session;

  @override
  State<_EditTerrainDialog> createState() => _EditTerrainDialogState();
}

class _EditTerrainDialogState extends State<_EditTerrainDialog> {
  late final TextEditingController _drivingNotesController;
  late final TextEditingController _breakagesController;
  late final TextEditingController _partsReplacedController;
  late final TextEditingController _maintenanceController;

  @override
  void initState() {
    super.initState();
    final session = widget.session;
    _drivingNotesController = TextEditingController(text: session.drivingNotes);
    _breakagesController = TextEditingController(text: session.breakages);
    _partsReplacedController = TextEditingController(
      text: session.partsReplacedOnSite,
    );
    _maintenanceController = TextEditingController(
      text: session.maintenanceToDo,
    );
  }

  @override
  void dispose() {
    _drivingNotesController.dispose();
    _breakagesController.dispose();
    _partsReplacedController.dispose();
    _maintenanceController.dispose();
    super.dispose();
  }

  void _save() {
    Navigator.of(context).pop(
      _EditTerrainResult(
        drivingNotes: _drivingNotesController.text.trim(),
        breakages: _breakagesController.text.trim(),
        partsReplacedOnSite: _partsReplacedController.text.trim(),
        maintenanceToDo: _maintenanceController.text.trim(),
        partsToOrder: widget.session.partsToOrder,
        changesBeforeNextSession: widget.session.changesBeforeNextSession,
        generalNotes: widget.session.generalNotes,
      ),
    );
  }

  Future<void> _openLargeEditor(
    TextEditingController controller,
    String label,
  ) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            _TerrainTextEditorPage(title: label, initialText: controller.text),
      ),
    );

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      controller.text = result;
      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
    });
  }

  Widget _compactField(TextEditingController controller, String label) {
    final text = controller.text.trim();
    final hasText = text.isNotEmpty;
    final normalizedText = text.replaceAll(RegExp(r'\s+'), ' ');
    final hasMoreContent = text.contains('\n') || normalizedText.length > 70;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openLargeEditor(controller, label),
        child: Container(
          height: 92,
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).colorScheme.outline),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.open_in_full, size: 18),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Text(
                  hasText ? text : 'Toucher pour saisir…',
                  maxLines: hasMoreContent ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: hasText
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (hasMoreContent)
                Row(
                  children: [
                    Icon(
                      Icons.more_horiz,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Suite…',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = (screenSize.width - 24).clamp(320.0, 980.0);

    return AlertDialog(
      insetPadding: const EdgeInsets.all(12),
      title: const Text('Modifier les informations terrain'),
      content: SizedBox(
        width: dialogWidth,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 760 ? 3 : 2;
            final spacing = 10.0;
            final itemWidth =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;

            final fields = <Widget>[
              _compactField(
                _drivingNotesController,
                'Comportement pendant la session',
              ),
              _compactField(_breakagesController, 'Casses'),
              _compactField(
                _partsReplacedController,
                'Maintenance / réglages sur place',
              ),
              _compactField(
                _maintenanceController,
                'Entretien / réglages / modifications avant prochaine session',
              ),
            ];

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final field in fields)
                  SizedBox(width: itemWidth, child: field),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _save, child: const Text('Enregistrer')),
      ],
    );
  }
}

class _TerrainTextEditorPage extends StatefulWidget {
  const _TerrainTextEditorPage({
    required this.title,
    required this.initialText,
  });

  final String title;
  final String initialText;

  @override
  State<_TerrainTextEditorPage> createState() => _TerrainTextEditorPageState();
}

class _TerrainTextEditorPageState extends State<_TerrainTextEditorPage> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  late bool _isEditing;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _focusNode = FocusNode();
    _isEditing = widget.initialText.trim().isEmpty;

    if (_isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _startEditing() {
    setState(() {
      _isEditing = true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
        _controller.selection = TextSelection.collapsed(
          offset: _controller.text.length,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: _isEditing ? 'Annuler les modifications' : 'Fermer',
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(_isEditing ? Icons.close : Icons.arrow_back),
        ),
        title: Text(widget.title),
        actions: [
          if (_isEditing)
            TextButton.icon(
              onPressed: () => Navigator.of(context).pop(_controller.text),
              icon: const Icon(Icons.check),
              label: const Text('Valider'),
            )
          else
            TextButton.icon(
              onPressed: _startEditing,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Modifier'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _isEditing
              ? TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  expands: true,
                  minLines: null,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    hintText: 'Saisir les informations…',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                )
              : Container(
                  width: double.infinity,
                  height: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _controller.text.trim().isEmpty
                          ? 'Aucune information renseignée.'
                          : _controller.text,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ),
        ),
      ),
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
  }

  @override
  void dispose() {
    _capacityController.dispose();
    _temperatureController.dispose();

    for (final controller in _voltageControllers) {
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

    if (capacity == null || capacity < 0 || capacity > 100) {
      setState(() {
        _errorMessage =
            'La capacité restante doit être comprise entre 0 et 100 %.';
      });
      return;
    }

    final temperature = _parseDouble(_temperatureController.text);

    final voltages = <double>[];

    for (var index = 0; index < _voltageControllers.length; index++) {
      final voltage = _parseDouble(_voltageControllers[index].text);

      if (voltage == null || voltage <= 0) {
        setState(() {
          _errorMessage = 'Renseigne la tension de chaque cellule.';
        });
        return;
      }

      voltages.add(voltage);
    }

    Navigator.of(context).pop(
      BatteryRunReading(
        batteryId: widget.battery.id,
        measuredAt: widget.initialReading?.measuredAt ?? DateTime.now(),
        remainingCapacityPercent: capacity,
        temperatureCelsius: temperature,
        cellVoltages: List<double>.unmodifiable(voltages),
      ),
    );
  }

  InputDecoration _decoration(String label, {String? suffix}) {
    return InputDecoration(
      labelText: label,
      suffixText: suffix,
      border: const OutlineInputBorder(),
    );
  }

  double get _totalVoltage {
    return _voltageControllers.fold<double>(0, (total, controller) {
      return total + (_parseDouble(controller.text) ?? 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = (screenSize.width - 24).clamp(320.0, 980.0);

    return AlertDialog(
      insetPadding: const EdgeInsets.all(12),
      title: Text('Relevé fin de roulage — ${widget.battery.id}'),
      content: SizedBox(
        width: dialogWidth,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 820
                ? 4
                : constraints.maxWidth >= 520
                ? 3
                : 2;
            final spacing = 8.0;
            final itemWidth =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _capacityController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: _decoration(
                          'Capacité restante',
                          suffix: '%',
                        ).copyWith(isDense: true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _temperatureController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: _decoration(
                          'Température (facultative)',
                          suffix: '°C',
                        ).copyWith(isDense: true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Tension totale automatique',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        child: Text(
                          '${_totalVoltage.toStringAsFixed(3)} V',
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (
                      var index = 0;
                      index < _voltageControllers.length;
                      index++
                    )
                      SizedBox(
                        width: itemWidth,
                        child: TextField(
                          controller: _voltageControllers[index],
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Cellule ${index + 1}',
                            suffixText: 'V',
                            border: const OutlineInputBorder(),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 11,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _save, child: const Text('Enregistrer')),
      ],
    );
  }
}
