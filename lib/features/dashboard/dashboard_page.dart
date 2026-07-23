import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../pages/radios_page.dart';
import '../../models/battery.dart';
import '../../services/battery_local_store.dart';
import '../../services/battery_service.dart';
import '../batteries/batteries_page.dart';
import '../info/info_page.dart';
import '../maintenance/maintenance_page.dart';
import '../models/models_page.dart';
import '../sessions/sessions_page.dart';

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
  Map<String, dynamic>? lastSession;
  String lastModelCategory = 'Voiture';
  int totalRunMinutes = 0;
  int totalPacks = 0;
  List<double> chartValues = const <double>[];

  StreamSubscription<List<Battery>>? _batterySubscription;
  StreamSubscription? _measurementSubscription;
  Timer? _batteryRefreshDebounce;
  Timer? _dashboardRefreshDebounce;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  RealtimeChannel? _dashboardRealtimeChannel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startBatteryLiveUpdates();
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

  void _scheduleBatteryMetricsRefresh() {
    _batteryRefreshDebounce?.cancel();
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
    _connectivitySubscription?.cancel();

    final channel = _dashboardRealtimeChannel;
    if (channel != null) {
      Supabase.instance.client.removeChannel(channel);
    }

    super.dispose();
  }

  Future<void> _loadDashboard() async {
    try {
      final localBatteries = await BatteryService.getCachedBatteries();

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

      final connectivity = await Connectivity().checkConnectivity();
      final isOffline =
          connectivity.isEmpty ||
          connectivity.every((result) => result == ConnectivityResult.none);

      if (isOffline) {
        return;
      }

      // Supabase alimente uniquement le cache local. Le Dashboard reste basé
      // sur Drift et se met à jour via les streams ci-dessus.
      try {
        await BatteryService.getBatteries();
      } catch (_) {}

      final client = Supabase.instance.client;

      final results = await Future.wait<int>([
        _countRows(client, 'rc_models'),
        _countRows(client, 'rc_sessions'),
        _countRows(client, 'maintenance_records'),
      ]).timeout(const Duration(seconds: 4));

      Map<String, dynamic>? recent;
      String category = 'Voiture';
      int runMinutes = 0;
      int packs = 0;
      final valuesByDay = <DateTime, int>{};

      try {
        final sessions = await client
            .from('rc_sessions')
            .select(
              'id, model_id, model_name, started_at, ended_at, location, breakages',
            )
            .order('started_at', ascending: false)
            .limit(30);

        if (sessions.isNotEmpty) {
          recent = Map<String, dynamic>.from(sessions.first);

          final modelId = recent['model_id']?.toString();
          if (modelId != null && modelId.isNotEmpty) {
            final models = await client
                .from('rc_models')
                .select('category')
                .eq('id', modelId)
                .limit(1);
            if (models.isNotEmpty) {
              category =
                  models.first['category']?.toString().trim() ?? 'Voiture';
            }
          }

          final sessionIds = sessions
              .map((row) => row['id']?.toString())
              .whereType<String>()
              .where((id) => id.isNotEmpty)
              .toList();

          if (sessionIds.isNotEmpty) {
            final runs = await client
                .from('session_runs')
                .select('session_id, started_at, duration_minutes')
                .inFilter('session_id', sessionIds);

            for (final raw in runs) {
              final row = Map<String, dynamic>.from(raw);
              final duration =
                  int.tryParse('${row['duration_minutes'] ?? 0}') ?? 0;
              runMinutes += duration;
              packs += 1;

              final startedAt = DateTime.tryParse(
                '${row['started_at'] ?? ''}',
              )?.toLocal();
              if (startedAt != null) {
                final day = DateTime(
                  startedAt.year,
                  startedAt.month,
                  startedAt.day,
                );
                valuesByDay.update(
                  day,
                  (value) => value + duration,
                  ifAbsent: () => duration,
                );
              }
            }

            final recentId = recent['id']?.toString();
            if (recentId != null) {
              final recentRuns = await client
                  .from('session_runs')
                  .select('duration_minutes')
                  .eq('session_id', recentId);
              recent['dashboard_duration_minutes'] = recentRuns.fold<int>(
                0,
                (sum, row) =>
                    sum +
                    (int.tryParse('${row['duration_minutes'] ?? 0}') ?? 0),
              );
            }
          }
        }
      } catch (_) {}

      final sortedDays = valuesByDay.keys.toList()..sort();
      var cumulativeMinutes = 0.0;
      final chart = <double>[];
      for (final day in sortedDays) {
        cumulativeMinutes += valuesByDay[day]!.toDouble();
        chart.add(cumulativeMinutes);
      }

      if (!mounted) return;
      setState(() {
        modelCount = results[0];
        sessionCount = results[1];
        maintenanceCount = results[2];
        lastSession = recent;
        lastModelCategory = category;
        totalRunMinutes = runMinutes;
        totalPacks = packs;
        chartValues = chart;
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

  Future<int> _countRows(SupabaseClient client, String table) async {
    try {
      final rows = await client.from(table).select('id');
      return rows.length;
    } catch (_) {
      return 0;
    }
  }

  void _open(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    ).then((_) => _loadDashboard());
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
        final desktop = constraints.maxWidth >= 860;
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
                        onSessions: () => _open(const SessionsPage()),
                        onMaintenance: () => _open(const MaintenancePage()),
                        onRadios: () => _open(const RadiosPage()),
                        onInfo: () => _open(const InfoPage()),
                      ),
                      Expanded(child: _dashboardContent(desktop: true)),
                    ],
                  )
                : _dashboardContent(desktop: false),
          ),
          bottomNavigationBar: desktop
              ? null
              : _MobileNavigation(
                  onHome: () {},
                  onModels: () => _open(const ModelsPage()),
                  onBatteries: () => _open(const BatteriesPage()),
                  onSessions: () => _open(const SessionsPage()),
                  onMore: _showMoreMenu,
                ),
        );
      },
    );
  }

  Widget _dashboardContent({required bool desktop}) {
    final email = Supabase.instance.client.auth.currentUser?.email;
    final name = _displayName(email);

    return RefreshIndicator(
      onRefresh: _loadDashboard,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _TopBar(
              desktop: desktop,
              name: name,
              onInfo: () => _open(const InfoPage()),
              onLogout: _logout,
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
        onTap: () => _open(const ModelsPage()),
      ),
      _MetricCardData(
        value: batteryCount,
        label: 'BATTERIES',
        asset: 'assets/images/rc_icon_batteries_hd.png',
        color: const Color(0xFFFF3D36),
        onTap: () => _open(const BatteriesPage()),
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
        label: 'MAINTENANCES',
        asset: 'assets/images/rc_icon_maintenance_hd.png',
        color: const Color(0xFFD9DEE8),
        onTap: () => _open(const MaintenancePage()),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = desktop ? 4 : 1;
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
              child: Transform.scale(
                scale: 1.65,
                child: Image.asset(
                  _categoryAsset(lastModelCategory),
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
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
                  OutlinedButton(
                    onPressed: () => _open(const BatteriesPage()),
                    child: const Text(
                      'Voir mes batteries',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.visible,
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
                icon: Icons.rocket_launch_outlined,
                label: 'Nombre de packs utilisés',
                value: '$totalPacks',
              ),
            ],
          );

          final chart = SizedBox(
            height: 150,
            child: CustomPaint(
              painter: _DashboardChartPainter(chartValues),
              child: const SizedBox.expand(),
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
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Se déconnecter'),
              onTap: () {
                Navigator.pop(sheetContext);
                _logout();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.desktop,
    required this.name,
    required this.onInfo,
    required this.onLogout,
  });

  final bool desktop;
  final String name;
  final VoidCallback onInfo;
  final VoidCallback onLogout;

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
                    'Voici un résumé de votre activité.',
                    style: TextStyle(color: Color(0xFF7F8DA0)),
                  ),
                ],
              ),
            ),
          ],
          IconButton(
            onPressed: onInfo,
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          if (desktop) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: const Color(0xFF185BEA),
              child: Text(
                name.isEmpty ? 'R' : name[0].toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              onPressed: onLogout,
              icon: const Icon(Icons.logout_rounded),
            ),
          ],
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
  });

  final int value;
  final String label;
  final String asset;
  final Color color;
  final VoidCallback onTap;
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
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            data.label,
                            maxLines: 1,
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
  const _DashboardPanel({required this.title, required this.child});

  final String title;
  final Widget child;

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
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900),
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

class _DashboardChartPainter extends CustomPainter {
  const _DashboardChartPainter(this.values);

  final List<double> values;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFF18304B)
      ..strokeWidth = 1;

    for (var i = 0; i <= 5; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (var i = 0; i <= 6; i++) {
      final x = size.width * i / 6;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }

    final usableValues = values.length >= 2
        ? values
        : const <double>[0, 0, 0, 0, 0, 0, 0];
    final maxValue = usableValues.fold<double>(
      1,
      (current, value) => value > current ? value : current,
    );

    final path = Path();
    for (var i = 0; i < usableValues.length; i++) {
      final x = usableValues.length == 1
          ? 0.0
          : size.width * i / (usableValues.length - 1);
      final y =
          size.height -
          (usableValues[i] / maxValue * (size.height * .88)) -
          size.height * .05;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x553B82F6), Color(0x00168CFF)],
        ).createShader(Offset.zero & size)
        ..style = PaintingStyle.fill,
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF168CFF)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _DashboardChartPainter oldDelegate) {
    return oldDelegate.values != values;
  }
}

class _MobileNavigation extends StatelessWidget {
  const _MobileNavigation({
    required this.onHome,
    required this.onModels,
    required this.onBatteries,
    required this.onSessions,
    required this.onMore,
  });

  final VoidCallback onHome;
  final VoidCallback onModels;
  final VoidCallback onBatteries;
  final VoidCallback onSessions;
  final VoidCallback onMore;

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
            onMore();
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
          icon: Icon(Icons.more_horiz_rounded),
          label: 'Plus',
        ),
      ],
    );
  }
}
