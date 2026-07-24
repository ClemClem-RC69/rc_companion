import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

class LocalBatteries extends Table {
  TextColumn get localKey => text()();
  TextColumn get userId => text()();
  TextColumn get batteryCode => text()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get cachedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {localKey};
}

class LocalBatteryMeasurements extends Table {
  TextColumn get localKey => text()();
  TextColumn get userId => text()();
  IntColumn get remoteId => integer().nullable()();
  TextColumn get batteryCode => text()();
  TextColumn get measurementType => text()();
  DateTimeColumn get measuredAt => dateTime()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get cachedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {localKey};
}

class LocalModels extends Table {
  TextColumn get localKey => text()();
  TextColumn get userId => text()();
  TextColumn get modelId => text()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get createdAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get cachedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {localKey};
}

class LocalSessions extends Table {
  TextColumn get localKey => text()();
  TextColumn get userId => text()();
  TextColumn get sessionId => text()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get cachedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {localKey};
}

class LocalModelSetups extends Table {
  TextColumn get localKey => text()();
  TextColumn get userId => text()();
  TextColumn get modelId => text()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get updatedAt => dateTime().nullable()();
  DateTimeColumn get cachedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {localKey};
}

class SyncQueueEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get userId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()();
  TextColumn get payloadJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  BoolColumn get isProcessing => boolean().withDefault(const Constant(false))();
}

class LocalSyncStates extends Table {
  TextColumn get userId => text()();
  DateTimeColumn get lastSuccessfulPullAt => dateTime().nullable()();
  DateTimeColumn get lastSuccessfulPushAt => dateTime().nullable()();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {userId};
}

@DriftDatabase(
  tables: [
    LocalBatteries,
    LocalBatteryMeasurements,
    LocalSessions,
    LocalModels,
    LocalModelSetups,
    SyncQueueEntries,
    LocalSyncStates,
  ],
)
final class AppDatabase extends _$AppDatabase {
  AppDatabase._()
    : super(
        driftDatabase(
          name: 'rc_companion',
          native: const DriftNativeOptions(shareAcrossIsolates: true),
        ),
      );

  static final AppDatabase instance = AppDatabase._();

  static Future<void> initialize() async {
    await instance.customSelect('SELECT 1').get();
  }

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (migrator) async {
        await migrator.createAll();
      },
      onUpgrade: (migrator, from, to) async {
        if (from < 2) {
          await migrator.createTable(localBatteries);
          await migrator.createTable(localBatteryMeasurements);
        }
        if (from < 3) {
          await migrator.createTable(localSessions);
        }
        if (from < 4) {
          await migrator.createTable(localModels);
        }
        if (from < 5) {
          await migrator.createTable(localModelSetups);
        }
      },
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<Set<String>> getPendingEntityIds({
    required String userId,
    required String entityType,
  }) async {
    final rows =
        await (select(syncQueueEntries)..where(
              (row) =>
                  row.userId.equals(userId) & row.entityType.equals(entityType),
            ))
            .get();

    return rows.map((row) => row.entityId).toSet();
  }

  Future<int> replacePendingSyncOperation({
    required String userId,
    required String entityType,
    required String entityId,
    required String operation,
    String? payloadJson,
  }) async {
    return transaction(() async {
      await (delete(syncQueueEntries)..where(
            (row) =>
                row.userId.equals(userId) &
                row.entityType.equals(entityType) &
                row.entityId.equals(entityId),
          ))
          .go();

      return enqueueSyncOperation(
        userId: userId,
        entityType: entityType,
        entityId: entityId,
        operation: operation,
        payloadJson: payloadJson,
      );
    });
  }

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
    final now = DateTime.now();

    return (select(syncQueueEntries)
          ..where(
            (row) =>
                row.isProcessing.equals(false) &
                (row.nextAttemptAt.isNull() |
                    row.nextAttemptAt.isSmallerOrEqualValue(now)),
          )
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
