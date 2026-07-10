import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/auth_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../services/supabase_service.dart';

class RCCompanionApp extends StatelessWidget {
  const RCCompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RC Companion',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.red,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.red,
        brightness: Brightness.dark,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final StreamSubscription<AuthState> authSubscription;
  Session? session;

  @override
  void initState() {
    super.initState();

    session = SupabaseService.client.auth.currentSession;

    authSubscription =
        SupabaseService.client.auth.onAuthStateChange.listen(
      (data) {
        if (!mounted) return;

        setState(() {
          session = data.session;
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Erreur d’authentification Supabase : $error');
      },
    );
  }

  @override
  void dispose() {
    authSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (session == null) {
      return const AuthPage();
    }

    return const DashboardPage();
  }
}