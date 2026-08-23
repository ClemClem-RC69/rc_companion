import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../models/battery.dart';
import '../../models/rc_model.dart';
import '../../models/rc_session.dart';
import '../../services/battery_service.dart';
import '../../services/model_local_store.dart';
import '../../services/model_operational_event_service.dart';
import '../../services/supabase_service.dart';
import '../../services/session_local_store.dart';
import '../../services/session_service.dart';
import '../batteries/battery_scanner_page.dart';
import 'session_detail_page.dart';

class SessionsPage extends StatefulWidget {
  const SessionsPage({super.key, this.historyOnly = false});

  final bool historyOnly;

  @override
  State<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<SessionsPage> {
  final Map<String, Battery?> _battery1BySession = {};
  final Map<String, Battery?> _battery2BySession = {};

  String _sessionKey(RcSession session) {
    final id = session.id?.trim();
    if (id != null && id.isNotEmpty) {
      return id;
    }
    return '${session.model.id}|${session.startedAt.microsecondsSinceEpoch}';
  }

  Battery? _battery1For(RcSession session) =>
      _battery1BySession[_sessionKey(session)];

  Battery? _battery2For(RcSession session) =>
      _battery2BySession[_sessionKey(session)];

  void _setBattery1For(RcSession session, Battery? battery) {
    final key = _sessionKey(session);
    _battery1BySession[key] = battery;
    if (battery == null) {
      _battery2BySession[key] = null;
    }
  }

  void _setBattery2For(RcSession session, Battery? battery) {
    _battery2BySession[_sessionKey(session)] = battery;
  }

  void _clearBatteriesFor(RcSession session) {
    final key = _sessionKey(session);
    _battery1BySession.remove(key);
    _battery2BySession.remove(key);
  }

  Set<String> _batteryIdsReservedByOtherSessions(RcSession session) {
    final currentKey = _sessionKey(session);
    final reserved = <String>{};

    for (final other in _activeSessions) {
      if (_sessionKey(other) == currentKey) {
        continue;
      }

      for (final run in other.runs) {
        for (final battery in run.batteries) {
          reserved.add(battery.id);
        }
      }

      final selected1 = _battery1For(other);
      final selected2 = _battery2For(other);

      if (selected1 != null) {
        reserved.add(selected1.id);
      }
      if (selected2 != null) {
        reserved.add(selected2.id);
      }
    }

    return reserved;
  }

  List<Battery> _availableBatteriesFor(RcSession session) {
    final reserved = _batteryIdsReservedByOtherSessions(session);

    return _availableBatteries
        .where((battery) => !reserved.contains(battery.id))
        .toList(growable: false);
  }

  List<RcModel> _availableModels = [];
  List<Battery> _availableBatteries = [];
  bool _isLoadingData = true;
  String? _loadingError;

  final TextEditingController _historySearchController =
      TextEditingController();
  String _historySearch = '';
  String _historyCategory = 'Tous';

  String? _focusedSessionKey;

  StreamSubscription<List<RcModel>>? _modelSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _sessionSubscription;
  StreamSubscription? _operationalEventSubscription;

  Map<String, ModelOperationalStatus> _modelOperationalStatuses =
      <String, ModelOperationalStatus>{};

  @override
  void initState() {
    super.initState();
    _startModelLiveUpdates();
    _startSessionLiveUpdates();
    _startOperationalEventLiveUpdates();
    _loadData();
  }

  @override
  void dispose() {
    _modelSubscription?.cancel();
    _sessionSubscription?.cancel();
    _operationalEventSubscription?.cancel();
    _historySearchController.dispose();
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
      if (!mounted) {
        return;
      }

      setState(() {
        _availableModels = models;
      });

      unawaited(_refreshSessionsFromLocal());
    });
  }

  void _startOperationalEventLiveUpdates() {
    _operationalEventSubscription =
        ModelOperationalEventService.watchOpenEvents().listen((events) {
          if (!mounted) {
            return;
          }

          setState(() {
            _modelOperationalStatuses =
                ModelOperationalEventService.statusesFromEvents(events);
          });
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

  Future<void> _refreshSessionsFromLocal() async {
    if (_availableModels.isEmpty) {
      return;
    }

    try {
      final loadedSessions = await SessionService.getSessions(
        models: _availableModels,
        batteries: _availableBatteries,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        sessions
          ..clear()
          ..addAll(loadedSessions);
        _loadingError = null;
        _isLoadingData = false;
      });
    } catch (_) {
      // Une notification Drift ne doit jamais rendre la page inutilisable.
    }
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

      final cachedModels = await ModelLocalStore.getModels(userId: user.id);
      final hasModelCache = await ModelLocalStore.hasModelCache(
        userId: user.id,
      );
      final loadedBatteries = await BatteryService.getBatteries();

      if (hasModelCache) {
        final loadedSessions = await SessionService.getSessions(
          models: cachedModels,
          batteries: loadedBatteries,
        );

        if (!mounted) {
          return;
        }

        setState(() {
          _availableModels = cachedModels;
          _availableBatteries = loadedBatteries;
          sessions
            ..clear()
            ..addAll(loadedSessions);
          _isLoadingData = false;
        });

        unawaited(_refreshModelsAndSessions(user.id));
        return;
      }

      await _refreshModelsAndSessions(user.id, showLoading: false);
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

  Future<void> _refreshModelsAndSessions(
    String userId, {
    bool showLoading = false,
  }) async {
    if (showLoading && mounted) {
      setState(() {
        _isLoadingData = true;
        _loadingError = null;
      });
    }

    try {
      final modelResponse = await SupabaseService.client
          .from('rc_models')
          .select()
          .eq('user_id', userId)
          .order('created_at')
          .timeout(const Duration(seconds: 8));

      final modelRows = modelResponse
          .map<Map<String, dynamic>>(
            (row) => Map<String, dynamic>.from(row as Map),
          )
          .toList(growable: false);

      await ModelLocalStore.replaceModels(userId: userId, rows: modelRows);

      final loadedModels = await ModelLocalStore.getModels(userId: userId);
      final loadedBatteries = await BatteryService.getBatteries();
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
        _loadingError = null;
        _isLoadingData = false;
      });
    } catch (error) {
      if (!mounted || !showLoading) {
        return;
      }

      setState(() {
        _loadingError = error.toString();
        _isLoadingData = false;
      });
    }
  }

  List<RcSession> get _activeSessions {
    final active =
        sessions
            .where(
              (session) => !session.isClosed && !_isHistoricalSession(session),
            )
            .toList()
          ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    return List<RcSession>.unmodifiable(active);
  }

  RcSession? get _activeSession {
    final active = _activeSessions;
    return active.isEmpty ? null : active.first;
  }

  bool _isBoatSession(RcSession session) =>
      session.model.category.trim().toLowerCase() == 'bateau';

  RcSession? get _focusedSession {
    final key = _focusedSessionKey;
    if (key == null) {
      return null;
    }

    for (final session in _activeSessions) {
      if (_sessionKey(session) == key) {
        return session;
      }
    }

    return null;
  }

  void _focusSession(RcSession session) {
    setState(() {
      _focusedSessionKey = _sessionKey(session);
    });
  }

  void _clearFocusedSession() {
    setState(() {
      _focusedSessionKey = null;
    });
  }

  bool _isHistoricalSession(RcSession session) {
    return session.isHistorical;
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
    final sessionId = session.id?.trim();

    if (sessionId != null && sessionId.isNotEmpty) {
      return sessions.indexWhere((item) => item.id?.trim() == sessionId);
    }

    // Fallback uniquement pour une session qui n'aurait pas encore d'ID.
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
    final first = _battery1For(session);

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
    if (_availableModels.isEmpty) {
      _showMessage('Enregistre d’abord un modèle.');
      return;
    }

    final result = await showDialog<_OpenSessionResult>(
      context: context,
      builder: (context) => _OpenSessionDialog(
        models: _availableModels,
        operationalStatuses: _modelOperationalStatuses,
        activeModelIds: _activeSessions
            .map((session) => session.model.id?.trim())
            .whereType<String>()
            .where((id) => id.isNotEmpty)
            .toSet(),
      ),
    );

    if (result == null) {
      return;
    }

    if (!result.isHistorical && _activeSessions.length >= 2) {
      _showMessage('Deux sessions sont déjà ouvertes.');
      return;
    }

    try {
      final savedSession = await SessionService.saveSession(
        RcSession(
          model: result.model,
          startedAt: result.startedAt,
          location: result.location,
          terrainType: result.terrainType,
          isHistorical: result.isHistorical,
        ),
      );

      if (!mounted) {
        return;
      }

      if (result.isHistorical) {
        await _openHistoricalSession(savedSession);
        return;
      }

      setState(() {
        sessions.add(savedSession);
      });
    } catch (error) {
      _showMessage('Ouverture de la session impossible : $error');
    }
  }

  Future<void> _openHistoricalSession(RcSession session) async {
    final result = await showDialog<_HistoricalSessionResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _HistoricalSessionDialog(
        session: session,
        batteries: _availableBatteries,
      ),
    );

    if (result == null) {
      final sessionId = session.id;
      if (sessionId != null && sessionId.isNotEmpty) {
        try {
          await SessionService.deleteSession(sessionId);
        } catch (_) {
          // La création rétroactive annulée ne doit pas laisser une session
          // ouverte dans l'application.
        }
      }
      return;
    }

    final runs = <RcRun>[];
    var cursor = session.startedAt;

    for (final item in result.runs) {
      final endedAt = cursor.add(Duration(minutes: item.durationMinutes));
      runs.add(
        RcRun(
          startedAt: cursor,
          endedAt: endedAt,
          durationMinutes: item.durationMinutes,
          batteries: item.batteries,
          historicalBatteries: item.historicalBatteries,
          notes: item.notes,
        ),
      );
      cursor = endedAt;
    }

    final closedSession = session.copyWith(
      runs: runs,
      endedAt: runs.isEmpty ? session.startedAt : cursor,
      drivingNotes: result.drivingNotes,
      breakages: result.breakages,
      partsReplacedOnSite: result.partsReplacedOnSite,
      maintenanceToDo: result.maintenanceToDo,
      partsToOrder: result.partsToOrder,
      changesBeforeNextSession: result.changesBeforeNextSession,
      generalNotes: result.generalNotes,
    );

    try {
      final savedSession = await SessionService.saveSession(closedSession);

      if (!mounted) {
        return;
      }

      setState(() {
        sessions.add(savedSession);
      });

      _showMessage('Session antérieure enregistrée.');
    } catch (error) {
      _showMessage(
        'Enregistrement de la session antérieure impossible : $error',
      );
    }
  }

  Future<void> _scanBattery({
    required RcSession session,
    required int position,
  }) async {
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
        _isBoatSession(session)
            ? '${battery.id} est « ${battery.chargeDisplayLabel} » et ne peut pas être utilisée pour une navigation.'
            : '${battery.id} est « ${battery.chargeDisplayLabel} » et ne peut pas être utilisée pour un roulage.',
      );
      return;
    }

    if (_batteryIdsReservedByOtherSessions(session).contains(battery.id)) {
      _showMessage(
        '${battery.id} est déjà utilisée par l’autre session ouverte.',
      );
      return;
    }

    setState(() {
      if (position == 1) {
        _setBattery1For(session, battery);
        _setBattery2For(session, null);
      } else {
        _setBattery2For(session, battery);
      }
    });

    if (position == 1 && mounted) {
      if (_canAddSecondBattery(session)) {
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
    final first = _battery1For(session);

    if (first == null) {
      return const [];
    }

    final modelTotalCells = _modelTotalCells(session.model);

    final compatible = _availableBatteriesFor(session).where((battery) {
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
    required RcSession session,
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
        _setBattery1For(session, selected);
        _setBattery2For(session, null);
      } else {
        _setBattery2For(session, selected);
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

    final first = _battery1For(session);

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

    final second = _battery2For(session);

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
      _showMessage(
        _isBoatSession(session)
            ? 'Une navigation est déjà en cours.'
            : 'Un roulage est déjà en cours.',
      );
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

    if (_battery1For(session) != null) {
      selectedBatteries.add(_battery1For(session)!);
    }

    if (_battery2For(session) != null) {
      selectedBatteries.add(_battery2For(session)!);
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
      _clearBatteriesFor(session);
    });

    _showMessage(
      _isBoatSession(session) ? 'Navigation démarrée.' : 'Roulage démarré.',
    );
  }

  Future<void> _editRun(RcSession session, int runIndex) async {
    if (runIndex < 0 || runIndex >= session.runs.length) {
      return;
    }

    final run = session.runs[runIndex];

    if (run.isActive) {
      _showMessage(
        _isBoatSession(session)
            ? 'Termine la navigation avant de la modifier.'
            : 'Termine le roulage avant de le modifier.',
      );
      return;
    }

    final result = await showDialog<_EndRunResult>(
      context: context,
      builder: (context) => _EditRunDialog(
        isBoat: _isBoatSession(session),
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
      _showMessage(
        _isBoatSession(session) ? 'Navigation modifiée.' : 'Roulage modifié.',
      );
    }
  }

  Future<RcRun?> _askMeasurementsAfterRun(
    RcSession session,
    RcRun run,
    int runNumber,
  ) async {
    final choice = await showDialog<_MeasurementChoice>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.monitor_heart_outlined),
        title: const Text('Mesures des batteries'),
        content: Text(
          _isBoatSession(session)
              ? 'Souhaites-tu renseigner maintenant le relevé de fin de navigation des batteries utilisées ?'
              : 'Souhaites-tu renseigner maintenant le relevé de fin de roulage des batteries utilisées ?',
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
        builder: (context) => _BatteryMeasurementDialog(
          battery: battery,
          runNumber: runNumber,
          isBoat: _isBoatSession(session),
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
      builder: (context) => _EndRunDialog(
        suggestedDuration: elapsedMinutes,
        isBoat: _isBoatSession(session),
      ),
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
      session,
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

    _showMessage(
      _isBoatSession(session)
          ? 'Navigation enregistrée.'
          : 'Roulage enregistré.',
    );
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
        content: Text(
          _isBoatSession(session)
              ? 'Souhaites-tu renseigner maintenant les relevés de fin de navigation manquants des batteries utilisées pendant cette session ?'
              : 'Souhaites-tu renseigner maintenant les relevés de fin de roulage manquants des batteries utilisées pendant cette session ?',
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
            isBoat: _isBoatSession(session),
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
      session.copyWith(
        model: result.model,
        location: result.location,
        terrainType: result.terrainType,
      ),
    );

    if (saved) {
      _showMessage('Modèle, lieu et type de terrain modifiés.');
    }
  }

  Future<void> _closeSession(RcSession session) async {
    if (session.hasActiveRun) {
      _showMessage(
        _isBoatSession(session)
            ? 'Termine la navigation en cours avant de clôturer la session.'
            : 'Termine le roulage en cours avant de clôturer la session.',
      );
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
      _clearBatteriesFor(session);
      if (_focusedSessionKey == _sessionKey(session)) {
        _focusedSessionKey = null;
      }
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
        content: Text(
          _isBoatSession(session)
              ? 'Toutes les navigations et toutes les mesures enregistrées dans cette session seront supprimées définitivement.\n\nCette action est irréversible.'
              : 'Tous les roulages et toutes les mesures enregistrés dans cette session seront supprimés définitivement.\n\nCette action est irréversible.',
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
        _clearBatteriesFor(session);
        if (_focusedSessionKey == _sessionKey(session)) {
          _focusedSessionKey = null;
        }
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
    final activeSessions = _activeSessions;

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
      floatingActionButton: !widget.historyOnly && activeSessions.isEmpty
          ? FloatingActionButton.extended(
              onPressed: _openSession,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Ouvrir une session'),
            )
          : null,
      body: widget.historyOnly
          ? _buildSessionHistory()
          : activeSessions.isEmpty
          ? _buildSessionHistory()
          : _focusedSession != null && activeSessions.length > 1
          ? _buildFocusedSession(_focusedSession!)
          : _buildActiveSessions(activeSessions),
    );
  }

  Widget _buildSessionHistory() {
    final activeSessions = _activeSessions;
    final allClosedSessions =
        sessions.where((session) => session.isClosed).toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

    if (activeSessions.isEmpty && allClosedSessions.isEmpty) {
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

    final query = _historySearch.trim().toLowerCase();
    final closedSessions = allClosedSessions
        .where((session) {
          final matchesCategory =
              _historyCategory == 'Tous' ||
              session.model.category.toLowerCase() ==
                  _historyCategory.toLowerCase();
          final matchesSearch =
              query.isEmpty ||
              session.model.name.toLowerCase().contains(query) ||
              session.model.brand.toLowerCase().contains(query);

          return matchesCategory && matchesSearch;
        })
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        const Text(
          'Historique',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        for (final activeSession in activeSessions) ...[
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            color: const Color(0xFF0A2C5A),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SessionsPage()),
                ).then((_) => _loadData());
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                child: Row(
                  children: [
                    const Icon(
                      Icons.play_circle_fill_rounded,
                      size: 32,
                      color: Color(0xFF58A6FF),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1565C0),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'SESSION EN COURS',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: .4,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            activeSession.model.name,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(_formatDateTime(activeSession.startedAt)),
                              const Text('•'),
                              Text(
                                '${activeSession.runs.length} ${_isBoatSession(activeSession) ? 'navigation(s)' : 'roulage(s)'}',
                              ),
                              const Text('•'),
                              Text(
                                _durationLabel(
                                  activeSession.totalDurationMinutes,
                                ),
                              ),
                              if (activeSession.location.isNotEmpty) ...[
                                const Text('•'),
                                Text(
                                  activeSession.location,
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
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        _HistoryFilterBar(
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
        if (closedSessions.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(
              child: Text(
                'Aucune session ne correspond à la recherche.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
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
                              Text(
                                '${session.runs.length} ${_isBoatSession(session) ? 'navigation(s)' : 'roulage(s)'}',
                              ),
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
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_horiz),
                      onSelected: (value) {
                        switch (value) {
                          case 'edit':
                            _editSessionGeneral(session);
                            break;
                          case 'delete':
                            _deleteClosedSession(session);
                            break;
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: ListTile(
                            leading: Icon(Icons.edit_outlined),
                            title: Text('Modifier'),
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            leading: Icon(Icons.delete_outline),
                            title: Text('Supprimer'),
                          ),
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

  Widget _buildFocusedSession(RcSession session) {
    return Column(
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(
            bottom: false,
            child: Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Retour aux deux sessions',
                onPressed: _clearFocusedSession,
                icon: const Icon(Icons.arrow_back),
              ),
            ),
          ),
        ),
        Expanded(child: _buildActiveSession(session)),
      ],
    );
  }

  Widget _buildActiveSessions(List<RcSession> activeSessions) {
    if (activeSessions.length == 1) {
      return _buildActiveSession(activeSessions.first);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isLandscape = constraints.maxWidth > constraints.maxHeight;

        Widget preview(RcSession session) {
          return InkWell(
            onTap: () => _focusSession(session),
            child: IgnorePointer(
              ignoring: true,
              child: _buildActiveSession(session),
            ),
          );
        }

        if (isLandscape) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: preview(activeSessions[0])),
              const VerticalDivider(width: 1),
              Expanded(child: preview(activeSessions[1])),
            ],
          );
        }

        return Column(
          children: [
            Expanded(child: preview(activeSessions[0])),
            const Divider(height: 1),
            Expanded(child: preview(activeSessions[1])),
          ],
        );
      },
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.flag_circle),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        session.model.name,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip:
                                  'Modifier les informations de la session',
                              onPressed: () => _editSessionGeneral(session),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            const Chip(label: Text('EN COURS')),
                          ],
                        ),
                        if (_activeSessions.length == 1) ...[
                          const SizedBox(height: 6),
                          OutlinedButton.icon(
                            onPressed: _openSession,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              side: BorderSide(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            icon: const Icon(Icons.add_circle_outline),
                            label: const Text('Ouvrir une 2e session'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('${session.model.brand} • ${session.model.motorization}'),
                Text('Ouverte le ${_formatDateTime(session.startedAt)}'),
                if (session.location.isNotEmpty)
                  Text('Lieu : ${session.location}'),
                const SizedBox(height: 8),
                Text(
                  '${session.runs.length} ${_isBoatSession(session) ? 'navigation(s)' : 'roulage(s)'} • '
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
            session.runs.isEmpty
                ? (_isBoatSession(session)
                      ? 'Première navigation'
                      : 'Premier roulage')
                : (_isBoatSession(session)
                      ? 'Nouvelle navigation'
                      : 'Nouveau roulage'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (isElectric) ...[
            _BatterySelector(
              number: 1,
              battery: _battery1For(session),
              batteries: _availableBatteriesFor(session),
              labelBuilder: _batteryLabel,
              onScan: () => _scanBattery(session: session, position: 1),
              onManualSelect: () => _selectBatteryManually(
                session: session,
                position: 1,
                choices: _availableBatteriesFor(session),
              ),
              onChanged: (value) {
                setState(() {
                  _setBattery1For(session, value);
                  _setBattery2For(session, null);
                });
              },
            ),
            if (canAddSecondBattery) ...[
              const SizedBox(height: 14),
              _BatterySelector(
                number: 2,
                battery: _battery2For(session),
                batteries: _compatibleSecondBatteries(session),
                labelBuilder: _batteryLabel,
                onScan: () => _scanBattery(session: session, position: 2),
                onManualSelect: () => _selectBatteryManually(
                  session: session,
                  position: 2,
                  choices: _compatibleSecondBatteries(session),
                ),
                onChanged: (value) {
                  setState(() {
                    _setBattery2For(session, value);
                  });
                },
              ),
            ],
            const SizedBox(height: 14),
            _CompatibilityCard(result: compatibility),
          ] else
            Card(
              child: ListTile(
                leading: Icon(Icons.local_gas_station),
                title: Text('Modèle thermique'),
                subtitle: Text(
                  _isBoatSession(session)
                      ? 'La navigation peut être démarrée sans batterie de propulsion.'
                      : 'Le roulage peut être démarré sans batterie de propulsion.',
                ),
              ),
            ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: () => _startRun(session),
            icon: const Icon(Icons.timer),
            label: Text(
              _isBoatSession(session)
                  ? 'Démarrer cette navigation'
                  : 'Démarrer ce roulage',
            ),
          ),
        ],
        if (session.runs.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            _isBoatSession(session)
                ? 'Navigations de la session'
                : 'Roulages de la session',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          for (var index = session.runs.length - 1; index >= 0; index--)
            _RunCard(
              number: index + 1,
              run: session.runs[index],
              formatDateTime: _formatDateTime,
              durationLabel: _durationLabel,
              isBoat: _isBoatSession(session),
              onEdit: session.runs[index].isActive
                  ? null
                  : () => _editRun(session, index),
            ),
        ],
        const SizedBox(height: 24),
        if (session.hasActiveRun)
          FilledButton.icon(
            onPressed: () => _endActiveRun(session),
            icon: const Icon(Icons.stop),
            label: Text(
              _isBoatSession(session)
                  ? 'Terminer cette navigation'
                  : 'Terminer ce roulage',
            ),
          )
        else
          OutlinedButton.icon(
            onPressed: () => _closeSession(session),
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
              _isBoatSession(session)
                  ? 'Navigation en cours'
                  : 'Roulage en cours',
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
          ],
        ),
      ),
    );
  }
}

class _HistoryFilterBar extends StatelessWidget {
  const _HistoryFilterBar({
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
    required this.isBoat,
    this.onEdit,
  });

  final int number;
  final RcRun run;
  final String Function(DateTime value) formatDateTime;
  final String Function(int minutes) durationLabel;
  final bool isBoat;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text('$number')),
        title: Text(
          run.isActive
              ? (isBoat ? 'Navigation en cours' : 'Roulage en cours')
              : durationLabel(run.effectiveDurationMinutes),
        ),
        subtitle: Text(
          [
            formatDateTime(run.startedAt),
            if (run.batteries.isNotEmpty)
              run.batteries.map((battery) => battery.id).join(' + '),
            if (run.historicalBatteries.isNotEmpty)
              run.historicalBatteries
                  .map((battery) => battery.displayLabel)
                  .join(' + '),
            if (run.notes.isNotEmpty) run.notes,
          ].join('\n'),
        ),
        trailing: run.isActive
            ? const Icon(Icons.timer)
            : IconButton(
                tooltip: isBoat
                    ? 'Modifier cette navigation'
                    : 'Modifier ce roulage',
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
  const _OpenSessionDialog({
    required this.models,
    required this.operationalStatuses,
    this.activeModelIds = const <String>{},
  });

  final List<RcModel> models;
  final Map<String, ModelOperationalStatus> operationalStatuses;
  final Set<String> activeModelIds;

  @override
  State<_OpenSessionDialog> createState() => _OpenSessionDialogState();
}

class _OpenSessionDialogState extends State<_OpenSessionDialog> {
  RcModel? _selectedModel;
  final _locationController = TextEditingController();
  final _terrainTypeController = TextEditingController();
  DateTime _startedAt = DateTime.now();

  @override
  void dispose() {
    _locationController.dispose();
    _terrainTypeController.dispose();
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

  ModelOperationalStatus _statusFor(RcModel model) {
    final id = model.id?.trim();
    if (id == null || id.isEmpty) {
      return ModelOperationalStatus.ready;
    }
    return widget.operationalStatuses[id] ?? ModelOperationalStatus.ready;
  }

  Color _statusColor(BuildContext context, ModelOperationalStatus status) {
    switch (status.state) {
      case ModelOperationalState.ready:
        return Colors.green.shade700;
      case ModelOperationalState.maintenance:
        return Colors.orange.shade800;
      case ModelOperationalState.unavailable:
        return Theme.of(context).colorScheme.error;
    }
  }

  IconData _statusIcon(ModelOperationalStatus status) {
    switch (status.state) {
      case ModelOperationalState.ready:
        return Icons.check_circle_outline;
      case ModelOperationalState.maintenance:
        return Icons.build_circle_outlined;
      case ModelOperationalState.unavailable:
        return Icons.error_outline;
    }
  }

  Future<bool> _confirmOperationalStatus(RcModel model) async {
    if (_isHistorical) {
      return true;
    }

    final status = _statusFor(model);
    if (status.isReady) {
      return true;
    }

    if (status.hasMaintenance) {
      final details = status.maintenanceDescriptions.isEmpty
          ? 'Une maintenance est à prévoir avant la prochaine session.'
          : status.maintenanceDescriptions.map((item) => '• $item').join('\n');

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: Icon(
            Icons.warning_amber_rounded,
            color: Colors.orange.shade800,
          ),
          title: const Text('Maintenance à prévoir'),
          content: Text('$details\n\nLe modèle reste disponible pour rouler.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Continuer'),
            ),
          ],
        ),
      );

      return mounted;
    }

    final repairText = status.repairDescriptions.isEmpty
        ? 'Une réparation est encore en attente.'
        : status.repairDescriptions.map((item) => '• $item').join('\n');
    final maintenanceText = status.maintenanceDescriptions.isEmpty
        ? ''
        : '\n\nAutres opérations prévues :\n'
              '${status.maintenanceDescriptions.map((item) => '• $item').join('\n')}';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(
          Icons.error_outline,
          color: Theme.of(dialogContext).colorScheme.error,
        ),
        title: const Text('Modèle indisponible'),
        content: Text(
          '$repairText$maintenanceText\n\n'
          'Voulez-vous quand même utiliser ce modèle ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Choisir un autre modèle'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            child: const Text('Utiliser quand même'),
          ),
        ],
      ),
    );

    return confirmed == true;
  }

  List<RcModel> get _selectableModels {
    if (_isHistorical || widget.activeModelIds.isEmpty) {
      return widget.models;
    }

    return widget.models
        .where((model) {
          final id = model.id?.trim();
          return id == null ||
              id.isEmpty ||
              !widget.activeModelIds.contains(id);
        })
        .toList(growable: false);
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

      final selectedModelId = _selectedModel?.id?.trim();
      if (!_isHistorical &&
          selectedModelId != null &&
          selectedModelId.isNotEmpty &&
          widget.activeModelIds.contains(selectedModelId)) {
        _selectedModel = null;
      }
    });
  }

  Future<void> _selectTime() async {
    final selected = await showDialog<TimeOfDay>(
      context: context,
      builder: (context) =>
          _NumericTimeDialog(initialTime: TimeOfDay.fromDateTime(_startedAt)),
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
                items: _selectableModels.map((model) {
                  final status = _statusFor(model);

                  return DropdownMenuItem(
                    value: model,
                    child: Row(
                      children: [
                        if (!_isHistorical) ...[
                          Icon(
                            _statusIcon(status),
                            size: 18,
                            color: _statusColor(context, status),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            _isHistorical
                                ? '${model.name} — ${model.brand}'
                                : '${model.name} — ${model.brand} • ${status.label}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) async {
                  if (value == null) {
                    setState(() {
                      _selectedModel = null;
                    });
                    return;
                  }

                  final confirmed = await _confirmOperationalStatus(value);
                  if (!mounted) {
                    return;
                  }

                  if (!confirmed) {
                    setState(() {
                      _selectedModel = null;
                    });
                    return;
                  }

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
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.history),
                    title: const Text('Session rétroactive'),
                    subtitle: Text(
                      _selectedModel?.category.trim().toLowerCase() == 'bateau'
                          ? 'Les batteries et leurs relevés sont facultatifs. Les navigations seront enregistrées à cette date.'
                          : 'Les batteries et leurs relevés sont facultatifs. Les roulages seront enregistrés à cette date.',
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
              const SizedBox(height: 12),
              TextField(
                controller: _terrainTypeController,
                decoration: const InputDecoration(
                  labelText: 'Type de terrain (facultatif)',
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
                      terrainType: _terrainTypeController.text.trim(),
                      startedAt: _startedAt,
                      isHistorical: _isHistorical,
                    ),
                  );
                },
          child: Text(_isHistorical ? 'Créer' : 'Ouvrir'),
        ),
      ],
    );
  }
}

class _NumericTimeDialog extends StatefulWidget {
  const _NumericTimeDialog({required this.initialTime});

  final TimeOfDay initialTime;

  @override
  State<_NumericTimeDialog> createState() => _NumericTimeDialogState();
}

class _NumericTimeDialogState extends State<_NumericTimeDialog> {
  late final TextEditingController _hourController;
  late final TextEditingController _minuteController;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _hourController = TextEditingController(
      text: widget.initialTime.hour.toString().padLeft(2, '0'),
    );
    _minuteController = TextEditingController(
      text: widget.initialTime.minute.toString().padLeft(2, '0'),
    );
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  void _validate() {
    final hour = int.tryParse(_hourController.text.trim());
    final minute = int.tryParse(_minuteController.text.trim());

    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      setState(() {
        _errorText = 'Indique une heure valide entre 00:00 et 23:59.';
      });
      return;
    }

    Navigator.of(context).pop(TimeOfDay(hour: hour, minute: minute));
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    required int maxValue,
  }) {
    return Expanded(
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 2,
        onSubmitted: (_) => _validate(),
        decoration: InputDecoration(
          labelText: label,
          counterText: '',
          border: const OutlineInputBorder(),
        ),
        onChanged: (value) {
          final parsed = int.tryParse(value.trim());
          if (parsed != null && parsed > maxValue) {
            setState(() {
              _errorText = label == 'Heures'
                  ? 'Les heures vont de 00 à 23.'
                  : 'Les minutes vont de 00 à 59.';
            });
          } else if (_errorText != null) {
            setState(() {
              _errorText = null;
            });
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Heure de début de la session'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _numberField(
                  controller: _hourController,
                  label: 'Heures',
                  maxValue: 23,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    ':',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                  ),
                ),
                _numberField(
                  controller: _minuteController,
                  label: 'Minutes',
                  maxValue: 59,
                ),
              ],
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _errorText!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _validate, child: const Text('Valider')),
      ],
    );
  }
}

class _EditSessionGeneralResult {
  const _EditSessionGeneralResult({
    required this.model,
    required this.location,
    required this.terrainType,
  });

  final RcModel model;
  final String location;
  final String terrainType;
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
  late final TextEditingController _terrainTypeController;

  @override
  void initState() {
    super.initState();
    _selectedModel = widget.models.firstWhere(
      (model) => model.id == widget.session.model.id,
      orElse: () => widget.session.model,
    );
    _locationController = TextEditingController(text: widget.session.location);
    _terrainTypeController = TextEditingController(
      text: widget.session.terrainType,
    );
  }

  @override
  void dispose() {
    _locationController.dispose();
    _terrainTypeController.dispose();
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
            const SizedBox(height: 14),
            TextField(
              controller: _terrainTypeController,
              decoration: const InputDecoration(
                labelText: 'Type de terrain (facultatif)',
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
                terrainType: _terrainTypeController.text.trim(),
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
  const _EndRunDialog({required this.suggestedDuration, required this.isBoat});

  final int suggestedDuration;
  final bool isBoat;

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
      title: Text(
        widget.isBoat ? 'Terminer la navigation' : 'Terminer le roulage',
      ),
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
                  labelText: widget.isBoat
                      ? 'Temps de navigation (minutes)'
                      : 'Temps de roulage (minutes)',
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
              Text(
                widget.isBoat
                    ? 'Le relevé de fin de navigation pourra être complété depuis le détail de la session.'
                    : 'Le relevé de fin de roulage pourra être complété depuis le détail de la session.',
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
  const _EditRunDialog({
    required this.durationMinutes,
    required this.notes,
    required this.isBoat,
  });

  final int durationMinutes;
  final String notes;
  final bool isBoat;

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
      title: Text(
        widget.isBoat ? 'Modifier la navigation' : 'Modifier le roulage',
      ),
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
                  labelText: widget.isBoat
                      ? 'Temps de navigation (minutes)'
                      : 'Temps de roulage (minutes)',
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

Future<String?> _openSessionTextEditor(
  BuildContext context, {
  required String title,
  required String initialText,
}) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) =>
          _SessionTextEditorPage(title: title, initialText: initialText),
    ),
  );
}

class _SessionCompactTextField extends StatelessWidget {
  const _SessionCompactTextField({
    required this.label,
    required this.text,
    required this.onTap,
  });

  final String label;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cleanText = text.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
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
                  cleanText.isEmpty ? 'Toucher pour saisir…' : cleanText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cleanText.isEmpty
                        ? Theme.of(context).colorScheme.onSurfaceVariant
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionTextEditorPage extends StatefulWidget {
  const _SessionTextEditorPage({
    required this.title,
    required this.initialText,
  });

  final String title;
  final String initialText;

  @override
  State<_SessionTextEditorPage> createState() => _SessionTextEditorPageState();
}

class _SessionTextEditorPageState extends State<_SessionTextEditorPage> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _focusNode = FocusNode();
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
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Annuler',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
        ),
        title: Text(widget.title),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(_controller.text),
            icon: const Icon(Icons.check),
            label: const Text('Valider'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
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
          ),
        ),
      ),
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

  @override
  void dispose() {
    _drivingNotesController.dispose();
    _breakagesController.dispose();
    _partsReplacedController.dispose();
    _maintenanceController.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      alignLabelWithHint: true,
    );
  }

  Widget _compactField(TextEditingController controller, String label) {
    return _SessionCompactTextField(
      label: label,
      text: controller.text,
      onTap: () async {
        final result = await _openSessionTextEditor(
          context,
          title: label,
          initialText: controller.text,
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
      },
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
                child: _compactField(controller, label),
              );
            }

            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                field(
                  _drivingNotesController,
                  'Comportement et réglages pendant la session',
                ),
                field(_breakagesController, 'Casses'),
                field(_partsReplacedController, 'Maintenance sur place'),
                field(
                  _maintenanceController,
                  'Entretien / réglages / modifications avant prochaine session',
                ),
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
                partsToOrder: '',
                changesBeforeNextSession: '',
                generalNotes: '',
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
    required this.isBoat,
  });

  final Battery battery;
  final int runNumber;
  final bool isBoat;

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
              text: widget.isBoat
                  ? 'Relevé fin de navigation ${widget.runNumber} — ${widget.battery.id}'
                  : 'Relevé fin de roulage ${widget.runNumber} — ${widget.battery.id}',
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
    required this.terrainType,
    required this.startedAt,
    required this.isHistorical,
  });

  final RcModel model;
  final String location;
  final String terrainType;
  final DateTime startedAt;
  final bool isHistorical;
}

class _HistoricalRunInput {
  const _HistoricalRunInput({
    required this.durationMinutes,
    required this.notes,
    required this.batteries,
    required this.historicalBatteries,
  });

  final int durationMinutes;
  final String notes;
  final List<Battery> batteries;
  final List<HistoricalBattery> historicalBatteries;
}

class _HistoricalSessionResult {
  const _HistoricalSessionResult({
    required this.runs,
    required this.drivingNotes,
    required this.breakages,
    required this.partsReplacedOnSite,
    required this.maintenanceToDo,
    required this.partsToOrder,
    required this.changesBeforeNextSession,
    required this.generalNotes,
  });

  final List<_HistoricalRunInput> runs;
  final String drivingNotes;
  final String breakages;
  final String partsReplacedOnSite;
  final String maintenanceToDo;
  final String partsToOrder;
  final String changesBeforeNextSession;
  final String generalNotes;
}

class _HistoricalSessionDialog extends StatefulWidget {
  const _HistoricalSessionDialog({
    required this.session,
    required this.batteries,
  });

  final RcSession session;
  final List<Battery> batteries;

  @override
  State<_HistoricalSessionDialog> createState() =>
      _HistoricalSessionDialogState();
}

class _HistoricalSessionDialogState extends State<_HistoricalSessionDialog> {
  final List<_HistoricalRunInput> _runs = [];
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

  bool get _isBoat =>
      widget.session.model.category.trim().toLowerCase() == 'bateau';

  Future<void> _addRun() async {
    final result = await showDialog<_HistoricalRunResult>(
      context: context,
      builder: (context) =>
          _HistoricalRunDialog(batteries: widget.batteries, isBoat: _isBoat),
    );

    if (result == null || !mounted) {
      return;
    }

    setState(() {
      _runs.add(
        _HistoricalRunInput(
          durationMinutes: result.durationMinutes,
          notes: result.notes,
          batteries: result.batteries,
          historicalBatteries: result.historicalBatteries,
        ),
      );
    });
  }

  void _save() {
    Navigator.of(context).pop(
      _HistoricalSessionResult(
        runs: List<_HistoricalRunInput>.unmodifiable(_runs),
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

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      isDense: true,
      alignLabelWithHint: true,
    );
  }

  Widget _compactField(TextEditingController controller, String label) {
    return _SessionCompactTextField(
      label: label,
      text: controller.text,
      onTap: () async {
        final result = await _openSessionTextEditor(
          context,
          title: label,
          initialText: controller.text,
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
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      title: Text('Session antérieure — ${widget.session.model.name}'),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.history),
                  title: Text('Saisie rétroactive'),
                  subtitle: Text(
                    _isBoat
                        ? 'Ajoute les navigations déjà effectuées. Les batteries et les '
                              'relevés restent facultatifs pour l’historique initial.'
                        : 'Ajoute les roulages déjà effectués. Les batteries et les '
                              'relevés restent facultatifs pour l’historique initial.',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _runs.isEmpty
                          ? (_isBoat
                                ? 'Aucune navigation renseignée'
                                : 'Aucun roulage renseigné')
                          : '${_runs.length} ${_isBoat ? 'navigation(s)' : 'roulage(s)'} • '
                                '${_runs.fold<int>(0, (total, run) => total + run.durationMinutes)} min',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _addRun,
                    icon: const Icon(Icons.add),
                    label: Text(
                      _isBoat ? 'Ajouter une navigation' : 'Ajouter un roulage',
                    ),
                  ),
                ],
              ),
              if (_runs.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (var index = 0; index < _runs.length; index++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    title: Text('${_runs[index].durationMinutes} min'),
                    subtitle: Text(
                      [
                        if (_runs[index].batteries.isNotEmpty)
                          'Batteries : ${_runs[index].batteries.map((battery) => battery.id).join(' + ')}',
                        if (_runs[index].historicalBatteries.isNotEmpty)
                          'Anciennes : ${_runs[index].historicalBatteries.map((battery) => battery.displayLabel).join(' + ')}',
                        if (_runs[index].notes.isNotEmpty) _runs[index].notes,
                      ].join('\n'),
                    ),
                    trailing: IconButton(
                      tooltip: _isBoat
                          ? 'Supprimer cette navigation'
                          : 'Supprimer ce roulage',
                      onPressed: () {
                        setState(() {
                          _runs.removeAt(index);
                        });
                      },
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: 235,
                    child: _compactField(
                      _drivingNotesController,
                      'Comportement et réglages',
                    ),
                  ),
                  SizedBox(
                    width: 235,
                    child: _compactField(_breakagesController, 'Casses'),
                  ),
                  SizedBox(
                    width: 235,
                    child: _compactField(
                      _partsReplacedController,
                      'Pièces remplacées sur place',
                    ),
                  ),
                  SizedBox(
                    width: 235,
                    child: _compactField(
                      _maintenanceController,
                      'Entretien à effectuer',
                    ),
                  ),
                  SizedBox(
                    width: 235,
                    child: _compactField(
                      _partsToOrderController,
                      'Pièces à commander',
                    ),
                  ),
                  SizedBox(
                    width: 235,
                    child: _compactField(
                      _changesController,
                      'Modifications avant prochaine session',
                    ),
                  ),
                  SizedBox(
                    width: 235,
                    child: _compactField(
                      _generalNotesController,
                      'Notes générales',
                    ),
                  ),
                ],
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
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Enregistrer la session antérieure'),
        ),
      ],
    );
  }
}

enum _HistoricalBatteryMode { none, existing, historical }

class _HistoricalRunDialog extends StatefulWidget {
  const _HistoricalRunDialog({required this.batteries, required this.isBoat});

  final List<Battery> batteries;
  final bool isBoat;

  @override
  State<_HistoricalRunDialog> createState() => _HistoricalRunDialogState();
}

class _HistoricalRunDialogState extends State<_HistoricalRunDialog> {
  final _durationController = TextEditingController();
  final _notesController = TextEditingController();

  _HistoricalBatteryMode _mode1 = _HistoricalBatteryMode.none;
  _HistoricalBatteryMode _mode2 = _HistoricalBatteryMode.none;
  Battery? _battery1;
  Battery? _battery2;

  final _oldBrand1 = TextEditingController();
  final _oldCapacity1 = TextEditingController();
  final _oldCells1 = TextEditingController();
  final _oldCRate1 = TextEditingController();

  final _oldBrand2 = TextEditingController();
  final _oldCapacity2 = TextEditingController();
  final _oldCells2 = TextEditingController();
  final _oldCRate2 = TextEditingController();

  String? _errorText;

  String _existingBatteryLabel(Battery battery) {
    final pairLabel = battery.isPaired
        ? ' — [P-${battery.pairId!.split('-').last}]'
        : '';

    return '${battery.id} — ${battery.brand} — ${battery.technology} — '
        '${battery.cells} — ${battery.capacity} mAh — ${battery.cRate}C'
        '$pairLabel';
  }

  @override
  void dispose() {
    _durationController.dispose();
    _notesController.dispose();
    for (final controller in [
      _oldBrand1,
      _oldCapacity1,
      _oldCells1,
      _oldCRate1,
      _oldBrand2,
      _oldCapacity2,
      _oldCells2,
      _oldCRate2,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  HistoricalBattery _historicalBattery(
    TextEditingController brand,
    TextEditingController capacity,
    TextEditingController cells,
    TextEditingController cRate,
  ) {
    return HistoricalBattery(
      name: '',
      brand: brand.text.trim(),
      capacityMah: int.tryParse(capacity.text.trim()),
      cells: int.tryParse(cells.text.trim()),
      cRate: int.tryParse(cRate.text.trim()),
    );
  }

  void _save() {
    final duration = int.tryParse(_durationController.text.trim());
    if (duration == null || duration <= 0) {
      setState(() {
        _errorText = 'Indique une durée valide.';
      });
      return;
    }

    final existing = <Battery>[
      if (_mode1 == _HistoricalBatteryMode.existing && _battery1 != null)
        _battery1!,
      if (_mode2 == _HistoricalBatteryMode.existing && _battery2 != null)
        _battery2!,
    ];

    final historical = <HistoricalBattery>[
      if (_mode1 == _HistoricalBatteryMode.historical)
        _historicalBattery(_oldBrand1, _oldCapacity1, _oldCells1, _oldCRate1),
      if (_mode2 == _HistoricalBatteryMode.historical)
        _historicalBattery(_oldBrand2, _oldCapacity2, _oldCells2, _oldCRate2),
    ];

    Navigator.of(context).pop(
      _HistoricalRunResult(
        durationMinutes: duration,
        notes: _notesController.text.trim(),
        batteries: List<Battery>.unmodifiable(existing),
        historicalBatteries: List<HistoricalBattery>.unmodifiable(historical),
      ),
    );
  }

  Widget _batterySlot({
    required int number,
    required _HistoricalBatteryMode mode,
    required ValueChanged<_HistoricalBatteryMode> onModeChanged,
    required Battery? selectedBattery,
    required ValueChanged<Battery?> onBatteryChanged,
    required TextEditingController brand,
    required TextEditingController capacity,
    required TextEditingController cells,
    required TextEditingController cRate,
  }) {
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            DropdownButtonFormField<_HistoricalBatteryMode>(
              initialValue: mode,
              decoration: InputDecoration(
                labelText: 'Batterie $number (facultative)',
                border: const OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: _HistoricalBatteryMode.none,
                  child: Text('Aucune'),
                ),
                DropdownMenuItem(
                  value: _HistoricalBatteryMode.existing,
                  child: Text('Batterie existante'),
                ),
                DropdownMenuItem(
                  value: _HistoricalBatteryMode.historical,
                  child: Text('Ancienne batterie'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  onModeChanged(value);
                }
              },
            ),
            if (mode == _HistoricalBatteryMode.existing) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<Battery>(
                initialValue: selectedBattery,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Choisir la batterie',
                  border: OutlineInputBorder(),
                ),
                items: widget.batteries
                    .where(
                      (battery) =>
                          number == 1 ||
                          _battery1 == null ||
                          battery.id != _battery1!.id,
                    )
                    .map(
                      (battery) => DropdownMenuItem(
                        value: battery,
                        child: Text(
                          _existingBatteryLabel(battery),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: onBatteryChanged,
              ),
            ],
            if (mode == _HistoricalBatteryMode.historical) ...[
              const SizedBox(height: 10),
              TextField(
                controller: brand,
                decoration: const InputDecoration(
                  labelText: 'Marque',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: capacity,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Capacité',
                        suffixText: 'mAh',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: cells,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Cellules',
                        suffixText: 'S',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: cRate,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Taux',
                        suffixText: 'C',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.isBoat
            ? 'Ajouter une navigation antérieure'
            : 'Ajouter un roulage antérieur',
      ),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _durationController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: widget.isBoat
                      ? 'Temps de navigation (minutes)'
                      : 'Temps de roulage (minutes)',
                  border: const OutlineInputBorder(),
                  errorText: _errorText,
                ),
              ),
              _batterySlot(
                number: 1,
                mode: _mode1,
                onModeChanged: (value) {
                  setState(() {
                    _mode1 = value;
                    if (value != _HistoricalBatteryMode.existing) {
                      _battery1 = null;
                    }
                  });
                },
                selectedBattery: _battery1,
                onBatteryChanged: (value) {
                  setState(() {
                    _battery1 = value;
                    if (_battery2?.id == value?.id) {
                      _battery2 = null;
                    }
                  });
                },
                brand: _oldBrand1,
                capacity: _oldCapacity1,
                cells: _oldCells1,
                cRate: _oldCRate1,
              ),
              _batterySlot(
                number: 2,
                mode: _mode2,
                onModeChanged: (value) {
                  setState(() {
                    _mode2 = value;
                    if (value != _HistoricalBatteryMode.existing) {
                      _battery2 = null;
                    }
                  });
                },
                selectedBattery: _battery2,
                onBatteryChanged: (value) {
                  setState(() {
                    _battery2 = value;
                  });
                },
                brand: _oldBrand2,
                capacity: _oldCapacity2,
                cells: _oldCells2,
                cRate: _oldCRate2,
              ),
              const SizedBox(height: 8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Les anciennes batteries servent uniquement à documenter '
                  'la session antérieure. Elles ne sont jamais ajoutées à '
                  'l’inventaire Batteries.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _notesController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Observations (facultatif)',
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
        FilledButton(onPressed: _save, child: const Text('Ajouter')),
      ],
    );
  }
}

class _HistoricalRunResult {
  const _HistoricalRunResult({
    required this.durationMinutes,
    required this.notes,
    required this.batteries,
    required this.historicalBatteries,
  });

  final int durationMinutes;
  final String notes;
  final List<Battery> batteries;
  final List<HistoricalBattery> historicalBatteries;
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
