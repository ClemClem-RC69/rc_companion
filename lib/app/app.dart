import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/auth_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../services/supabase_service.dart';

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
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
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

class _AuthGateState extends State<AuthGate> {
  late final StreamSubscription<AuthState> authSubscription;
  Session? session;

  @override
  void initState() {
    super.initState();
    session = SupabaseService.client.auth.currentSession;

    authSubscription = SupabaseService.client.auth.onAuthStateChange.listen(
      (data) {
        if (!mounted) return;
        setState(() => session = data.session);
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
    return session == null ? const AuthPage() : const DashboardPage();
  }
}
