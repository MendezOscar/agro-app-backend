import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'db/database.dart';

/// Escrituras y consultas locales (Drift). Todo cambio se marca `dirty` para el próximo sync.
class LocalRepository {
  LocalRepository(this._db);
  final AppDatabase _db;
  static const _uuid = Uuid();

  // --- Streams reactivos para la UI ---
  Stream<List<Stage>> watchStages(String cycleId) =>
      (_db.select(_db.stages)..where((t) => t.cycleId.equals(cycleId))..orderBy([(t) => OrderingTerm(expression: t.kind)])).watch();

  Stream<List<Task>> watchTasks(String stageId) =>
      (_db.select(_db.tasks)..where((t) => t.stageId.equals(stageId))).watch();

  Stream<List<Observation>> watchObservations(String cycleId) =>
      (_db.select(_db.observations)..where((t) => t.cycleId.equals(cycleId))..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])).watch();

  Stream<List<Cost>> watchCosts(String cycleId) =>
      (_db.select(_db.costs)..where((t) => t.cycleId.equals(cycleId))).watch();

  /// Ciclos activos (estado = 1) cacheados localmente, para accesos directos.
  Future<List<Cycle>> activeCycles() =>
      (_db.select(_db.cycles)..where((t) => t.status.equals(1))).get();

  /// Etapas de un ciclo (ordenadas), para el timeline del dashboard.
  Future<List<Stage>> stagesOf(String cycleId) =>
      (_db.select(_db.stages)..where((t) => t.cycleId.equals(cycleId))..orderBy([(t) => OrderingTerm(expression: t.kind)])).get();

  /// Actualiza el estado de una etapa localmente (la persistencia server-side es best-effort vía API).
  Future<void> setStageStatus(String stageId, int status) =>
      (_db.update(_db.stages)..where((t) => t.id.equals(stageId))).write(StagesCompanion(
        status: Value(status),
        updatedAt: Value(DateTime.now()),
      ));

  // --- Escrituras locales (offline) ---
  Future<void> createObservation({
    required String cycleId,
    required String userId,
    String? note,
    double? lng,
    double? lat,
    String? photoLocalPath,
  }) =>
      _db.into(_db.observations).insert(ObservationsCompanion.insert(
            id: _uuid.v4(),
            cycleId: cycleId,
            createdByUserId: userId,
            note: Value(note),
            lng: Value(lng),
            lat: Value(lat),
            photoLocalPath: Value(photoLocalPath),
            updatedAt: DateTime.now(),
            dirty: const Value(true),
          ));

  Future<void> createTask(String stageId, String title,
          {String? description, String? assignedToUserId, DateTime? dueDate}) =>
      _db.into(_db.tasks).insert(TasksCompanion.insert(
            id: _uuid.v4(),
            stageId: stageId,
            title: title,
            description: Value(description),
            assignedToUserId: Value(assignedToUserId),
            dueDate: Value(dueDate),
            updatedAt: DateTime.now(),
            dirty: const Value(true),
          ));

  Future<void> setTaskStatus(String taskId, int status) =>
      (_db.update(_db.tasks)..where((t) => t.id.equals(taskId))).write(TasksCompanion(
        status: Value(status),
        completedAt: Value(status == 2 ? DateTime.now() : null),
        updatedAt: Value(DateTime.now()),
        dirty: const Value(true),
      ));

  Future<void> createCost({
    required String cycleId,
    required int kind,
    String? description,
    String? inputId,
    String? stageId,
    required double quantity,
    required double unitCost,
  }) =>
      _db.into(_db.costs).insert(CostsCompanion.insert(
            id: _uuid.v4(),
            cycleId: cycleId,
            kind: kind,
            description: Value(description),
            inputId: Value(inputId),
            stageId: Value(stageId),
            quantity: quantity,
            unitCost: unitCost,
            total: quantity * unitCost,
            incurredAt: DateTime.now(),
            updatedAt: DateTime.now(),
            dirty: const Value(true),
          ));
}
