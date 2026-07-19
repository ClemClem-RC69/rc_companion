import 'package:flutter/material.dart';

import '../../../models/battery.dart';
import '../../../models/rc_model.dart';
import '../../../models/rc_session.dart';
import '../../../services/battery_service.dart';
import '../../../services/session_service.dart';

class ModelHistoryTab extends StatefulWidget {
  const ModelHistoryTab({
    super.key,
    required this.model,
  });

  final RcModel model;

  @override
  State<ModelHistoryTab> createState() => _ModelHistoryTabState();
}

class _ModelHistoryTabState extends State<ModelHistoryTab> {
  List<RcSession> _sessions = [];
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
      final sessions = await SessionService.getSessions(
        models: [widget.model],
        batteries: batteries,
      );

      final closedSessions = sessions
          .where((session) => session.isClosed)
          .toList(growable: false)
        ..sort(
          (first, second) =>
              second.startedAt.compareTo(first.startedAt),
        );

      if (!mounted) {
        return;
      }

      setState(() {
        _sessions = closedSessions;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage =
            'Impossible de charger l’historique du modèle.\n$error';
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
    return _sessions.fold<int>(
      0,
      (total, session) => total + session.totalDurationMinutes,
    );
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
                label: 'Sessions clôturées',
                value: _sessions.length.toString(),
              ),
              _SummaryValue(
                icon: Icons.sports_motorsports_outlined,
                label: 'Nombre de roulages',
                value: _totalRuns.toString(),
              ),
              _SummaryValue(
                icon: Icons.timer_outlined,
                label: 'Temps total de roulage',
                value: _durationLabel(_totalDurationMinutes),
              ),
            ];

            if (compact) {
              return Column(
                children: [
                  for (var index = 0; index < items.length; index++) ...[
                    items[index],
                    if (index < items.length - 1)
                      const Divider(height: 24),
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
          if (icon != null) ...[
            Icon(icon, size: 19),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
            ),
          ),
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
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Roulage ${index + 1}',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
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
            for (var batteryIndex = 0;
                batteryIndex < run.batteries.length;
                batteryIndex++) ...[
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
        leading: const Icon(Icons.history),
        title: Text(
          '${_formatDateTime(session.startedAt)} — $location',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${_durationLabel(session.totalDurationMinutes)} • '
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
        ],
      ),
    );
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
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
              ),
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

    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          _summaryCard(),
          const SizedBox(height: 16),
          Text(
            'Historique des sessions',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          if (_sessions.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(22),
                child: Column(
                  children: [
                    Icon(Icons.history_toggle_off, size: 56),
                    SizedBox(height: 12),
                    Text(
                      'Aucune session clôturée pour ce modèle.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            ..._sessions.map(_sessionCard),
        ],
      ),
    );
  }
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
        Icon(
          icon,
          size: 30,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
