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

  Future<void> changePassword(String current, String next) async {
    await _api.dio.post('/api/auth/change-password', data: {
      'currentPassword': current,
      'newPassword': next,
    });
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

  /// Crea un usuario en la organización (Owner/Manager).
  /// Lanza un [String] con el mensaje del servidor si falla.
  Future<void> createUser(String email, String fullName, String password, int role) async {
    try {
      await _api.dio.post('/api/users', data: {
        'email': email, 'fullName': fullName, 'password': password, 'role': role,
      });
    } on DioException catch (e) {
      throw _userError(e, 'No se pudo crear el usuario.');
    }
  }

  Future<void> updateUser(String id, String fullName, int role) async {
    try {
      await _api.dio.put('/api/users/$id', data: {'fullName': fullName, 'role': role});
    } on DioException catch (e) {
      throw _userError(e, 'No se pudo editar el usuario.');
    }
  }

  Future<void> deleteUser(String id) async {
    try {
      await _api.dio.delete('/api/users/$id');
    } on DioException catch (e) {
      throw _userError(e, 'No se pudo eliminar el usuario.');
    }
  }

  String _userError(DioException e, String fallback) {
    final data = e.response?.data;
    if (data is Map) {
      if (data['message'] != null) return data['message'].toString();
      if (data['errors'] is List) return (data['errors'] as List).join('\n');
    }
    return fallback;
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

  /// Indicadores agronómicos del ciclo. El backend da el contexto (lat/lng/cultivo/fecha);
  /// Open-Meteo se llama desde el dispositivo (IP propia) para evitar el límite por IP
  /// compartida de Render. Devuelve {soil, water, gdd, disease, message}.
  Future<Map<String, dynamic>?> loadAgronomy(String cycleId) async {
    Map<String, dynamic> ctx;
    try {
      final res = await _api.dio.get('/api/cycles/$cycleId/agronomy');
      ctx = res.data as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
    final msg = ctx['message'] as String?;
    final lat = (ctx['lat'] as num?)?.toDouble();
    final lng = (ctx['lng'] as num?)?.toDouble();
    if (msg != null || lat == null || lng == null) {
      return {'soil': [], 'water': null, 'gdd': null, 'disease': null, 'message': msg ?? 'Sin ubicación.'};
    }
    return _computeAgronomy(lat, lng, ctx['cycleStart'] as String?, (ctx['baseTempC'] as num).toDouble());
  }

  Future<Map<String, dynamic>> _computeAgronomy(double lat, double lng, String? cycleStart, double baseTemp) async {
    final dio = Dio();
    List<dynamic> soil = [];
    Map<String, dynamic>? water, gdd, disease;

    // Pronóstico: suelo actual, balance hídrico 7+7 y riesgo de enfermedad.
    try {
      final res = await dio.get('https://api.open-meteo.com/v1/forecast', queryParameters: {
        'latitude': lat, 'longitude': lng,
        'hourly': 'soil_temperature_0cm,soil_temperature_6cm,soil_temperature_18cm,soil_temperature_54cm,'
            'soil_moisture_0_1cm,soil_moisture_1_3cm,soil_moisture_3_9cm,soil_moisture_9_27cm,'
            'relative_humidity_2m,temperature_2m',
        'daily': 'et0_fao_evapotranspiration,precipitation_sum',
        'past_days': 7, 'forecast_days': 7, 'timezone': 'auto',
      });
      final data = res.data as Map<String, dynamic>;
      final h = data['hourly'] as Map<String, dynamic>?;
      if (h != null) {
        List<num?> col(String k) => ((h[k] as List?) ?? []).map((e) => e as num?).toList();
        final temps = col('temperature_2m');
        var idx = -1;
        for (var i = temps.length - 1; i >= 0; i--) { if (temps[i] != null) { idx = i; break; } }
        num? at(String k) { final c = col(k); return idx >= 0 && idx < c.length ? c[idx] : null; }
        double? pct(num? v) => v == null ? null : (v * 1000).round() / 10;
        soil = [
          {'depthLabel': '0 cm', 'tempC': at('soil_temperature_0cm'), 'moisturePct': pct(at('soil_moisture_0_1cm'))},
          {'depthLabel': '6 cm', 'tempC': at('soil_temperature_6cm'), 'moisturePct': pct(at('soil_moisture_1_3cm'))},
          {'depthLabel': '18 cm', 'tempC': at('soil_temperature_18cm'), 'moisturePct': pct(at('soil_moisture_3_9cm'))},
          {'depthLabel': '54 cm', 'tempC': at('soil_temperature_54cm'), 'moisturePct': pct(at('soil_moisture_9_27cm'))},
        ];
        final rh = col('relative_humidity_2m'), tp = col('temperature_2m');
        final n = rh.length < tp.length ? rh.length : tp.length;
        final from = n - 48 < 0 ? 0 : n - 48;
        var fav = 0;
        for (var i = from; i < n; i++) {
          if (rh[i] != null && tp[i] != null && rh[i]! >= 85 && tp[i]! >= 15 && tp[i]! <= 28) fav++;
        }
        final level = fav >= 18 ? 'high' : fav >= 8 ? 'medium' : fav >= 3 ? 'low' : 'none';
        disease = {'level': level, 'reason': '$fav h con humedad ≥85% y 15–28 °C en las últimas 48 h (favorable a hongos).'};
      }
      final d = data['daily'] as Map<String, dynamic>?;
      if (d != null) {
        double s(String k) => ((d[k] as List?) ?? []).fold(0.0, (a, v) => a + ((v as num?)?.toDouble() ?? 0));
        final et0 = s('et0_fao_evapotranspiration'), pr = s('precipitation_sum');
        final deficit = (et0 - pr) < 0 ? 0.0 : et0 - pr;
        water = {
          'et0Mm7d': (et0 * 10).round() / 10, 'precipMm7d': (pr * 10).round() / 10,
          'deficitMm': (deficit * 10).round() / 10, 'irrigationSuggested': deficit > 15, 'suggestedMm': deficit.round(),
        };
      }
    } catch (_) {/* pronóstico opcional */}

    // Histórico: grados-día acumulados desde el inicio del ciclo.
    if (cycleStart != null) {
      final start = DateTime.tryParse(cycleStart);
      if (start != null && start.isBefore(DateTime.now())) {
        try {
          final end = DateTime.now().subtract(const Duration(days: 1)).toIso8601String().substring(0, 10);
          final res = await dio.get('https://archive-api.open-meteo.com/v1/archive', queryParameters: {
            'latitude': lat, 'longitude': lng, 'start_date': cycleStart, 'end_date': end,
            'daily': 'temperature_2m_max,temperature_2m_min', 'timezone': 'auto',
          });
          final d = (res.data as Map<String, dynamic>)['daily'] as Map<String, dynamic>?;
          if (d != null) {
            final tmax = ((d['temperature_2m_max'] as List?) ?? []).map((e) => e as num?).toList();
            final tmin = ((d['temperature_2m_min'] as List?) ?? []).map((e) => e as num?).toList();
            final n = tmax.length < tmin.length ? tmax.length : tmin.length;
            var acc = 0.0, days = 0;
            for (var i = 0; i < n; i++) {
              if (tmax[i] == null || tmin[i] == null) continue;
              final g = (tmax[i]! + tmin[i]!) / 2 - baseTemp;
              acc += g > 0 ? g : 0;
              days++;
            }
            gdd = {'baseTempC': baseTemp, 'accumulated': acc.round(), 'days': days};
          }
        } catch (_) {/* histórico opcional */}
      }
    }

    return {'soil': soil, 'water': water, 'gdd': gdd, 'disease': disease, 'message': null};
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

  Future<void> createInput(Map<String, dynamic> body) => _api.dio.post('/api/inputs', data: body);
  Future<void> updateInput(String id, Map<String, dynamic> body) => _api.dio.put('/api/inputs/$id', data: body);
  Future<void> deleteInput(String id) => _api.dio.delete('/api/inputs/$id');
  Future<void> restockInput(String id, double quantity) => _api.dio.post('/api/inputs/$id/restock', data: {'quantity': quantity});

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
