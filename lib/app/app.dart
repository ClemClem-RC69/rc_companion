import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/auth_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../services/battery_sync_service.dart';
import '../services/supabase_service.dart';
import '../services/user_access_service.dart';

class RCColors {
  const RCColors._();

  static const background = Color(0xFF0B1220);
  static const surface = Color(0xFF172033);
  static const surfaceHigh = Color(0xFF1E2B42);
  static const primary = Color(0xFF2563EB);
  static const primaryLight = Color(0xFF3B82F6);
  static const accent = Color(0xFFEF4444);
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFF59E0B);
  static const textPrimary = Color(0xFFF8FAFC);
  static const textSecondary = Color(0xFFCBD5E1);
  static const border = Color(0xFF334155);
}

class RCCompanionApp extends StatelessWidget {
  const RCCompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RC Companion',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: _buildTheme(),
      home: const AuthGate(),
    );
  }

  ThemeData _buildTheme() {
    const colorScheme = ColorScheme.dark(
      primary: RCColors.primary,
      onPrimary: Colors.white,
      secondary: RCColors.primaryLight,
      onSecondary: Colors.white,
      error: RCColors.accent,
      onError: Colors.white,
      surface: RCColors.surface,
      onSurface: RCColors.textPrimary,
      surfaceContainerHighest: RCColors.surfaceHigh,
      onSurfaceVariant: RCColors.textSecondary,
      outline: RCColors.border,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: RCColors.background,
      fontFamily: 'Arial',
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: RCColors.background,
        foregroundColor: RCColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: RCColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: RCColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: Colors.black.withValues(alpha: 0.35),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: RCColors.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: RCColors.background.withValues(alpha: 0.55),
        labelStyle: const TextStyle(color: RCColors.textSecondary),
        hintStyle: TextStyle(
          color: RCColors.textSecondary.withValues(alpha: 0.7),
        ),
        prefixIconColor: RCColors.textSecondary,
        suffixIconColor: RCColors.textSecondary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: RCColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: RCColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: RCColors.primaryLight, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: RCColors.accent),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: RCColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: RCColors.textPrimary,
          minimumSize: const Size(0, 52),
          side: const BorderSide(color: RCColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: RCColors.primaryLight,
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: RCColors.border,
        thickness: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: RCColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: RCColors.border),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: RCColors.surfaceHigh,
        contentTextStyle: const TextStyle(color: RCColors.textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: RCColors.surface,
        indicatorColor: Color(0x332563EB),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(color: RCColors.textPrimary, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

enum _AccessGateState { signedOut, checking, allowed, blocked }

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  late final StreamSubscription<AuthState> authSubscription;
  StreamSubscription<List<ConnectivityResult>>? connectivitySubscription;
  RealtimeChannel? _deviceAccessChannel;
  Timer? _accessRecheckDebounce;

  Session? session;
  _AccessGateState gateState = _AccessGateState.signedOut;
  DeviceAccessResult? accessResult;
  String? accessError;
  bool _handlingAuthEvent = false;
  bool _accessCheckRunning = false;

  @override
  void initState() {
    super.initState();

    session = SupabaseService.client.auth.currentSession;

    if (session == null) {
      gateState = _AccessGateState.signedOut;
    } else {
      gateState = _AccessGateState.checking;
      unawaited(_checkRememberedSession());
    }

    WidgetsBinding.instance.addObserver(this);

    connectivitySubscription = Connectivity().onConnectivityChanged.listen(
      (results) {
        final online = results.any(
          (result) => result != ConnectivityResult.none,
        );
        if (online) {
          _scheduleAccessRecheck();
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Erreur de surveillance réseau : $error');
        debugPrintStack(stackTrace: stackTrace);
      },
    );

    authSubscription = SupabaseService.client.auth.onAuthStateChange.listen(
      _handleAuthStateChange,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Erreur d’authentification Supabase : $error');
        debugPrintStack(stackTrace: stackTrace);
      },
    );

    if (session != null) {
      _startDeviceAccessRealtime();
    }
  }

  Future<void> _handleAuthStateChange(AuthState data) async {
    if (!mounted || _handlingAuthEvent) return;

    _handlingAuthEvent = true;
    try {
      final nextSession = data.session;

      if (nextSession == null) {
        await _stopDeviceAccessRealtime();
        if (!mounted) return;
        setState(() {
          session = null;
          gateState = _AccessGateState.signedOut;
          accessResult = null;
          accessError = null;
        });
        return;
      }

      session = nextSession;
      _startDeviceAccessRealtime();

      // Une connexion volontaire peut prendre la place d’un autre appareil
      // de la même plateforme lorsque le quota du compte est atteint.
      if (data.event == AuthChangeEvent.signedIn) {
        await _activateAfterVoluntarySignIn(nextSession);
        return;
      }

      // Les renouvellements de token / reprises de session ne doivent jamais
      // reprendre automatiquement la place d’un appareil remplacé.
      await _checkExistingAccess(nextSession);
    } finally {
      _handlingAuthEvent = false;
    }
  }

  Future<void> _checkRememberedSession() async {
    final currentSession = session;
    if (currentSession == null) return;

    await _checkExistingAccess(currentSession);
  }

  Future<void> _activateAfterVoluntarySignIn(Session activeSession) async {
    if (!mounted) return;

    setState(() {
      session = activeSession;
      gateState = _AccessGateState.checking;
      accessResult = null;
      accessError = null;
    });

    try {
      final result = await UserAccessService.activateCurrentDevice();

      if (!mounted) return;

      if (result.allowed) {
        setState(() {
          gateState = _AccessGateState.allowed;
          accessResult = result;
          accessError = null;
        });

        unawaited(BatterySyncService.syncNow());
        return;
      }

      setState(() {
        gateState = _AccessGateState.blocked;
        accessResult = result;
        accessError = null;
      });
    } catch (error, stackTrace) {
      debugPrint('Erreur lors de l’activation de l’appareil : $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      // Si la connexion au serveur est momentanément impossible, on ne détruit
      // jamais la session ni les données locales. Le mode hors ligne reste
      // utilisable ; la synchronisation sera protégée ensuite dans les services
      // Realtime / Background.
      setState(() {
        gateState = _AccessGateState.allowed;
        accessResult = null;
        accessError =
            'Impossible de vérifier l’autorisation de cet appareil pour le '
            'moment. RC Companion reste disponible hors ligne.';
      });
    }
  }

  Future<void> _checkExistingAccess(Session activeSession) async {
    if (!mounted) return;

    setState(() {
      session = activeSession;
      gateState = _AccessGateState.checking;
      accessResult = null;
      accessError = null;
    });

    try {
      final result = await UserAccessService.checkCurrentDevice();

      if (!mounted) return;

      if (result.allowed) {
        setState(() {
          gateState = _AccessGateState.allowed;
          accessResult = result;
          accessError = null;
        });

        unawaited(BatterySyncService.syncNow());
        return;
      }

      setState(() {
        gateState = _AccessGateState.blocked;
        accessResult = result;
        accessError = null;
      });
    } catch (error, stackTrace) {
      debugPrint('Erreur lors de la vérification de l’appareil : $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      // Une panne réseau ne doit jamais bloquer l’usage local d’un appareil
      // qui possède déjà une session Supabase mémorisée.
      setState(() {
        gateState = _AccessGateState.allowed;
        accessResult = null;
        accessError =
            'Vérification en ligne indisponible. Les données locales restent '
            'accessibles et seront vérifiées au prochain retour réseau.';
      });
    }
  }

  Future<void> _reactivateCurrentDevice() async {
    final currentSession = session;
    if (currentSession == null) return;

    await _activateAfterVoluntarySignIn(currentSession);
  }

  Future<void> _signOutFromBlockedPage() async {
    try {
      await SupabaseService.client.auth.signOut();
    } catch (error, stackTrace) {
      debugPrint('Erreur lors de la déconnexion : $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    if (!mounted) return;

    setState(() {
      session = null;
      gateState = _AccessGateState.signedOut;
      accessResult = null;
      accessError = null;
    });
  }

  void _startDeviceAccessRealtime() {
    final userId = SupabaseService.client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      return;
    }

    unawaited(_stopDeviceAccessRealtime());

    final channel = SupabaseService.client.channel(
      'device-access-$userId-${DateTime.now().microsecondsSinceEpoch}',
    );

    _deviceAccessChannel = channel;

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'user_devices',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            if (!mounted) return;
            _scheduleAccessRecheck();
          },
        )
        .subscribe((status, error) {
          if (error != null) {
            debugPrint(
              'Erreur Realtime de surveillance des appareils : $error',
            );
          }
        });
  }

  Future<void> _stopDeviceAccessRealtime() async {
    final channel = _deviceAccessChannel;
    _deviceAccessChannel = null;

    if (channel == null) {
      return;
    }

    try {
      await SupabaseService.client.removeChannel(channel);
    } catch (error, stackTrace) {
      debugPrint(
        'Erreur lors de l’arrêt de la surveillance Realtime appareil : $error',
      );
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleAccessRecheck();
    }
  }

  void _scheduleAccessRecheck() {
    _accessRecheckDebounce?.cancel();
    _accessRecheckDebounce = Timer(
      const Duration(milliseconds: 250),
      () => unawaited(_recheckCurrentDevice()),
    );
  }

  Future<void> _recheckCurrentDevice() async {
    if (_accessCheckRunning || _handlingAuthEvent) {
      return;
    }

    final currentSession = SupabaseService.client.auth.currentSession;
    if (currentSession == null) {
      return;
    }

    _accessCheckRunning = true;
    try {
      final result = await UserAccessService.checkCurrentDevice();

      if (!mounted) return;

      session = currentSession;

      if (result.allowed) {
        if (gateState != _AccessGateState.allowed) {
          setState(() {
            gateState = _AccessGateState.allowed;
            accessResult = result;
            accessError = null;
          });
        }
        return;
      }

      setState(() {
        gateState = _AccessGateState.blocked;
        accessResult = result;
        accessError = null;
      });
    } catch (error, stackTrace) {
      debugPrint(
        'Vérification appareil au retour premier plan/réseau impossible : '
        '$error',
      );
      debugPrintStack(stackTrace: stackTrace);

      // Une simple coupure réseau ne doit pas retirer l'accès local.
      // On conserve l'état courant et aucune donnée locale n'est supprimée.
    } finally {
      _accessCheckRunning = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accessRecheckDebounce?.cancel();
    connectivitySubscription?.cancel();
    authSubscription.cancel();
    unawaited(_stopDeviceAccessRealtime());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    switch (gateState) {
      case _AccessGateState.signedOut:
        return const AuthPage();

      case _AccessGateState.checking:
        return const _DeviceAccessCheckingPage();

      case _AccessGateState.allowed:
        return DashboardPage(key: ValueKey(session?.user.id ?? 'dashboard'));

      case _AccessGateState.blocked:
        return _DeviceAccessBlockedPage(
          result: accessResult,
          onReactivate: _reactivateCurrentDevice,
          onSignOut: _signOutFromBlockedPage,
        );
    }
  }
}

class _DeviceAccessCheckingPage extends StatelessWidget {
  const _DeviceAccessCheckingPage();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 18),
              Text(
                'Vérification de cet appareil…',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceAccessBlockedPage extends StatelessWidget {
  const _DeviceAccessBlockedPage({
    required this.result,
    required this.onReactivate,
    required this.onSignOut,
  });

  final DeviceAccessResult? result;
  final Future<void> Function() onReactivate;
  final Future<void> Function() onSignOut;

  String _platformLabel(String platform) {
    switch (platform) {
      case 'android':
        return 'Android';
      case 'windows':
        return 'Windows';
      case 'macos':
        return 'macOS';
      case 'ios':
        return 'iPhone / iPad';
      default:
        return 'cette plateforme';
    }
  }

  @override
  Widget build(BuildContext context) {
    final reason = result?.reason ?? 'unknown';
    final platform = result?.payload['platform']?.toString() ?? '';
    final maxActive = result?.maxActive;
    final serverMessage = result?.message;

    String title = 'Cet appareil n’est pas autorisé';
    String message =
        'RC Companion ne peut pas utiliser les services en ligne avec cet '
        'appareil pour le moment.';

    if (reason == 'device_replaced') {
      title = 'Connexion utilisée sur un autre appareil';
      message =
          'Un autre appareil ${_platformLabel(platform)} utilise actuellement '
          'la connexion autorisée pour ce compte.';
    } else if (reason == 'platform_not_allowed') {
      title = 'Plateforme non autorisée';
      message =
          'Ce compte ne possède actuellement aucune autorisation pour '
          '${_platformLabel(platform)}.';
    } else if (reason == 'user_not_authorized') {
      title = 'Compte non autorisé';
      message =
          'Ce compte n’est plus autorisé à utiliser RC Companion. '
          'Contactez l’administrateur.';
    }

    if (maxActive != null && maxActive > 0) {
      message =
          '$message\n\nNombre de connexions simultanées autorisées sur cette '
          'plateforme : $maxActive.';
    }

    if (serverMessage != null && serverMessage.isNotEmpty) {
      message = '$message\n\n$serverMessage';
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.devices_other_rounded,
                        size: 54,
                        color: RCColors.warning,
                      ),
                      const SizedBox(height: 18),
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: RCColors.textSecondary,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Les données déjà enregistrées hors ligne sur cet '
                        'appareil restent conservées localement. Elles ne sont '
                        'pas supprimées.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: onReactivate,
                          icon: const Icon(Icons.swap_horiz_rounded),
                          label: const Text('Utiliser cet appareil à la place'),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Cette action peut remplacer un autre appareil actif '
                        'de la même plateforme lorsque la limite est atteinte.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: RCColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextButton(
                        onPressed: onSignOut,
                        child: const Text('Se déconnecter'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
