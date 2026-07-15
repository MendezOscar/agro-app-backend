import 'package:dio/dio.dart';
import 'package:drift/drift.dart';

import '../db/database.dart';
import 'api_client.dart';

class AuthRepository {
  AuthRepository(this._api, this._tokensSaver);
  final ApiClient _api;
  final Future<void> Function(Map<String, dynamic>) _tokensSaver;

  Future<void> login(String email, String password) async {
    final res = await _api.dio.post('/api/auth/login',
        data: {'email': email, 'password': password});
    await _tokensSaver(res.data);
  }

  Future<void> register(String orgName, String fullName, String email, String password) async {
    final res = await _api.dio.post('/api/auth/register', data: {
      'orgName': orgName,
      'fullName': fullName,
      'email': email,
      'password': password,
    });
    await _tokensSaver(res.data);
  }
}

/// Repositorio online para el flujo del jornalero: sus tareas y observaciones.
class TaskRepository {
  TaskRepository(this._api);
  final ApiClient _api;

  Future<List<Map<String, dynamic>>> myTasks() async {
    final res = await _api.dio.get('/api/my/tasks');
    return (res.data as List).cast<Map<String, dynamic>>();
  }

  Future<void> setStatus(String taskId, int status) async {
    await _api.dio.post('/api/tasks/$taskId/status/$status');
  }

  Future<String> createObservation(String cycleId, String? note) async {
    final res = await _api.dio.post('/api/cycles/$cycleId/observations', data: {'note': note});
    return (res.data as Map<String, dynamic>)['id'] as String;
  }

  Future<void> uploadPhoto(String obsId, String path) async {
    final form = FormData.fromMap({'file': await MultipartFile.fromFile(path)});
    await _api.dio.post('/api/observations/$obsId/photo', data: form);
  }
}

/// Lecturas online de fincas/lotes/ciclos que además se cachean en Drift para uso offline.
class FarmRepository {
  FarmRepository(this._api, this._db);
  final ApiClient _api;
  final AppDatabase _db;

  Future<List<Farm>> loadFarms() async {
    final res = await _api.dio.get('/api/farms');
    final list = (res.data as List).cast<Map<String, dynamic>>();
    final ids = list.map((f) => f['id'] as String).toList();
    await _db.batch((b) {
      for (final f in list) {
        b.insert(_db.farms, _farmCompanion(f), onConflict: DoUpdate((_) => _farmCompanion(f)));
      }
    });
    // Reconciliar eliminaciones: quitar fincas (y sus lotes) que ya no existen en el servidor.
    await (_db.delete(_db.farms)..where((t) => ids.isEmpty ? const Constant(true) : t.id.isNotIn(ids))).go();
    await (_db.delete(_db.plots)..where((t) => ids.isEmpty ? const Constant(true) : t.farmId.isNotIn(ids))).go();
    return _db.select(_db.farms).get();
  }

  Future<List<Plot>> loadPlots(String farmId) async {
    final res = await _api.dio.get('/api/farms/$farmId/plots');
    final list = (res.data as List).cast<Map<String, dynamic>>();
    final ids = list.map((p) => p['id'] as String).toList();
    await _db.batch((b) {
      for (final pl in list) {
        b.insert(_db.plots, _plotCompanion(farmId, pl), onConflict: DoUpdate((_) => _plotCompanion(farmId, pl)));
      }
    });
    await (_db.delete(_db.plots)
          ..where((t) => t.farmId.equals(farmId) & (ids.isEmpty ? const Constant(true) : t.id.isNotIn(ids))))
        .go();
    return (_db.select(_db.plots)..where((t) => t.farmId.equals(farmId))).get();
  }

  /// Equipo de la organización (para asignar tareas). Puede fallar por permisos → [].
  Future<List<Map<String, dynamic>>> loadTeam() async {
    try {
      final res = await _api.dio.get('/api/users');
      return (res.data as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  // --- Análisis de suelo/agua por lote (online) ---
  Future<List<Map<String, dynamic>>> loadAnalyses(String plotId) async {
    final res = await _api.dio.get('/api/plots/$plotId/analyses');
    return (res.data as List).cast<Map<String, dynamic>>();
  }

  Future<void> createAnalysis(String plotId, Map<String, dynamic> body) async {
    await _api.dio.post('/api/plots/$plotId/analyses', data: body);
  }

  /// Avanza el estado de una etapa en el servidor (best-effort; requiere conexión).
  Future<void> advanceStage(String stageId, int status) async {
    await _api.dio.put('/api/stages/$stageId', data: {'status': status});
  }

  /// Métricas del dashboard de inicio.
  Future<Map<String, dynamic>> loadDashboard() async {
    final res = await _api.dio.get('/api/dashboard');
    return res.data as Map<String, dynamic>;
  }

  /// Clima por coordenadas (Open-Meteo, sin auth: se usa un Dio limpio).
  Future<Map<String, dynamic>?> loadWeather(double lat, double lng) async {
    try {
      final res = await Dio().get('https://api.open-meteo.com/v1/forecast', queryParameters: {
        'latitude': lat, 'longitude': lng,
        'current': 'temperature_2m,relative_humidity_2m,precipitation,wind_speed_10m,weather_code',
        'daily': 'temperature_2m_max,temperature_2m_min,precipitation_sum,weather_code',
        'timezone': 'auto', 'forecast_days': 5,
      });
      return res.data as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// Catálogo de insumos de la organización.
  Future<List<Map<String, dynamic>>> loadInputs() async {
    try {
      final res = await _api.dio.get('/api/inputs');
      return (res.data as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  // --- Monitoreo fenológico (online) ---
  Future<List<Map<String, dynamic>>> loadPhenology(String cycleId) async {
    final res = await _api.dio.get('/api/cycles/$cycleId/phenology');
    return (res.data as List).cast<Map<String, dynamic>>();
  }

  Future<void> createPhenology(String cycleId, Map<String, dynamic> body) async {
    await _api.dio.post('/api/cycles/$cycleId/phenology', data: body);
  }

  Future<List<Cycle>> loadCycles(String plotId) async {
    final res = await _api.dio.get('/api/plots/$plotId/cycles');
    final list = (res.data as List).cast<Map<String, dynamic>>();
    final ids = list.map((c) => c['id'] as String).toList();
    await _db.batch((b) {
      for (final c in list) {
        b.insert(_db.cycles, _cycleCompanion(c), onConflict: DoUpdate((_) => _cycleCompanion(c)));
      }
    });
    await (_db.delete(_db.cycles)
          ..where((t) => t.plotId.equals(plotId) & (ids.isEmpty ? const Constant(true) : t.id.isNotIn(ids))))
        .go();
    return (_db.select(_db.cycles)..where((t) => t.plotId.equals(plotId))).get();
  }

  FarmsCompanion _farmCompanion(Map<String, dynamic> f) {
    final loc = f['location'] as List?;
    final b = f['boundary'] as List?;
    return FarmsCompanion.insert(
      id: f['id'],
      name: f['name'],
      areaHa: Value((f['areaHa'] as num).toDouble()),
      boundaryJson: Value(b?.toString()),
      lng: Value(loc == null ? null : (loc[0] as num).toDouble()),
      lat: Value(loc == null ? null : (loc[1] as num).toDouble()),
    );
  }

  PlotsCompanion _plotCompanion(String farmId, Map<String, dynamic> pl) {
    final b = pl['boundary'] as List?;
    return PlotsCompanion.insert(
      id: pl['id'],
      farmId: farmId,
      name: pl['name'],
      areaHa: Value((pl['areaHa'] as num).toDouble()),
      boundaryJson: Value(b?.toString()),
      soilType: Value(pl['soilType']),
    );
  }

  CyclesCompanion _cycleCompanion(Map<String, dynamic> c) => CyclesCompanion.insert(
        id: c['id'],
        plotId: c['plotId'],
        crop: c['crop'],
        variety: Value(c['variety']),
        status: Value(c['status']),
        updatedAt: DateTime.now(),
      );

  Future<Map<String, dynamic>> createCycle(Map<String, dynamic> body) async {
    final res = await _api.dio.post('/api/cycles', data: body);
    return res.data as Map<String, dynamic>;
  }
}
