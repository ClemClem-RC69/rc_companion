import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../models/battery.dart';
import '../../models/rc_model.dart';
import '../../models/rc_session.dart';
import '../../services/battery_service.dart';
import '../../services/supabase_service.dart';
import '../../services/session_service.dart';
import '../batteries/battery_scanner_page.dart';
import 'session_detail_page.dart';

class SessionsPage extends StatefulWidget {
  const SessionsPage({super.key});

  @override
  State<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<SessionsPage> {
  Battery? _battery1;
  Battery? _battery2;

  List<RcModel> _availableModels = [];
  List<Battery> _availableBatteries = [];
  bool _isLoadingData = true;
  String? _loadingError;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoadingData = true;
      _loadingError = null;
    });

    try {
      final user = SupabaseService.client.auth.currentUser;

      if (user == null) {
        throw StateError('Aucun utilisateur connecté.');
      }

      final modelFuture = SupabaseService.client
          .from('rc_models')
          .select()
          .eq('user_id', user.id)
          .order('created_at');

      final batteriesFuture = BatteryService.getBatteries();

      final modelRows = await modelFuture;
      final loadedBatteries = await batteriesFuture;

      final loadedModels = modelRows.map((row) {
        final json = Map<String, dynamic>.from(row as Map);

        final maxCellsValue = json['max_cells'];
        final batteryCountValue = json['battery_count'];

        return RcModel(
          id: json['id'] as String?,
          name: json['name'] as String? ?? 'Modèle sans nom',
          brand: json['brand'] as String? ?? 'Marque non renseignée',
          category: json['category'] as String? ?? '',
          discipline: json['discipline'] as String? ?? '',
          motorization: json['motorization'] as String? ?? 'Électrique',
          scale: json['scale'] as String? ?? '',
          weightKg: (json['weight_kg'] as num?)?.toDouble(),
          batteryCount: (batteryCountValue as num?)?.toInt() ?? 0,
          maxCells: maxCellsValue == null
              ? 'Aucune'
              : '${(maxCellsValue as num).toInt()}S',
          photoUrl: json['photo_url'] as String?,
          acquisitionDate: json['acquisition_date'] == null
              ? null
              : DateTime.tryParse(json['acquisition_date'].toString()),
          purchaseType: json['purchase_type'] as String?,
          purchaseLocation: json['purchase_location'] as String?,
          radioId: json['radio_id'] as String?,
        );
      }).toList();

      final loadedSessions = await SessionService.getSessions(
        models: loadedModels,
        batteries: loadedBatteries,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _availableModels = loadedModels;
        _availableBatteries = loadedBatteries;
        sessions
          ..clear()
          ..addAll(loadedSessions);
        _isLoadingData = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingError = error.toString();
        _isLoadingData = false;
      });
    }
  }

  RcSession? get _activeSession {
    for (final session in sessions.reversed) {
      if (!session.isClosed) {
        return session;
      }
    }
    return null;
  }

  bool _isHistoricalSession(RcSession session) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final sessionDay = DateTime(
      session.startedAt.year,
      session.startedAt.month,
      session.startedAt.day,
    );

    return sessionDay.isBefore(today);
  }

  DateTime _historicalRunStart(RcSession session) {
    if (session.runs.isEmpty) {
      return session.startedAt;
    }

    final previous = session.runs.last;
    return previous.endedAt ??
        previous.startedAt.add(
          Duration(minutes: previous.effectiveDurationMinutes),
        );
  }

  int _sessionIndex(RcSession session) {
    return sessions.indexWhere((item) => identical(item, session));
  }

  Future<bool> _replaceSession(RcSession current, RcSession updated) async {
    final index = _sessionIndex(current);

    if (index == -1) {
      return false;
    }

    try {
      final savedSession = await SessionService.saveSession(updated);

      if (!mounted) {
        return false;
      }

      setState(() {
        sessions[index] = savedSession;
      });

      return true;
    } catch (error) {
      _showMessage('Sauvegarde de la session impossible : $error');
      return false;
    }
  }

  int _cellsNumber(String value) {
    return int.tryParse(value.replaceAll('S', '').trim()) ?? 0;
  }

  int _modelTotalCells(RcModel model) {
    final cellsPerPack = _cellsNumber(model.maxCells);
    final configuredBatteryCount = model.batteryCount <= 0
        ? 1
        : model.batteryCount;

    return cellsPerPack * configuredBatteryCount;
  }

  bool _canAddSecondBattery(RcSession session) {
    final first = _battery1;

    if (first == null) {
      return false;
    }

    final firstCells = _cellsNumber(first.cells);
    final totalLimit = _modelTotalCells(session.model);

    return firstCells > 0 && firstCells * 2 <= totalLimit;
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

  String _batteryLabel(Battery battery) {
    return '${battery.brand} — ${battery.technology} — '
        '${battery.cells} — ${battery.capacity} mAh — ${battery.cRate}C — '
        '${battery.chargeDisplayLabel}';
  }

  Future<void> _openSession() async {
    if (_activeSession != null) {
      _showMessage('Une session est déjà ouverte.');
      return;
    }

    if (_availableModels.isEmpty) {
      _showMessage('Enregistre d’abord un modèle.');
      return;
    }

    final result = await showDialog<_OpenSessionResult>(
      context: context,
      builder: (context) => _OpenSessionDialog(models: _availableModels),
    );

    if (result == null) {
      return;
    }

    try {
      final savedSession = await SessionService.saveSession(
        RcSession(
          model: result.model,
          startedAt: result.startedAt,
          location: result.location,
        ),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        sessions.add(savedSession);
        _battery1 = null;
        _battery2 = null;
      });
    } catch (error) {
      _showMessage('Ouverture de la session impossible : $error');
    }
  }

  Future<void> _scanBattery({required int position}) async {
    final scannedValue = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => BatteryScannerPage(
          title: position == 1
              ? 'Scanner la batterie 1'
              : 'Scanner la batterie 2',
        ),
      ),
    );

    if (!mounted || scannedValue == null) {
      return;
    }

    final battery = _findBatteryFromQr(scannedValue);

    if (battery == null) {
      _showMessage('Aucune batterie enregistrée ne correspond à ce QR Code.');
      return;
    }

    if (!battery.isUsable) {
      _showMessage(
        '${battery.id} est « ${battery.chargeDisplayLabel} » et ne peut pas être utilisée pour un roulage.',
      );
      return;
    }

    setState(() {
      if (position == 1) {
        _battery1 = battery;
        _battery2 = null;
      } else {
        _battery2 = battery;
      }
    });

    final activeSession = _activeSession;

    if (position == 1 && activeSession != null && mounted) {
      if (_canAddSecondBattery(activeSession)) {
        _showMessage(
          'Première batterie reconnue. Tu peux ajouter une deuxième batterie compatible.',
        );
      } else {
        _showMessage(
          'Batterie reconnue. La limite totale du modèle est atteinte : aucune deuxième batterie n’est nécessaire.',
        );
      }
    }
  }

  Battery? _findBatteryFromQr(String scannedValue) {
    final normalized = scannedValue.trim();

    for (final battery in _availableBatteries) {
      if (battery.id.toLowerCase() == normalized.toLowerCase()) {
        return battery;
      }
    }

    final containedMatches = _availableBatteries.where(
      (battery) => normalized.toLowerCase().contains(battery.id.toLowerCase()),
    );

    if (containedMatches.length == 1) {
      return containedMatches.first;
    }

    return null;
  }

  List<Battery> _compatibleSecondBatteries(RcSession session) {
    final first = _battery1;

    if (first == null) {
      return const [];
    }

    final modelTotalCells = _modelTotalCells(session.model);

    final compatible = _availableBatteries.where((battery) {
      if (battery.id == first.id) {
        return false;
      }

      if (!battery.isUsable) {
        return false;
      }

      if (_cellsNumber(first.cells) + _cellsNumber(battery.cells) >
          modelTotalCells) {
        return false;
      }

      // Le pairId et la marque ne bloquent jamais la sélection.
      // Seules les caractéristiques techniques validées pour une paire
      // sont obligatoires.
      return battery.technology == first.technology &&
          battery.cells == first.cells &&
          battery.capacity == first.capacity &&
          battery.cRate == first.cRate;
    }).toList();

    compatible.sort((a, b) {
      final aIsTwin =
          first.pairId != null &&
          first.pairId!.isNotEmpty &&
          a.pairId == first.pairId;
      final bIsTwin =
          first.pairId != null &&
          first.pairId!.isNotEmpty &&
          b.pairId == first.pairId;

      if (aIsTwin != bIsTwin) {
        return aIsTwin ? -1 : 1;
      }

      return a.id.compareTo(b.id);
    });

    return List<Battery>.unmodifiable(compatible);
  }

  Future<void> _selectBatteryManually({
    required int position,
    required List<Battery> choices,
  }) async {
    final selected = await showDialog<Battery>(
      context: context,
      builder: (context) => _BatteryChoiceDialog(
        title: 'Choisir la batterie $position',
        batteries: choices,
        labelBuilder: _batteryLabel,
      ),
    );

    if (selected == null || !mounted) {
      return;
    }

    setState(() {
      if (position == 1) {
        _battery1 = selected;
        _battery2 = null;
      } else {
        _battery2 = selected;
      }
    });
  }

  _CompatibilityResult _checkCompatibility(RcSession session) {
    final model = session.model;

    if (model.motorization == 'Thermique') {
      return const _CompatibilityResult(
        isValid: true,
        message: 'Modèle thermique : aucune batterie de propulsion requise.',
      );
    }

    final first = _battery1;

    if (first == null) {
      if (_isHistoricalSession(session)) {
        return const _CompatibilityResult(
          isValid: true,
          message:
              'Session rétroactive : les batteries utilisées peuvent rester non renseignées.',
        );
      }

      return const _CompatibilityResult(
        isValid: false,
        message: 'Scanne ou sélectionne la première batterie.',
      );
    }

    if (!first.isUsable) {
      return _CompatibilityResult(
        isValid: false,
        message:
            '${first.id} ne peut pas être utilisée : état de charge « ${first.chargeDisplayLabel} ».',
      );
    }

    final totalLimit = _modelTotalCells(model);
    final firstCells = _cellsNumber(first.cells);

    if (firstCells > totalLimit) {
      return _CompatibilityResult(
        isValid: false,
        message:
            '${first.id} est en ${first.cells}, alors que la configuration du modèle accepte ${totalLimit}S au total maximum.',
      );
    }

    final second = _battery2;

    if (second == null) {
      if (_canAddSecondBattery(session)) {
        final warnings = <String>[];

        if (first.isPaired) {
          warnings.add('Cette batterie appartient à une paire enregistrée.');
        }

        return _CompatibilityResult(
          isValid: true,
          hasWarning: warnings.isNotEmpty,
          message: warnings.isNotEmpty
              ? '${warnings.join(' ')} Tu peux l’utiliser seule ou ajouter une deuxième batterie compatible.'
              : 'Batterie compatible. Tu peux démarrer avec cette seule batterie ou en ajouter une deuxième compatible.',
        );
      }

      if (first.isPaired) {
        return const _CompatibilityResult(
          isValid: true,
          hasWarning: true,
          message:
              'Cette batterie appartient à une paire enregistrée. La limite totale du modèle est atteinte, elle sera utilisée seule.',
        );
      }

      return const _CompatibilityResult(
        isValid: true,
        message:
            'Batterie compatible. La limite totale du modèle est atteinte, aucune deuxième batterie n’est nécessaire.',
      );
    }

    if (identical(first, second) || first.id == second.id) {
      return const _CompatibilityResult(
        isValid: false,
        message: 'La même batterie ne peut pas être utilisée deux fois.',
      );
    }

    if (!second.isUsable) {
      return _CompatibilityResult(
        isValid: false,
        message:
            '${second.id} ne peut pas être utilisée : état de charge « ${second.chargeDisplayLabel} ».',
      );
    }

    final secondCells = _cellsNumber(second.cells);

    if (firstCells + secondCells > totalLimit) {
      return _CompatibilityResult(
        isValid: false,
        message:
            'Le total de ${firstCells + secondCells}S dépasse la limite de ${totalLimit}S du modèle.',
      );
    }

    if (first.technology != second.technology) {
      return const _CompatibilityResult(
        isValid: false,
        message: 'Les deux batteries doivent avoir la même technologie.',
      );
    }

    if (first.cells != second.cells) {
      return const _CompatibilityResult(
        isValid: false,
        message: 'Les deux batteries doivent avoir le même nombre de cellules.',
      );
    }

    if (first.capacity != second.capacity) {
      return const _CompatibilityResult(
        isValid: false,
        message: 'Les deux batteries doivent avoir la même capacité.',
      );
    }

    if (first.cRate != second.cRate) {
      return const _CompatibilityResult(
        isValid: false,
        message: 'Les deux batteries doivent avoir le même taux C.',
      );
    }

    final warnings = <String>[];

    final sameRegisteredPair =
        first.pairId != null &&
        first.pairId!.isNotEmpty &&
        first.pairId == second.pairId;

    if (!sameRegisteredPair) {
      warnings.add(
        'Ces batteries ne correspondent pas à la même paire enregistrée.',
      );
    }

    if (first.brand != second.brand) {
      warnings.add('Leurs marques sont différentes.');
    }

    if (warnings.isNotEmpty) {
      return _CompatibilityResult(
        isValid: true,
        hasWarning: true,
        message:
            '${warnings.join(' ')} Leurs caractéristiques restent compatibles.',
      );
    }

    return const _CompatibilityResult(
      isValid: true,
      message: 'Jeu de batteries compatible.',
    );
  }

  Future<void> _startRun(RcSession session) async {
    if (session.hasActiveRun) {
      _showMessage('Un roulage est déjà en cours.');
      return;
    }

    final compatibility = _checkCompatibility(session);

    if (!compatibility.isValid) {
      _showMessage(compatibility.message);
      return;
    }

    if (compatibility.hasWarning) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.warning_amber),
          title: const Text('Vérification du jeu de batteries'),
          content: Text(compatibility.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Scanner à nouveau'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Utiliser quand même'),
            ),
          ],
        ),
      );

      if (confirmed != true || !mounted) {
        return;
      }
    }

    final selectedBatteries = <Battery>[];

    if (_battery1 != null) {
      selectedBatteries.add(_battery1!);
    }

    if (_battery2 != null) {
      selectedBatteries.add(_battery2!);
    }

    final updatedRuns = List<RcRun>.from(session.runs)
      ..add(
        RcRun(
          startedAt: _isHistoricalSession(session)
              ? _historicalRunStart(session)
              : DateTime.now(),
          batteries: List<Battery>.unmodifiable(selectedBatteries),
        ),
      );

    final saved = await _replaceSession(
      session,
      session.copyWith(runs: updatedRuns),
    );

    if (!saved || !mounted) {
      return;
    }

    setState(() {
      _battery1 = null;
      _battery2 = null;
    });

    _showMessage('Roulage démarré.');
  }

  Future<void> _editRun(RcSession session, int runIndex) async {
    if (runIndex < 0 || runIndex >= session.runs.length) {
      return;
    }

    final run = session.runs[runIndex];

    if (run.isActive) {
      _showMessage('Termine le roulage avant de le modifier.');
      return;
    }

    final result = await showDialog<_EndRunResult>(
      context: context,
      builder: (context) => _EditRunDialog(
        durationMinutes: run.effectiveDurationMinutes,
        notes: run.notes,
      ),
    );

    if (result == null) {
      return;
    }

    final updatedRuns = List<RcRun>.from(session.runs);
    updatedRuns[runIndex] = run.copyWith(
      durationMinutes: result.durationMinutes,
      notes: result.notes,
    );

    final saved = await _replaceSession(
      session,
      session.copyWith(runs: updatedRuns),
    );

    if (saved) {
      _showMessage('Roulage modifié.');
    }
  }

  Future<RcRun?> _askMeasurementsAfterRun(RcRun run, int runNumber) async {
    final choice = await showDialog<_MeasurementChoice>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.monitor_heart_outlined),
        title: const Text('Mesures des batteries'),
        content: const Text(
          'Souhaites-tu renseigner maintenant le relevé de fin de roulage '
          'des batteries utilisées ?',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_MeasurementChoice.later),
            child: const Text('Ultérieurement dans Batteries'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_MeasurementChoice.now),
            child: const Text('Renseigner maintenant'),
          ),
        ],
      ),
    );

    if (choice == null) {
      return null;
    }

    if (choice == _MeasurementChoice.later) {
      return run;
    }

    final updatedReadings = List<BatteryRunReading>.from(run.readings);

    for (final battery in run.batteries) {
      final existingIndex = updatedReadings.indexWhere(
        (reading) => reading.batteryId == battery.id,
      );

      if (existingIndex != -1 &&
          updatedReadings[existingIndex].hasMeasurements) {
        continue;
      }

      if (!mounted) {
        return null;
      }

      final reading = await showDialog<BatteryRunReading?>(
        context: context,
        barrierDismissible: false,
        builder: (context) =>
            _BatteryMeasurementDialog(battery: battery, runNumber: runNumber),
      );

      if (reading == null) {
        continue;
      }

      if (existingIndex == -1) {
        updatedReadings.add(reading);
      } else {
        updatedReadings[existingIndex] = reading;
      }
    }

    return run.copyWith(readings: updatedReadings);
  }

  Future<void> _endActiveRun(RcSession session) async {
    final activeRun = session.activeRun;

    if (activeRun == null) {
      return;
    }

    final elapsedMinutes = _isHistoricalSession(session)
        ? 1
        : DateTime.now()
              .difference(activeRun.startedAt)
              .inMinutes
              .clamp(1, 9999);

    final result = await showDialog<_EndRunResult>(
      context: context,
      builder: (context) => _EndRunDialog(suggestedDuration: elapsedMinutes),
    );

    if (result == null) {
      return;
    }

    final updatedRuns = List<RcRun>.from(session.runs);
    final runIndex = updatedRuns.lastIndexWhere(
      (run) => identical(run, activeRun),
    );

    if (runIndex == -1) {
      return;
    }

    final completedRun = activeRun.copyWith(
      endedAt: _isHistoricalSession(session)
          ? activeRun.startedAt.add(Duration(minutes: result.durationMinutes))
          : DateTime.now(),
      durationMinutes: result.durationMinutes,
      notes: result.notes,
    );

    final completedRunWithMeasurements = await _askMeasurementsAfterRun(
      completedRun,
      runIndex + 1,
    );

    if (completedRunWithMeasurements == null || !mounted) {
      return;
    }

    updatedRuns[runIndex] = completedRunWithMeasurements;

    final saved = await _replaceSession(
      session,
      session.copyWith(runs: updatedRuns),
    );

    if (!saved) {
      return;
    }

    _showMessage('Roulage enregistré.');
  }

  Future<RcSession?> _askForMeasurementsBeforeClosing(RcSession session) async {
    final hasMissingMeasurements = session.runs.any(
      (run) => run.batteries.any((battery) {
        final reading = run.readings.where(
          (item) => item.batteryId == battery.id,
        );

        return reading.isEmpty || !reading.first.hasMeasurements;
      }),
    );

    if (!hasMissingMeasurements) {
      return session;
    }

    final choice = await showDialog<_MeasurementChoice>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.monitor_heart_outlined),
        title: const Text('Mesures des batteries'),
        content: const Text(
          'Souhaites-tu renseigner maintenant les relevés de fin de roulage '
          'manquants des batteries utilisées pendant cette session ?',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_MeasurementChoice.later),
            child: const Text('Ultérieurement dans Batteries'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_MeasurementChoice.now),
            child: const Text('Renseigner maintenant'),
          ),
        ],
      ),
    );

    if (choice == null) {
      return null;
    }

    if (choice == _MeasurementChoice.later) {
      return session;
    }

    var updatedSession = session;
    final updatedRuns = List<RcRun>.from(session.runs);

    for (var runIndex = 0; runIndex < updatedRuns.length; runIndex++) {
      final run = updatedRuns[runIndex];
      final updatedReadings = List<BatteryRunReading>.from(run.readings);

      for (final battery in run.batteries) {
        final existingIndex = updatedReadings.indexWhere(
          (reading) => reading.batteryId == battery.id,
        );

        if (existingIndex != -1 &&
            updatedReadings[existingIndex].hasMeasurements) {
          continue;
        }

        if (!mounted) {
          return null;
        }

        final reading = await showDialog<BatteryRunReading?>(
          context: context,
          barrierDismissible: false,
          builder: (context) => _BatteryMeasurementDialog(
            battery: battery,
            runNumber: runIndex + 1,
          ),
        );

        if (reading == null) {
          continue;
        }

        if (existingIndex == -1) {
          updatedReadings.add(reading);
        } else {
          updatedReadings[existingIndex] = reading;
        }
      }

      updatedRuns[runIndex] = run.copyWith(readings: updatedReadings);
    }

    updatedSession = session.copyWith(runs: updatedRuns);
    return updatedSession;
  }

  Future<void> _editSessionGeneral(RcSession session) async {
    final result = await showDialog<_EditSessionGeneralResult>(
      context: context,
      builder: (context) =>
          _EditSessionGeneralDialog(session: session, models: _availableModels),
    );

    if (result == null) {
      return;
    }

    final saved = await _replaceSession(
      session,
      session.copyWith(model: result.model, location: result.location),
    );

    if (saved) {
      _showMessage('Modèle et lieu modifiés.');
    }
  }

  Future<void> _closeSession(RcSession session) async {
    if (session.hasActiveRun) {
      _showMessage('Termine le roulage en cours avant de clôturer la session.');
      return;
    }

    final sessionWithMeasurements = await _askForMeasurementsBeforeClosing(
      session,
    );

    if (sessionWithMeasurements == null || !mounted) {
      return;
    }

    final result = await showDialog<_CloseSessionResult>(
      context: context,
      builder: (context) => const _CloseSessionDialog(),
    );

    if (result == null) {
      return;
    }

    final saved = await _replaceSession(
      session,
      sessionWithMeasurements.copyWith(
        endedAt: _isHistoricalSession(sessionWithMeasurements)
            ? (sessionWithMeasurements.runs.isEmpty
                  ? sessionWithMeasurements.startedAt
                  : sessionWithMeasurements.runs.last.endedAt ??
                        sessionWithMeasurements.runs.last.startedAt.add(
                          Duration(
                            minutes: sessionWithMeasurements
                                .runs
                                .last
                                .effectiveDurationMinutes,
                          ),
                        ))
            : DateTime.now(),
        drivingNotes: result.drivingNotes,
        breakages: result.breakages,
        partsReplacedOnSite: result.partsReplacedOnSite,
        maintenanceToDo: result.maintenanceToDo,
        partsToOrder: result.partsToOrder,
        changesBeforeNextSession: result.changesBeforeNextSession,
        generalNotes: result.generalNotes,
      ),
    );

    if (!saved || !mounted) {
      return;
    }

    setState(() {
      _battery1 = null;
      _battery2 = null;
    });

    _showMessage('Session clôturée.');
  }

  Future<void> _cancelActiveSession(RcSession session) async {
    final sessionId = session.id;

    if (sessionId == null || sessionId.isEmpty) {
      _showMessage('Cette session ne peut pas être annulée.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded),
        title: const Text('Annuler la session en cours ?'),
        content: const Text(
          'Tous les roulages et toutes les mesures enregistrés dans cette '
          'session seront supprimés définitivement.\n\n'
          'Cette action est irréversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Conserver la session'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Annuler la session'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await SessionService.deleteSession(sessionId);

      if (!mounted) {
        return;
      }

      setState(() {
        sessions.removeWhere((item) => item.id == sessionId);
        _battery1 = null;
        _battery2 = null;
      });

      _showMessage('Session annulée.');
    } catch (error) {
      _showMessage('Annulation impossible : $error');
    }
  }

  Future<void> _openSessionDetail(RcSession session) async {
    final updatedSession = await Navigator.of(context).push<RcSession>(
      MaterialPageRoute(builder: (_) => SessionDetailPage(session: session)),
    );

    if (updatedSession == null || !mounted) {
      return;
    }

    final index = sessions.indexWhere((item) => item.id == updatedSession.id);

    if (index == -1) {
      return;
    }

    setState(() {
      sessions[index] = updatedSession;
    });
  }

  Future<void> _deleteClosedSession(RcSession session) async {
    final sessionId = session.id;

    if (sessionId == null || sessionId.isEmpty) {
      _showMessage('Cette session ne peut pas être supprimée.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_forever_outlined),
        title: const Text('Supprimer cette session ?'),
        content: Text(
          'La session de ${session.model.name} sera supprimée définitivement.\n\n'
          'Cette action est irréversible.',
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

    try {
      await SessionService.deleteSession(sessionId);

      if (!mounted) {
        return;
      }

      setState(() {
        sessions.removeWhere((item) => item.id == sessionId);
      });

      _showMessage('Session supprimée.');
    } catch (error) {
      _showMessage('Suppression impossible : $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final activeSession = _activeSession;

    if (_isLoadingData) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mes sessions')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_loadingError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mes sessions')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Impossible de charger les modèles et les batteries.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(_loadingError!, textAlign: TextAlign.center),
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
        title: const Text('Mes sessions'),
        actions: [
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: activeSession == null
          ? FloatingActionButton.extended(
              onPressed: _openSession,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Ouvrir une session'),
            )
          : null,
      body: activeSession == null
          ? _buildSessionHistory()
          : _buildActiveSession(activeSession),
    );
  }

  Widget _buildSessionHistory() {
    final closedSessions =
        sessions.where((session) => session.isClosed).toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

    if (closedSessions.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Aucune session enregistrée.\n\n'
            'Ouvre une session pour commencer une journée de roulage.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        const Text(
          'Historique',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        for (final session in closedSessions)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _openSessionDetail(session),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                child: Row(
                  children: [
                    const Icon(Icons.flag_outlined, size: 30),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.model.name,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(_formatDateTime(session.startedAt)),
                              const Text('•'),
                              Text('${session.runs.length} roulage(s)'),
                              const Text('•'),
                              Text(
                                _durationLabel(session.totalDurationMinutes),
                              ),
                              if (session.location.isNotEmpty) ...[
                                const Text('•'),
                                Text(
                                  session.location,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Wrap(
                      spacing: 4,
                      children: [
                        TextButton.icon(
                          onPressed: () => _editSessionGeneral(session),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Modifier'),
                        ),
                        TextButton.icon(
                          onPressed: () => _deleteClosedSession(session),
                          style: TextButton.styleFrom(
                            foregroundColor: Theme.of(
                              context,
                            ).colorScheme.error,
                          ),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Supprimer'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildActiveSession(RcSession session) {
    final activeRun = session.activeRun;
    final compatibility = _checkCompatibility(session);
    final isElectric = session.model.motorization == 'Électrique';
    final canAddSecondBattery = _canAddSecondBattery(session);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.flag_circle),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        session.model.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Modifier les informations de la session',
                      onPressed: () => _editSessionGeneral(session),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    const Chip(label: Text('EN COURS')),
                  ],
                ),
                const SizedBox(height: 8),
                Text('${session.model.brand} • ${session.model.motorization}'),
                Text('Ouverte le ${_formatDateTime(session.startedAt)}'),
                if (session.location.isNotEmpty)
                  Text('Lieu : ${session.location}'),
                const SizedBox(height: 8),
                Text(
                  '${session.runs.length} roulage(s) • '
                  '${_durationLabel(session.totalDurationMinutes)} enregistré',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _cancelActiveSession(session),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Annuler la session'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (activeRun != null)
          _buildActiveRunCard(session, activeRun)
        else ...[
          Text(
            session.runs.isEmpty ? 'Premier roulage' : 'Nouveau roulage',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (isElectric) ...[
            _BatterySelector(
              number: 1,
              battery: _battery1,
              batteries: _availableBatteries,
              labelBuilder: _batteryLabel,
              onScan: () => _scanBattery(position: 1),
              onManualSelect: () => _selectBatteryManually(
                position: 1,
                choices: _availableBatteries,
              ),
              onChanged: (value) {
                setState(() {
                  _battery1 = value;
                  _battery2 = null;
                });
              },
            ),
            if (canAddSecondBattery) ...[
              const SizedBox(height: 14),
              _BatterySelector(
                number: 2,
                battery: _battery2,
                batteries: _compatibleSecondBatteries(session),
                labelBuilder: _batteryLabel,
                onScan: () => _scanBattery(position: 2),
                onManualSelect: () => _selectBatteryManually(
                  position: 2,
                  choices: _compatibleSecondBatteries(session),
                ),
                onChanged: (value) {
                  setState(() {
                    _battery2 = value;
                  });
                },
              ),
            ],
            const SizedBox(height: 14),
            _CompatibilityCard(result: compatibility),
          ] else
            const Card(
              child: ListTile(
                leading: Icon(Icons.local_gas_station),
                title: Text('Modèle thermique'),
                subtitle: Text(
                  'Le roulage peut être démarré sans batterie de propulsion.',
                ),
              ),
            ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => _startRun(session),
            icon: const Icon(Icons.timer),
            label: const Text('Démarrer ce roulage'),
          ),
        ],
        if (session.runs.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            'Roulages de la session',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          for (var index = session.runs.length - 1; index >= 0; index--)
            _RunCard(
              number: index + 1,
              run: session.runs[index],
              formatDateTime: _formatDateTime,
              durationLabel: _durationLabel,
              onEdit: session.runs[index].isActive
                  ? null
                  : () => _editRun(session, index),
            ),
        ],
        const SizedBox(height: 24),
        OutlinedButton.icon(
          onPressed: session.hasActiveRun ? null : () => _closeSession(session),
          icon: const Icon(Icons.stop_circle_outlined),
          label: const Text('Clôturer la session'),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildActiveRunCard(RcSession session, RcRun activeRun) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            const Icon(Icons.timer, size: 42),
            const SizedBox(height: 8),
            Text(
              'Roulage en cours',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 6),
            Text('Démarré à ${_formatDateTime(activeRun.startedAt)}'),
            if (activeRun.batteries.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final battery in activeRun.batteries)
                Text(
                  battery.id,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => _endActiveRun(session),
              icon: const Icon(Icons.stop),
              label: const Text('Terminer ce roulage'),
            ),
          ],
        ),
      ),
    );
  }
}

class _BatterySelector extends StatelessWidget {
  const _BatterySelector({
    required this.number,
    required this.battery,
    required this.batteries,
    required this.labelBuilder,
    required this.onScan,
    required this.onManualSelect,
    required this.onChanged,
  });

  final int number;
  final Battery? battery;
  final List<Battery> batteries;
  final String Function(Battery battery) labelBuilder;
  final VoidCallback onScan;
  final VoidCallback onManualSelect;
  final ValueChanged<Battery?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Batterie $number',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: onScan,
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(
                battery == null
                    ? 'Scanner la batterie $number'
                    : 'Scanner à nouveau',
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: batteries.isEmpty ? null : onManualSelect,
              icon: const Icon(Icons.touch_app_outlined),
              label: const Text('Sélection batterie'),
            ),
            if (battery != null) ...[
              const SizedBox(height: 10),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.battery_full),
                title: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: battery!.id),
                      if (battery!.isPaired)
                        TextSpan(
                          text: '  [P-${battery!.pairId!.split('-').last}]',
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                    ],
                  ),
                ),
                subtitle: Text(labelBuilder(battery!)),
                trailing: IconButton(
                  tooltip: 'Retirer',
                  onPressed: () => onChanged(null),
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BatteryChoiceDialog extends StatelessWidget {
  const _BatteryChoiceDialog({
    required this.title,
    required this.batteries,
    required this.labelBuilder,
  });

  final String title;
  final List<Battery> batteries;
  final String Function(Battery battery) labelBuilder;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 620,
        height: 480,
        child: batteries.isEmpty
            ? const Center(
                child: Text('Aucune batterie compatible disponible.'),
              )
            : ListView.separated(
                itemCount: batteries.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final battery = batteries[index];

                  return ListTile(
                    enabled: battery.isUsable,
                    leading: Icon(
                      Icons.battery_charging_full,
                      color: battery.isUsable ? null : Colors.red.shade700,
                    ),
                    title: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: battery.id),
                          if (battery.isPaired)
                            TextSpan(
                              text: '  [P-${battery.pairId!.split('-').last}]',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                        ],
                      ),
                    ),
                    subtitle: Text(labelBuilder(battery)),
                    trailing: battery.isUsable
                        ? null
                        : Text(
                            battery.chargeDisplayLabel,
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                    onTap: battery.isUsable
                        ? () => Navigator.of(context).pop(battery)
                        : null,
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
      ],
    );
  }
}

class _CompatibilityCard extends StatelessWidget {
  const _CompatibilityCard({required this.result});

  final _CompatibilityResult result;

  @override
  Widget build(BuildContext context) {
    final icon = result.isValid
        ? result.hasWarning
              ? Icons.warning_amber_rounded
              : Icons.check_circle
        : Icons.error;

    final accentColor = result.isValid
        ? result.hasWarning
              ? Colors.orange.shade700
              : Colors.green.shade700
        : Colors.red.shade700;

    final backgroundColor = result.isValid
        ? accentColor.withValues(alpha: 0.16)
        : Colors.red.withValues(alpha: 0.22);

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accentColor, width: 2),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 10,
        ),
        leading: Icon(icon, color: accentColor, size: 36),
        title: Text(
          result.isValid
              ? result.hasWarning
                    ? 'ATTENTION'
                    : 'CONFIGURATION VALIDÉE'
              : 'VÉRIFICATION REQUISE',
          style: TextStyle(
            color: accentColor,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            result.message,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}

class _RunCard extends StatelessWidget {
  const _RunCard({
    required this.number,
    required this.run,
    required this.formatDateTime,
    required this.durationLabel,
    this.onEdit,
  });

  final int number;
  final RcRun run;
  final String Function(DateTime value) formatDateTime;
  final String Function(int minutes) durationLabel;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text('$number')),
        title: Text(
          run.isActive
              ? 'Roulage en cours'
              : durationLabel(run.effectiveDurationMinutes),
        ),
        subtitle: Text(
          [
            formatDateTime(run.startedAt),
            if (run.batteries.isNotEmpty)
              run.batteries.map((battery) => battery.id).join(' + '),
            if (run.notes.isNotEmpty) run.notes,
          ].join('\n'),
        ),
        trailing: run.isActive
            ? const Icon(Icons.timer)
            : IconButton(
                tooltip: 'Modifier ce roulage',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
      ),
    );
  }
}

class _HistoryLine extends StatelessWidget {
  const _HistoryLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text('$label : $value'),
      ),
    );
  }
}

class _OpenSessionDialog extends StatefulWidget {
  const _OpenSessionDialog({required this.models});

  final List<RcModel> models;

  @override
  State<_OpenSessionDialog> createState() => _OpenSessionDialogState();
}

class _OpenSessionDialogState extends State<_OpenSessionDialog> {
  RcModel? _selectedModel;
  final _locationController = TextEditingController();
  DateTime _startedAt = DateTime.now();

  @override
  void dispose() {
    _locationController.dispose();
    super.dispose();
  }

  bool get _isHistorical {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selectedDay = DateTime(
      _startedAt.year,
      _startedAt.month,
      _startedAt.day,
    );
    return selectedDay.isBefore(today);
  }

  DateTime get _firstAllowedDate {
    final acquisitionDate = _selectedModel?.acquisitionDate;
    if (acquisitionDate == null) {
      return DateTime(1900);
    }

    return DateTime(
      acquisitionDate.year,
      acquisitionDate.month,
      acquisitionDate.day,
    );
  }

  Future<void> _selectDate() async {
    final now = DateTime.now();
    final firstDate = _firstAllowedDate;
    var initialDate = DateTime(
      _startedAt.year,
      _startedAt.month,
      _startedAt.day,
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
      helpText: 'Date de la session',
      cancelText: 'Annuler',
      confirmText: 'Valider',
    );

    if (selected == null || !mounted) {
      return;
    }

    setState(() {
      _startedAt = DateTime(
        selected.year,
        selected.month,
        selected.day,
        _startedAt.hour,
        _startedAt.minute,
      );
    });
  }

  Future<void> _selectTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startedAt),
      helpText: 'Heure de début de la session',
      cancelText: 'Annuler',
      confirmText: 'Valider',
    );

    if (selected == null || !mounted) {
      return;
    }

    final candidate = DateTime(
      _startedAt.year,
      _startedAt.month,
      _startedAt.day,
      selected.hour,
      selected.minute,
    );

    if (candidate.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La date et l’heure ne peuvent pas être futures.'),
        ),
      );
      return;
    }

    setState(() {
      _startedAt = candidate;
    });
  }

  String _formatDate(DateTime value) {
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    return '$day/$month/${value.year}';
  }

  String _formatTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ouvrir une session'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<RcModel>(
                initialValue: _selectedModel,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Modèle utilisé',
                  border: OutlineInputBorder(),
                ),
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
                    final firstDate = _firstAllowedDate;
                    if (_startedAt.isBefore(firstDate)) {
                      _startedAt = DateTime(
                        firstDate.year,
                        firstDate.month,
                        firstDate.day,
                        _startedAt.hour,
                        _startedAt.minute,
                      );
                    }
                  });
                },
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) {
                  final dateField = InkWell(
                    onTap: _selectedModel == null ? null : _selectDate,
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Date',
                        border: OutlineInputBorder(),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_month_outlined),
                          const SizedBox(width: 10),
                          Expanded(child: Text(_formatDate(_startedAt))),
                        ],
                      ),
                    ),
                  );

                  final timeField = InkWell(
                    onTap: _selectTime,
                    borderRadius: BorderRadius.circular(12),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Heure',
                        border: OutlineInputBorder(),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.schedule),
                          const SizedBox(width: 10),
                          Expanded(child: Text(_formatTime(_startedAt))),
                        ],
                      ),
                    ),
                  );

                  if (constraints.maxWidth >= 430) {
                    return Row(
                      children: [
                        Expanded(child: dateField),
                        const SizedBox(width: 12),
                        Expanded(child: timeField),
                      ],
                    );
                  }

                  return Column(
                    children: [
                      dateField,
                      const SizedBox(height: 12),
                      timeField,
                    ],
                  );
                },
              ),
              if (_isHistorical) ...[
                const SizedBox(height: 12),
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.history),
                    title: Text('Session rétroactive'),
                    subtitle: Text(
                      'Les batteries et leurs relevés sont facultatifs. '
                      'Les roulages seront enregistrés à cette date.',
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: _locationController,
                decoration: const InputDecoration(
                  labelText: 'Lieu (facultatif)',
                  border: OutlineInputBorder(),
                ),
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
          onPressed: _selectedModel == null
              ? null
              : () {
                  if (_startedAt.isAfter(DateTime.now())) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'La date et l’heure ne peuvent pas être futures.',
                        ),
                      ),
                    );
                    return;
                  }

                  Navigator.of(context).pop(
                    _OpenSessionResult(
                      model: _selectedModel!,
                      location: _locationController.text.trim(),
                      startedAt: _startedAt,
                    ),
                  );
                },
          child: Text(_isHistorical ? 'Créer' : 'Ouvrir'),
        ),
      ],
    );
  }
}

class _EditSessionGeneralResult {
  const _EditSessionGeneralResult({
    required this.model,
    required this.location,
  });

  final RcModel model;
  final String location;
}

class _EditSessionGeneralDialog extends StatefulWidget {
  const _EditSessionGeneralDialog({
    required this.session,
    required this.models,
  });

  final RcSession session;
  final List<RcModel> models;

  @override
  State<_EditSessionGeneralDialog> createState() =>
      _EditSessionGeneralDialogState();
}

class _EditSessionGeneralDialogState extends State<_EditSessionGeneralDialog> {
  late RcModel _selectedModel;
  late final TextEditingController _locationController;

  @override
  void initState() {
    super.initState();
    _selectedModel = widget.models.firstWhere(
      (model) => model.id == widget.session.model.id,
      orElse: () => widget.session.model,
    );
    _locationController = TextEditingController(text: widget.session.location);
  }

  @override
  void dispose() {
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Modifier la session'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<RcModel>(
              initialValue: _selectedModel,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Modèle utilisé',
                border: OutlineInputBorder(),
              ),
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
                if (value == null) {
                  return;
                }
                setState(() {
                  _selectedModel = value;
                });
              },
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: 'Lieu (facultatif)',
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
          onPressed: () {
            Navigator.of(context).pop(
              _EditSessionGeneralResult(
                model: _selectedModel,
                location: _locationController.text.trim(),
              ),
            );
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class _EndRunDialog extends StatefulWidget {
  const _EndRunDialog({required this.suggestedDuration});

  final int suggestedDuration;

  @override
  State<_EndRunDialog> createState() => _EndRunDialogState();
}

class _EndRunDialogState extends State<_EndRunDialog> {
  late final TextEditingController _durationController;
  final _notesController = TextEditingController();
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _durationController = TextEditingController();
  }

  @override
  void dispose() {
    _durationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _validate() {
    final duration = int.tryParse(_durationController.text.trim());

    if (duration == null || duration <= 0) {
      setState(() {
        _errorText = 'Indique une durée valide.';
      });
      return;
    }

    Navigator.of(context).pop(
      _EndRunResult(
        durationMinutes: duration,
        notes: _notesController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Terminer le roulage'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
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
                  labelText: 'Observations (facultatif)',
                  hintText:
                      'Comportement, coupure, chauffe, perte de puissance…',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Le relevé de fin de roulage pourra être complété depuis le détail de la session.',
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
        FilledButton(onPressed: _validate, child: const Text('Enregistrer')),
      ],
    );
  }
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
      _EndRunResult(
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
        child: SingleChildScrollView(
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

class _CloseSessionDialog extends StatefulWidget {
  const _CloseSessionDialog();

  @override
  State<_CloseSessionDialog> createState() => _CloseSessionDialogState();
}

class _CloseSessionDialogState extends State<_CloseSessionDialog> {
  final _drivingNotesController = TextEditingController();
  final _breakagesController = TextEditingController();
  final _partsReplacedController = TextEditingController();
  final _maintenanceController = TextEditingController();
  final _partsToOrderController = TextEditingController();
  final _changesController = TextEditingController();
  final _generalNotesController = TextEditingController();

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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      title: const Text('Clôturer la session'),
      content: SizedBox(
        width: 760,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final fieldWidth = constraints.maxWidth < 620
                ? (constraints.maxWidth - 10) / 2
                : (constraints.maxWidth - 20) / 3;

            Widget field(TextEditingController controller, String label) {
              return SizedBox(
                width: fieldWidth,
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 2,
                  decoration: _decoration(label).copyWith(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                ),
              );
            }

            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                field(_drivingNotesController, 'Comportement et réglages'),
                field(_breakagesController, 'Casses'),
                field(_partsReplacedController, 'Pièces remplacées sur place'),
                field(_maintenanceController, 'Entretien à effectuer'),
                field(_partsToOrderController, 'Pièces à commander'),
                field(
                  _changesController,
                  'Modifications avant prochaine session',
                ),
                field(_generalNotesController, 'Notes générales'),
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
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              _CloseSessionResult(
                drivingNotes: _drivingNotesController.text.trim(),
                breakages: _breakagesController.text.trim(),
                partsReplacedOnSite: _partsReplacedController.text.trim(),
                maintenanceToDo: _maintenanceController.text.trim(),
                partsToOrder: _partsToOrderController.text.trim(),
                changesBeforeNextSession: _changesController.text.trim(),
                generalNotes: _generalNotesController.text.trim(),
              ),
            );
          },
          child: const Text('Clôturer'),
        ),
      ],
    );
  }
}

enum _MeasurementChoice { now, later }

class _BatteryMeasurementDialog extends StatefulWidget {
  const _BatteryMeasurementDialog({
    required this.battery,
    required this.runNumber,
  });

  final Battery battery;
  final int runNumber;

  @override
  State<_BatteryMeasurementDialog> createState() =>
      _BatteryMeasurementDialogState();
}

class _BatteryMeasurementDialogState extends State<_BatteryMeasurementDialog> {
  final _capacityController = TextEditingController();
  final _temperatureController = TextEditingController();
  late final List<TextEditingController> _cellVoltageControllers;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    final cellCount =
        int.tryParse(widget.battery.cells.replaceAll('S', '')) ?? 0;

    _cellVoltageControllers = List.generate(
      cellCount,
      (_) => TextEditingController(),
    );
  }

  @override
  void dispose() {
    _capacityController.dispose();
    _temperatureController.dispose();

    for (final controller in _cellVoltageControllers) {
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

    for (final controller in _cellVoltageControllers) {
      final voltage = _parseDouble(controller.text);

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
        measuredAt: DateTime.now(),
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
    return _cellVoltageControllers.fold<double>(
      0,
      (total, controller) => total + (_parseDouble(controller.text) ?? 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      title: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text:
                  'Relevé fin de roulage ${widget.runNumber} — ${widget.battery.id}',
            ),
            if (widget.battery.isPaired)
              TextSpan(
                text: '  [P-${widget.battery.pairId!.split('-').last}]',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
          ],
        ),
      ),
      content: SizedBox(
        width: 760,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth < 430
                ? 3
                : constraints.maxWidth < 680
                ? 4
                : 6;
            final itemWidth =
                (constraints.maxWidth - ((columns - 1) * 8)) / columns;

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      child: Container(
                        height: 50,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Total : ${_totalVoltage.toStringAsFixed(3)} V',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (
                      var index = 0;
                      index < _cellVoltageControllers.length;
                      index++
                    )
                      SizedBox(
                        width: itemWidth,
                        child: TextField(
                          controller: _cellVoltageControllers[index],
                          onChanged: (_) => setState(() {}),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            labelText: 'C${index + 1}',
                            hintText: '0,000',
                            suffixText: 'V',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 12,
                            ),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ),
                  ],
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
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Passer cette batterie'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Enregistrer le relevé'),
        ),
      ],
    );
  }
}

class _OpenSessionResult {
  const _OpenSessionResult({
    required this.model,
    required this.location,
    required this.startedAt,
  });

  final RcModel model;
  final String location;
  final DateTime startedAt;
}

class _EndRunResult {
  const _EndRunResult({required this.durationMinutes, required this.notes});

  final int durationMinutes;
  final String notes;
}

class _CloseSessionResult {
  const _CloseSessionResult({
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

class _CompatibilityResult {
  const _CompatibilityResult({
    required this.isValid,
    required this.message,
    this.hasWarning = false,
  });

  final bool isValid;
  final String message;
  final bool hasWarning;
}
