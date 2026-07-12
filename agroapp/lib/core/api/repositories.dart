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

/// Lecturas online de fincas/lotes/ciclos que además se cachean en Drift para uso offline.
class FarmRepository {
  FarmRepository(this._api, this._db);
  final ApiClient _api;
  final AppDatabase _db;

  Future<List<Farm>> loadFarms() async {
    final res = await _api.dio.get('/api/farms');
    final list = (res.data as List).cast<Map<String, dynamic>>();
    await _db.batch((b) {
      for (final f in list) {
        b.insert(_db.farms, _farmCompanion(f), onConflict: DoUpdate((_) => _farmCompanion(f)));
      }
    });
    return _db.select(_db.farms).get();
  }

  Future<List<Plot>> loadPlots(String farmId) async {
    final res = await _api.dio.get('/api/farms/$farmId/plots');
    final list = (res.data as List).cast<Map<String, dynamic>>();
    await _db.batch((b) {
      for (final pl in list) {
        b.insert(_db.plots, _plotCompanion(farmId, pl), onConflict: DoUpdate((_) => _plotCompanion(farmId, pl)));
      }
    });
    return (_db.select(_db.plots)..where((t) => t.farmId.equals(farmId))).get();
  }

  Future<List<Cycle>> loadCycles(String plotId) async {
    final res = await _api.dio.get('/api/plots/$plotId/cycles');
    final list = (res.data as List).cast<Map<String, dynamic>>();
    await _db.batch((b) {
      for (final c in list) {
        b.insert(_db.cycles, _cycleCompanion(c), onConflict: DoUpdate((_) => _cycleCompanion(c)));
      }
    });
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
