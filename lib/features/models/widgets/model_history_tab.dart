import 'package:flutter/material.dart';

import '../../../models/battery.dart';
import '../../../models/model_history_event.dart';
import '../../../models/rc_model.dart';
import '../../../models/rc_session.dart';
import '../../../services/battery_service.dart';
import '../../../services/model_history_event_service.dart';
import '../../../services/session_service.dart';
import 'model_history_event_form_page.dart';

class ModelHistoryTab extends StatefulWidget {
  const ModelHistoryTab({
    super.key,
    required this.modelId,
    required this.model,
  });

  final String modelId;
  final RcModel model;

  @override
  State<ModelHistoryTab> createState() => _ModelHistoryTabState();
}

class _ModelHistoryTabState extends State<ModelHistoryTab> {
  List<RcSession> _sessions = [];
  List<ModelHistoryEvent> _events = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final batteries = await BatteryService.getBatteries();

      final results = await Future.wait([
        SessionService.getSessions(
          models: [widget.model],
          batteries: batteries,
        ),
        ModelHistoryEventService.getEvents(widget.modelId),
      ]);

      final sessions =
          (results[0] as List<RcSession>)
              .where((session) => session.isClosed)
              .toList(growable: false)
            ..sort(
              (first, second) => second.startedAt.compareTo(first.startedAt),
            );

      final events = results[1] as List<ModelHistoryEvent>;

      if (!mounted) {
        return;
      }

      setState(() {
        _sessions = sessions;
        _events = events;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = 'Impossible de charger l’historique du modèle.\n$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  int get _totalRuns {
    return _sessions.fold<int>(
      0,
      (total, session) => total + session.runs.length,
    );
  }

  int get _totalDurationMinutes {
    final sessionDuration = _sessions.fold<int>(
      0,
      (total, session) => total + session.totalDurationMinutes,
    );

    final manualDuration = _events.fold<int>(
      0,
      (total, event) => total + (event.durationMinutes ?? 0),
    );

    return sessionDuration + manualDuration;
  }

  List<_TimelineItem> get _timelineItems {
    final items = <_TimelineItem>[
      for (final session in _sessions) _TimelineItem.session(session),
      for (final event in _events) _TimelineItem.event(event),
    ];

    final acquisitionDate = widget.model.acquisitionDate;
    if (acquisitionDate != null) {
      items.add(
        _TimelineItem.acquisition(
          DateTime(
            acquisitionDate.year,
            acquisitionDate.month,
            acquisitionDate.day,
          ),
        ),
      );
    }

    items.sort((first, second) => second.date.compareTo(first.date));

    return items;
  }

  Future<void> _addEvent() async {
    final event = await Navigator.push<ModelHistoryEvent>(
      context,
      MaterialPageRoute(
        builder: (_) => ModelHistoryEventFormPage(
          modelId: widget.modelId,
          model: widget.model,
        ),
      ),
    );

    if (event == null || !mounted) {
      return;
    }

    try {
      await ModelHistoryEventService.createEvent(event);
      await _loadHistory();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Événement ajouté à l’historique')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible d’ajouter l’événement : $error')),
      );
    }
  }

  Future<void> _editEvent(ModelHistoryEvent event) async {
    final edited = await Navigator.push<ModelHistoryEvent>(
      context,
      MaterialPageRoute(
        builder: (_) => ModelHistoryEventFormPage(
          modelId: widget.modelId,
          model: widget.model,
          existingEvent: event,
        ),
      ),
    );

    if (edited == null || !mounted) {
      return;
    }

    try {
      await ModelHistoryEventService.updateEvent(edited);
      await _loadHistory();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Événement modifié')));
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible de modifier l’événement : $error')),
      );
    }
  }

  Future<void> _deleteEvent(ModelHistoryEvent event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Supprimer l’événement'),
          content: Text('Veux-tu vraiment supprimer « ${event.title} » ?'),
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

    if (confirmed != true) {
      return;
    }

    try {
      await ModelHistoryEventService.deleteEvent(event.id);
      await _loadHistory();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Événement supprimé')));
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Impossible de supprimer l’événement : $error')),
      );
    }
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year.toString();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '$day/$month/$year à $hour:$minute';
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day/$month/${local.year}';
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

  String _batteryType(Battery battery) {
    return '${battery.technology} ${battery.cells} '
        '${battery.capacity} mAh ${battery.cRate}C';
  }

  IconData _eventIcon(String type) {
    return switch (type) {
      'Session' => Icons.sports_motorsports_outlined,
      'Entretien' => Icons.handyman_outlined,
      'Réparation' => Icons.build_outlined,
      'Modification' => Icons.tune,
      _ => Icons.event_note_outlined,
    };
  }

  Widget _summaryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 680;

            final items = [
              _SummaryValue(
                icon: Icons.calendar_month_outlined,
                label: 'Sessions',
                value: _sessions.length.toString(),
              ),
              _SummaryValue(
                icon: Icons.handyman_outlined,
                label: 'Maintenance',
                value: _events.length.toString(),
              ),
              _SummaryValue(
                icon: Icons.sports_motorsports_outlined,
                label: 'Nombre de roulages',
                value: _totalRuns.toString(),
              ),
              _SummaryValue(
                icon: Icons.timer_outlined,
                label: 'Temps total',
                value: _durationLabel(_totalDurationMinutes),
              ),
            ];

            if (compact) {
              return Column(
                children: [
                  for (var index = 0; index < items.length; index++) ...[
                    items[index],
                    if (index < items.length - 1) const Divider(height: 24),
                  ],
                ],
              );
            }

            return Row(
              children: [
                for (var index = 0; index < items.length; index++) ...[
                  Expanded(child: items[index]),
                  if (index < items.length - 1)
                    const VerticalDivider(width: 28),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _automaticLine({
    required String label,
    required String value,
    IconData? icon,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[Icon(icon, size: 19), const SizedBox(width: 8)],
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(child: Text(value, textAlign: TextAlign.end)),
        ],
      ),
    );
  }

  Widget _optionalSection({
    required String title,
    required String value,
    required IconData icon,
  }) {
    if (value.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                  Text(value.trim()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _runCard(RcRun run, int index) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Roulage ${index + 1}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          _automaticLine(
            label: 'Durée',
            value: _durationLabel(run.effectiveDurationMinutes),
            icon: Icons.timer_outlined,
          ),
          if (run.batteries.isEmpty)
            _automaticLine(
              label: 'Batterie',
              value: 'Non renseignée',
              icon: Icons.battery_unknown,
            )
          else
            for (
              var batteryIndex = 0;
              batteryIndex < run.batteries.length;
              batteryIndex++
            ) ...[
              if (batteryIndex > 0) const Divider(height: 16),
              _automaticLine(
                label: run.batteries.length == 1
                    ? 'Batterie'
                    : 'Batterie ${batteryIndex + 1}',
                value: _batteryType(run.batteries[batteryIndex]),
                icon: Icons.battery_charging_full,
              ),
              _automaticLine(
                label: 'ID',
                value: run.batteries[batteryIndex].id,
                icon: Icons.qr_code_2,
              ),
            ],
        ],
      ),
    );
  }

  Widget _sessionCard(RcSession session) {
    final location = session.location.trim().isEmpty
        ? 'Lieu non renseigné'
        : session.location.trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: const Icon(Icons.sports_motorsports_outlined),
        title: Text(
          'Session — ${_formatDateTime(session.startedAt)}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '$location • ${_durationLabel(session.totalDurationMinutes)} • '
          '${session.runs.length} roulage(s)',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const SizedBox(height: 8),
          _automaticLine(
            label: 'Date et heure',
            value: _formatDateTime(session.startedAt),
            icon: Icons.calendar_month_outlined,
          ),
          _automaticLine(
            label: 'Lieu',
            value: location,
            icon: Icons.location_on_outlined,
          ),
          _automaticLine(
            label: 'Durée totale',
            value: _durationLabel(session.totalDurationMinutes),
            icon: Icons.timer_outlined,
          ),
          _automaticLine(
            label: 'Nombre de roulages',
            value: session.runs.length.toString(),
            icon: Icons.sports_motorsports_outlined,
          ),
          const SizedBox(height: 10),
          for (var index = 0; index < session.runs.length; index++)
            _runCard(session.runs[index], index),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.tune, size: 22),
                    SizedBox(width: 10),
                    Text(
                      'Comportement et réglages constatés',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  session.drivingNotes.trim().isEmpty
                      ? 'RAS'
                      : session.drivingNotes.trim(),
                ),
              ],
            ),
          ),
          _optionalSection(
            title: 'Casses',
            value: session.breakages,
            icon: Icons.warning_amber_outlined,
          ),
          _optionalSection(
            title: 'Pièces remplacées sur place',
            value: session.partsReplacedOnSite,
            icon: Icons.build_outlined,
          ),
          _optionalSection(
            title: 'Entretien à effectuer',
            value: session.maintenanceToDo,
            icon: Icons.handyman_outlined,
          ),
          _optionalSection(
            title: 'Pièces à commander',
            value: session.partsToOrder,
            icon: Icons.shopping_cart_outlined,
          ),
          _optionalSection(
            title: 'Modifications avant prochaine session',
            value: session.changesBeforeNextSession,
            icon: Icons.tune,
          ),
          _optionalSection(
            title: 'Notes générales',
            value: session.generalNotes,
            icon: Icons.notes_outlined,
          ),
        ],
      ),
    );
  }

  Widget _manualEventCard(ModelHistoryEvent event) {
    final details = <String>[
      event.eventType,
      if (event.location.trim().isNotEmpty) event.location.trim(),
      if (event.durationMinutes != null) _durationLabel(event.durationMinutes!),
      if (event.cost != null)
        '${event.cost!.toStringAsFixed(2).replaceAll('.', ',')} €',
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: ExpansionTile(
        leading: Icon(_eventIcon(event.eventType)),
        title: Text(
          event.title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${_formatDateTime(event.eventDate)} • ${details.join(' • ')}',
        ),
        trailing: PopupMenuButton<String>(
          tooltip: 'Options',
          onSelected: (value) {
            if (value == 'edit') {
              _editEvent(event);
            } else if (value == 'delete') {
              _deleteEvent(event);
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
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const SizedBox(height: 8),
          _automaticLine(
            label: 'Type',
            value: event.eventType,
            icon: _eventIcon(event.eventType),
          ),
          _automaticLine(
            label: 'Date',
            value: _formatDateTime(event.eventDate),
            icon: Icons.calendar_month_outlined,
          ),
          if (event.location.trim().isNotEmpty)
            _automaticLine(
              label: 'Lieu',
              value: event.location.trim(),
              icon: Icons.location_on_outlined,
            ),
          if (event.durationMinutes != null)
            _automaticLine(
              label: 'Durée',
              value: _durationLabel(event.durationMinutes!),
              icon: Icons.timer_outlined,
            ),
          if (event.cost != null)
            _automaticLine(
              label: 'Coût',
              value: '${event.cost!.toStringAsFixed(2).replaceAll('.', ',')} €',
              icon: Icons.euro,
            ),
          _optionalSection(
            title: 'Description',
            value: event.description,
            icon: Icons.notes_outlined,
          ),
        ],
      ),
    );
  }

  Widget _acquisitionCard(DateTime date) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: ListTile(
        leading: const Icon(Icons.shopping_bag_outlined),
        title: const Text(
          'Acquisition du modèle',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${_formatDate(date)} • ${widget.model.formattedAcquisition}',
        ),
      ),
    );
  }

  Widget _timelineCard(_TimelineItem item) {
    if (item.session != null) {
      return _sessionCard(item.session!);
    }

    if (item.event != null) {
      return _manualEventCard(item.event!);
    }

    return _acquisitionCard(item.date);
  }

  @override
  Widget build(BuildContext context) {
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
              const Icon(Icons.error_outline, size: 54),
              const SizedBox(height: 14),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _loadHistory,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    final timeline = _timelineItems;

    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _summaryCard(),
          const SizedBox(height: 18),
          Text(
            'Historique du modèle',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          if (timeline.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(22),
                child: Column(
                  children: [
                    Icon(Icons.history_toggle_off, size: 56),
                    SizedBox(height: 12),
                    Text(
                      'Aucun événement enregistré pour ce modèle.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            ...timeline.map(_timelineCard),
        ],
      ),
    );
  }
}

class _TimelineItem {
  const _TimelineItem._({required this.date, this.session, this.event});

  factory _TimelineItem.session(RcSession session) {
    return _TimelineItem._(date: session.startedAt, session: session);
  }

  factory _TimelineItem.event(ModelHistoryEvent event) {
    return _TimelineItem._(date: event.eventDate, event: event);
  }

  factory _TimelineItem.acquisition(DateTime date) {
    return _TimelineItem._(date: date);
  }

  final DateTime date;
  final RcSession? session;
  final ModelHistoryEvent? event;
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 30, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
