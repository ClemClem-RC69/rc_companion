import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../../models/battery.dart';
import '../../../models/rc_model.dart';
import '../../../models/rc_session.dart';
import '../../../services/battery_service.dart';
import '../../../services/session_local_store.dart';
import '../../../services/session_service.dart';
import '../../../services/maintenance_local_store.dart';
import '../../../services/maintenance_service.dart';
import '../../../services/model_photo_file_store.dart';
import '../../../services/model_local_store.dart';
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
  late RcModel _currentModel;

  bool _isLoading = true;
  String? _errorMessage;
  StreamSubscription<List<RcModel>>? _modelSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _sessionSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _maintenanceSubscription;

  @override
  void initState() {
    super.initState();
    _currentModel = widget.model;
    _startModelLiveUpdates();
    _startSessionLiveUpdates();
    _startMaintenanceLiveUpdates();
    _loadHistory();
  }

  @override
  void dispose() {
    _modelSubscription?.cancel();
    _sessionSubscription?.cancel();
    _maintenanceSubscription?.cancel();
    super.dispose();
  }

  void _startModelLiveUpdates() {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
      return;
    }

    _modelSubscription = ModelLocalStore.watchModels(userId: user.id).listen((
      models,
    ) {
      RcModel? updated;
      for (final model in models) {
        if (model.id?.trim() == widget.modelId) {
          updated = model;
          break;
        }
      }

      if (!mounted || updated == null) {
        return;
      }

      setState(() {
        _currentModel = updated!;
      });

      unawaited(_refreshSessionsFromLocal());
    });
  }

  void _startSessionLiveUpdates() {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
      return;
    }

    _sessionSubscription = SessionLocalStore.watchSessionRows(userId: user.id)
        .listen((_) {
          unawaited(_refreshSessionsFromLocal());
        });
  }

  void _startMaintenanceLiveUpdates() {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
      return;
    }

    _maintenanceSubscription =
        MaintenanceLocalStore.watchRecords(userId: user.id).listen((rows) {
          final maintenances =
              rows
                  .where((row) => row['model_id']?.toString() == widget.modelId)
                  .map(
                    (row) => _ModelMaintenanceRecord.fromMap(
                      Map<String, dynamic>.from(row),
                    ),
                  )
                  .toList(growable: false)
                ..sort((a, b) => b.date.compareTo(a.date));

          if (!mounted) {
            return;
          }

          setState(() {
            _maintenances = maintenances;
          });
        });
  }

  Future<void> _refreshMaintenancesFromLocal() async {
    final rows = await MaintenanceService.getRecords();

    final maintenances =
        rows
            .where((row) => row['model_id']?.toString() == widget.modelId)
            .map(
              (row) => _ModelMaintenanceRecord.fromMap(
                Map<String, dynamic>.from(row),
              ),
            )
            .toList(growable: false)
          ..sort((a, b) => b.date.compareTo(a.date));

    if (!mounted) {
      return;
    }

    setState(() {
      _maintenances = maintenances;
    });
  }

  Future<void> _refreshSessionsFromLocal() async {
    try {
      final batteries = await BatteryService.getCachedBatteries();
      final sessions =
          (await SessionService.getSessions(
            models: [_currentModel],
            batteries: batteries,
          )).where((session) => session.isClosed).toList(growable: false)..sort(
            (first, second) => second.startedAt.compareTo(first.startedAt),
          );

      if (!mounted) {
        return;
      }

      setState(() {
        _sessions = sessions;
      });
    } catch (_) {
      // L'historique déjà affiché reste disponible si une lecture locale échoue.
    }
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

      final batteries = await BatteryService.getCachedBatteries();
      final sessions =
          (await SessionService.getSessions(
            models: [_currentModel],
            batteries: batteries,
          )).where((session) => session.isClosed).toList(growable: false)..sort(
            (first, second) => second.startedAt.compareTo(first.startedAt),
          );

      final maintenanceRows = await MaintenanceService.getRecords();
      final maintenances =
          maintenanceRows
              .where((row) => row['model_id']?.toString() == widget.modelId)
              .map(
                (row) => _ModelMaintenanceRecord.fromMap(
                  Map<String, dynamic>.from(row),
                ),
              )
              .toList(growable: false)
            ..sort((a, b) => b.date.compareTo(a.date));

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

  List<_ModelMaintenanceGroup> get _maintenanceGroups {
    final grouped = <String, List<_ModelMaintenanceRecord>>{};

    for (final maintenance in _maintenances) {
      grouped
          .putIfAbsent(
            maintenance.maintenanceGroupId,
            () => <_ModelMaintenanceRecord>[],
          )
          .add(maintenance);
    }

    final groups = grouped.entries
        .map((entry) {
          final interventions = List<_ModelMaintenanceRecord>.from(entry.value)
            ..sort((a, b) => a.date.compareTo(b.date));
          return _ModelMaintenanceGroup(
            id: entry.key,
            interventions: List<_ModelMaintenanceRecord>.unmodifiable(
              interventions,
            ),
          );
        })
        .toList(growable: false);

    return groups;
  }

  List<_TimelineItem> get _timelineItems {
    final items = <_TimelineItem>[
      for (final session in _sessions) _TimelineItem.session(session),
      for (final maintenanceGroup in _maintenanceGroups)
        _TimelineItem.maintenanceGroup(maintenanceGroup),
    ];

    final acquisitionDate = _currentModel.acquisitionDate;

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

  List<_TimelineItem> get _pdfTimelineItems {
    final items = List<_TimelineItem>.from(_timelineItems);
    items.sort((first, second) => first.date.compareTo(second.date));
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

  bool get _isBoat => _currentModel.category.trim().toLowerCase() == 'bateau';

  String get _runPluralLabel => _isBoat ? 'Navigations' : 'Roulages';

  String _batteryType(Battery battery) {
    final brand = battery.brand.trim();
    final characteristics =
        '${battery.technology} ${battery.cells} ${battery.capacity} mAh ${battery.cRate}C';

    return brand.isEmpty ? characteristics : '$brand - $characteristics';
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
        label: _runPluralLabel,
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
            '${_isBoat ? 'Navigation' : 'Roulage'} ${index + 1}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          _automaticLine(
            label: 'Durée',
            value: _durationLabel(run.effectiveDurationMinutes),
            icon: Icons.timer_outlined,
          ),
          _automaticLine(
            label: 'Nombre de batteries utilisées',
            value: (run.batteries.length + run.historicalBatteries.length)
                .toString(),
            icon: Icons.battery_charging_full,
          ),
          if (run.batteries.isEmpty && run.historicalBatteries.isEmpty)
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
          for (
            var historicalIndex = 0;
            historicalIndex < run.historicalBatteries.length;
            historicalIndex++
          ) ...[
            if (run.batteries.isNotEmpty || historicalIndex > 0)
              const Divider(height: 16),
            _automaticLine(
              label: run.historicalBatteries.length == 1
                  ? 'Ancienne batterie'
                  : 'Ancienne batterie ${historicalIndex + 1}',
              value: run.historicalBatteries[historicalIndex].displayLabel,
              icon: Icons.battery_unknown,
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
    final terrainType = session.terrainType.trim().isEmpty
        ? 'Type de terrain non renseigné'
        : session.terrainType.trim();

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
          '${session.runs.length} ${_isBoat ? 'navigation(s)' : 'roulage(s)'}',
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
            label: 'Type de terrain',
            value: terrainType,
            icon: Icons.landscape_outlined,
          ),
          _automaticLine(
            label: 'Durée totale',
            value: _durationLabel(session.totalDurationMinutes),
            icon: Icons.timer_outlined,
          ),
          _automaticLine(
            label: _isBoat ? 'Nombre de navigations' : 'Nombre de roulages',
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

  Widget _maintenanceGroupCard(_ModelMaintenanceGroup group) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: ExpansionTile(
        leading: const Icon(Icons.build_circle_outlined),
        title: Text(
          'Maintenance — ${_formatDate(group.date)}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text('${group.interventions.length} intervention(s)'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          for (var index = 0; index < group.interventions.length; index++) ...[
            if (index > 0) const Divider(height: 22),
            Builder(
              builder: (context) {
                final record = group.interventions[index];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _automaticLine(
                      label: record.typeLabel,
                      value: record.title.trim().isEmpty
                          ? record.typeLabel
                          : record.title.trim(),
                      icon: record.icon,
                    ),
                    if (record.isRevision) ...[
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
                    if (record.fluids.isNotEmpty)
                      for (final entry in record.fluids.entries)
                        _automaticLine(
                          label: _fluidLabel(entry.key),
                          value: '${entry.value} cSt',
                          icon: Icons.opacity_outlined,
                        ),
                    if (record.setupChanges.isNotEmpty)
                      for (final change in record.setupChanges)
                        _automaticLine(
                          label: change['field'] ?? 'Réglage',
                          value: change['newValue'] ?? '',
                          icon: Icons.tune,
                        ),
                    if (record.notes.trim().isNotEmpty)
                      _optionalSection(
                        title: record.isRevision
                            ? 'Texte libre'
                            : 'Description',
                        value: record.notes,
                        icon: Icons.notes_outlined,
                      ),
                  ],
                );
              },
            ),
          ],
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
          '${_formatDate(date)} • ${_currentModel.formattedAcquisition}',
        ),
      ),
    );
  }

  Widget _timelineCard(_TimelineItem item) {
    if (item.session != null) {
      return _sessionCard(item.session!);
    }

    if (item.maintenanceGroup != null) {
      return _maintenanceGroupCard(item.maintenanceGroup!);
    }

    return _acquisitionCard(item.date);
  }

  String _pdfSafeText(String value) {
    return value
        .replaceAll('•', ' - ')
        .replaceAll('—', ' - ')
        .replaceAll('–', ' - ')
        .replaceAll('\u00A0', ' ');
  }

  Future<Uint8List> _buildPdf(PdfPageFormat format) async {
    pw.ImageProvider? modelImage;

    final localPhotoPath = _currentModel.photoLocalPath?.trim() ?? '';
    if (localPhotoPath.isNotEmpty) {
      try {
        final bytes = await ModelPhotoFileStore.readBytes(localPhotoPath);
        if (bytes != null && bytes.isNotEmpty) {
          modelImage = pw.MemoryImage(bytes);
        }
      } catch (_) {
        modelImage = null;
      }
    }

    if (modelImage == null) {
      final photoUrl = _currentModel.photoUrl?.trim() ?? '';
      if (photoUrl.isNotEmpty) {
        try {
          modelImage = await networkImage(photoUrl);
        } catch (_) {
          modelImage = null;
        }
      }
    }

    final document = pw.Document(
      title: 'Historique ${_currentModel.name}',
      author: 'RC Companion',
      subject: 'Carnet de vie du modèle',
      creator: 'RC Companion',
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(20, 18, 20, 22),
        footer: (context) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 5),
          padding: const pw.EdgeInsets.only(top: 4),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              top: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
            ),
          ),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  'Document généré par RC Companion - Données indicatives, '
                  "ne remplace pas une vérification technique ni l'entretien régulier.",
                  maxLines: 1,
                  style: const pw.TextStyle(
                    fontSize: 6.8,
                    color: PdfColors.grey700,
                  ),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Text(
                'Page ${context.pageNumber}/${context.pagesCount}',
                style: const pw.TextStyle(
                  fontSize: 7,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
        ),
        build: (context) => [
          _pdfVisualHeader(modelImage),
          pw.SizedBox(height: 10),
          _pdfVisualSummary(),
          pw.SizedBox(height: 13),
          _pdfLineSectionTitle('Informations du modèle'),
          _pdfCompactModelInformation(),
          pw.SizedBox(height: 12),
          _pdfLineSectionTitle('Statistiques détaillées'),
          _pdfDetailedStatistics(),
          pw.SizedBox(height: 13),
          _pdfLineSectionTitle('Historique (du plus ancien au plus récent)'),
          _pdfHistoryTable(),
        ],
      ),
    );

    return document.save();
  }

  pw.Widget _pdfVisualHeader(pw.ImageProvider? modelImage) {
    final subtitleValues = <String>[
      _currentModel.brand.trim(),
      _currentModel.category.trim(),
      _currentModel.scale.trim(),
      if (_currentModel.discipline.trim().isNotEmpty)
        _currentModel.discipline.trim(),
      _currentModel.motorization.trim(),
    ].where((value) => value.isNotEmpty).toList(growable: false);

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 105,
          height: 82,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey500, width: 0.7),
            borderRadius: pw.BorderRadius.circular(7),
          ),
          padding: const pw.EdgeInsets.all(5),
          child: modelImage == null
              ? pw.Center(
                  child: pw.Text(
                    'Aucune photo',
                    style: const pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey600,
                    ),
                  ),
                )
              : pw.Image(modelImage, fit: pw.BoxFit.contain),
        ),
        pw.SizedBox(width: 14),
        pw.Expanded(
          child: pw.Padding(
            padding: const pw.EdgeInsets.only(top: 2),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  _pdfSafeText(_currentModel.name),
                  style: pw.TextStyle(
                    fontSize: 25,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  _pdfSafeText(subtitleValues.join(' - ')),
                  style: const pw.TextStyle(fontSize: 11),
                ),
                pw.SizedBox(height: 7),
                pw.Text(
                  'Carnet de vie du modèle',
                  style: pw.TextStyle(
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blueGrey900,
                  ),
                ),
                pw.SizedBox(height: 5),
                pw.Text(
                  'Généré le ${_formatDateTime(DateTime.now())}',
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _pdfVisualSummary() {
    final values = <List<String>>[
      ['Sessions', _sessions.length.toString()],
      [_runPluralLabel, _totalRuns.toString()],
      ['Packs utilisés', _totalPacks.toString()],
      ['Temps total', _durationLabel(_totalDurationMinutes)],
    ];

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey500, width: 0.7),
        borderRadius: pw.BorderRadius.circular(7),
      ),
      child: pw.Row(
        children: [
          for (var index = 0; index < values.length; index++) ...[
            pw.Expanded(
              child: pw.Column(
                children: [
                  pw.Text(
                    values[index][0],
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    values[index][1],
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(
                      fontSize: 15,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            if (index < values.length - 1)
              pw.Container(width: 0.6, height: 34, color: PdfColors.grey400),
          ],
        ],
      ),
    );
  }

  pw.Widget _pdfLineSectionTitle(String title) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 12.5,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.blueGrey900,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Container(height: 0.7, color: PdfColors.blueGrey800),
        pw.SizedBox(height: 7),
      ],
    );
  }

  pw.Widget _pdfCompactModelInformation() {
    final items = <_PdfLabelValue>[
      _PdfLabelValue('Catégorie', _currentModel.category),
      if (_currentModel.discipline.trim().isNotEmpty)
        _PdfLabelValue('Discipline', _currentModel.discipline),
      _PdfLabelValue('Motorisation', _currentModel.motorization),
      _PdfLabelValue('Échelle', _currentModel.scale),
      if (_currentModel.motorization == 'Électrique')
        _PdfLabelValue(
          'Nombre de batteries',
          _currentModel.batteryCount.toString(),
        ),
      if (_currentModel.motorization == 'Électrique')
        _PdfLabelValue('Configuration maxi', _currentModel.maxCells),
      if (_currentModel.weightKg != null)
        _PdfLabelValue('Poids', _currentModel.formattedWeight),
      if (_currentModel.hasAcquisitionDate)
        _PdfLabelValue('Acquisition', _currentModel.formattedAcquisitionDate),
      if (_currentModel.purchaseType != null &&
          _currentModel.purchaseType!.trim().isNotEmpty)
        _PdfLabelValue('Type d\u0027achat', _currentModel.purchaseType!.trim()),
      if (_currentModel.purchaseLocation != null &&
          _currentModel.purchaseLocation!.trim().isNotEmpty)
        _PdfLabelValue(
          'Lieu d\u0027achat',
          _currentModel.purchaseLocation!.trim(),
        ),
    ];

    return pw.Wrap(
      spacing: 12,
      runSpacing: 7,
      children: [
        for (final item in items)
          pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Text(
                '${item.label} : ',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                _pdfSafeText(item.value),
                style: const pw.TextStyle(fontSize: 9),
              ),
              pw.SizedBox(width: 3),
              pw.Text(
                ' - ',
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
      ],
    );
  }

  pw.Widget _pdfDetailedStatistics() {
    final averageRuns = _sessions.isEmpty ? 0.0 : _totalRuns / _sessions.length;
    final averageSessionMinutes = _sessions.isEmpty
        ? 0
        : (_totalDurationMinutes / _sessions.length).round();
    final averageRunMinutes = _totalRuns == 0
        ? 0
        : (_totalDurationMinutes / _totalRuns).round();

    DateTime? firstSession;
    DateTime? lastSession;
    if (_sessions.isNotEmpty) {
      final ordered = List<RcSession>.from(_sessions)
        ..sort((first, second) => first.startedAt.compareTo(second.startedAt));
      firstSession = ordered.first.startedAt;
      lastSession = ordered.last.startedAt;
    }

    final values = <List<String>>[
      [
        'Moyenne par session',
        '${averageRuns.toStringAsFixed(1).replaceAll('.', ',')} ${_isBoat ? 'navigation(s)' : 'roulage(s)'}'
            ' - ${_durationLabel(averageSessionMinutes)}',
      ],
      [
        _isBoat ? 'Moyenne par navigation' : 'Moyenne par roulage',
        _durationLabel(averageRunMinutes),
      ],
      ['Moyenne par pack', _durationLabel(averageRunMinutes)],
      [
        'Première session',
        firstSession == null ? '-' : _formatDate(firstSession),
      ],
      [
        'Dernière session',
        lastSession == null ? '-' : _formatDate(lastSession),
      ],
    ];

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < values.length; index++) ...[
          pw.Expanded(
            child: pw.Column(
              children: [
                pw.Text(
                  values[index][0],
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(fontSize: 8),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  values[index][1],
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (index < values.length - 1)
            pw.Container(width: 0.5, height: 30, color: PdfColors.grey400),
        ],
      ],
    );
  }

  pw.Widget _pdfHistoryTable() {
    if (_pdfTimelineItems.isEmpty) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 12),
        child: pw.Text(
          'Aucun événement enregistré pour ce modèle.',
          style: const pw.TextStyle(fontSize: 9),
        ),
      );
    }

    return pw.Table(
      border: const pw.TableBorder(
        horizontalInside: pw.BorderSide(color: PdfColors.grey400, width: 0.45),
        top: pw.BorderSide(color: PdfColors.grey500, width: 0.55),
        bottom: pw.BorderSide(color: PdfColors.grey500, width: 0.55),
      ),
      columnWidths: const {
        0: pw.FixedColumnWidth(66),
        1: pw.FixedColumnWidth(78),
        2: pw.FlexColumnWidth(3.8),
        3: pw.FixedColumnWidth(82),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            _pdfHistoryCell('Date', header: true),
            _pdfHistoryCell('Type', header: true),
            _pdfHistoryCell('Détails', header: true),
            _pdfHistoryCell('Infos clés', header: true),
          ],
        ),
        for (final item in _pdfTimelineItems) _pdfHistoryRow(item),
      ],
    );
  }

  pw.TableRow _pdfHistoryRow(_TimelineItem item) {
    if (item.session != null) {
      final session = item.session!;
      final location = session.location.trim().isEmpty
          ? 'Lieu non renseigné'
          : session.location.trim();
      final terrainType = session.terrainType.trim().isEmpty
          ? 'Type de terrain non renseigné'
          : session.terrainType.trim();

      final batteryDescriptions = <String>[];
      var physicalBatteryUses = 0;
      for (final run in session.runs) {
        physicalBatteryUses +=
            run.batteries.length + run.historicalBatteries.length;
        for (final battery in run.batteries) {
          final description = '${battery.id} — ${_batteryType(battery)}';
          if (!batteryDescriptions.contains(description)) {
            batteryDescriptions.add(description);
          }
        }
        for (final battery in run.historicalBatteries) {
          final description = 'Ancienne batterie — ${battery.displayLabel}';
          if (!batteryDescriptions.contains(description)) {
            batteryDescriptions.add(description);
          }
        }
      }

      final details = <String>[
        'Lieu : $location - Type de terrain : $terrainType - '
            '${session.runs.length} ${_isBoat ? 'navigation(s)' : 'roulage(s)'} '
            '(${_durationLabel(session.totalDurationMinutes)})',
        'Batteries utilisées : $physicalBatteryUses',
        if (batteryDescriptions.isNotEmpty)
          'Caractéristiques : ${batteryDescriptions.join(' / ')}',
        if (session.drivingNotes.trim().isNotEmpty)
          'Comportement et réglages : ${session.drivingNotes.trim()}',
        if (session.breakages.trim().isNotEmpty)
          'Casses : ${session.breakages.trim()}',
        if (session.partsReplacedOnSite.trim().isNotEmpty)
          'Pièces remplacées : ${session.partsReplacedOnSite.trim()}',
        if (session.maintenanceToDo.trim().isNotEmpty)
          'Entretien : ${session.maintenanceToDo.trim()}',
        if (session.partsToOrder.trim().isNotEmpty)
          'Pièces à commander : ${session.partsToOrder.trim()}',
        if (session.changesBeforeNextSession.trim().isNotEmpty)
          'Modifications : ${session.changesBeforeNextSession.trim()}',
        if (session.generalNotes.trim().isNotEmpty)
          'Notes : ${session.generalNotes.trim()}',
      ].join('\n');

      return pw.TableRow(
        children: [
          _pdfHistoryCell(_formatDate(session.startedAt)),
          _pdfHistoryCell('Session'),
          _pdfHistoryCell(details),
          _pdfHistoryCell(
            '${_durationLabel(session.totalDurationMinutes)}'
            ' - ${session.runs.length} pack(s)',
          ),
        ],
      );
    }

    if (item.maintenanceGroup != null) {
      final group = item.maintenanceGroup!;
      final details = <String>[];

      for (final record in group.interventions) {
        final interventionDetails = <String>[
          if (record.title.trim().isNotEmpty) record.title.trim(),
          if (record.notes.trim().isNotEmpty) record.notes.trim(),
          if (record.fluids.isNotEmpty)
            record.fluids.entries
                .map(
                  (entry) => '${_fluidLabel(entry.key)} : ${entry.value} cSt',
                )
                .join(' / '),
          if (record.setupChanges.isNotEmpty)
            record.setupChanges
                .map(
                  (change) =>
                      '${change['field'] ?? 'Réglage'} : '
                      '${change['newValue'] ?? ''}',
                )
                .join(' / '),
        ].where((value) => value.isNotEmpty).join(' - ');

        details.add(
          interventionDetails.isEmpty
              ? record.typeLabel
              : '${record.typeLabel} : $interventionDetails',
        );
      }

      return pw.TableRow(
        children: [
          _pdfHistoryCell(_formatDate(group.date)),
          _pdfHistoryCell('Maintenance'),
          _pdfHistoryCell(details.join('\n')),
          _pdfHistoryCell('${group.interventions.length} intervention(s)'),
        ],
      );
    }

    final acquisitionDetails = <String>[
      if (_currentModel.purchaseType != null &&
          _currentModel.purchaseType!.trim().isNotEmpty)
        'Modèle acheté ${_currentModel.purchaseType!.trim().toLowerCase()}',
      if (_currentModel.purchaseLocation != null &&
          _currentModel.purchaseLocation!.trim().isNotEmpty)
        'chez ${_currentModel.purchaseLocation!.trim()}',
    ].join(' ');

    return pw.TableRow(
      children: [
        _pdfHistoryCell(_formatDate(item.date)),
        _pdfHistoryCell('Acquisition'),
        _pdfHistoryCell(
          acquisitionDetails.isEmpty
              ? _currentModel.formattedAcquisition
              : '$acquisitionDetails.',
        ),
        _pdfHistoryCell('-'),
      ],
    );
  }

  pw.Widget _pdfHistoryCell(String value, {bool header = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 6),
      child: pw.Text(
        _pdfSafeText(value),
        style: pw.TextStyle(
          fontSize: header ? 8.2 : 7.7,
          fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  String get _pdfFileName {
    final cleanName = _currentModel.name
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final now = DateTime.now();
    final date =
        '${now.year}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    return 'RC_Companion_${cleanName.isEmpty ? 'modele' : cleanName}_$date.pdf';
  }

  Future<void> _openPdfPreview() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ModelHistoryPdfPreviewPage(
          title: 'Historique — ${_currentModel.name}',
          fileName: _pdfFileName,
          buildPdf: _buildPdf,
        ),
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
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _openPdfPreview,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Exporter en PDF'),
            ),
          ),
          const SizedBox(height: 12),
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

class _ModelHistoryPdfPreviewPage extends StatelessWidget {
  const _ModelHistoryPdfPreviewPage({
    required this.title,
    required this.fileName,
    required this.buildPdf,
  });

  final String title;
  final String fileName;
  final Future<Uint8List> Function(PdfPageFormat format) buildPdf;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: PdfPreview(
        build: buildPdf,
        pdfFileName: fileName,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
        allowPrinting: true,
        allowSharing: true,
        loadingWidget: const Center(child: CircularProgressIndicator()),
        onError: (context, error) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Impossible de générer le PDF.\n$error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class _PdfLabelValue {
  const _PdfLabelValue(this.label, this.value);

  final String label;
  final String value;
}

class _TimelineItem {
  const _TimelineItem._({
    required this.date,
    this.session,
    this.maintenanceGroup,
  });

  factory _TimelineItem.session(RcSession session) {
    return _TimelineItem._(date: session.startedAt, session: session);
  }

  factory _TimelineItem.maintenanceGroup(
    _ModelMaintenanceGroup maintenanceGroup,
  ) {
    return _TimelineItem._(
      date: maintenanceGroup.date,
      maintenanceGroup: maintenanceGroup,
    );
  }

  factory _TimelineItem.acquisition(DateTime date) {
    return _TimelineItem._(date: date);
  }

  final DateTime date;
  final RcSession? session;
  final _ModelMaintenanceGroup? maintenanceGroup;
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

  String get maintenanceGroupId {
    final value = data['maintenanceGroupId']?.toString().trim() ?? '';
    return value.isEmpty ? id : value;
  }

  bool get isAdjustment =>
      recordType == 'MODIFICATION' &&
      data['interventionSubtype']?.toString() == 'REGLAGE';

  bool get isCleaning =>
      recordType == 'MODIFICATION' &&
      data['interventionSubtype']?.toString() == 'NETTOYAGE';

  String get typeLabel {
    if (isAdjustment) {
      return 'Réglage';
    }

    if (isCleaning) {
      return 'Nettoyage';
    }

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
    if (isAdjustment) {
      return Icons.tune_outlined;
    }

    if (isCleaning) {
      return Icons.cleaning_services_outlined;
    }

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

class _ModelMaintenanceGroup {
  const _ModelMaintenanceGroup({required this.id, required this.interventions});

  final String id;
  final List<_ModelMaintenanceRecord> interventions;

  DateTime get date => interventions
      .map((record) => record.date)
      .reduce((a, b) => a.isAfter(b) ? a : b);
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
