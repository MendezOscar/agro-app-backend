import 'package:dio/dio.dart';
import 'package:drift/drift.dart';

import '../api/api_client.dart';
import '../db/database.dart';

/// Motor de sincronización offline-first.
///
/// 1) Empuja las filas `dirty` (tareas/observaciones/costos) al endpoint `/api/sync`.
/// 2) Sube las fotos pendientes de las observaciones.
/// 3) Aplica el delta del servidor a Drift y avanza el token `lastSyncAt`.
class SyncService {
  SyncService(this._api, this._db);
  final ApiClient _api;
  final AppDatabase _db;

  String _iso(DateTime d) => d.toUtc().toIso8601String();

  Future<void> sync() async {
    final since = await _db.lastSyncAt();

    final dirtyTasks = await (_db.select(_db.tasks)..where((t) => t.dirty.equals(true))).get();
    final dirtyObs = await (_db.select(_db.observations)..where((t) => t.dirty.equals(true))).get();
    final dirtyCosts = await (_db.select(_db.costs)..where((t) => t.dirty.equals(true))).get();

    final body = {
      'since': since == null ? null : _iso(since),
      'tasks': dirtyTasks.map(_taskDto).toList(),
      'observations': dirtyObs.map(_obsDto).toList(),
      'costs': dirtyCosts.map(_costDto).toList(),
    };

    final res = await _api.dio.post('/api/sync', data: body);
    final data = res.data as Map<String, dynamic>;

    await _applyDelta(data);

    // Fotos pendientes: la observación ya existe server-side tras el push.
    for (final o in dirtyObs) {
      if (o.photoLocalPath != null) await _uploadPhoto(o.id, o.photoLocalPath!);
    }

    // Limpiar dirty de lo empujado.
    await _clearDirty(dirtyTasks.map((e) => e.id), dirtyObs.map((e) => e.id), dirtyCosts.map((e) => e.id));

    final serverTime = DateTime.parse(data['serverTime']);
    await _db.setLastSyncAt(serverTime);
  }

  Future<void> _uploadPhoto(String obsId, String path) async {
    final form = FormData.fromMap({'file': await MultipartFile.fromFile(path)});
    final res = await _api.dio.post('/api/observations/$obsId/photo', data: form);
    final key = (res.data as Map<String, dynamic>)['photoUrl'];
    await (_db.update(_db.observations)..where((t) => t.id.equals(obsId)))
        .write(ObservationsCompanion(photoKey: Value(key), photoLocalPath: const Value(null)));
  }

  Future<void> _applyDelta(Map<String, dynamic> data) async {
    await _db.batch((b) {
      for (final c in (data['cycles'] as List).cast<Map<String, dynamic>>()) {
        b.insert(_db.cycles, CyclesCompanion.insert(
          id: c['id'], plotId: c['plotId'], crop: c['crop'],
          variety: Value(c['variety']), status: Value(c['status']),
          updatedAt: DateTime.parse(c['updatedAt']),
        ), onConflict: DoUpdate((_) => CyclesCompanion(
          crop: Value(c['crop']), variety: Value(c['variety']),
          status: Value(c['status']), updatedAt: Value(DateTime.parse(c['updatedAt'])),
        )));
      }
      for (final s in (data['stages'] as List).cast<Map<String, dynamic>>()) {
        final comp = StagesCompanion.insert(
          id: s['id'], cycleId: s['cropCycleId'], kind: s['kind'],
          status: Value(s['status']),
          startedAt: Value(_dt(s['startedAt'])), completedAt: Value(_dt(s['completedAt'])),
          notes: Value(s['notes']), updatedAt: DateTime.parse(s['updatedAt']),
        );
        b.insert(_db.stages, comp, onConflict: DoUpdate((_) => comp));
      }
      for (final t in (data['tasks'] as List).cast<Map<String, dynamic>>()) {
        final comp = TasksCompanion.insert(
          id: t['id'], stageId: t['stageId'], title: t['title'],
          description: Value(t['description']), assignedToUserId: Value(t['assignedToUserId']),
          status: Value(t['status']), dueDate: Value(_dt(t['dueDate'])),
          completedAt: Value(_dt(t['completedAt'])), updatedAt: DateTime.parse(t['updatedAt']),
          dirty: const Value(false),
        );
        b.insert(_db.tasks, comp, onConflict: DoUpdate((_) => comp));
      }
      for (final c in (data['costs'] as List).cast<Map<String, dynamic>>()) {
        final comp = CostsCompanion.insert(
          id: c['id'], cycleId: c['cropCycleId'], kind: c['kind'],
          description: Value(c['description']), inputId: Value(c['inputId']),
          workTaskId: Value(c['workTaskId']), stageId: Value(c['stageId']),
          quantity: (c['quantity'] as num).toDouble(), unitCost: (c['unitCost'] as num).toDouble(),
          total: (c['total'] as num).toDouble(), incurredAt: DateTime.parse(c['incurredAt']),
          updatedAt: DateTime.parse(c['updatedAt']), dirty: const Value(false),
        );
        b.insert(_db.costs, comp, onConflict: DoUpdate((_) => comp));
      }
      for (final o in (data['observations'] as List).cast<Map<String, dynamic>>()) {
        final comp = ObservationsCompanion.insert(
          id: o['id'], cycleId: o['cropCycleId'], createdByUserId: o['createdByUserId'],
          note: Value(o['note']), photoKey: Value(o['photoKey']),
          updatedAt: DateTime.parse(o['updatedAt']), dirty: const Value(false),
        );
        b.insert(_db.observations, comp, onConflict: DoUpdate((_) => ObservationsCompanion(
          note: Value(o['note']), photoKey: Value(o['photoKey']),
          updatedAt: Value(DateTime.parse(o['updatedAt'])),
        )));
      }
    });
  }

  Future<void> _clearDirty(Iterable<String> tasks, Iterable<String> obs, Iterable<String> costs) async {
    if (tasks.isNotEmpty) {
      await (_db.update(_db.tasks)..where((t) => t.id.isIn(tasks))).write(const TasksCompanion(dirty: Value(false)));
    }
    if (costs.isNotEmpty) {
      await (_db.update(_db.costs)..where((t) => t.id.isIn(costs))).write(const CostsCompanion(dirty: Value(false)));
    }
    // Las observaciones limpian dirty al confirmar foto/pull; marcarlas también aquí.
    if (obs.isNotEmpty) {
      await (_db.update(_db.observations)..where((t) => t.id.isIn(obs))).write(const ObservationsCompanion(dirty: Value(false)));
    }
  }

  DateTime? _dt(dynamic v) => v == null ? null : DateTime.parse(v);

  Map<String, dynamic> _taskDto(Task t) => {
        'id': t.id, 'stageId': t.stageId, 'title': t.title, 'description': t.description,
        'assignedToUserId': t.assignedToUserId, 'status': t.status,
        'dueDate': t.dueDate == null ? null : t.dueDate!.toIso8601String().substring(0, 10), // DateOnly en el server
        'completedAt': t.completedAt == null ? null : _iso(t.completedAt!),
        'updatedAt': _iso(t.updatedAt),
      };

  Map<String, dynamic> _obsDto(Observation o) => {
        'id': o.id, 'cropCycleId': o.cycleId, 'createdByUserId': o.createdByUserId,
        'location': (o.lng != null && o.lat != null) ? [o.lng, o.lat] : null,
        'note': o.note, 'photoKey': o.photoKey, 'updatedAt': _iso(o.updatedAt),
      };

  Map<String, dynamic> _costDto(Cost c) => {
        'id': c.id, 'cropCycleId': c.cycleId, 'kind': c.kind, 'description': c.description,
        'inputId': c.inputId, 'workTaskId': c.workTaskId, 'stageId': c.stageId,
        'quantity': c.quantity, 'unitCost': c.unitCost, 'total': c.total, 'incurredAt': _iso(c.incurredAt),
        'updatedAt': _iso(c.updatedAt),
      };
}
