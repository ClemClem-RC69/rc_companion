import 'package:flutter/material.dart';

import '../../../models/battery.dart';
import '../../../models/rc_model.dart';
import '../../../models/rc_session.dart';
import '../../../services/battery_service.dart';
import '../../../services/session_service.dart';
import '../../../services/supabase_service.dart';

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
  List<_ModelMaintenanceRecord> _maintenances = [];

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
      final user = SupabaseService.client.auth.currentUser;

      if (user == null) {
        throw StateError('Aucun utilisateur connecté.');
      }

      // Le recalcul à l’ouverture de l’historique garantit qu’une session
      // ajoutée ou modifiée rétroactivement est bien prise en compte.
      await _recalculateRevisionCounters(user.id);

      final batteriesFuture = BatteryService.getBatteries();
      final maintenanceFuture = SupabaseService.client
          .from('maintenance_records')
          .select()
          .eq('user_id', user.id)
          .eq('model_id', widget.modelId)
          .order('maintenance_date', ascending: false);

      final batteries = await batteriesFuture;

      final sessions =
          (await SessionService.getSessions(
            models: [widget.model],
            batteries: batteries,
          )).where((session) => session.isClosed).toList(growable: false)..sort(
            (first, second) => second.startedAt.compareTo(first.startedAt),
          );

      final rawMaintenances = await maintenanceFuture;
      final maintenances = rawMaintenances
          .map(
            (raw) => _ModelMaintenanceRecord.fromMap(
              Map<String, dynamic>.from(raw as Map),
            ),
          )
          .toList(growable: false);

      if (!mounted) {
        return;
      }

      setState(() {
        _sessions = sessions;
        _maintenances = maintenances;
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

  Future<void> _recalculateRevisionCounters(String userId) async {
    final revisionRows = await SupabaseService.client
        .from('maintenance_records')
        .select('id, maintenance_date')
        .eq('user_id', userId)
        .eq('model_id', widget.modelId)
        .eq('record_type', 'REVISION')
        .order('maintenance_date');

    if (revisionRows.isEmpty) {
      return;
    }

    final sessionRows = await SupabaseService.client
        .from('rc_sessions')
        .select('''
          id,
          started_at,
          session_runs (
            started_at,
            ended_at,
            duration_minutes
          )
        ''')
        .eq('user_id', userId)
        .eq('model_id', widget.modelId)
        .order('started_at');

    final runs = <_HistoryRunStat>[];

    for (final rawSession in sessionRows) {
      final session = Map<String, dynamic>.from(rawSession as Map);
      final rawRuns = session['session_runs'] as List<dynamic>? ?? const [];

      for (final rawRun in rawRuns) {
        final run = Map<String, dynamic>.from(rawRun as Map);
        final startedAt = DateTime.tryParse(
          run['started_at']?.toString() ?? '',
        )?.toLocal();

        if (startedAt == null) {
          continue;
        }

        int? durationMinutes = (run['duration_minutes'] as num?)?.toInt();

        if (durationMinutes == null) {
          final endedAt = DateTime.tryParse(
            run['ended_at']?.toString() ?? '',
          )?.toLocal();

          if (endedAt != null) {
            durationMinutes = endedAt.difference(startedAt).inMinutes;
          }
        }

        runs.add(
          _HistoryRunStat(
            startedAt: startedAt,
            durationMinutes: durationMinutes,
          ),
        );
      }
    }

    DateTime? previousRevisionDate;

    for (final rawRevision in revisionRows) {
      final revision = Map<String, dynamic>.from(rawRevision as Map);
      final revisionDate = DateTime.parse(
        revision['maintenance_date'].toString(),
      ).toLocal();

      final eligibleRuns = runs
          .where((run) {
            final afterPrevious =
                previousRevisionDate == null ||
                run.startedAt.isAfter(previousRevisionDate);
            final beforeOrAtRevision = !run.startedAt.isAfter(revisionDate);
            return afterPrevious && beforeOrAtRevision;
          })
          .toList(growable: false);

      final packs = eligibleRuns.length;
      final knownMinutes = eligibleRuns
          .where((run) => run.durationMinutes != null)
          .fold<int>(0, (total, run) => total + run.durationMinutes!);

      await SupabaseService.client
          .from('maintenance_records')
          .update({
            'packs_since_last_revision': packs,
            'runtime_minutes_since_last_revision': knownMinutes,
          })
          .eq('id', revision['id'])
          .eq('user_id', userId);

      previousRevisionDate = revisionDate;
    }
  }

  int get _totalRuns {
    return _sessions.fold<int>(
      0,
      (total, session) => total + session.runs.length,
    );
  }

  int get _totalPacks {
    // Règle RC Companion : un roulage enregistré correspond à un pack consommé,
    // qu'il utilise une ou deux batteries physiques.
    return _totalRuns;
  }

  int get _totalDurationMinutes {
    return _sessions.fold<int>(
      0,
      (total, session) => total + session.totalDurationMinutes,
    );
  }

  List<_TimelineItem> get _timelineItems {
    final items = <_TimelineItem>[
      for (final session in _sessions) _TimelineItem.session(session),
      for (final maintenance in _maintenances)
        _TimelineItem.maintenance(maintenance),
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

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');

    return '$day/$month/${local.year} à $hour:$minute';
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day/$month/${local.year}';
  }

  String _durationLabel(int? minutes) {
    if (minutes == null) {
      return 'Non calculé';
    }

    if (minutes < 60) {
      return '$minutes min';
    }

    final hours = minutes ~/ 60;
    final remaining = minutes % 60;

    if (remaining == 0) {
      return '${hours}h';
    }

    return '${hours}h ${remaining}min';
  }

  String _batteryType(Battery battery) {
    return '${battery.technology} ${battery.cells} '
        '${battery.capacity} mAh ${battery.cRate}C';
  }

  Widget _summaryCard() {
    final items = [
      _SummaryValue(
        icon: Icons.calendar_month_outlined,
        label: 'Sessions',
        value: _sessions.length.toString(),
      ),
      _SummaryValue(
        icon: Icons.sports_motorsports_outlined,
        label: 'Roulages',
        value: _totalRuns.toString(),
      ),
      _SummaryValue(
        icon: Icons.battery_charging_full,
        label: 'Packs',
        value: _totalPacks.toString(),
      ),
      _SummaryValue(
        icon: Icons.timer_outlined,
        label: 'Temps',
        value: _durationLabel(_totalDurationMinutes),
      ),
      _SummaryValue(
        icon: Icons.handyman_outlined,
        label: 'Maintenance',
        value: _maintenances.length.toString(),
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 680) {
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
                  SelectableText(value.trim()),
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

  Widget _maintenanceCard(_ModelMaintenanceRecord record) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: ExpansionTile(
        leading: Icon(record.icon),
        title: Text(
          record.title.isEmpty ? record.typeLabel : record.title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          '${record.typeLabel} • ${_formatDate(record.date)}'
          '${record.isRevision ? ' • ${record.packsSinceLastRevision ?? 0} pack(s)' : ''}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const SizedBox(height: 8),
          _automaticLine(
            label: 'Type',
            value: record.typeLabel,
            icon: record.icon,
          ),
          _automaticLine(
            label: 'Date',
            value: _formatDate(record.date),
            icon: Icons.calendar_month_outlined,
          ),
          if (record.isRevision) ...[
            const SizedBox(height: 8),
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
                  const Text(
                    'Depuis la révision précédente',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  _automaticLine(
                    label: 'Packs consommés',
                    value: '${record.packsSinceLastRevision ?? 0}',
                    icon: Icons.battery_charging_full,
                  ),
                  _automaticLine(
                    label: 'Temps d’utilisation',
                    value: _durationLabel(
                      record.runtimeMinutesSinceLastRevision,
                    ),
                    icon: Icons.timer_outlined,
                  ),
                ],
              ),
            ),
          ],
          if (record.fluids.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Fluides remplacés',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            for (final entry in record.fluids.entries)
              _automaticLine(
                label: _fluidLabel(entry.key),
                value: '${entry.value} cSt',
                icon: Icons.opacity_outlined,
              ),
          ],
          if (record.setupChanges.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Réglages modifiés',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            for (final change in record.setupChanges)
              _automaticLine(
                label: change['field'] ?? 'Réglage',
                value: change['newValue'] ?? '',
                icon: Icons.tune,
              ),
          ],
          _optionalSection(
            title: record.isRevision ? 'Texte libre' : 'Description',
            value: record.notes,
            icon: Icons.notes_outlined,
          ),
        ],
      ),
    );
  }

  String _fluidLabel(String key) {
    switch (key) {
      case 'diffFront':
        return 'Différentiel avant';
      case 'diffCenter':
        return 'Différentiel central';
      case 'diffRear':
        return 'Différentiel arrière';
      case 'shockFront':
        return 'Amortisseurs avant';
      case 'shockRear':
        return 'Amortisseurs arrière';
      default:
        return key;
    }
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

    if (item.maintenance != null) {
      return _maintenanceCard(item.maintenance!);
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
  const _TimelineItem._({required this.date, this.session, this.maintenance});

  factory _TimelineItem.session(RcSession session) {
    return _TimelineItem._(date: session.startedAt, session: session);
  }

  factory _TimelineItem.maintenance(_ModelMaintenanceRecord maintenance) {
    return _TimelineItem._(date: maintenance.date, maintenance: maintenance);
  }

  factory _TimelineItem.acquisition(DateTime date) {
    return _TimelineItem._(date: date);
  }

  final DateTime date;
  final RcSession? session;
  final _ModelMaintenanceRecord? maintenance;
}

class _ModelMaintenanceRecord {
  const _ModelMaintenanceRecord({
    required this.id,
    required this.date,
    required this.recordType,
    required this.title,
    required this.notes,
    required this.data,
    this.packsSinceLastRevision,
    this.runtimeMinutesSinceLastRevision,
  });

  final String id;
  final DateTime date;
  final String recordType;
  final String title;
  final String notes;
  final Map<String, dynamic> data;
  final int? packsSinceLastRevision;
  final int? runtimeMinutesSinceLastRevision;

  bool get isRevision => recordType == 'REVISION';

  String get typeLabel {
    switch (recordType) {
      case 'REPARATION':
        return 'Réparation';
      case 'MODIFICATION':
        return 'Modification';
      case 'REVISION':
      default:
        return 'Révision';
    }
  }

  IconData get icon {
    switch (recordType) {
      case 'REPARATION':
        return Icons.handyman_outlined;
      case 'MODIFICATION':
        return Icons.construction_outlined;
      case 'REVISION':
      default:
        return Icons.tune;
    }
  }

  Map<String, String> get fluids {
    final raw = data['fluids'];

    if (raw is! Map) {
      return const {};
    }

    return raw.map((key, value) => MapEntry(key.toString(), value.toString()));
  }

  List<Map<String, String>> get setupChanges {
    final raw = data['setupChanges'];

    if (raw is! List) {
      return const [];
    }

    return raw
        .whereType<Map>()
        .map((item) {
          return item.map(
            (key, value) => MapEntry(key.toString(), value.toString()),
          );
        })
        .toList(growable: false);
  }

  factory _ModelMaintenanceRecord.fromMap(Map<String, dynamic> row) {
    final rawData = row['data'];

    return _ModelMaintenanceRecord(
      id: row['id'] as String,
      date: DateTime.parse(row['maintenance_date'].toString()).toLocal(),
      recordType: row['record_type'] as String? ?? 'REVISION',
      title: row['title'] as String? ?? '',
      notes: row['notes'] as String? ?? '',
      data: rawData is Map
          ? Map<String, dynamic>.from(rawData)
          : const <String, dynamic>{},
      packsSinceLastRevision: (row['packs_since_last_revision'] as num?)
          ?.toInt(),
      runtimeMinutesSinceLastRevision:
          (row['runtime_minutes_since_last_revision'] as num?)?.toInt(),
    );
  }
}

class _HistoryRunStat {
  const _HistoryRunStat({
    required this.startedAt,
    required this.durationMinutes,
  });

  final DateTime startedAt;
  final int? durationMinutes;
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
