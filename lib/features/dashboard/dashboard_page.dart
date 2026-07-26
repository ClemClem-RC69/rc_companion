import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../pages/radios_page.dart';
import '../../data/radio_control_catalog.dart';
import '../../models/battery.dart';
import '../../models/rc_model.dart';
import '../../models/rc_session.dart';
import '../../services/account_service.dart';
import '../../services/battery_local_store.dart';
import '../../services/battery_service.dart';
import '../../services/session_local_store.dart';
import '../../services/session_service.dart';
import '../../services/maintenance_local_store.dart';
import '../../services/maintenance_service.dart';
import '../batteries/batteries_page.dart';
import '../batteries/battery_detail_page.dart';
import '../info/info_page.dart';
import '../maintenance/maintenance_page.dart';
import '../models/models_page.dart';
import '../models/model_detail_page.dart';
import '../sessions/sessions_page.dart';
import '../sessions/session_detail_page.dart';
import '../../services/model_local_store.dart';
import '../../services/model_setup_service.dart';
import '../../services/model_radio_setup_service.dart';
import '../../services/radio_service.dart';

class _BatteryChargeMetrics {
  const _BatteryChargeMetrics({
    required this.charged,
    required this.storage,
    required this.toCharge,
  });

  final int charged;
  final int storage;
  final int toCharge;
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with WidgetsBindingObserver {
  int modelCount = 0;
  int batteryCount = 0;
  int sessionCount = 0;
  int maintenanceCount = 0;
  int chargedBatteries = 0;
  int storageBatteries = 0;
  int batteriesToCharge = 0;
  bool loading = true;
  bool hasActiveSession = false;
  Map<String, dynamic>? lastSession;
  String lastModelCategory = 'Voiture';
  String lastModelName = '';
  int totalRunMinutes = 0;
  int totalPacks = 0;
  List<double> chartValues = const <double>[];
  List<double> chartPackValues = const <double>[];
  List<String> chartDateLabels = const <String>[];
  String? accountPseudo;

  StreamSubscription<List<Battery>>? _batterySubscription;
  StreamSubscription? _measurementSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _sessionSubscription;
  StreamSubscription<List<RcModel>>? _modelSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _maintenanceSubscription;
  Timer? _batteryRefreshDebounce;
  Timer? _sessionRefreshDebounce;
  Timer? _dashboardRefreshDebounce;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  RealtimeChannel? _dashboardRealtimeChannel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    accountPseudo = Supabase
        .instance
        .client
        .auth
        .currentUser
        ?.userMetadata?['pseudo']
        ?.toString()
        .trim();
    _startBatteryLiveUpdates();
    _startModelLiveUpdates();
    _startSessionLiveUpdates();
    _startMaintenanceLiveUpdates();
    _startDashboardRefreshTriggers();
    _loadDashboard();
  }

  void _startDashboardRefreshTriggers() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      final isOnline =
          results.isNotEmpty &&
          results.any((result) => result != ConnectivityResult.none);
      if (isOnline) {
        _scheduleDashboardRefresh();
      }
    });

    final client = Supabase.instance.client;
    _dashboardRealtimeChannel = client
        .channel('dashboard-live-${client.auth.currentUser?.id ?? 'anonymous'}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rc_models',
          callback: (_) => _scheduleDashboardRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'rc_sessions',
          callback: (_) => _scheduleDashboardRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'session_runs',
          callback: (_) => _scheduleDashboardRefresh(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'maintenance_records',
          callback: (_) => _scheduleDashboardRefresh(),
        )
        .subscribe();
  }

  void _scheduleDashboardRefresh() {
    _dashboardRefreshDebounce?.cancel();
    _dashboardRefreshDebounce = Timer(
      const Duration(milliseconds: 250),
      _loadDashboard,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleDashboardRefresh();
    }
  }

  void _startBatteryLiveUpdates() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return;
    }

    _batterySubscription = BatteryLocalStore.watchBatteries(
      userId: user.id,
    ).listen((_) => _scheduleBatteryMetricsRefresh());

    _measurementSubscription = BatteryLocalStore.watchMeasurements(
      userId: user.id,
    ).listen((_) => _scheduleBatteryMetricsRefresh());
  }

  void _startModelLiveUpdates() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return;
    }

    _modelSubscription = ModelLocalStore.watchModels(userId: user.id).listen((
      models,
    ) {
      if (!mounted) {
        return;
      }

      final currentModelId = lastSession?['model_id']?.toString().trim();
      String? currentCategory;
      String? currentName;
      if (currentModelId != null && currentModelId.isNotEmpty) {
        for (final model in models) {
          if (model.id?.trim() == currentModelId) {
            final category = model.category.trim();
            if (category.isNotEmpty) {
              currentCategory = category;
            }

            final name = model.name.trim();
            if (name.isNotEmpty) {
              currentName = name;
            }
            break;
          }
        }
      }

      setState(() {
        modelCount = models.length;
        if (currentCategory != null) {
          lastModelCategory = currentCategory!;
        }
        if (currentName != null) {
          lastModelName = currentName!;
        }
        loading = false;
      });
    });
  }

  void _startSessionLiveUpdates() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return;
    }

    _sessionSubscription = SessionLocalStore.watchSessionRows(
      userId: user.id,
    ).listen((rows) => _scheduleSessionMetricsRefresh(rows));
  }

  void _scheduleSessionMetricsRefresh(List<Map<String, dynamic>> rows) {
    _sessionRefreshDebounce?.cancel();
    _sessionRefreshDebounce = Timer(
      const Duration(milliseconds: 80),
      () => _applyLocalSessionMetrics(rows),
    );
  }

  Future<void> _refreshSessionMetricsFromDrift() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return;
    }

    final rows = await SessionLocalStore.getSessionRows(userId: user.id);
    _applyLocalSessionMetrics(rows);
  }

  Future<void> _applyLocalSessionMetrics(
    List<Map<String, dynamic>> rows,
  ) async {
    if (!mounted) {
      return;
    }

    final recent = rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
    final recentModelId = recent?['model_id']?.toString().trim();
    final activeSessionExists = rows.any((row) {
      final endedAt = row['ended_at']?.toString().trim();
      return endedAt == null || endedAt.isEmpty;
    });

    var runMinutes = 0;
    var packs = 0;
    final minutesByDay = <DateTime, int>{};
    final packsByDay = <DateTime, int>{};

    // Le bloc Statistiques représente toujours le même modèle que la carte
    // "Dernière session". Les autres modèles n'entrent pas dans le calcul.
    for (final session in rows) {
      final sessionModelId = session['model_id']?.toString().trim();

      if (recentModelId == null ||
          recentModelId.isEmpty ||
          sessionModelId != recentModelId) {
        continue;
      }

      final runs = (session['session_runs'] as List<dynamic>? ?? const []);
      for (final rawRun in runs) {
        final run = Map<String, dynamic>.from(rawRun as Map);
        final duration = int.tryParse('${run['duration_minutes'] ?? 0}') ?? 0;
        runMinutes += duration;
        packs += 1;

        final startedAt = DateTime.tryParse(
          '${run['started_at'] ?? ''}',
        )?.toLocal();
        if (startedAt != null) {
          final day = DateTime(startedAt.year, startedAt.month, startedAt.day);
          minutesByDay.update(
            day,
            (value) => value + duration,
            ifAbsent: () => duration,
          );
          packsByDay.update(day, (value) => value + 1, ifAbsent: () => 1);
        }
      }
    }

    final sortedDays = minutesByDay.keys.toList()..sort();
    var cumulativeMinutes = 0.0;
    var cumulativePacks = 0.0;
    final chart = <double>[];
    final packChart = <double>[];
    final dateLabels = <String>[];

    for (final day in sortedDays) {
      cumulativeMinutes += minutesByDay[day]!.toDouble();
      cumulativePacks += (packsByDay[day] ?? 0).toDouble();
      chart.add(cumulativeMinutes);
      packChart.add(cumulativePacks);
      dateLabels.add(
        '${day.day.toString().padLeft(2, '0')}/'
        '${day.month.toString().padLeft(2, '0')}',
      );
    }

    var category = 'Voiture';
    var modelName =
        _firstText(recent, ['model_name', 'name', 'model', 'title']) ?? '';

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null && recentModelId != null && recentModelId.isNotEmpty) {
      final model = await ModelLocalStore.getModel(
        userId: user.id,
        modelId: recentModelId,
      );

      final localCategory = model?.category.trim();
      if (localCategory != null && localCategory.isNotEmpty) {
        category = localCategory;
      }

      // RcModel.name contient le nom du modèle uniquement : la marque
      // n'est donc pas ajoutée au titre des statistiques.
      final localName = model?.name.trim();
      if (localName != null && localName.isNotEmpty) {
        modelName = localName;
      }
    }

    if (!mounted) {
      return;
    }

    setState(() {
      sessionCount = rows.length;
      hasActiveSession = activeSessionExists;
      lastSession = recent;
      lastModelCategory = category;
      lastModelName = modelName;
      totalRunMinutes = runMinutes;
      totalPacks = packs;
      chartValues = chart;
      chartPackValues = packChart;
      chartDateLabels = dateLabels;
      loading = false;
    });
  }

  void _startMaintenanceLiveUpdates() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return;
    }

    _maintenanceSubscription =
        MaintenanceLocalStore.watchRecords(userId: user.id).listen((rows) {
          if (!mounted) {
            return;
          }

          setState(() {
            maintenanceCount = rows.length;
            loading = false;
          });
        });
  }

  Future<void> _refreshMaintenanceMetricsFromDrift() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return;
    }

    final rows = await MaintenanceLocalStore.getRecords(userId: user.id);

    if (!mounted) {
      return;
    }

    setState(() {
      maintenanceCount = rows.length;
      loading = false;
    });
  }

  void _scheduleBatteryMetricsRefresh() {
    _batteryRefreshDebounce?.cancel();
    _sessionRefreshDebounce?.cancel();
    _batteryRefreshDebounce = Timer(
      const Duration(milliseconds: 80),
      _refreshBatteryMetricsFromDrift,
    );
  }

  Future<void> _refreshBatteryMetricsFromDrift() async {
    final batteries = await BatteryService.getCachedBatteries();
    if (!mounted) return;

    final metrics = _batteryChargeMetrics(batteries);

    setState(() {
      batteryCount = batteries.length;
      chargedBatteries = metrics.charged;
      storageBatteries = metrics.storage;
      batteriesToCharge = metrics.toCharge;
      loading = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _batteryRefreshDebounce?.cancel();
    _dashboardRefreshDebounce?.cancel();
    _batterySubscription?.cancel();
    _measurementSubscription?.cancel();
    _sessionSubscription?.cancel();
    _modelSubscription?.cancel();
    _maintenanceSubscription?.cancel();
    _connectivitySubscription?.cancel();

    final channel = _dashboardRealtimeChannel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }

    super.dispose();
  }

  Future<void> _refreshDashboardManually() async {
    if (mounted) {
      setState(() => loading = true);
    }

    try {
      await BatteryService.refreshBatteries();
    } catch (_) {
      // Hors ligne, le Dashboard continue d'utiliser le cache Drift.
    }

    await _refreshBatteryMetricsFromDrift();
    await _refreshSessionMetricsFromDrift();
    await _refreshMaintenanceMetricsFromDrift();

    try {
      await MaintenanceService.refreshFromCloud();
    } catch (_) {
      // Hors ligne, le Dashboard conserve les maintenances présentes dans Drift.
    }

    await _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    try {
      final localBatteries = await BatteryService.getCachedBatteries();
      final user = Supabase.instance.client.auth.currentUser;

      if (user != null) {
        final localModels = await ModelLocalStore.getModels(userId: user.id);

        if (mounted) {
          setState(() {
            modelCount = localModels.length;
          });
        }
      }

      if (mounted) {
        final metrics = _batteryChargeMetrics(localBatteries);
        setState(() {
          batteryCount = localBatteries.length;
          chargedBatteries = metrics.charged;
          storageBatteries = metrics.storage;
          batteriesToCharge = metrics.toCharge;
          loading = false;
        });
      }

      await _refreshSessionMetricsFromDrift();
      await _refreshMaintenanceMetricsFromDrift();

      final connectivity = await Connectivity().checkConnectivity();
      final isOffline =
          connectivity.isEmpty ||
          connectivity.every((result) => result == ConnectivityResult.none);

      if (isOffline) {
        return;
      }

      await _refreshAccountProfile();

      // Supabase alimente uniquement le cache local. Le Dashboard reste basé
      // sur Drift et se met à jour via les streams ci-dessus.
      try {
        await BatteryService.getBatteries();
      } catch (_) {}

      try {
        await MaintenanceService.refreshFromCloud();
      } catch (_) {
        // Le cache Drift Maintenance reste prioritaire.
      }

      // Les compteurs restent issus du cache Drift. Les rafraîchissements
      // cloud alimentent uniquement les caches locaux, dont les streams
      // mettent ensuite le Dashboard à jour.
      if (!mounted) return;
      setState(() {
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  _BatteryChargeMetrics _batteryChargeMetrics(List<Battery> batteries) {
    var charged = 0;
    var storage = 0;
    var toCharge = 0;

    for (final battery in batteries) {
      final status = battery.status.toLowerCase();

      if (status.contains('hs') || status.contains('retir')) {
        continue;
      }

      switch (battery.chargeState) {
        case BatteryChargeState.charged:
          charged += 1;
          break;
        case BatteryChargeState.storage:
          storage += 1;
          break;
        case BatteryChargeState.partial:
        case BatteryChargeState.discharged:
          toCharge += 1;
          break;
      }
    }

    return _BatteryChargeMetrics(
      charged: charged,
      storage: storage,
      toCharge: toCharge,
    );
  }

  void _open(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    ).then((_) => _loadDashboard());
  }

  Future<void> _refreshAccountProfile() async {
    try {
      final user = await AccountService.refreshUser();
      if (!mounted) {
        return;
      }

      final pseudo = user.userMetadata?['pseudo']?.toString().trim();
      setState(() {
        accountPseudo = pseudo == null || pseudo.isEmpty ? null : pseudo;
      });
    } catch (_) {
      // Hors ligne : le pseudo déjà présent dans la session reste affiché.
    }
  }

  Future<void> _showAccountDialog() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || !mounted) {
      return;
    }

    try {
      await _refreshAccountProfile();
    } catch (_) {}

    if (!mounted) {
      return;
    }

    final currentUser = Supabase.instance.client.auth.currentUser ?? user;
    final pseudoController = TextEditingController(text: accountPseudo ?? '');

    var savingPseudo = false;
    String? message;
    bool messageSuccess = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> savePseudo() async {
            final pseudo = pseudoController.text.trim();

            setDialogState(() {
              savingPseudo = true;
              message = null;
            });

            try {
              final updated = await AccountService.updatePseudo(pseudo);
              final updatedPseudo = updated.userMetadata?['pseudo']
                  ?.toString()
                  .trim();

              if (mounted) {
                setState(() {
                  accountPseudo = updatedPseudo == null || updatedPseudo.isEmpty
                      ? null
                      : updatedPseudo;
                });
              }

              if (!dialogContext.mounted) return;
              setDialogState(() {
                savingPseudo = false;
                messageSuccess = true;
                message = 'Pseudo enregistré et synchronisé.';
              });
            } on AuthException catch (error) {
              if (!dialogContext.mounted) return;
              setDialogState(() {
                savingPseudo = false;
                messageSuccess = false;
                message = error.message;
              });
            } catch (_) {
              if (!dialogContext.mounted) return;
              setDialogState(() {
                savingPseudo = false;
                messageSuccess = false;
                message = 'Impossible de modifier le pseudo.';
              });
            }
          }

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.account_circle_rounded),
                SizedBox(width: 10),
                Text('Mon compte'),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      initialValue:
                          currentUser.email ?? 'Adresse e-mail non renseignée',
                      readOnly: true,
                      decoration: const InputDecoration(
                        labelText: 'Adresse e-mail',
                        prefixIcon: Icon(Icons.email_outlined),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: pseudoController,
                      enabled: !savingPseudo,
                      decoration: const InputDecoration(
                        labelText: 'Pseudo',
                        hintText: 'Ajouter un pseudo',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: savingPseudo ? null : savePseudo,
                      icon: savingPseudo
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(
                        savingPseudo
                            ? 'Enregistrement...'
                            : 'Enregistrer le pseudo',
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Divider(),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: savingPseudo
                          ? null
                          : () async {
                              Navigator.pop(dialogContext);
                              await _showPasswordDialog();
                            },
                      icon: const Icon(Icons.lock_outline_rounded),
                      label: const Text('Modifier mon mot de passe'),
                    ),
                    const SizedBox(height: 22),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF201A0D),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF8A6825)),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Color(0xFFFFC857),
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Après une déconnexion, une connexion Internet '
                              'est nécessaire pour se reconnecter à RC Companion.',
                              style: TextStyle(
                                color: Color(0xFFFFD98A),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Divider(),
                    const SizedBox(height: 14),
                    const Text(
                      'ZONE DANGEREUSE',
                      style: TextStyle(
                        color: Color(0xFFFF6B64),
                        fontWeight: FontWeight.w900,
                        letterSpacing: .4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Le RESET supprime les données de RC Companion sur le '
                      'cloud et sur cet appareil. Le compte, l’adresse e-mail, '
                      'le pseudo et le mot de passe sont conservés.',
                      style: TextStyle(color: Color(0xFFB9C5D4)),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(dialogContext);
                        await _confirmReset();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFF6B64),
                        side: const BorderSide(color: Color(0xFF8A3430)),
                      ),
                      icon: const Icon(Icons.restart_alt_rounded),
                      label: const Text('RESET — Réinitialiser l’application'),
                    ),
                  ],
                ),
              ),
            ),
            actionsAlignment: MainAxisAlignment.end,
            actions: [
              SizedBox(
                width: 220,
                height: 48,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(dialogContext),
                  icon: const Icon(Icons.close_rounded),
                  label: const Text(
                    'Fermer',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 40,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(dialogContext);
                    await _logout();
                  },
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('Se déconnecter'),
                ),
              ),
            ],
          );
        },
      ),
    );

    pseudoController.dispose();
  }

  Future<void> _showPasswordDialog() async {
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    var savingPassword = false;
    var obscurePassword = true;
    var obscureConfirmation = true;
    String? message;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> savePassword() async {
            final password = passwordController.text;
            final confirmation = confirmPasswordController.text;

            if (password != confirmation) {
              setDialogState(() {
                message = 'Les deux mots de passe ne correspondent pas.';
              });
              return;
            }

            setDialogState(() {
              savingPassword = true;
              message = null;
            });

            try {
              await AccountService.updatePassword(password);

              if (!dialogContext.mounted) {
                return;
              }

              Navigator.pop(dialogContext);

              if (!mounted) {
                return;
              }

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Mot de passe modifié avec succès.'),
                ),
              );
            } on AuthException catch (error) {
              if (!dialogContext.mounted) return;
              setDialogState(() {
                savingPassword = false;
                message = error.message;
              });
            } catch (_) {
              if (!dialogContext.mounted) return;
              setDialogState(() {
                savingPassword = false;
                message = 'Impossible de modifier le mot de passe.';
              });
            }
          }

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.lock_outline_rounded),
                SizedBox(width: 10),
                Text('Modifier mon mot de passe'),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Le mot de passe ne sera modifié qu’après validation.',
                    style: TextStyle(color: Color(0xFF7F8DA0)),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    enabled: !savingPassword,
                    decoration: InputDecoration(
                      labelText: 'Nouveau mot de passe',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        tooltip: obscurePassword
                            ? 'Afficher le mot de passe'
                            : 'Masquer le mot de passe',
                        onPressed: savingPassword
                            ? null
                            : () {
                                setDialogState(() {
                                  obscurePassword = !obscurePassword;
                                });
                              },
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmPasswordController,
                    obscureText: obscureConfirmation,
                    enabled: !savingPassword,
                    onSubmitted: (_) => savePassword(),
                    decoration: InputDecoration(
                      labelText: 'Confirmer le mot de passe',
                      prefixIcon: const Icon(Icons.lock_reset_rounded),
                      suffixIcon: IconButton(
                        tooltip: obscureConfirmation
                            ? 'Afficher le mot de passe'
                            : 'Masquer le mot de passe',
                        onPressed: savingPassword
                            ? null
                            : () {
                                setDialogState(() {
                                  obscureConfirmation = !obscureConfirmation;
                                });
                              },
                        icon: Icon(
                          obscureConfirmation
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  if (message != null) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        message!,
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
                onPressed: savingPassword
                    ? null
                    : () => Navigator.pop(dialogContext),
                child: const Text('Annuler'),
              ),
              FilledButton.icon(
                onPressed: savingPassword ? null : savePassword,
                icon: savingPassword
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.password_rounded),
                label: Text(
                  savingPassword
                      ? 'Modification...'
                      : 'Modifier le mot de passe',
                ),
              ),
            ],
          );
        },
      ),
    );

    passwordController.dispose();
    confirmPasswordController.dispose();

    if (mounted) {
      await _showAccountDialog();
    }
  }

  Future<void> _confirmReset() async {
    final confirmationController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final valid = confirmationController.text.trim() == 'RESET';

          return AlertDialog(
            title: const Text('RESET de RC Companion'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Cette opération est irréversible. Tous les modèles, '
                  'batteries, relevés, sessions, maintenances, radios, '
                  'documents et historiques seront supprimés.',
                ),
                const SizedBox(height: 12),
                const Text(
                  'Le RESET nécessite Internet et sera propagé aux autres '
                  'appareils du même compte lorsqu’ils se reconnecteront.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Pour continuer, saisis RESET en majuscules :',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmationController,
                  autofocus: true,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: const InputDecoration(
                    hintText: 'RESET',
                    prefixIcon: Icon(Icons.warning_amber_rounded),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Annuler'),
              ),
              FilledButton(
                onPressed: valid
                    ? () => Navigator.pop(dialogContext, true)
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFB3261E),
                ),
                child: const Text('Continuer'),
              ),
            ],
          );
        },
      ),
    );

    confirmationController.dispose();

    if (confirmed != true || !mounted) {
      return;
    }

    final finalConfirmation = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Dernière confirmation'),
        content: const Text(
          'Supprimer définitivement toutes les données de RC Companion ? '
          'Cette action ne pourra pas être annulée.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB3261E),
            ),
            child: const Text('Réinitialiser définitivement'),
          ),
        ],
      ),
    );

    if (finalConfirmation != true || !mounted) {
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 18),
            Expanded(child: Text('Réinitialisation en cours...')),
          ],
        ),
      ),
    );

    try {
      await AccountService.resetApplicationData();

      if (!mounted) {
        return;
      }

      Navigator.of(context, rootNavigator: true).pop();
      await _loadDashboard();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'RC Companion a été réinitialisé. Le compte est conservé.',
          ),
        ),
      );
    } on AuthException catch (error) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Le RESET n’a pas pu être terminé : $error')),
      );
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Déconnexion'),
        content: const Text(
          'Veux-tu vraiment te déconnecter de RC Companion ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Se déconnecter'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await Supabase.instance.client.auth.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop =
            constraints.maxWidth >= 860 && constraints.maxHeight >= 640;
        return Scaffold(
          backgroundColor: const Color(0xFF050D18),
          body: SafeArea(
            child: desktop
                ? Row(
                    children: [
                      _DesktopSidebar(
                        onHome: () {},
                        onModels: () => _open(const ModelsPage()),
                        onBatteries: () => _open(const BatteriesPage()),
                        onSessions: () =>
                            _open(const SessionsPage(historyOnly: true)),
                        onMaintenance: () => _open(const MaintenancePage()),
                        onRadios: () => _open(const RadiosPage()),
                        onInfo: () => _open(const InfoPage()),
                      ),
                      Expanded(child: _dashboardContent(desktop: true)),
                    ],
                  )
                : _compactMobileDashboard(),
          ),
          bottomNavigationBar: desktop
              ? null
              : _MobileNavigation(
                  onHome: () {},
                  onModels: () => _open(const ModelsPage()),
                  onBatteries: () => _open(const BatteriesPage()),
                  onSessions: () =>
                      _open(const SessionsPage(historyOnly: true)),
                  onRadios: () => _open(const RadiosPage()),
                ),
        );
      },
    );
  }

  Widget _compactMobileDashboard() {
    final email = Supabase.instance.client.auth.currentUser?.email;
    final name = (accountPseudo != null && accountPseudo!.isNotEmpty)
        ? accountPseudo!
        : _displayName(email);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final isPhone = width < 600;

        final horizontalPadding = isPhone ? 8.0 : 14.0;
        final gap = isPhone ? 6.0 : 10.0;
        final topBarHeight = isPhone ? 48.0 : 56.0;
        final copyrightHeight = isPhone ? 15.0 : 18.0;

        // Les blocs occupent tout l'espace vertical disponible.
        // Sur un grand écran portrait, ils grandissent au lieu de laisser
        // une grande zone vide sous les statistiques.
        final usableHeight =
            height - topBarHeight - copyrightHeight - gap * 4 - 4;

        final metricsFlex = isPhone ? 14 : 16;
        final middleFlex = isPhone ? 34 : 36;
        final statsFlex = isPhone ? 52 : 48;
        final totalFlex = metricsFlex + middleFlex + statsFlex;

        final metricHeight = usableHeight * metricsFlex / totalFlex;

        final calculatedMiddleHeight = usableHeight * middleFlex / totalFlex;
        final minMiddleHeight = isPhone ? 118.0 : 138.0;
        final middleHeight = calculatedMiddleHeight < minMiddleHeight
            ? minMiddleHeight
            : calculatedMiddleHeight;

        final remainingForStats = usableHeight - metricHeight - middleHeight;
        final minStatsHeight = isPhone ? 120.0 : 150.0;
        final statsHeight = remainingForStats < minStatsHeight
            ? minStatsHeight
            : remainingForStats;

        final metricWidth = (width - horizontalPadding * 2 - gap * 4) / 5;

        return RefreshIndicator(
          onRefresh: _loadDashboard,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: height,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  0,
                  horizontalPadding,
                  2,
                ),
                child: Column(
                  children: [
                    SizedBox(
                      height: topBarHeight,
                      child: _CompactTopBar(
                        name: name,
                        onRefresh: _refreshDashboardManually,
                        onInfo: () => _open(const InfoPage()),
                        onAccount: _showAccountDialog,
                        onSession: _handleNewSessionButton,
                        hasActiveSession: hasActiveSession,
                      ),
                    ),
                    SizedBox(height: gap),
                    SizedBox(
                      height: metricHeight,
                      child: Row(
                        children: [
                          SizedBox(
                            width: metricWidth,
                            child: _CompactMetricCard(
                              value: modelCount,
                              label: 'MODÈLES',
                              asset: 'assets/images/rc_icon_models_hd.png',
                              color: const Color(0xFF218BFF),
                              loading: loading,
                              onTap: _openContextualModel,
                            ),
                          ),
                          SizedBox(width: gap),
                          SizedBox(
                            width: metricWidth,
                            child: _CompactMetricCard(
                              value: batteryCount,
                              label: 'BATTERIES',
                              asset: 'assets/images/rc_icon_batteries_hd.png',
                              color: const Color(0xFFFF3D36),
                              loading: loading,
                              onTap: _openContextualBattery,
                            ),
                          ),
                          SizedBox(width: gap),
                          SizedBox(
                            width: metricWidth,
                            child: _CompactMetricCard(
                              value: sessionCount,
                              label: 'SESSIONS',
                              asset: 'assets/images/rc_icon_sessions_hd.png',
                              color: const Color(0xFF168CFF),
                              loading: loading,
                              onTap: () => _open(const SessionsPage()),
                            ),
                          ),
                          SizedBox(width: gap),
                          SizedBox(
                            width: metricWidth,
                            child: _CompactMetricCard(
                              value: maintenanceCount,
                              label: 'MAINTENANCE',
                              asset: 'assets/images/rc_icon_maintenance_hd.png',
                              color: const Color(0xFFD9DEE8),
                              loading: loading,
                              onTap: _openContextualMaintenance,
                            ),
                          ),
                          SizedBox(width: gap),
                          SizedBox(
                            width: metricWidth,
                            child: _CompactMetricCard(
                              value: 0,
                              label: 'COMMANDE\nRADIO',
                              asset: 'assets/images/rc_icon_radio_nb4_hd.png',
                              color: const Color(0xFFD9DEE8),
                              loading: false,
                              showValue: false,
                              onTap: _showCurrentSessionRadioCommands,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: gap),
                    SizedBox(
                      height: middleHeight,
                      child: Row(
                        children: [
                          Expanded(
                            child: _compactLastSessionCard(isPhone: isPhone),
                          ),
                          SizedBox(width: gap),
                          Expanded(
                            child: _compactBatteryChargeCard(isPhone: isPhone),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: gap),
                    SizedBox(
                      height: statsHeight,
                      child: _compactStatisticsCard(isPhone: isPhone),
                    ),
                    SizedBox(height: gap),
                    SizedBox(
                      height: copyrightHeight,
                      child: Center(
                        child: Text(
                          '© ${DateTime.now().year} RC Companion — Tous droits réservés.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: const Color(0xFF65758A),
                            fontSize: isPhone ? 8 : 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _compactLastSessionCard({required bool isPhone}) {
    final row = lastSession;
    final date = _formatSessionDate(row);
    final model =
        _firstText(row, ['model_name', 'name', 'model', 'title']) ??
        'Aucun modèle';
    final duration = _durationText(row);

    return _CompactPanel(
      title: 'DERNIÈRE SESSION',
      isPhone: isPhone,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final veryTight = constraints.maxHeight < 95;
          final tight = constraints.maxHeight < 120;

          return Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!veryTight)
                      Text(
                        date,
                        maxLines: 1,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: isPhone ? 8 : 10,
                        ),
                      ),
                    if (!veryTight) const SizedBox(height: 2),
                    Text(
                      model,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: isPhone ? 12 : 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (!veryTight) ...[
                      const SizedBox(height: 2),
                      Text(
                        duration,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: isPhone ? 10 : 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                    const Spacer(),
                    SizedBox(
                      height: veryTight
                          ? 22
                          : tight
                          ? 25
                          : (isPhone ? 27 : 32),
                      child: OutlinedButton(
                        onPressed: () => _open(const SessionsPage()),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(
                            horizontal: veryTight ? 5 : (isPhone ? 7 : 10),
                          ),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Voir la session',
                            style: TextStyle(
                              fontSize: veryTight ? 8 : (isPhone ? 9 : 11),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: EdgeInsets.all(veryTight ? 2 : 4),
                  child: Center(
                    child: Transform.translate(
                      offset: Offset(
                        isPhone
                            ? 0
                            : veryTight
                            ? -18
                            : tight
                            ? -22
                            : -26,
                        0,
                      ),
                      child: Transform.scale(
                        scale: isPhone
                            ? 1.12
                            : veryTight
                            ? 1.85
                            : tight
                            ? 1.95
                            : 2.05,
                        child: Image.asset(
                          _categoryAsset(lastModelCategory),
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _compactBatteryChargeCard({required bool isPhone}) {
    return _CompactPanel(
      title: 'ÉTAT DES BATTERIES',
      isPhone: isPhone,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final veryTight = constraints.maxHeight < 95;
          final tight = constraints.maxHeight < 120;

          return Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _compactBatteryStateLine(
                      label: 'Chargées',
                      value: chargedBatteries,
                      color: const Color(0xFF2E9B57),
                      isPhone: isPhone,
                    ),
                    SizedBox(height: veryTight ? 1 : (isPhone ? 2 : 4)),
                    _compactBatteryStateLine(
                      label: 'Storage',
                      value: storageBatteries,
                      color: const Color(0xFF3578C8),
                      isPhone: isPhone,
                    ),
                    SizedBox(height: veryTight ? 1 : (isPhone ? 2 : 4)),
                    _compactBatteryStateLine(
                      label: 'À charger',
                      value: batteriesToCharge,
                      color: const Color(0xFFE28A2B),
                      isPhone: isPhone,
                    ),
                    const Spacer(),
                    SizedBox(
                      height: veryTight
                          ? 22
                          : tight
                          ? 25
                          : (isPhone ? 27 : 32),
                      child: OutlinedButton(
                        onPressed: () => _open(const BatteriesPage()),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(
                            horizontal: veryTight ? 4 : (isPhone ? 5 : 8),
                          ),
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            'Voir mes batteries',
                            style: TextStyle(
                              fontSize: veryTight ? 7 : (isPhone ? 8 : 10),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: EdgeInsets.all(veryTight ? 2 : 4),
                  child: Center(
                    child: Transform.scale(
                      scale: isPhone
                          ? 1.00
                          : veryTight
                          ? 1.45
                          : tight
                          ? 1.55
                          : 1.65,
                      child: Image.asset(
                        'assets/images/rc_battery_dashboard_hd.png',
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _compactBatteryStateLine({
    required String label,
    required int value,
    required Color color,
    required bool isPhone,
  }) {
    return Row(
      children: [
        Container(
          width: isPhone ? 6 : 8,
          height: isPhone ? 6 : 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: isPhone ? 4 : 6),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: isPhone ? 9 : 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          '$value',
          style: TextStyle(
            color: color,
            fontSize: isPhone ? 11 : 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _compactStatisticsCard({required bool isPhone}) {
    final hours = totalRunMinutes ~/ 60;
    final minutes = totalRunMinutes % 60;

    return _CompactPanel(
      title: 'STATISTIQUES — ÉVOLUTION RÉELLE',
      isPhone: isPhone,
      titleTrailing: lastModelName.isEmpty
          ? null
          : Text(
              lastModelName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: const Color(0xFF168CFF),
                fontSize: isPhone ? 10 : 12,
                fontWeight: FontWeight.w900,
              ),
            ),
      child: Row(
        children: [
          Expanded(
            flex: isPhone ? 4 : 3,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _CompactStatLine(
                  icon: Icons.schedule_rounded,
                  label: 'Temps total',
                  value: '${hours}h ${minutes.toString().padLeft(2, '0')}m',
                  isPhone: isPhone,
                ),
                SizedBox(height: isPhone ? 4 : 7),
                _CompactStatLine(
                  icon: Icons.battery_5_bar_rounded,
                  label: 'Packs',
                  value: '$totalPacks',
                  isPhone: isPhone,
                ),
              ],
            ),
          ),
          SizedBox(width: isPhone ? 6 : 10),
          Expanded(
            flex: isPhone ? 5 : 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ChartLegend(compact: isPhone),
                SizedBox(height: isPhone ? 2 : 4),
                Expanded(
                  child: CustomPaint(
                    painter: _DashboardChartPainter(
                      minutesValues: chartValues,
                      packValues: chartPackValues,
                      dateLabels: chartDateLabels,
                      compact: isPhone,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashboardContent({required bool desktop}) {
    final email = Supabase.instance.client.auth.currentUser?.email;
    final name = (accountPseudo != null && accountPseudo!.isNotEmpty)
        ? accountPseudo!
        : _displayName(email);

    return RefreshIndicator(
      onRefresh: _loadDashboard,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _TopBar(
              desktop: desktop,
              name: name,
              onRefresh: _refreshDashboardManually,
              onInfo: () => _open(const InfoPage()),
              onAccount: _showAccountDialog,
              onSession: _openContextualSession,
              hasActiveSession: hasActiveSession,
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              desktop ? 24 : 16,
              8,
              desktop ? 24 : 16,
              28,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _metricGrid(desktop),
                const SizedBox(height: 16),
                if (desktop)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _lastSessionCard()),
                      const SizedBox(width: 16),
                      Expanded(child: _batteryChargeCard()),
                    ],
                  )
                else ...[
                  _lastSessionCard(),
                  const SizedBox(height: 14),
                  _batteryChargeCard(),
                ],
                const SizedBox(height: 16),
                _statisticsCard(),
                const SizedBox(height: 18),
                Center(
                  child: Text(
                    '© ${DateTime.now().year} RC Companion — Tous droits réservés.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF65758A),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricGrid(bool desktop) {
    final cards = [
      _MetricCardData(
        value: modelCount,
        label: 'MODÈLES',
        asset: 'assets/images/rc_icon_models_hd.png',
        color: const Color(0xFF218BFF),
        onTap: _openContextualModel,
      ),
      _MetricCardData(
        value: batteryCount,
        label: 'BATTERIES',
        asset: 'assets/images/rc_icon_batteries_hd.png',
        color: const Color(0xFFFF3D36),
        onTap: _openContextualBattery,
      ),
      _MetricCardData(
        value: sessionCount,
        label: 'SESSIONS',
        asset: 'assets/images/rc_icon_sessions_hd.png',
        color: const Color(0xFF168CFF),
        onTap: () => _open(const SessionsPage()),
      ),
      _MetricCardData(
        value: maintenanceCount,
        label: 'MAINTENANCE',
        asset: 'assets/images/rc_icon_maintenance_hd.png',
        color: const Color(0xFFD9DEE8),
        onTap: _openContextualMaintenance,
      ),
      _MetricCardData(
        value: 0,
        label: 'COMMANDE\nRADIO',
        asset: 'assets/images/rc_icon_radio_nb4_hd.png',
        color: const Color(0xFFD9DEE8),
        showValue: false,
        onTap: _showCurrentSessionRadioCommands,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = desktop ? 5 : 1;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards
              .map(
                (card) => SizedBox(
                  width: width,
                  child: _MetricCard(data: card, loading: loading),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _lastSessionCard() {
    final row = lastSession;
    final date = _formatSessionDate(row);
    final model =
        _firstText(row, ['model_name', 'name', 'model', 'title']) ??
        'Aucun modèle';
    final place =
        _firstText(row, ['location', 'place', 'terrain']) ??
        'Lieu non renseigné';
    final breakages = _firstText(row, ['breakages']);
    final incidentText = breakages == null || breakages.trim().isEmpty
        ? 'Aucune casse'
        : breakages;
    final duration = _durationText(row);

    return _DashboardPanel(
      title: 'DERNIÈRE SESSION',
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(date, style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 6),
                Text(
                  model,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  duration,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  incidentText,
                  style: const TextStyle(color: Color(0xFF7F8DA0)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  place,
                  style: const TextStyle(
                    color: Color(0xFF65758A),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: () => _open(const SessionsPage()),
                  child: const Text('Voir la session'),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 210,
            height: 145,
            child: Center(
              child: Transform.translate(
                offset: const Offset(-26, 0),
                child: Transform.scale(
                  scale: 1.85,
                  child: Image.asset(
                    _categoryAsset(lastModelCategory),
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _batteryChargeCard() {
    return _DashboardPanel(
      title: 'ÉTAT DES BATTERIES',
      child: SizedBox(
        height: 190,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _batteryStateLine(
                    label: 'Chargées',
                    value: chargedBatteries,
                    color: const Color(0xFF2E9B57),
                  ),
                  const SizedBox(height: 7),
                  _batteryStateLine(
                    label: 'Storage',
                    value: storageBatteries,
                    color: const Color(0xFF3578C8),
                  ),
                  const SizedBox(height: 7),
                  _batteryStateLine(
                    label: 'À charger',
                    value: batteriesToCharge,
                    color: const Color(0xFFE28A2B),
                  ),
                  const SizedBox(height: 13),
                  Center(
                    child: SizedBox(
                      width: 180,
                      height: 48,
                      child: OutlinedButton(
                        onPressed: () => _open(const BatteriesPage()),
                        style: OutlinedButton.styleFrom(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        child: const Text(
                          'Voir mes batteries',
                          maxLines: 1,
                          softWrap: false,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 210,
              height: 190,
              child: Center(
                child: Transform.scale(
                  scale: 0.95,
                  child: Image.asset(
                    'assets/images/rc_battery_dashboard_hd.png',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _batteryStateLine({
    required String label,
    required int value,
    required Color color,
  }) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$value',
          style: TextStyle(
            color: color,
            fontSize: 19,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _statisticsCard() {
    final hours = totalRunMinutes ~/ 60;
    final minutes = totalRunMinutes % 60;

    return _DashboardPanel(
      title: 'STATISTIQUES — ÉVOLUTION RÉELLE',
      titleTrailing: lastModelName.isEmpty
          ? null
          : Text(
              lastModelName,
              style: const TextStyle(
                color: Color(0xFF168CFF),
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth > 620;
          final stats = Column(
            children: [
              _StatLine(
                icon: Icons.schedule_rounded,
                label: 'Temps total',
                value: '${hours}h ${minutes.toString().padLeft(2, '0')}m',
              ),
              const SizedBox(height: 12),
              _StatLine(
                icon: Icons.battery_5_bar_rounded,
                label: 'Nombre de packs utilisés',
                value: '$totalPacks',
              ),
            ],
          );

          final chart = SizedBox(
            height: 170,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _ChartLegend(),
                const SizedBox(height: 5),
                Expanded(
                  child: CustomPaint(
                    painter: _DashboardChartPainter(
                      minutesValues: chartValues,
                      packValues: chartPackValues,
                      dateLabels: chartDateLabels,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ],
            ),
          );

          if (wide) {
            return Row(
              children: [
                Expanded(flex: 2, child: stats),
                const SizedBox(width: 18),
                Expanded(flex: 3, child: chart),
              ],
            );
          }
          return Column(children: [stats, const SizedBox(height: 18), chart]);
        },
      ),
    );
  }

  String _categoryAsset(String category) {
    final normalized = category.toLowerCase();
    if (normalized.contains('moto')) {
      return 'assets/images/rc_vehicle_moto_hd.png';
    }
    if (normalized.contains('bateau')) {
      return 'assets/images/rc_vehicle_boat_hd.png';
    }
    return 'assets/images/rc_vehicle_car_hd.png';
  }

  String _formatSessionDate(Map<String, dynamic>? row) {
    final raw = _firstText(row, ['started_at', 'session_date', 'date']);
    final date = raw == null ? null : DateTime.tryParse(raw)?.toLocal();
    if (date == null) return 'Aucune session';
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '$day/$month/${date.year}';
  }

  String _displayName(String? email) {
    final metadata =
        Supabase.instance.client.auth.currentUser?.userMetadata ?? {};
    final pseudo = metadata['pseudo']?.toString().trim();
    if (pseudo != null && pseudo.isNotEmpty) {
      return pseudo;
    }
    final raw = email?.split('@').first.trim();
    if (raw == null || raw.isEmpty) return 'Pilote';
    return '${raw[0].toUpperCase()}${raw.substring(1)}';
  }

  String? _firstText(Map<String, dynamic>? row, List<String> keys) {
    if (row == null) return null;
    for (final key in keys) {
      final value = row[key];
      if (value != null && '$value'.trim().isNotEmpty) {
        return '$value';
      }
    }
    return null;
  }

  String _durationText(Map<String, dynamic>? row) {
    if (row == null) return '0 min';
    final value =
        row['dashboard_duration_minutes'] ??
        row['duration_minutes'] ??
        row['runtime_minutes'] ??
        row['total_minutes'];
    final minutes = int.tryParse('$value') ?? 0;
    if (minutes < 60) return '$minutes min';
    return '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
  }

  Future<RcSession?> _currentOpenSession() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return null;
    }

    final models = await ModelLocalStore.getModels(userId: user.id);
    final batteries = await BatteryService.getCachedBatteries();
    final sessions = await SessionService.getSessions(
      models: models,
      batteries: batteries,
    );

    for (final session in sessions) {
      if (!session.isClosed) {
        return session;
      }
    }

    return null;
  }

  Future<void> _openContextualModel() async {
    final session = await _currentOpenSession();

    if (!mounted) {
      return;
    }

    if (session == null) {
      _open(const ModelsPage());
      return;
    }

    final modelId = session.model.id?.trim();
    if (modelId == null || modelId.isEmpty) {
      _open(const ModelsPage());
      return;
    }

    _open(ModelDetailPage(modelId: modelId, model: session.model));
  }

  Future<void> _openContextualBattery() async {
    final session = await _currentOpenSession();

    if (!mounted) {
      return;
    }

    if (session == null) {
      _open(const BatteriesPage());
      return;
    }

    List<Battery> batteries = const <Battery>[];

    final activeRun = session.activeRun;
    if (activeRun != null && activeRun.batteries.isNotEmpty) {
      batteries = activeRun.batteries;
    } else if (session.runs.isNotEmpty) {
      final latestRun = session.runs.last;
      if (latestRun.batteries.isNotEmpty) {
        batteries = latestRun.batteries;
      }
    }

    if (batteries.isEmpty) {
      _open(const BatteriesPage());
      return;
    }

    if (batteries.length == 1) {
      _open(BatteryDetailPage(battery: batteries.first));
      return;
    }

    final selected = await showDialog<Battery>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Batteries de la session en cours'),
        content: SizedBox(
          width: 460,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: batteries.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final battery = batteries[index];
              return ListTile(
                leading: const Icon(
                  Icons.battery_charging_full_rounded,
                  color: Color(0xFF168CFF),
                ),
                title: Text(
                  battery.id,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${battery.brand} • ${battery.technology} • '
                  '${battery.cells} • ${battery.capacity} mAh',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(dialogContext, battery),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );

    if (selected != null && mounted) {
      _open(BatteryDetailPage(battery: selected));
    }
  }

  Future<void> _handleNewSessionButton() async {
    final activeSession = await _currentOpenSession();

    if (!mounted) {
      return;
    }

    if (activeSession != null) {
      final accessSession = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.info_outline_rounded),
          title: const Text('Session déjà en cours'),
          content: Text(
            'Une session est déjà en cours avec '
            '${activeSession.model.name}.'
            '\n\nSouhaites-tu accéder à cette session ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Non'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Accéder à la session'),
            ),
          ],
        ),
      );

      if (accessSession == true && mounted) {
        _open(const SessionsPage());
      }
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      return;
    }

    final models = await ModelLocalStore.getModels(userId: user.id);

    if (!mounted) {
      return;
    }

    if (models.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Nouvelle session'),
          content: const Text(
            'Aucun modèle n’est enregistré. '
            'Enregistre d’abord un modèle avant d’ouvrir une session.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
      return;
    }

    final result = await showDialog<_DashboardNewSessionResult>(
      context: context,
      builder: (dialogContext) => _DashboardNewSessionDialog(models: models),
    );

    if (result == null || !mounted) {
      return;
    }

    try {
      await SessionService.saveSession(
        RcSession(
          model: result.model,
          startedAt: DateTime.now(),
          location: result.location,
        ),
      );

      if (!mounted) {
        return;
      }

      await _refreshSessionMetricsFromDrift();

      if (!mounted) {
        return;
      }

      _open(const SessionsPage());
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ouverture de la session impossible : $error')),
      );
    }
  }

  Future<void> _openContextualSession() async {
    final session = await _currentOpenSession();

    if (!mounted) {
      return;
    }

    if (session == null) {
      _open(const SessionsPage());
      return;
    }

    _open(SessionDetailPage(session: session));
  }

  Future<void> _openContextualMaintenance() async {
    final session = await _currentOpenSession();

    if (!mounted) {
      return;
    }

    if (session == null) {
      _open(const MaintenancePage());
      return;
    }

    final modelId = session.model.id?.trim();
    if (modelId == null || modelId.isEmpty) {
      _open(const MaintenancePage());
      return;
    }

    final setup = await ModelSetupService.getLocalSetup(modelId);

    if (!mounted) {
      return;
    }

    final fields = setup.enabledFields
        .where((field) => setup.currentValue(field).trim().isNotEmpty)
        .toList(growable: false);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.tune_rounded),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Setup actuel — ${session.model.name}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 560,
          child: fields.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    'Aucun réglage de setup actuel n’est renseigné '
                    'pour ce modèle.',
                    textAlign: TextAlign.center,
                  ),
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 520),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: fields.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final key = fields[index];
                      final value = setup.currentValue(key).trim();

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.settings_rounded,
                          color: Color(0xFF168CFF),
                        ),
                        title: Text(
                          _setupFieldLabel(key),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(value),
                      );
                    },
                  ),
                ),
        ),
        actions: [
          const Text(
            'Lecture seule',
            style: TextStyle(color: Color(0xFF7F8DA0), fontSize: 12),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  String _setupFieldLabel(String key) {
    const labels = <String, String>{
      'pinion': 'Pignon moteur',
      'spur': 'Couronne',
      'front_diff_oil': 'Huile diff avant',
      'center_diff_oil': 'Huile diff central',
      'rear_diff_oil': 'Huile diff arrière',
      'front_shock_oil': 'Huile amortisseurs avant',
      'rear_shock_oil': 'Huile amortisseurs arrière',
      'front_camber': 'Carrossage avant',
      'rear_camber': 'Carrossage arrière',
      'front_toe': 'Pincement avant',
      'rear_toe': 'Pincement arrière',
      'front_ride_height': 'Garde au sol avant',
      'rear_ride_height': 'Garde au sol arrière',
      'esc': 'ESC',
      'motor': 'Moteur',
      'servo': 'Servo',
      'tires': 'Pneus',
      'notes': 'Notes',
    };

    return labels[key] ?? key;
  }

  Future<void> _showCurrentSessionRadioCommands() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null || !mounted) {
      return;
    }

    final rows = await SessionLocalStore.getSessionRows(userId: user.id);

    Map<String, dynamic>? activeSession;
    for (final row in rows) {
      final endedAt = row['ended_at']?.toString().trim();
      if (endedAt == null || endedAt.isEmpty) {
        activeSession = row;
        break;
      }
    }

    if (!mounted) {
      return;
    }

    String? modelId = activeSession?['model_id']?.toString().trim();

    if (activeSession == null) {
      final models = await ModelLocalStore.getModels(userId: user.id);

      if (!mounted) {
        return;
      }

      if (models.isEmpty) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Commande radio'),
            content: const Text(
              'Aucun modèle disponible. Créez d’abord un modèle pour '
              'consulter ses commandes radio.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Fermer'),
              ),
            ],
          ),
        );
        return;
      }

      modelId = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Commande radio'),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Aucune session en cours. Sélectionnez un modèle '
                    'pour afficher ses commandes radio.',
                  ),
                  const SizedBox(height: 14),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 420),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: models.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final model = models[index];
                        return ListTile(
                          leading: const Icon(
                            Icons.directions_car_rounded,
                            color: Color(0xFF168CFF),
                          ),
                          title: Text(
                            model.name,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.pop(dialogContext, model.id),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Fermer'),
              ),
            ],
          );
        },
      );

      if (modelId == null || modelId.isEmpty || !mounted) {
        return;
      }
    }

    if (modelId == null || modelId.isEmpty) {
      return;
    }

    final model = await ModelLocalStore.getModel(
      userId: user.id,
      modelId: modelId,
    );

    if (!mounted) {
      return;
    }

    if (model == null) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Commandes radio'),
          content: const Text(
            'Le modèle de la session en cours est introuvable.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
      return;
    }

    final radioId = model.radioId?.trim();
    if (radioId == null || radioId.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Commandes radio — ${model.name}'),
          content: const Text('Aucune radio n’est associée à ce modèle.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
      return;
    }

    final setupService = ModelRadioSetupService();
    final radioService = RadioService();

    final setup = await setupService.getSetup(modelId: modelId);
    final radios = await radioService.fetchRadios();

    dynamic selectedRadio;
    for (final radio in radios) {
      if (radio.id == radioId) {
        selectedRadio = radio;
        break;
      }
    }

    RadioControlLayout? layout;
    if (selectedRadio != null) {
      layout = radioControlLayoutFor(
        brand: selectedRadio.brand,
        model: selectedRadio.model,
      );
    }

    final assignments = <({String label, String value})>[];

    if (setup != null && layout != null) {
      for (final control in layout.controls) {
        final key = 'control_assignment_${control.key}';
        if (!setup.enabledFields.contains(key)) {
          continue;
        }

        final value = setup.value(key).trim();
        assignments.add((
          label: control.label,
          value: value.isEmpty ? 'Non renseignée' : value,
        ));
      }
    }

    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.settings_remote_rounded),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Commandes radio — ${model.name}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (selectedRadio != null) ...[
                Text(
                  selectedRadio.fullName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (assignments.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    'Aucune affectation de commande radio enregistrée '
                    'pour ce modèle.',
                    textAlign: TextAlign.center,
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: assignments.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = assignments[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.radio_button_checked_rounded,
                          color: Color(0xFF168CFF),
                        ),
                        title: Text(
                          item.label,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(item.value),
                      );
                    },
                  ),
                ),
              const SizedBox(height: 8),
              const Text(
                'Affichage uniquement — aucune modification possible ici.',
                style: TextStyle(color: Color(0xFF7F8DA0), fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  void _showMoreMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.build_rounded),
              title: const Text('Maintenance'),
              onTap: () {
                Navigator.pop(sheetContext);
                _open(const MaintenancePage());
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_remote_rounded),
              title: const Text('Mes radios'),
              onTap: () {
                Navigator.pop(sheetContext);
                _open(const RadiosPage());
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('Informations & Références'),
              onTap: () {
                Navigator.pop(sheetContext);
                _open(const InfoPage());
              },
            ),
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: const Text('Mon compte'),
              onTap: () {
                Navigator.pop(sheetContext);
                _showAccountDialog();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardNewSessionResult {
  const _DashboardNewSessionResult({
    required this.model,
    required this.location,
  });

  final RcModel model;
  final String location;
}

class _DashboardNewSessionDialog extends StatefulWidget {
  const _DashboardNewSessionDialog({required this.models});

  final List<RcModel> models;

  @override
  State<_DashboardNewSessionDialog> createState() =>
      _DashboardNewSessionDialogState();
}

class _DashboardNewSessionDialogState
    extends State<_DashboardNewSessionDialog> {
  RcModel? _selectedModel;
  final TextEditingController _locationController = TextEditingController();

  @override
  void dispose() {
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nouvelle session'),
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
                    (model) => DropdownMenuItem<RcModel>(
                      value: model,
                      child: Text(
                        '${model.name} — ${model.brand}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
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
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: _selectedModel == null
              ? null
              : () {
                  Navigator.pop(
                    context,
                    _DashboardNewSessionResult(
                      model: _selectedModel!,
                      location: _locationController.text.trim(),
                    ),
                  );
                },
          child: const Text('Ouvrir'),
        ),
      ],
    );
  }
}

class _CompactTopBar extends StatelessWidget {
  const _CompactTopBar({
    required this.name,
    required this.onRefresh,
    required this.onInfo,
    required this.onAccount,
    required this.onSession,
    required this.hasActiveSession,
  });

  final String name;
  final Future<void> Function() onRefresh;
  final VoidCallback onInfo;
  final VoidCallback onAccount;
  final VoidCallback onSession;
  final bool hasActiveSession;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Bonjour, $name !',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(width: 6),
        FilledButton.icon(
          onPressed: onSession,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            visualDensity: VisualDensity.compact,
          ),
          icon: const Icon(Icons.add_rounded, size: 17),
          label: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              'Nouvelle session',
              maxLines: 1,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Actualiser le Dashboard',
          onPressed: () => onRefresh(),
          icon: const Icon(Icons.refresh_rounded, size: 21),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: 'Informations & Références',
          onPressed: onInfo,
          icon: const Icon(Icons.info_outline_rounded, size: 20),
        ),
        const SizedBox(width: 2),
        InkWell(
          onTap: onAccount,
          borderRadius: BorderRadius.circular(18),
          child: CircleAvatar(
            radius: 16,
            backgroundColor: const Color(0xFF185BEA),
            child: Text(
              name.isEmpty ? 'R' : name[0].toUpperCase(),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }
}

class _CompactMetricCard extends StatelessWidget {
  const _CompactMetricCard({
    required this.value,
    required this.label,
    required this.asset,
    required this.color,
    required this.loading,
    required this.onTap,
    this.showValue = true,
  });

  final int value;
  final String label;
  final String asset;
  final Color color;
  final bool loading;
  final VoidCallback onTap;
  final bool showValue;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1A2D),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF23405E)),
        ),
        child: loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Image.asset(
                      asset,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Expanded(
                    flex: 5,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showValue) ...[
                            Text(
                              '$value',
                              style: TextStyle(
                                color: color,
                                fontSize: 18,
                                height: 1,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                          ],
                          Text(
                            label,
                            maxLines: 2,
                            textAlign: TextAlign.left,
                            style: const TextStyle(
                              fontSize: 8,
                              height: 1,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _CompactPanel extends StatelessWidget {
  const _CompactPanel({
    required this.title,
    required this.child,
    required this.isPhone,
    this.titleTrailing,
  });

  final String title;
  final Widget child;
  final bool isPhone;
  final Widget? titleTrailing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final veryTight = constraints.maxHeight < 110;
        final padding = veryTight ? 6.0 : (isPhone ? 8.0 : 10.0);
        final titleGap = veryTight ? 3.0 : (isPhone ? 5.0 : 7.0);

        return Container(
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: const Color(0xFF071426),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: const Color(0xFF23405E)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: veryTight ? 8 : (isPhone ? 9 : 11),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  if (titleTrailing != null) ...[
                    const SizedBox(width: 4),
                    const Text('—'),
                    const SizedBox(width: 4),
                    Flexible(child: titleTrailing!),
                  ],
                ],
              ),
              SizedBox(height: titleGap),
              Expanded(child: child),
            ],
          ),
        );
      },
    );
  }
}

class _CompactStatLine extends StatelessWidget {
  const _CompactStatLine({
    required this.icon,
    required this.label,
    required this.value,
    required this.isPhone,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isPhone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isPhone ? 6 : 8,
        vertical: isPhone ? 5 : 7,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1A2D),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF168CFF), size: isPhone ? 16 : 20),
          SizedBox(width: isPhone ? 4 : 7),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: const Color(0xFF7F8DA0),
                fontSize: isPhone ? 8 : 10,
              ),
            ),
          ),
          const SizedBox(width: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: isPhone ? 10 : 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.desktop,
    required this.name,
    required this.onRefresh,
    required this.onInfo,
    required this.onAccount,
    required this.onSession,
    required this.hasActiveSession,
  });

  final bool desktop;
  final String name;
  final Future<void> Function() onRefresh;
  final VoidCallback onInfo;
  final VoidCallback onAccount;
  final VoidCallback onSession;
  final bool hasActiveSession;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: desktop ? 88 : 78,
      padding: EdgeInsets.symmetric(horizontal: desktop ? 24 : 16),
      decoration: const BoxDecoration(
        color: Color(0xFF071426),
        border: Border(bottom: BorderSide(color: Color(0xFF18304B))),
      ),
      child: Row(
        children: [
          if (!desktop) ...[
            const Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'RC ',
                    style: TextStyle(
                      color: Color(0xFFFF3D36),
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  TextSpan(
                    text: 'COMPANION',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
          ] else ...[
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Bonjour, $name !',
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Dashboard',
                    style: TextStyle(
                      color: Color(0xFF168BFF),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (desktop) ...[
            FilledButton.icon(
              onPressed: onSession,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Nouvelle session',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(width: 10),
          ],
          IconButton(
            tooltip: 'Actualiser le Dashboard',
            onPressed: () => onRefresh(),
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Informations & Références',
            onPressed: onInfo,
            icon: const Icon(Icons.info_outline_rounded),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Mon compte',
            child: InkWell(
              onTap: onAccount,
              borderRadius: BorderRadius.circular(24),
              child: CircleAvatar(
                backgroundColor: const Color(0xFF185BEA),
                child: Text(
                  name.isEmpty ? 'R' : name[0].toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  const _DesktopSidebar({
    required this.onHome,
    required this.onModels,
    required this.onBatteries,
    required this.onSessions,
    required this.onMaintenance,
    required this.onRadios,
    required this.onInfo,
  });

  final VoidCallback onHome;
  final VoidCallback onModels;
  final VoidCallback onBatteries;
  final VoidCallback onSessions;
  final VoidCallback onMaintenance;
  final VoidCallback onRadios;
  final VoidCallback onInfo;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 248,
      decoration: const BoxDecoration(
        color: Color(0xFF061222),
        border: Border(right: BorderSide(color: Color(0xFF17314D))),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
            child: SizedBox(
              height: 250,
              child: Center(
                child: Transform.scale(
                  scale: 1.18,
                  child: Image.asset(
                    'assets/images/rc_logo_login_hd.png',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
            ),
          ),
          _SideItem(
            icon: Icons.home_rounded,
            label: 'Accueil',
            selected: true,
            onTap: onHome,
          ),
          _SideItem(
            icon: Icons.directions_car_filled_rounded,
            asset: 'assets/images/rc_icon_models_hd.png',
            label: 'Modèles',
            onTap: onModels,
          ),
          _SideItem(
            icon: Icons.battery_charging_full_rounded,
            asset: 'assets/images/rc_icon_batteries_hd.png',
            label: 'Batteries',
            onTap: onBatteries,
          ),
          _SideItem(
            icon: Icons.calendar_month_rounded,
            asset: 'assets/images/rc_icon_sessions_hd.png',
            label: 'Sessions',
            onTap: onSessions,
          ),
          _SideItem(
            icon: Icons.build_rounded,
            asset: 'assets/images/rc_icon_maintenance_hd.png',
            label: 'Maintenance',
            onTap: onMaintenance,
          ),
          _SideItem(
            icon: Icons.settings_remote_rounded,
            asset: 'assets/images/rc_icon_radio_nb4_hd.png',
            label: 'Radios',
            onTap: onRadios,
          ),
          const Spacer(),
          _SideItem(
            icon: Icons.info_outline_rounded,
            label: 'Informations',
            onTap: onInfo,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _SideItem extends StatelessWidget {
  const _SideItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.asset,
  });

  final IconData icon;
  final String? asset;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF092F67) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: selected
            ? const Border(left: BorderSide(color: Color(0xFF168CFF), width: 4))
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          dense: false,
          minTileHeight: 60,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          horizontalTitleGap: 12,
          leading: asset == null
              ? SizedBox(
                  width: 48,
                  height: 48,
                  child: Icon(
                    icon,
                    size: selected ? 34 : 28,
                    color: selected ? const Color(0xFF168CFF) : Colors.white70,
                  ),
                )
              : SizedBox(
                  width: 48,
                  height: 48,
                  child: Image.asset(
                    asset!,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                  ),
                ),
          title: Text(
            label,
            style: TextStyle(
              fontSize: 17,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _MetricCardData {
  const _MetricCardData({
    required this.value,
    required this.label,
    required this.asset,
    required this.color,
    required this.onTap,
    this.showValue = true,
  });

  final int value;
  final String label;
  final String asset;
  final Color color;
  final VoidCallback onTap;
  final bool showValue;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.data, required this.loading});

  final _MetricCardData data;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: data.onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 120,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1A2D),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF23405E)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black38,
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            SizedBox(
              width: 70,
              height: 70,
              child: Image.asset(
                data.asset,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: loading
                  ? const LinearProgressIndicator()
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (data.showValue) ...[
                          Text(
                            '${data.value}',
                            style: TextStyle(
                              color: data.color,
                              fontSize: 29,
                              height: 1,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            data.label,
                            maxLines: 2,
                            textAlign: TextAlign.left,
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardPanel extends StatelessWidget {
  const _DashboardPanel({
    required this.title,
    required this.child,
    this.titleTrailing,
  });

  final String title;
  final Widget child;
  final Widget? titleTrailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF071426),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF23405E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (titleTrailing != null) ...[
                const Text(
                  '—',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
                ),
                titleTrailing!,
              ],
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _StatLine extends StatelessWidget {
  const _StatLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0B1A2D),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF168CFF), size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Color(0xFF7F8DA0)),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final fontSize = compact ? 8.0 : 10.0;
    final dotSize = compact ? 6.0 : 8.0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          width: dotSize,
          height: dotSize,
          decoration: const BoxDecoration(
            color: Color(0xFF168CFF),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          'Temps cumulé',
          style: TextStyle(
            color: const Color(0xFF8DBDFF),
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(width: compact ? 8 : 14),
        Container(
          width: dotSize,
          height: dotSize,
          decoration: const BoxDecoration(
            color: Color(0xFFE28A2B),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          'Packs cumulés',
          style: TextStyle(
            color: const Color(0xFFFFC36D),
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _DashboardChartPainter extends CustomPainter {
  const _DashboardChartPainter({
    required this.minutesValues,
    required this.packValues,
    required this.dateLabels,
    this.compact = false,
  });

  final List<double> minutesValues;
  final List<double> packValues;
  final List<String> dateLabels;
  final bool compact;

  @override
  void paint(Canvas canvas, Size size) {
    final left = compact ? 28.0 : 38.0;
    final right = compact ? 24.0 : 34.0;
    final top = 5.0;
    final bottom = compact ? 18.0 : 22.0;

    final plotWidth = (size.width - left - right).clamp(1.0, double.infinity);
    final plotHeight = (size.height - top - bottom).clamp(1.0, double.infinity);
    final plotRect = Rect.fromLTWH(left, top, plotWidth, plotHeight);

    final grid = Paint()
      ..color = const Color(0xFF18304B)
      ..strokeWidth = 1;

    const horizontalLines = 4;
    const verticalLines = 6;

    for (var i = 0; i <= horizontalLines; i++) {
      final y = plotRect.top + plotRect.height * i / horizontalLines;
      canvas.drawLine(
        Offset(plotRect.left, y),
        Offset(plotRect.right, y),
        grid,
      );
    }

    for (var i = 0; i <= verticalLines; i++) {
      final x = plotRect.left + plotRect.width * i / verticalLines;
      canvas.drawLine(
        Offset(x, plotRect.top),
        Offset(x, plotRect.bottom),
        grid,
      );
    }

    final minuteSeries = minutesValues.isNotEmpty
        ? minutesValues
        : const <double>[0, 0];
    final packSeries = packValues.isNotEmpty
        ? packValues
        : const <double>[0, 0];

    final maxMinutes = minuteSeries.fold<double>(
      1,
      (current, value) => value > current ? value : current,
    );
    final maxPacks = packSeries.fold<double>(
      1,
      (current, value) => value > current ? value : current,
    );

    double xFor(int index, int count) {
      if (count <= 1) return plotRect.left;
      return plotRect.left + plotRect.width * index / (count - 1);
    }

    double yFor(double value, double maxValue) {
      return plotRect.bottom - (value / maxValue) * plotRect.height * .92;
    }

    Path makePath(List<double> values, double maxValue) {
      final path = Path();
      for (var i = 0; i < values.length; i++) {
        final point = Offset(xFor(i, values.length), yFor(values[i], maxValue));
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      return path;
    }

    final minutesPath = makePath(minuteSeries, maxMinutes);
    final packsPath = makePath(packSeries, maxPacks);

    final fillPath = Path.from(minutesPath)
      ..lineTo(plotRect.right, plotRect.bottom)
      ..lineTo(plotRect.left, plotRect.bottom)
      ..close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x33168CFF), Color(0x00168CFF)],
        ).createShader(plotRect)
        ..style = PaintingStyle.fill,
    );

    canvas.drawPath(
      minutesPath,
      Paint()
        ..color = const Color(0xFF168CFF)
        ..strokeWidth = compact ? 2.0 : 2.6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    canvas.drawPath(
      packsPath,
      Paint()
        ..color = const Color(0xFFE28A2B)
        ..strokeWidth = compact ? 1.8 : 2.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final labelStyle = TextStyle(
      color: const Color(0xFF7F8DA0),
      fontSize: compact ? 7.0 : 9.0,
      fontWeight: FontWeight.w600,
    );

    void drawText(
      String text,
      Offset offset, {
      TextAlign align = TextAlign.left,
    }) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: TextDirection.ltr,
        textAlign: align,
      )..layout();

      var dx = offset.dx;
      if (align == TextAlign.center) {
        dx -= painter.width / 2;
      } else if (align == TextAlign.right) {
        dx -= painter.width;
      }

      painter.paint(canvas, Offset(dx, offset.dy));
    }

    String minuteLabel(double minutes) {
      final rounded = minutes.round();
      if (rounded >= 60) {
        final h = rounded ~/ 60;
        final m = rounded % 60;
        return m == 0 ? '${h}h' : '${h}h${m.toString().padLeft(2, '0')}';
      }
      return '${rounded}m';
    }

    // Axe gauche : temps cumulé.
    for (var i = 0; i <= horizontalLines; i++) {
      final ratio = 1 - i / horizontalLines;
      final y = plotRect.top + plotRect.height * i / horizontalLines;
      drawText(
        minuteLabel(maxMinutes * ratio),
        Offset(plotRect.left - 4, y - (compact ? 4 : 5)),
        align: TextAlign.right,
      );
    }

    // Axe droit : packs cumulés.
    for (var i = 0; i <= horizontalLines; i++) {
      final ratio = 1 - i / horizontalLines;
      final y = plotRect.top + plotRect.height * i / horizontalLines;
      drawText(
        '${(maxPacks * ratio).round()}',
        Offset(plotRect.right + 4, y - (compact ? 4 : 5)),
      );
    }

    // Dates : nombre limité automatiquement pour ne jamais chevaucher.
    if (dateLabels.isNotEmpty) {
      final maxLabels = compact ? 3 : 6;
      final count = dateLabels.length;
      final step = count <= maxLabels
          ? 1
          : ((count - 1) / (maxLabels - 1)).ceil();

      final indexes = <int>{0, count - 1};
      for (var i = 0; i < count; i += step) {
        indexes.add(i);
      }

      final sortedIndexes = indexes.toList()..sort();
      for (final i in sortedIndexes) {
        drawText(
          dateLabels[i],
          Offset(xFor(i, count), plotRect.bottom + (compact ? 4 : 6)),
          align: TextAlign.center,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashboardChartPainter oldDelegate) {
    return oldDelegate.minutesValues != minutesValues ||
        oldDelegate.packValues != packValues ||
        oldDelegate.dateLabels != dateLabels ||
        oldDelegate.compact != compact;
  }
}

class _MobileNavigation extends StatelessWidget {
  const _MobileNavigation({
    required this.onHome,
    required this.onModels,
    required this.onBatteries,
    required this.onSessions,
    required this.onRadios,
  });

  final VoidCallback onHome;
  final VoidCallback onModels;
  final VoidCallback onBatteries;
  final VoidCallback onSessions;
  final VoidCallback onRadios;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: 0,
      onDestinationSelected: (index) {
        switch (index) {
          case 0:
            onHome();
          case 1:
            onModels();
          case 2:
            onBatteries();
          case 3:
            onSessions();
          case 4:
            onRadios();
        }
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: 'Accueil',
        ),
        NavigationDestination(
          icon: Icon(Icons.directions_car_outlined),
          selectedIcon: Icon(Icons.directions_car_filled_rounded),
          label: 'Modèles',
        ),
        NavigationDestination(
          icon: Icon(Icons.battery_4_bar_outlined),
          selectedIcon: Icon(Icons.battery_charging_full_rounded),
          label: 'Batteries',
        ),
        NavigationDestination(
          icon: Icon(Icons.calendar_month_outlined),
          selectedIcon: Icon(Icons.calendar_month_rounded),
          label: 'Sessions',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_remote_outlined),
          selectedIcon: Icon(Icons.settings_remote_rounded),
          label: 'Radios',
        ),
      ],
    );
  }
}
