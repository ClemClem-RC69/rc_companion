import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../database/app_database.dart';
import 'battery_service.dart';
import 'battery_sync_service.dart';
import 'maintenance_service.dart';
import 'model_document_service.dart';
import 'model_local_store.dart';
import 'model_radio_setup_service.dart';
import 'model_setup_service.dart';
import 'model_service.dart';
import 'radio_service.dart';
import 'session_local_store.dart';
import 'supabase_service.dart';

class BackgroundSyncService {
  BackgroundSyncService._();

  static const String periodicTaskName =
      'com.clementg.rccompanion.background.sync';
  static const String recoveryTaskName =
      'com.clementg.rccompanion.background.recovery';

  static const Duration periodicFrequency = Duration(minutes: 15);

  static bool get _isSupported => Platform.isAndroid || Platform.isIOS;

  static Future<void> schedule() async {
    if (!_isSupported) {
      return;
    }

    final constraints = Constraints(networkType: NetworkType.connected);

    await Workmanager().registerPeriodicTask(
      periodicTaskName,
      periodicTaskName,
      frequency: periodicFrequency,
      constraints: constraints,
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      tag: 'rc-companion-background-sync',
    );

    if (Platform.isAndroid) {
      await Workmanager().registerOneOffTask(
        recoveryTaskName,
        recoveryTaskName,
        constraints: constraints,
        existingWorkPolicy: ExistingWorkPolicy.update,
        tag: 'rc-companion-network-recovery',
      );
    } else if (Platform.isIOS) {
      try {
        await Workmanager().registerProcessingTask(
          recoveryTaskName,
          recoveryTaskName,
          constraints: constraints,
        );
      } catch (_) {
        // Une tâche identique peut déjà être en attente.
      }
    }
  }

  static Future<bool> executeTask(String taskName) async {
    if (!_isSupported) {
      return true;
    }

    WidgetsFlutterBinding.ensureInitialized();

    try {
      await AppDatabase.initialize();
      await SupabaseService.initialize();

      final user = SupabaseService.client.auth.currentUser;
      if (user == null) {
        return true;
      }

      await AppDatabase.instance.releasePendingSyncOperations(userId: user.id);

      // PUSH avant PULL : protège toujours les saisies terrain.
      await BatterySyncService.syncNow();

      await _pullEverything(user.id);

      return true;
    } catch (error, stackTrace) {
      debugPrint('BackgroundSyncService: échec: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  static Future<void> _pullEverything(String userId) async {
    // Modèles d'abord : documents et setups en dépendent.
    await ModelService.refreshModels();

    await Future.wait<void>([
      BatteryService.refreshBatteries().then((_) {}),
      _refreshSessionsFromCloud(userId),
      MaintenanceService.refreshFromCloud(),
      _refreshRadiosAndManuals(),
    ]);

    final models = await ModelLocalStore.getModels(userId: userId);
    final radioSetupService = ModelRadioSetupService();

    for (final model in models) {
      final modelId = model.id?.trim();
      if (modelId == null || modelId.isEmpty) {
        continue;
      }

      await Future.wait<void>([
        ModelSetupService.refreshSetup(modelId).then((_) {}),
        radioSetupService.refreshSetup(modelId: modelId).then((_) {}),
        _refreshDocumentsAndFiles(modelId),
      ]);
    }
  }

  static Future<void> _refreshSessionsFromCloud(String userId) async {
    final response = await SupabaseService.client
        .from('rc_sessions')
        .select('''
          *,
          session_runs (
            *,
            session_run_batteries (
              battery_code,
              created_at
            ),
            session_run_measurements (
              battery_code,
              measured_at,
              remaining_capacity_percent,
              temperature_celsius,
              cell_voltages,
              cell_resistances
            )
          )
        ''')
        .eq('user_id', userId)
        .order('started_at', ascending: false)
        .timeout(const Duration(seconds: 12));

    final rows = response
        .map<Map<String, dynamic>>((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);

    await SessionLocalStore.replaceSessions(userId: userId, rows: rows);
  }

  static Future<void> _refreshDocumentsAndFiles(String modelId) async {
    final documents = await ModelDocumentService.refreshDocuments(modelId);

    await Future.wait(
      documents.map((document) async {
        try {
          await ModelDocumentService.openDocument(document);
        } catch (_) {
          // Retenté automatiquement au prochain passage.
        }
      }),
    );
  }

  static Future<void> _refreshRadiosAndManuals() async {
    final service = RadioService();
    final radios = await service.refreshRadios();

    await Future.wait(
      radios.map((radio) async {
        final storagePath = radio.manualStoragePath?.trim() ?? '';
        final manualName = radio.manualName?.trim() ?? '';

        if (storagePath.isEmpty || manualName.isEmpty) {
          return;
        }

        try {
          await service.getManualLocalPath(radio);
        } catch (_) {
          // Retenté automatiquement au prochain passage.
        }
      }),
    );
  }
}
