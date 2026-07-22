import 'package:flutter/material.dart';

import 'app/app.dart';
import 'database/app_database.dart';
import 'services/battery_sync_service.dart';
import 'services/supabase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppDatabase.initialize();
  await SupabaseService.initialize();
  await BatterySyncService.initialize();

  runApp(const RCCompanionApp());
}
