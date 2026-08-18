import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../models/rc_session.dart';
import 'supabase_service.dart';

enum ModelOperationalState { ready, maintenance, unavailable }

class ModelOperationalStatus {
  const ModelOperationalStatus({
    required this.state,
    this.repairDescriptions = const <String>[],
    this.maintenanceDescriptions = const <String>[],
  });

  static const ready = ModelOperationalStatus(
    state: ModelOperationalState.ready,
  );

  final ModelOperationalState state;
  final List<String> repairDescriptions;
  final List<String> maintenanceDescriptions;

  bool get isReady => state == ModelOperationalState.ready;
  bool get hasMaintenance => state == ModelOperationalState.maintenance;
  bool get isUnavailable => state == ModelOperationalState.unavailable;

  String get label {
    switch (state) {
      case ModelOperationalState.ready:
        return 'Prêt à rouler';
      case ModelOperationalState.maintenance:
        return 'Maintenance';
      case ModelOperationalState.unavailable:
        return 'Indisponible';
    }
  }

  String get symbol {
    switch (state) {
      case ModelOperationalState.ready:
        return '🟢';
      case ModelOperationalState.maintenance:
        return '🟠';
      case ModelOperationalState.unavailable:
        return '🔴';
    }
  }

  List<String> get allDescriptions => <String>[
    ...repairDescriptions,
    ...maintenanceDescriptions,
  ];
}

class ModelOperationalEventService {
  ModelOperationalEventService._();

  static const String repairType = 'repair';
  static const String maintenanceType = 'maintenance';

  static final AppDatabase _database = AppDatabase.instance;

  static String _eventId({
    required String sessionId,
    required String eventType,
  }) {
    return '$sessionId::$eventType';
  }

  static String _localKey({required String userId, required String eventId}) {
    return '$userId::$eventId';
  }

  static Future<void> synchronizeSession(RcSession session) async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
      return;
    }

    final sessionId = session.id?.trim();
    final modelId = session.model.id?.trim();

    if (sessionId == null ||
        sessionId.isEmpty ||
        modelId == null ||
        modelId.isEmpty) {
      return;
    }

    if (!session.isClosed || session.isHistorical) {
      await removeOpenEventsForSession(userId: user.id, sessionId: sessionId);
      return;
    }

    await _synchronizeEvent(
      userId: user.id,
      sessionId: sessionId,
      modelId: modelId,
      eventType: repairType,
      description: session.breakages.trim(),
    );

    await _synchronizeEvent(
      userId: user.id,
      sessionId: sessionId,
      modelId: modelId,
      eventType: maintenanceType,
      description: session.maintenanceToDo.trim(),
    );
  }

  static Future<void> _synchronizeEvent({
    required String userId,
    required String sessionId,
    required String modelId,
    required String eventType,
    required String description,
  }) async {
    final eventId = _eventId(sessionId: sessionId, eventType: eventType);
    final localKey = _localKey(userId: userId, eventId: eventId);

    final existing =
        await (_database.select(_database.localModelOperationalEvents)
              ..where((row) => row.localKey.equals(localKey))
              ..limit(1))
            .getSingleOrNull();

    // Une résolution validée par une maintenance devient une trace figée :
    // les modifications ultérieures de la session source ne la réécrivent pas.
    if (existing?.resolvedAt != null) {
      return;
    }

    if (description.isEmpty) {
      if (existing != null) {
        await (_database.delete(
          _database.localModelOperationalEvents,
        )..where((row) => row.localKey.equals(localKey))).go();
      }
      return;
    }

    final resolutionMaintenanceId = await _resolutionMaintenanceIdForEvent(
      userId: userId,
      eventId: eventId,
    );
    final now = DateTime.now();

    await _database
        .into(_database.localModelOperationalEvents)
        .insert(
          LocalModelOperationalEventsCompanion.insert(
            localKey: localKey,
            userId: userId,
            eventId: eventId,
            modelId: modelId,
            sourceSessionId: sessionId,
            eventType: eventType,
            description: description,
            createdAt: existing?.createdAt ?? now,
            resolvedAt: Value(resolutionMaintenanceId == null ? null : now),
            resolutionMaintenanceId: Value(resolutionMaintenanceId),
          ),
          mode: InsertMode.insertOrReplace,
        );
  }

  static Future<String?> _resolutionMaintenanceIdForEvent({
    required String userId,
    required String eventId,
  }) async {
    final rows =
        await (_database.select(_database.localMaintenanceRecords)..where(
              (row) => row.userId.equals(userId) & row.isDeleted.equals(false),
            ))
            .get();

    for (final row in rows) {
      try {
        final payload = Map<String, dynamic>.from(
          jsonDecode(row.payloadJson) as Map,
        );
        final rawData = payload['data'];
        if (rawData is! Map) {
          continue;
        }

        final data = Map<String, dynamic>.from(rawData);
        final rawIds = data['resolvedOperationalEventIds'];
        if (rawIds is! List) {
          continue;
        }

        final resolvesEvent = rawIds.any(
          (rawId) => rawId?.toString().trim() == eventId,
        );
        if (resolvesEvent) {
          return row.maintenanceId;
        }
      } catch (_) {
        // Une ancienne maintenance sans métadonnée de résolution est ignorée.
      }
    }

    return null;
  }

  static Future<void> removeOpenEventsForSession({
    required String userId,
    required String sessionId,
  }) async {
    await (_database.delete(_database.localModelOperationalEvents)..where(
          (row) =>
              row.userId.equals(userId) &
              row.sourceSessionId.equals(sessionId) &
              row.resolvedAt.isNull(),
        ))
        .go();
  }

  static Future<void> removeAllEventsForSession({
    required String userId,
    required String sessionId,
  }) async {
    await (_database.delete(_database.localModelOperationalEvents)..where(
          (row) =>
              row.userId.equals(userId) & row.sourceSessionId.equals(sessionId),
        ))
        .go();
  }

  static Future<void> resolveEvents({
    required Iterable<String> eventIds,
    required String maintenanceId,
  }) async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
      return;
    }

    final ids = eventIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (ids.isEmpty) {
      return;
    }

    final now = DateTime.now();

    await (_database.update(_database.localModelOperationalEvents)..where(
          (row) =>
              row.userId.equals(user.id) &
              row.eventId.isIn(ids) &
              row.resolvedAt.isNull(),
        ))
        .write(
          LocalModelOperationalEventsCompanion(
            resolvedAt: Value(now),
            resolutionMaintenanceId: Value(maintenanceId),
          ),
        );
  }

  static Future<void> reopenEventsResolvedByMaintenance(
    String maintenanceId,
  ) async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null || maintenanceId.trim().isEmpty) {
      return;
    }

    await (_database.update(_database.localModelOperationalEvents)..where(
          (row) =>
              row.userId.equals(user.id) &
              row.resolutionMaintenanceId.equals(maintenanceId),
        ))
        .write(
          const LocalModelOperationalEventsCompanion(
            resolvedAt: Value(null),
            resolutionMaintenanceId: Value(null),
          ),
        );
  }

  static Future<void> rebuildFromLocalSessions({required String userId}) async {
    final sessionRows =
        await (_database.select(_database.localSessions)..where(
              (row) => row.userId.equals(userId) & row.isDeleted.equals(false),
            ))
            .get();

    await (_database.delete(
      _database.localModelOperationalEvents,
    )..where((row) => row.userId.equals(userId))).go();

    for (final localSession in sessionRows) {
      try {
        final session = Map<String, dynamic>.from(
          jsonDecode(localSession.payloadJson) as Map,
        );

        final sessionId = session['id']?.toString().trim() ?? '';
        final modelId = session['model_id']?.toString().trim() ?? '';
        final isClosed =
            session['ended_at'] != null &&
            session['ended_at'].toString().trim().isNotEmpty;
        final isHistorical =
            session['is_historical'] == true ||
            session['_local_is_historical'] == true;

        if (sessionId.isEmpty || modelId.isEmpty || !isClosed || isHistorical) {
          continue;
        }

        await _synchronizeEvent(
          userId: userId,
          sessionId: sessionId,
          modelId: modelId,
          eventType: repairType,
          description: session['breakages']?.toString().trim() ?? '',
        );

        await _synchronizeEvent(
          userId: userId,
          sessionId: sessionId,
          modelId: modelId,
          eventType: maintenanceType,
          description: session['maintenance_to_do']?.toString().trim() ?? '',
        );
      } catch (_) {
        // Une ancienne session locale illisible ne doit pas bloquer
        // la reconstruction des statuts des autres modèles.
      }
    }
  }

  static Future<List<LocalModelOperationalEvent>> getOpenEventsForModel(
    String modelId,
  ) async {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
      return const [];
    }

    return (_database.select(_database.localModelOperationalEvents)
          ..where(
            (row) =>
                row.userId.equals(user.id) &
                row.modelId.equals(modelId) &
                row.resolvedAt.isNull(),
          )
          ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]))
        .get();
  }

  static ModelOperationalStatus statusFromEvents(
    Iterable<LocalModelOperationalEvent> events,
  ) {
    final repairs = <String>[];
    final maintenances = <String>[];

    for (final event in events) {
      final description = event.description.trim();
      if (event.eventType == repairType) {
        if (description.isNotEmpty) {
          repairs.add(description);
        }
      } else if (event.eventType == maintenanceType) {
        if (description.isNotEmpty) {
          maintenances.add(description);
        }
      }
    }

    if (repairs.isNotEmpty) {
      return ModelOperationalStatus(
        state: ModelOperationalState.unavailable,
        repairDescriptions: List<String>.unmodifiable(repairs),
        maintenanceDescriptions: List<String>.unmodifiable(maintenances),
      );
    }

    if (maintenances.isNotEmpty) {
      return ModelOperationalStatus(
        state: ModelOperationalState.maintenance,
        maintenanceDescriptions: List<String>.unmodifiable(maintenances),
      );
    }

    return ModelOperationalStatus.ready;
  }

  static Map<String, ModelOperationalStatus> statusesFromEvents(
    Iterable<LocalModelOperationalEvent> events,
  ) {
    final grouped = <String, List<LocalModelOperationalEvent>>{};

    for (final event in events) {
      grouped.putIfAbsent(event.modelId, () => <LocalModelOperationalEvent>[])
        ..add(event);
    }

    return <String, ModelOperationalStatus>{
      for (final entry in grouped.entries)
        entry.key: statusFromEvents(entry.value),
    };
  }

  static Stream<List<LocalModelOperationalEvent>> watchOpenEvents() {
    final user = SupabaseService.client.auth.currentUser;
    if (user == null) {
      return const Stream.empty();
    }

    final query = _database.select(_database.localModelOperationalEvents)
      ..where((row) => row.userId.equals(user.id) & row.resolvedAt.isNull())
      ..orderBy([(row) => OrderingTerm.asc(row.createdAt)]);

    return query.watch();
  }
}
