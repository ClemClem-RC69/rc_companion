import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// Opérations locales restant à envoyer vers Supabase.
///
/// Une ligne représente une action complète et rejouable : création,
/// modification ou suppression d'une entité.
class SyncQueueEntries extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get userId => text()();

  /// Type fonctionnel : battery, battery_measurement, session, model, etc.
  TextColumn get entityType => text()();

  /// Identifiant stable de l'entité concernée.
  TextColumn get entityId => text()();

  /// create, update ou delete.
  TextColumn get operation => text()();

  /// Données JSON nécessaires pour rejouer l'opération.
  TextColumn get payloadJson => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get nextAttemptAt => dateTime().nullable()();

  IntColumn get attemptCount => integer().withDefault(const Constant(0))();

  TextColumn get lastError => text().nullable()();

  BoolColumn get isProcessing => boolean().withDefault(const Constant(false))();
}

/// État de synchronisation propre à chaque utilisateur connecté.
class LocalSyncStates extends Table {
  TextColumn get userId => text()();

  DateTimeColumn get lastSuccessfulPullAt => dateTime().nullable()();

  DateTimeColumn get lastSuccessfulPushAt => dateTime().nullable()();

  DateTimeColumn get lastAttemptAt => dateTime().nullable()();

  TextColumn get lastError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId};
}

@DriftDatabase(tables: [SyncQueueEntries, LocalSyncStates])
final class AppDatabase extends _$AppDatabase {
  AppDatabase._()
    : super(
        driftDatabase(
          name: 'rc_companion',
          native: const DriftNativeOptions(shareAcrossIsolates: true),
        ),
      );

  static final AppDatabase instance = AppDatabase._();

  /// Ouvre réellement le fichier SQLite afin de détecter immédiatement
  /// une éventuelle erreur d'initialisation.
  static Future<void> initialize() async {
    await instance.customSelect('SELECT 1').get();
  }

  @override
  int get schemaVersion => 1;

  Future<int> enqueueSyncOperation({
    required String userId,
    required String entityType,
    required String entityId,
    required String operation,
    String? payloadJson,
  }) {
    return into(syncQueueEntries).insert(
      SyncQueueEntriesCompanion.insert(
        userId: userId,
        entityType: entityType,
        entityId: entityId,
        operation: operation,
        payloadJson: Value(payloadJson),
      ),
    );
  }

  Future<List<SyncQueueEntry>> getPendingSyncOperations({int limit = 100}) {
    return (select(syncQueueEntries)
          ..where((row) => row.isProcessing.equals(false))
          ..orderBy([(row) => OrderingTerm.asc(row.createdAt)])
          ..limit(limit))
        .get();
  }

  Future<void> deleteSyncOperation(int id) async {
    await (delete(syncQueueEntries)..where((row) => row.id.equals(id))).go();
  }

  Future<void> markSyncOperationFailed({
    required int id,
    required Object error,
    required DateTime nextAttemptAt,
  }) async {
    final current = await (select(
      syncQueueEntries,
    )..where((row) => row.id.equals(id))).getSingleOrNull();

    if (current == null) {
      return;
    }

    await (update(syncQueueEntries)..where((row) => row.id.equals(id))).write(
      SyncQueueEntriesCompanion(
        isProcessing: const Value(false),
        attemptCount: Value(current.attemptCount + 1),
        nextAttemptAt: Value(nextAttemptAt),
        lastError: Value(error.toString()),
      ),
    );
  }

  Future<void> setSyncOperationProcessing({
    required int id,
    required bool value,
  }) async {
    await (update(syncQueueEntries)..where((row) => row.id.equals(id))).write(
      SyncQueueEntriesCompanion(
        isProcessing: Value(value),
        lastError: value ? const Value(null) : const Value.absent(),
      ),
    );
  }
}
