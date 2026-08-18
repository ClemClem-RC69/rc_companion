import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';

import '../../database/app_database.dart';
import '../../models/rc_model.dart';
import '../../services/maintenance_local_store.dart';
import '../../services/maintenance_service.dart';
import '../../services/model_operational_event_service.dart';
import '../../services/model_setup_service.dart';
import '../../services/supabase_service.dart';

class MaintenancePage extends StatefulWidget {
  const MaintenancePage({super.key, this.initialModelId, this.editRecordId});

  final String? initialModelId;
  final String? editRecordId;

  @override
  State<MaintenancePage> createState() => _MaintenancePageState();
}

class _MaintenancePageState extends State<MaintenancePage> {
  final AppDatabase _database = AppDatabase.instance;
  bool _isLoading = true;
  String? _errorMessage;

  List<RcModel> _models = [];
  List<_MaintenanceRecord> _records = [];

  final TextEditingController _historySearchController =
      TextEditingController();
  String _historySearch = '';
  String _historyCategory = 'Tous';

  StreamSubscription<List<Map<String, dynamic>>>? _maintenanceSubscription;
  StreamSubscription<List<LocalModelOperationalEvent>>?
  _operationalEventSubscription;

  Map<String, List<LocalModelOperationalEvent>> _openEventsByModel =
      <String, List<LocalModelOperationalEvent>>{};

  bool _initialRecordHandled = false;

  @override
  void initState() {
    super.initState();
    _startMaintenanceLiveUpdates();
    _startOperationalEventLiveUpdates();
    _loadData();
  }

  @override
  void dispose() {
    _maintenanceSubscription?.cancel();
    _operationalEventSubscription?.cancel();
    _historySearchController.dispose();
    super.dispose();
  }

  void _startOperationalEventLiveUpdates() {
    _operationalEventSubscription =
        ModelOperationalEventService.watchOpenEvents().listen((events) {
          if (!mounted) {
            return;
          }

          final grouped = <String, List<LocalModelOperationalEvent>>{};

          for (final event in events) {
            grouped
                .putIfAbsent(
                  event.modelId,
                  () => <LocalModelOperationalEvent>[],
                )
                .add(event);
          }

          setState(() {
            _openEventsByModel = grouped.map(
              (key, value) => MapEntry(
                key,
                List<LocalModelOperationalEvent>.unmodifiable(value),
              ),
            );
          });
        });
  }

  void _startMaintenanceLiveUpdates() {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
      return;
    }

    _maintenanceSubscription =
        MaintenanceLocalStore.watchRecords(userId: user.id).listen((rows) {
          if (!mounted || _models.isEmpty) {
            return;
          }

          final modelById = <String, RcModel>{
            for (final model in _models)
              if (model.id != null && model.id!.isNotEmpty) model.id!: model,
          };

          final records = rows
              .map((row) => _MaintenanceRecord.fromMap(row, modelById))
              .toList(growable: false);

          setState(() {
            _records = records;
            _errorMessage = null;
            _isLoading = false;
          });
        });
  }

  Future<void> _loadData({bool refreshRemote = true}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = SupabaseService.client.auth.currentUser;

      if (user == null) {
        throw StateError('Aucun utilisateur connecté.');
      }

      final localModelRows =
          await (_database.select(_database.localModels)
                ..where(
                  (row) =>
                      row.userId.equals(user.id) & row.isDeleted.equals(false),
                )
                ..orderBy([(row) => OrderingTerm.asc(row.modelId)]))
              .get();

      final models =
          localModelRows
              .map((localRow) {
                final row = Map<String, dynamic>.from(
                  jsonDecode(localRow.payloadJson) as Map,
                );
                return _rcModelFromMap(row);
              })
              .toList(growable: false)
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );

      final recordRows = await MaintenanceService.getRecords();

      final modelById = <String, RcModel>{
        for (final model in models)
          if (model.id != null && model.id!.isNotEmpty) model.id!: model,
      };

      final records = recordRows
          .map((row) => _MaintenanceRecord.fromMap(row, modelById))
          .toList(growable: false);

      if (!mounted) {
        return;
      }

      setState(() {
        _models = models;
        _records = records;
        _isLoading = false;
      });

      _openInitialRecordIfNeeded();
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = error.toString();
        _isLoading = false;
      });
    }
  }

  static RcModel _rcModelFromMap(Map<String, dynamic> row) {
    return RcModel(
      id: row['id'] as String?,
      name: row['name'] as String? ?? 'Modèle sans nom',
      brand: row['brand'] as String? ?? 'Marque non renseignée',
      category: row['category'] as String? ?? '',
      discipline: row['discipline'] as String? ?? '',
      motorization: row['motorization'] as String? ?? 'Électrique',
      scale: row['scale'] as String? ?? '',
      batteryCount: (row['battery_count'] as num?)?.toInt() ?? 0,
      maxCells: row['max_cells'] == null
          ? 'Aucune'
          : '${(row['max_cells'] as num).toInt()}S',
      photoUrl: row['photo_url'] as String?,
      weightKg: (row['weight_kg'] as num?)?.toDouble(),
      acquisitionDate: row['acquisition_date'] == null
          ? null
          : DateTime.tryParse(row['acquisition_date'].toString()),
      purchaseType: row['purchase_type'] as String?,
      purchaseLocation: row['purchase_location'] as String?,
      radioId: row['radio_id'] as String?,
    );
  }

  void _openInitialRecordIfNeeded() {
    if (_initialRecordHandled) {
      return;
    }

    final recordId = widget.editRecordId;

    if (recordId == null || recordId.trim().isEmpty) {
      _initialRecordHandled = true;
      return;
    }

    _MaintenanceRecord? record;

    for (final item in _records) {
      if (item.id == recordId) {
        record = item;
        break;
      }
    }

    _initialRecordHandled = true;

    if (record == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showMessage('Maintenance introuvable.');
      });
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }

      await _openEditDialog(record!);
    });
  }

  Future<void> _openCreateDialog() async {
    if (_models.isEmpty) {
      _showMessage('Enregistre d’abord un modèle.');
      return;
    }

    final draft = await showDialog<_MaintenanceDraft>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MaintenanceDialog(
        models: _models,
        initialModelId: widget.initialModelId,
        openEventsByModel: _openEventsByModel,
      ),
    );

    if (draft == null) {
      return;
    }

    final maintenanceGroupId =
        'maintenance-${DateTime.now().microsecondsSinceEpoch}';

    await _saveMaintenance(
      draft,
      allowContinuation: true,
      maintenanceGroupId: maintenanceGroupId,
    );
  }

  Future<void> _openEditDialog(_MaintenanceRecord record) async {
    final draft = await showDialog<_MaintenanceDraft>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MaintenanceDialog(models: _models, record: record),
    );

    if (draft == null) {
      return;
    }

    await _updateMaintenance(record, draft);
  }

  Future<void> _saveMaintenance(
    _MaintenanceDraft draft, {
    bool allowContinuation = false,
    required String maintenanceGroupId,
  }) async {
    final user = SupabaseService.client.auth.currentUser;

    if (user == null) {
      _showMessage('Aucun utilisateur connecté.');
      return;
    }

    final modelId = draft.model.id;

    if (modelId == null || modelId.isEmpty) {
      _showMessage('Ce modèle ne possède pas d’identifiant valide.');
      return;
    }

    try {
      final createdRecord = await MaintenanceService.createRecord(
        modelId: modelId,
        maintenanceDate: draft.date,
        recordType: draft.type.databaseValue,
        title: draft.title.trim(),
        notes: draft.notes.trim(),
        data: <String, dynamic>{
          ...draft.data,
          'maintenanceGroupId': maintenanceGroupId,
          if (draft.resolvedOperationalEventIds.isNotEmpty)
            'resolvedOperationalEventIds': draft.resolvedOperationalEventIds
                .toList(growable: false),
        },
        packsSinceLastRevision: draft.type == _MaintenanceType.revision
            ? 0
            : null,
        runtimeMinutesSinceLastRevision: draft.type == _MaintenanceType.revision
            ? 0
            : null,
      );

      final maintenanceId = createdRecord['id']?.toString() ?? '';

      if (maintenanceId.isNotEmpty &&
          draft.resolvedOperationalEventIds.isNotEmpty) {
        await ModelOperationalEventService.resolveEvents(
          eventIds: draft.resolvedOperationalEventIds,
          maintenanceId: maintenanceId,
        );
      }

      if (draft.type == _MaintenanceType.revision) {
        await _rebuildCurrentSetupFromHistory(modelId);
        await _recalculateRevisionCounters(modelId);
      }

      if (!mounted) {
        return;
      }

      _showMessage('${draft.type.label} enregistrée.');
      await _loadData(refreshRemote: false);

      if (allowContinuation && mounted) {
        await _offerAnotherIntervention(
          draft.model,
          maintenanceGroupId: maintenanceGroupId,
        );
      }
    } catch (error) {
      _showMessage('Enregistrement impossible : $error');
    }
  }

  Future<void> _offerAnotherIntervention(
    RcModel model, {
    required String maintenanceGroupId,
  }) async {
    final addAnother = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.build_circle_outlined),
        title: const Text('Effectuer une autre intervention ?'),
        content: Text(
          'L’intervention est enregistrée pour ${model.name}.\n\n'
          'Tu peux poursuivre cette maintenance avec une révision, une '
          'réparation, un réglage ou une modification.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Terminer la maintenance'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.add),
            label: const Text('Autre intervention'),
          ),
        ],
      ),
    );

    if (addAnother != true || !mounted) {
      return;
    }

    final modelId = model.id?.trim();
    if (modelId == null || modelId.isEmpty) {
      return;
    }

    final nextDraft = await showDialog<_MaintenanceDraft>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MaintenanceDialog(
        models: _models,
        initialModelId: modelId,
        openEventsByModel: _openEventsByModel,
      ),
    );

    if (nextDraft == null || !mounted) {
      return;
    }

    await _saveMaintenance(
      nextDraft,
      allowContinuation: true,
      maintenanceGroupId: maintenanceGroupId,
    );
  }

  Future<void> _updateMaintenance(
    _MaintenanceRecord record,
    _MaintenanceDraft draft,
  ) async {
    final user = SupabaseService.client.auth.currentUser;

    if (user == null) {
      _showMessage('Aucun utilisateur connecté.');
      return;
    }

    final modelId = draft.model.id;

    if (modelId == null || modelId.isEmpty) {
      _showMessage('Ce modèle ne possède pas d’identifiant valide.');
      return;
    }

    try {
      await MaintenanceService.updateRecord(
        maintenanceId: record.id,
        modelId: modelId,
        maintenanceDate: draft.date,
        recordType: draft.type.databaseValue,
        title: draft.title.trim(),
        notes: draft.notes.trim(),
        data: <String, dynamic>{
          ...draft.data,
          if (record.maintenanceGroupId.isNotEmpty)
            'maintenanceGroupId': record.maintenanceGroupId,
        },
        packsSinceLastRevision: record.packsSinceLastRevision,
        runtimeMinutesSinceLastRevision: record.runtimeMinutesSinceLastRevision,
      );

      final affectedModelIds = <String>{};

      if (record.type == _MaintenanceType.revision) {
        affectedModelIds.add(record.modelId);
      }

      if (draft.type == _MaintenanceType.revision) {
        affectedModelIds.add(modelId);
      }

      for (final affectedModelId in affectedModelIds) {
        await _rebuildCurrentSetupFromHistory(affectedModelId);
        await _recalculateRevisionCounters(affectedModelId);
      }

      if (!mounted) {
        return;
      }

      _showMessage('${draft.type.label} modifiée.');
      await _loadData(refreshRemote: false);
    } catch (error) {
      _showMessage('Modification impossible : $error');
    }
  }

  Future<void> _rebuildCurrentSetupFromHistory(String modelId) async {
    final user = SupabaseService.client.auth.currentUser;

    if (user == null || modelId.isEmpty) {
      return;
    }

    // Lecture strictement locale : aucun rafraîchissement Supabase ne doit
    // pouvoir réinjecter une ancienne révision pendant la reconstruction.
    final maintenanceRows = await MaintenanceService.getLocalRecords();
    final setup = await ModelSetupService.getLocalSetup(modelId);

    final revisions =
        maintenanceRows
            .where(
              (row) =>
                  row['model_id']?.toString() == modelId &&
                  row['record_type']?.toString() == 'REVISION',
            )
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false)
          ..sort((a, b) {
            final aDate =
                DateTime.tryParse(a['maintenance_date']?.toString() ?? '') ??
                DateTime(1900);
            final bDate =
                DateTime.tryParse(b['maintenance_date']?.toString() ?? '') ??
                DateTime(1900);
            final dateComparison = aDate.compareTo(bDate);

            if (dateComparison != 0) {
              return dateComparison;
            }

            final aCreated =
                DateTime.tryParse(a['created_at']?.toString() ?? '') ??
                DateTime(1900);
            final bCreated =
                DateTime.tryParse(b['created_at']?.toString() ?? '') ??
                DateTime(1900);
            final createdComparison = aCreated.compareTo(bCreated);

            if (createdComparison != 0) {
              return createdComparison;
            }

            return (a['id']?.toString() ?? '').compareTo(
              b['id']?.toString() ?? '',
            );
          });

    final enabledFields = List<String>.from(setup.enabledFields);
    final currentValues = Map<String, String>.from(setup.originalValues);

    for (final revision in revisions) {
      final rawData = revision['data'];
      final data = rawData is Map
          ? Map<String, dynamic>.from(rawData)
          : const <String, dynamic>{};

      final rawFluids = data['fluids'];
      if (rawFluids is Map) {
        final fluids = rawFluids.map(
          (key, value) => MapEntry(key.toString(), value.toString()),
        );

        void applyFluid(String sourceKey, String setupKey) {
          final value = fluids[sourceKey]?.trim() ?? '';

          if (value.isEmpty) {
            return;
          }

          currentValues[setupKey] = _withCstSuffix(value);

          if (!enabledFields.contains(setupKey)) {
            enabledFields.add(setupKey);
          }
        }

        applyFluid('diffFront', 'front_diff_oil');
        applyFluid('diffCenter', 'center_diff_oil');
        applyFluid('diffRear', 'rear_diff_oil');
        applyFluid('shockFront', 'front_shock_oil');
        applyFluid('shockRear', 'rear_shock_oil');
      }

      final rawSetupChanges = data['setupChanges'];
      if (rawSetupChanges is List) {
        for (final rawChange in rawSetupChanges) {
          if (rawChange is! Map) {
            continue;
          }

          final change = Map<String, dynamic>.from(rawChange);
          final fieldKey = change['fieldKey']?.toString().trim() ?? '';
          final newValue = change['newValue']?.toString().trim() ?? '';

          if (fieldKey.isEmpty || newValue.isEmpty) {
            continue;
          }

          currentValues[fieldKey] = newValue;

          if (!enabledFields.contains(fieldKey)) {
            enabledFields.add(fieldKey);
          }
        }
      }
    }

    // Les champs d'origine doivent rester visibles même si toutes les
    // révisions qui les modifiaient ont été supprimées.
    for (final fieldKey in setup.originalValues.keys) {
      if (!enabledFields.contains(fieldKey)) {
        enabledFields.add(fieldKey);
      }
    }

    await ModelSetupService.saveSetup(
      setup.copyWith(
        enabledFields: enabledFields,
        currentValues: currentValues,
      ),
    );
  }

  static String _withCstSuffix(String value) {
    final cleanValue = value.trim();

    if (cleanValue.toLowerCase().contains('cst')) {
      return cleanValue;
    }

    return '$cleanValue cSt';
  }

  Future<void> _recalculateRevisionCounters(String modelId) async {
    final user = SupabaseService.client.auth.currentUser;

    if (user == null) {
      return;
    }

    final maintenanceRows = await MaintenanceService.getLocalRecords();

    final revisions =
        maintenanceRows
            .where(
              (row) =>
                  row['model_id']?.toString() == modelId &&
                  row['record_type']?.toString() == 'REVISION',
            )
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false)
          ..sort((a, b) {
            final aDate =
                DateTime.tryParse(a['maintenance_date']?.toString() ?? '') ??
                DateTime(1900);
            final bDate =
                DateTime.tryParse(b['maintenance_date']?.toString() ?? '') ??
                DateTime(1900);
            return aDate.compareTo(bDate);
          });

    final sessionRows =
        await (_database.select(_database.localSessions)..where(
              (row) => row.userId.equals(user.id) & row.isDeleted.equals(false),
            ))
            .get();

    final runs = <_RunStat>[];

    for (final localSession in sessionRows) {
      final session = Map<String, dynamic>.from(
        jsonDecode(localSession.payloadJson) as Map,
      );

      if (session['model_id']?.toString() != modelId) {
        continue;
      }

      final rawRuns = session['session_runs'] as List<dynamic>? ?? const [];

      for (final rawRun in rawRuns) {
        if (rawRun is! Map) {
          continue;
        }

        final run = Map<String, dynamic>.from(rawRun);
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
          _RunStat(startedAt: startedAt, durationMinutes: durationMinutes),
        );
      }
    }

    DateTime? previousRevisionDate;

    for (final revision in revisions) {
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

      final maintenanceId = revision['id']?.toString();

      if (maintenanceId != null && maintenanceId.isNotEmpty) {
        await MaintenanceService.updateCounters(
          maintenanceId: maintenanceId,
          packsSinceLastRevision: packs,
          runtimeMinutesSinceLastRevision: knownMinutes,
        );
      }

      previousRevisionDate = revisionDate;
    }
  }

  Future<void> _deleteRecord(_MaintenanceRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.delete_forever_outlined),
        title: const Text('Supprimer cette maintenance ?'),
        content: Text(
          '${record.type.label} du ${_formatDate(record.date)} pour '
          '${record.modelName}.\n\nCette action est irréversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
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

    final user = SupabaseService.client.auth.currentUser;

    if (user == null) {
      return;
    }

    try {
      await MaintenanceService.deleteRecord(maintenanceId: record.id);
      await ModelOperationalEventService.reopenEventsResolvedByMaintenance(
        record.id,
      );

      if (record.type == _MaintenanceType.revision) {
        await _rebuildCurrentSetupFromHistory(record.modelId);
        await _recalculateRevisionCounters(record.modelId);
      }

      if (!mounted) {
        return;
      }

      _showMessage('Maintenance supprimée.');
      await _loadData(refreshRemote: false);
    } catch (error) {
      _showMessage('Suppression impossible : $error');
    }
  }

  Future<void> _showDetails(_MaintenanceRecord record) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _MaintenanceDetailsDialog(record: record),
    );
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }

  static String _durationLabel(int? minutes) {
    if (minutes == null) {
      return 'Non calculé';
    }

    final hours = minutes ~/ 60;
    final remaining = minutes % 60;

    if (hours == 0) {
      return '$remaining min';
    }

    if (remaining == 0) {
      return '${hours}h';
    }

    return '${hours}h ${remaining}min';
  }

  List<_MaintenanceGroup> _groupMaintenanceRecords(
    List<_MaintenanceRecord> records,
  ) {
    final grouped = <String, List<_MaintenanceRecord>>{};

    for (final record in records) {
      grouped
          .putIfAbsent(record.maintenanceGroupId, () => <_MaintenanceRecord>[])
          .add(record);
    }

    final groups =
        grouped.entries
            .map((entry) {
              final interventions = List<_MaintenanceRecord>.from(entry.value)
                ..sort((a, b) => a.date.compareTo(b.date));
              return _MaintenanceGroup(
                id: entry.key,
                interventions: List<_MaintenanceRecord>.unmodifiable(
                  interventions,
                ),
              );
            })
            .toList(growable: false)
          ..sort((a, b) => b.date.compareTo(a.date));

    return groups;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Maintenance')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Maintenance')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 52),
                const SizedBox(height: 16),
                const Text(
                  'Impossible de charger les maintenances.',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(_errorMessage!, textAlign: TextAlign.center),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _loadData,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Maintenance'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateDialog,
        icon: const Icon(Icons.add),
        label: const Text('Nouvelle maintenance'),
      ),
      body: _records.isEmpty
          ? const _EmptyMaintenanceState()
          : RefreshIndicator(
              onRefresh: _loadData,
              child: Builder(
                builder: (context) {
                  final query = _historySearch.trim().toLowerCase();
                  final filteredRecords = _records
                      .where((record) {
                        final matchesCategory =
                            _historyCategory == 'Tous' ||
                            record.modelCategory.toLowerCase() ==
                                _historyCategory.toLowerCase();
                        final matchesSearch =
                            query.isEmpty ||
                            record.modelName.toLowerCase().contains(query) ||
                            record.modelBrand.toLowerCase().contains(query);

                        return matchesCategory && matchesSearch;
                      })
                      .toList(growable: false);
                  final filteredGroups = _groupMaintenanceRecords(
                    filteredRecords,
                  );

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                    children: [
                      const Text(
                        'Historique',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _MaintenanceFilterBar(
                        controller: _historySearchController,
                        selectedCategory: _historyCategory,
                        onSearchChanged: (value) {
                          setState(() {
                            _historySearch = value;
                          });
                        },
                        onCategoryChanged: (value) {
                          setState(() {
                            _historyCategory = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      if (filteredGroups.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(
                            child: Text(
                              'Aucune maintenance ne correspond à la recherche.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      for (final group in filteredGroups)
                        Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ExpansionTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.build_circle_outlined),
                            ),
                            title: Text(
                              group.modelName,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            subtitle: Text(
                              'Maintenance • ${_formatDate(group.date)} • '
                              '${group.interventions.length} intervention(s)',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            childrenPadding: const EdgeInsets.fromLTRB(
                              12,
                              0,
                              8,
                              12,
                            ),
                            children: [
                              for (final record in group.interventions)
                                ListTile(
                                  leading: Icon(record.type.icon),
                                  title: Text(
                                    record.title.isEmpty
                                        ? record.type.label
                                        : record.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(record.type.label),
                                  onTap: () => _showDetails(record),
                                  trailing: PopupMenuButton<String>(
                                    tooltip: 'Options de l’intervention',
                                    onSelected: (value) {
                                      if (value == 'details') {
                                        _showDetails(record);
                                      } else if (value == 'edit') {
                                        _openEditDialog(record);
                                      } else if (value == 'delete') {
                                        _deleteRecord(record);
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: 'details',
                                        child: Row(
                                          children: [
                                            Icon(Icons.visibility_outlined),
                                            SizedBox(width: 10),
                                            Text('Voir'),
                                          ],
                                        ),
                                      ),
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
                                ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
    );
  }
}

class _MaintenanceFilterBar extends StatelessWidget {
  const _MaintenanceFilterBar({
    required this.controller,
    required this.selectedCategory,
    required this.onSearchChanged,
    required this.onCategoryChanged,
  });

  final TextEditingController controller;
  final String selectedCategory;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onCategoryChanged;

  static const List<String> _categories = ['Tous', 'Voiture', 'Bateau', 'Moto'];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            onChanged: onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: 'Marque ou modèle',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 12,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 112,
          child: DropdownButtonFormField<String>(
            initialValue: selectedCategory,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 12,
              ),
            ),
            items: _categories
                .map(
                  (category) => DropdownMenuItem(
                    value: category,
                    child: Text(category, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                onCategoryChanged(value);
              }
            },
          ),
        ),
      ],
    );
  }
}

class _EmptyMaintenanceState extends StatelessWidget {
  const _EmptyMaintenanceState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: const [
        SizedBox(height: 120),
        Icon(Icons.build_circle_outlined, size: 74),
        SizedBox(height: 18),
        Center(
          child: Text(
            'Aucune maintenance enregistrée',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(height: 8),
        Center(
          child: Text(
            'Ajoute une révision, une réparation ou une modification.',
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _MaintenanceDialog extends StatefulWidget {
  const _MaintenanceDialog({
    required this.models,
    this.record,
    this.initialModelId,
    this.openEventsByModel = const <String, List<LocalModelOperationalEvent>>{},
  });

  final List<RcModel> models;
  final _MaintenanceRecord? record;
  final String? initialModelId;
  final Map<String, List<LocalModelOperationalEvent>> openEventsByModel;

  @override
  State<_MaintenanceDialog> createState() => _MaintenanceDialogState();
}

class _MaintenanceDialogState extends State<_MaintenanceDialog> {
  RcModel? _selectedModel;
  _MaintenanceType _selectedType = _MaintenanceType.revision;
  DateTime _selectedDate = DateTime.now();

  final _titleController = TextEditingController();
  final _notesController = TextEditingController();

  final Map<String, TextEditingController> _fluidControllers = {
    'diffFront': TextEditingController(),
    'diffCenter': TextEditingController(),
    'diffRear': TextEditingController(),
    'shockFront': TextEditingController(),
    'shockRear': TextEditingController(),
  };

  final List<_SetupChangeEditor> _setupChanges = [];
  final Set<String> _resolvedOperationalEventIds = <String>{};

  String? _errorMessage;

  static const _setupFieldChoices = <_SetupFieldChoice>[
    _SetupFieldChoice('pinion', 'Pignon moteur'),
    _SetupFieldChoice('spur', 'Couronne'),
    _SetupFieldChoice('front_camber', 'Carrossage avant'),
    _SetupFieldChoice('rear_camber', 'Carrossage arrière'),
    _SetupFieldChoice('front_toe', 'Pincement avant'),
    _SetupFieldChoice('rear_toe', 'Pincement arrière'),
    _SetupFieldChoice('front_ride_height', 'Garde au sol avant'),
    _SetupFieldChoice('rear_ride_height', 'Garde au sol arrière'),
    _SetupFieldChoice('esc', 'ESC'),
    _SetupFieldChoice('motor', 'Moteur'),
    _SetupFieldChoice('servo', 'Servo'),
    _SetupFieldChoice('tires', 'Pneus'),
    _SetupFieldChoice('notes', 'Notes'),
  ];

  @override
  void initState() {
    super.initState();

    final record = widget.record;

    if (record == null) {
      final initialModelId = widget.initialModelId;

      if (initialModelId != null && initialModelId.isNotEmpty) {
        for (final model in widget.models) {
          if (model.id == initialModelId) {
            _selectedModel = model;
            break;
          }
        }
      }

      return;
    }

    _selectedModel = widget.models.cast<RcModel?>().firstWhere(
      (model) => model?.id == record.modelId,
      orElse: () => null,
    );
    _selectedType = record.type;
    _selectedDate = record.date;
    _titleController.text = record.title;
    _notesController.text = record.notes;

    for (final entry in record.fluids.entries) {
      _fluidControllers[entry.key]?.text = entry.value;
    }

    for (final change in record.setupChanges) {
      final editor = _SetupChangeEditor();
      editor.fieldKey =
          change['fieldKey'] ?? _setupKeyFromLegacyLabel(change['field']);
      editor.valueController.text = change['newValue'] ?? '';
      _setupChanges.add(editor);
    }
  }

  static String? _setupKeyFromLegacyLabel(String? label) {
    if (label == null || label.trim().isEmpty) {
      return null;
    }

    for (final choice in _setupFieldChoices) {
      if (choice.label == label) {
        return choice.keyName;
      }
    }

    return null;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();

    for (final controller in _fluidControllers.values) {
      controller.dispose();
    }

    for (final change in _setupChanges) {
      change.dispose();
    }

    super.dispose();
  }

  List<LocalModelOperationalEvent> get _selectedModelOpenEvents {
    if (widget.record != null) {
      return const <LocalModelOperationalEvent>[];
    }

    final modelId = _selectedModel?.id?.trim();
    if (modelId == null || modelId.isEmpty) {
      return const <LocalModelOperationalEvent>[];
    }

    return widget.openEventsByModel[modelId] ??
        const <LocalModelOperationalEvent>[];
  }

  Color _operationalEventColor(
    BuildContext context,
    LocalModelOperationalEvent event,
  ) {
    if (event.eventType == ModelOperationalEventService.repairType) {
      return Theme.of(context).colorScheme.error;
    }

    return Colors.orange.shade800;
  }

  IconData _operationalEventIcon(LocalModelOperationalEvent event) {
    if (event.eventType == ModelOperationalEventService.repairType) {
      return Icons.error_outline;
    }

    return Icons.build_circle_outlined;
  }

  String _operationalEventLabel(LocalModelOperationalEvent event) {
    if (event.eventType == ModelOperationalEventService.repairType) {
      return 'Réparation à effectuer';
    }

    return 'Entretien / réglage / modification à effectuer';
  }

  DateTime get _firstAllowedDate {
    final acquisition = _selectedModel?.acquisitionDate;

    if (acquisition == null) {
      return DateTime(1900);
    }

    return DateTime(acquisition.year, acquisition.month, acquisition.day);
  }

  Future<void> _selectDate() async {
    final now = DateTime.now();
    final firstDate = _firstAllowedDate;
    var initialDate = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );

    if (initialDate.isBefore(firstDate)) {
      initialDate = firstDate;
    }

    if (initialDate.isAfter(now)) {
      initialDate = now;
    }

    final selected = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: now,
      helpText: 'Date de la maintenance',
      cancelText: 'Annuler',
      confirmText: 'Valider',
    );

    if (selected == null || !mounted) {
      return;
    }

    setState(() {
      _selectedDate = DateTime(selected.year, selected.month, selected.day, 12);
    });
  }

  void _addSetupChange() {
    setState(() {
      _setupChanges.add(_SetupChangeEditor());
    });
  }

  void _removeSetupChange(int index) {
    setState(() {
      final removed = _setupChanges.removeAt(index);
      removed.dispose();
    });
  }

  void _save() {
    final model = _selectedModel;

    if (model == null) {
      setState(() {
        _errorMessage = 'Sélectionne un modèle.';
      });
      return;
    }

    var title = _titleController.text.trim();

    if (_selectedType == _MaintenanceType.revision && title.isEmpty) {
      title = 'Révision';
    }

    if (_selectedType != _MaintenanceType.revision && title.isEmpty) {
      setState(() {
        _errorMessage = 'Renseigne un titre.';
      });
      return;
    }

    final fluids = <String, String>{};

    for (final entry in _fluidControllers.entries) {
      final value = entry.value.text.trim();
      if (value.isNotEmpty) {
        fluids[entry.key] = value;
      }
    }

    final setupChanges = <Map<String, String>>[];

    for (final change in _setupChanges) {
      final fieldKey = change.fieldKey;
      final value = change.valueController.text.trim();

      if (fieldKey == null || value.isEmpty) {
        continue;
      }

      final choice = _setupFieldChoices.firstWhere(
        (item) => item.keyName == fieldKey,
      );

      setupChanges.add({
        'fieldKey': fieldKey,
        'field': choice.label,
        'newValue': value,
      });
    }

    Navigator.of(context).pop(
      _MaintenanceDraft(
        model: model,
        date: _selectedDate,
        type: _selectedType,
        title: title,
        notes: _notesController.text.trim(),
        data: <String, dynamic>{
          if (fluids.isNotEmpty) 'fluids': fluids,
          if (setupChanges.isNotEmpty) 'setupChanges': setupChanges,
          if (_selectedType == _MaintenanceType.reglage)
            'interventionSubtype': 'REGLAGE',
        },
        resolvedOperationalEventIds: Set<String>.unmodifiable(
          _resolvedOperationalEventIds,
        ),
      ),
    );
  }

  String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }

  InputDecoration _decoration(String label, {String? hint, String? suffix}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      suffixText: suffix,
      border: const OutlineInputBorder(),
      alignLabelWithHint: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      title: Text(
        widget.record == null
            ? 'Nouvelle maintenance'
            : 'Modifier la maintenance',
      ),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<RcModel>(
                initialValue: _selectedModel,
                isExpanded: true,
                decoration: _decoration('Modèle'),
                items: widget.models
                    .map(
                      (model) => DropdownMenuItem(
                        value: model,
                        child: Text(
                          '${model.name} — ${model.brand}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedModel = value;
                    _resolvedOperationalEventIds.clear();

                    if (_selectedDate.isBefore(_firstAllowedDate)) {
                      _selectedDate = _firstAllowedDate;
                    }
                  });
                },
              ),
              if (_selectedModelOpenEvents.isNotEmpty) ...[
                const SizedBox(height: 14),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.notification_important_outlined),
                          title: Text(
                            'Éléments en attente issus des sessions',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            'Coche uniquement ce qui est réellement traité '
                            'dans cette maintenance.',
                          ),
                        ),
                        for (final event in _selectedModelOpenEvents)
                          CheckboxListTile(
                            value: _resolvedOperationalEventIds.contains(
                              event.eventId,
                            ),
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            secondary: Icon(
                              _operationalEventIcon(event),
                              color: _operationalEventColor(context, event),
                            ),
                            title: Text(
                              _operationalEventLabel(event),
                              style: TextStyle(
                                color: _operationalEventColor(context, event),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            subtitle: Text(event.description),
                            onChanged: (checked) {
                              setState(() {
                                if (checked == true) {
                                  _resolvedOperationalEventIds.add(
                                    event.eventId,
                                  );
                                } else {
                                  _resolvedOperationalEventIds.remove(
                                    event.eventId,
                                  );
                                }
                              });
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              DropdownButtonFormField<_MaintenanceType>(
                initialValue: _selectedType,
                decoration: _decoration('Type'),
                items: _MaintenanceType.values
                    .map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Text(type.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) {
                    return;
                  }

                  setState(() {
                    _selectedType = value;
                    _errorMessage = null;
                  });
                },
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: _selectedModel == null ? null : _selectDate,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: _decoration('Date'),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_outlined),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_formatDate(_selectedDate))),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (_selectedType == _MaintenanceType.revision)
                _buildRevisionFields()
              else
                _buildSimpleFields(),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w700,
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
          child: const Text('Annuler la maintenance'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(
            widget.record == null
                ? 'Enregistrer'
                : 'Enregistrer les modifications',
          ),
        ),
      ],
    );
  }

  Future<void> _openExpandedTextEditor({
    required TextEditingController controller,
    required String title,
    required String hint,
  }) async {
    final editorController = TextEditingController(text: controller.text);

    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 680,
          child: TextField(
            controller: editorController,
            autofocus: true,
            minLines: 10,
            maxLines: 18,
            decoration: InputDecoration(
              hintText: hint,
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(editorController.text),
            child: const Text('Valider le texte'),
          ),
        ],
      ),
    );

    editorController.dispose();

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      controller.text = result;
    });
  }

  Widget _expandableTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    return InkWell(
      onTap: () => _openExpandedTextEditor(
        controller: controller,
        title: label,
        hint: hint,
      ),
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: _decoration(
          label,
          hint: hint,
        ).copyWith(suffixIcon: const Icon(Icons.open_in_full)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Align(
            alignment: Alignment.topLeft,
            child: Text(
              controller.text.trim().isEmpty ? hint : controller.text.trim(),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: controller.text.trim().isEmpty
                  ? TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRevisionFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Card(
          child: ListTile(
            leading: Icon(Icons.auto_graph_outlined),
            title: Text('Compteurs calculés automatiquement'),
            subtitle: Text(
              'Chaque roulage compte pour un pack consommé. '
              'Le temps correspond à la somme des durées renseignées. '
              'Une révision rétroactive recalcule la chronologie.',
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Fluides remplacés (optionnel)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 620
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;

            Widget field(String key, String label) {
              return SizedBox(
                width: width,
                child: TextField(
                  controller: _fluidControllers[key],
                  decoration: _decoration(
                    label,
                    hint: 'Ex. 500 000',
                    suffix: 'cSt',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              );
            }

            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                field('diffFront', 'Différentiel avant'),
                field('diffCenter', 'Différentiel central'),
                field('diffRear', 'Différentiel arrière'),
                field('shockFront', 'Amortisseurs avant'),
                field('shockRear', 'Amortisseurs arrière'),
              ],
            );
          },
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Text(
                'Réglages modifiés (optionnel)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            OutlinedButton.icon(
              onPressed: _addSetupChange,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un réglage'),
            ),
          ],
        ),
        if (_setupChanges.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (var index = 0; index < _setupChanges.length; index++) ...[
            _SetupChangeRow(
              editor: _setupChanges[index],
              choices: _setupFieldChoices,
              onRemove: () => _removeSetupChange(index),
            ),
            if (index != _setupChanges.length - 1) const SizedBox(height: 10),
          ],
        ],
        const SizedBox(height: 18),
        _expandableTextField(
          controller: _notesController,
          label: 'Texte libre',
          hint: 'Travaux effectués, éléments contrôlés, remarques…',
        ),
      ],
    );
  }

  Widget _buildSimpleFields() {
    final isRepair = _selectedType == _MaintenanceType.reparation;
    final isAdjustment = _selectedType == _MaintenanceType.reglage;

    return Column(
      children: [
        TextField(
          controller: _titleController,
          decoration: _decoration(
            isRepair
                ? 'Réparation effectuée'
                : isAdjustment
                ? 'Réglage effectué'
                : 'Modification réalisée',
            hint: isRepair
                ? 'Ex. Remplacement du servo de direction'
                : isAdjustment
                ? 'Ex. Contrôle de la direction et réglage du trim'
                : 'Ex. Montage d’un nouveau moteur',
          ),
        ),
        const SizedBox(height: 14),
        _expandableTextField(
          controller: _notesController,
          label: 'Description',
          hint: isRepair
              ? 'Décris simplement la panne et ce qui a été fait.'
              : isAdjustment
              ? 'Décris simplement le contrôle et les réglages effectués.'
              : 'Décris simplement les éléments ajoutés, retirés ou modifiés.',
        ),
      ],
    );
  }
}

class _SetupChangeRow extends StatefulWidget {
  const _SetupChangeRow({
    required this.editor,
    required this.choices,
    required this.onRemove,
  });

  final _SetupChangeEditor editor;
  final List<_SetupFieldChoice> choices;
  final VoidCallback onRemove;

  @override
  State<_SetupChangeRow> createState() => _SetupChangeRowState();
}

class _SetupChangeRowState extends State<_SetupChangeRow> {
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final dropdown = DropdownButtonFormField<String>(
              initialValue: widget.editor.fieldKey,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Élément du setup',
                border: OutlineInputBorder(),
              ),
              items: widget.choices
                  .map(
                    (choice) => DropdownMenuItem(
                      value: choice.keyName,
                      child: Text(
                        choice.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  widget.editor.fieldKey = value;
                });
              },
            );

            final valueField = TextField(
              controller: widget.editor.valueController,
              decoration: const InputDecoration(
                labelText: 'Nouvelle valeur',
                border: OutlineInputBorder(),
              ),
            );

            if (constraints.maxWidth < 560) {
              return Column(
                children: [
                  dropdown,
                  const SizedBox(height: 10),
                  valueField,
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      tooltip: 'Retirer ce réglage',
                      onPressed: widget.onRemove,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                ],
              );
            }

            return Row(
              children: [
                Expanded(flex: 2, child: dropdown),
                const SizedBox(width: 10),
                Expanded(child: valueField),
                IconButton(
                  tooltip: 'Retirer ce réglage',
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MaintenanceDetailsDialog extends StatelessWidget {
  const _MaintenanceDetailsDialog({required this.record});

  final _MaintenanceRecord record;

  @override
  Widget build(BuildContext context) {
    final fluids = record.fluids;
    final setupChanges = record.setupChanges;

    return AlertDialog(
      title: Text('${record.type.label} — ${record.modelName}'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailLine('Date', _formatDate(record.date)),
              if (record.title.isNotEmpty) _detailLine('Titre', record.title),
              if (record.type == _MaintenanceType.revision) ...[
                _detailLine(
                  'Packs consommés',
                  '${record.packsSinceLastRevision ?? 0}',
                ),
                _detailLine(
                  'Temps d’utilisation',
                  _durationLabel(record.runtimeMinutesSinceLastRevision),
                ),
              ],
              if (fluids.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  'Fluides remplacés',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final entry in fluids.entries)
                  _detailLine(_fluidLabel(entry.key), '${entry.value} cSt'),
              ],
              if (setupChanges.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  'Réglages modifiés',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (final change in setupChanges)
                  _detailLine(
                    change['field'] ?? 'Réglage',
                    change['newValue'] ?? '',
                  ),
              ],
              if (record.notes.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(
                  record.type == _MaintenanceType.revision
                      ? 'Texte libre'
                      : 'Description',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                SelectableText(record.notes),
              ],
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fermer'),
        ),
      ],
    );
  }

  static Widget _detailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label : ',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  static String _fluidLabel(String key) {
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

  static String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }

  static String _durationLabel(int? minutes) {
    if (minutes == null) {
      return 'Non calculé';
    }

    final hours = minutes ~/ 60;
    final remaining = minutes % 60;

    if (hours == 0) {
      return '$remaining min';
    }

    if (remaining == 0) {
      return '${hours}h';
    }

    return '${hours}h ${remaining}min';
  }
}

enum _MaintenanceType {
  revision,
  reparation,
  reglage,
  modification;

  String get label {
    switch (this) {
      case _MaintenanceType.revision:
        return 'Révision';
      case _MaintenanceType.reparation:
        return 'Réparation';
      case _MaintenanceType.reglage:
        return 'Réglage';
      case _MaintenanceType.modification:
        return 'Modification';
    }
  }

  String get databaseValue {
    switch (this) {
      case _MaintenanceType.revision:
        return 'REVISION';
      case _MaintenanceType.reparation:
        return 'REPARATION';
      case _MaintenanceType.reglage:
        return 'MODIFICATION';
      case _MaintenanceType.modification:
        return 'MODIFICATION';
    }
  }

  IconData get icon {
    switch (this) {
      case _MaintenanceType.revision:
        return Icons.tune;
      case _MaintenanceType.reparation:
        return Icons.handyman_outlined;
      case _MaintenanceType.reglage:
        return Icons.tune_outlined;
      case _MaintenanceType.modification:
        return Icons.construction_outlined;
    }
  }

  static _MaintenanceType fromDatabase(String value) {
    switch (value) {
      case 'REPARATION':
        return _MaintenanceType.reparation;
      case 'MODIFICATION':
        return _MaintenanceType.modification;
      case 'REVISION':
      default:
        return _MaintenanceType.revision;
    }
  }
}

class _MaintenanceDraft {
  const _MaintenanceDraft({
    required this.model,
    required this.date,
    required this.type,
    required this.title,
    required this.notes,
    required this.data,
    this.resolvedOperationalEventIds = const <String>{},
  });

  final RcModel model;
  final DateTime date;
  final _MaintenanceType type;
  final String title;
  final String notes;
  final Map<String, dynamic> data;
  final Set<String> resolvedOperationalEventIds;

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
}

class _MaintenanceRecord {
  const _MaintenanceRecord({
    required this.id,
    required this.modelId,
    required this.modelName,
    required this.modelBrand,
    required this.modelCategory,
    required this.date,
    required this.type,
    required this.title,
    required this.notes,
    required this.data,
    this.packsSinceLastRevision,
    this.runtimeMinutesSinceLastRevision,
  });

  final String id;
  final String modelId;
  final String modelName;
  final String modelBrand;
  final String modelCategory;
  final DateTime date;
  final _MaintenanceType type;
  final String title;
  final String notes;
  final Map<String, dynamic> data;
  final int? packsSinceLastRevision;
  final int? runtimeMinutesSinceLastRevision;

  String get maintenanceGroupId {
    final value = data['maintenanceGroupId']?.toString().trim() ?? '';
    return value.isEmpty ? id : value;
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

  factory _MaintenanceRecord.fromMap(
    Map<String, dynamic> row,
    Map<String, RcModel> modelById,
  ) {
    final modelId = row['model_id'] as String;
    final model = modelById[modelId];
    final rawData = row['data'];
    final data = rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : const <String, dynamic>{};

    return _MaintenanceRecord(
      id: row['id'] as String,
      modelId: modelId,
      modelName: model?.name ?? 'Modèle supprimé',
      modelBrand: model?.brand ?? '',
      modelCategory: model?.category ?? '',
      date: DateTime.parse(row['maintenance_date'].toString()).toLocal(),
      type:
          row['record_type']?.toString() == 'MODIFICATION' &&
              data['interventionSubtype']?.toString() == 'REGLAGE'
          ? _MaintenanceType.reglage
          : _MaintenanceType.fromDatabase(
              row['record_type'] as String? ?? 'REVISION',
            ),
      title: row['title'] as String? ?? '',
      notes: row['notes'] as String? ?? '',
      data: data,
      packsSinceLastRevision: (row['packs_since_last_revision'] as num?)
          ?.toInt(),
      runtimeMinutesSinceLastRevision:
          (row['runtime_minutes_since_last_revision'] as num?)?.toInt(),
    );
  }
}

class _MaintenanceGroup {
  const _MaintenanceGroup({required this.id, required this.interventions});

  final String id;
  final List<_MaintenanceRecord> interventions;

  _MaintenanceRecord get first => interventions.first;
  String get modelName => first.modelName;
  DateTime get date => interventions
      .map((record) => record.date)
      .reduce((a, b) => a.isAfter(b) ? a : b);
}

class _SetupFieldChoice {
  const _SetupFieldChoice(this.keyName, this.label);

  final String keyName;
  final String label;
}

class _SetupChangeEditor {
  String? fieldKey;
  final TextEditingController valueController = TextEditingController();

  void dispose() {
    valueController.dispose();
  }
}

class _RunStat {
  const _RunStat({required this.startedAt, required this.durationMinutes});

  final DateTime startedAt;
  final int? durationMinutes;
}
