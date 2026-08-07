import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';

import 'app/app.dart';
import 'database/app_database.dart';
import 'services/background_sync_service.dart';
import 'services/battery_sync_service.dart';
import 'services/realtime_sync_service.dart';
import 'services/supabase_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    DartPluginRegistrant.ensureInitialized();
    return BackgroundSyncService.executeTask(taskName);
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await AppDatabase.initialize();
    await SupabaseService.initialize();
    await BatterySyncService.initialize();

    runApp(const RCCompanionApp());

    // Le Realtime ne doit jamais bloquer l'affichage initial.
    unawaited(RealtimeSyncService.initialize());

    // Enregistre les tâches persistantes Android / iOS après l'affichage.
    unawaited(() async {
      await Workmanager().initialize(callbackDispatcher);
      await BackgroundSyncService.schedule();
    }());
  } catch (error, stackTrace) {
    debugPrint('Erreur de démarrage RC Companion: $error');
    debugPrintStack(stackTrace: stackTrace);

    runApp(_StartupErrorApp(error: error));
  }
}

class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 64),
                  const SizedBox(height: 18),
                  const Text(
                    'RC Companion ne peut pas démarrer.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Vérifie la configuration Supabase et la connexion réseau.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  SelectableText(error.toString(), textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
