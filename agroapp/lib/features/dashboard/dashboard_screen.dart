import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/providers.dart';
import '../cycles/cycle_detail_screen.dart';

const _wmo = {
  0: ['Despejado', '☀️'], 1: ['Mayormente despejado', '🌤'], 2: ['Parcialmente nublado', '⛅'], 3: ['Nublado', '☁️'],
  45: ['Niebla', '🌫'], 48: ['Niebla', '🌫'], 51: ['Llovizna', '🌦'], 53: ['Llovizna', '🌦'], 55: ['Llovizna', '🌧'],
  61: ['Lluvia', '🌧'], 63: ['Lluvia', '🌧'], 65: ['Lluvia fuerte', '🌧'], 80: ['Chubascos', '🌦'],
  81: ['Chubascos', '🌧'], 82: ['Chubascos fuertes', '⛈'], 95: ['Tormenta', '⛈'], 96: ['Tormenta', '⛈'], 99: ['Tormenta', '⛈'],
};
List<String> _desc(int code) => (_wmo[code] ?? const ['—', '🌡']).cast<String>();

/// Vista de inicio de la app: KPIs + clima de la finca.
class DashboardBody extends ConsumerStatefulWidget {
  const DashboardBody({super.key});
  @override
  ConsumerState<DashboardBody> createState() => _DashboardBodyState();
}

class _DashboardBodyState extends ConsumerState<DashboardBody> {
  Map<String, dynamic>? _data;
  Map<String, dynamic>? _weather;
  List<Cycle> _active = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final repo = ref.read(farmRepoProvider);
      final data = await repo.loadDashboard();
      final active = await ref.read(localRepoProvider).activeCycles();
      Map<String, dynamic>? weather;
      final farms = (data['farmsList'] as List).cast<Map<String, dynamic>>();
      final withLoc = farms.where((f) => f['lat'] != null && f['lng'] != null);
      if (withLoc.isNotEmpty) {
        final f = withLoc.first;
        weather = await repo.loadWeather((f['lat'] as num).toDouble(), (f['lng'] as num).toDouble());
      }
      if (mounted) setState(() { _data = data; _weather = weather; _active = active; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final d = _data;
    if (d == null) return const Center(child: Text('No se pudo cargar el inicio.'));

    final kpis = [
      ['🌱', '${d['farms']}', 'Fincas'],
      ['🗺', '${d['plots']}', 'Lotes'],
      ['🌾', '${d['activeCycles']}', 'Ciclos activos'],
      ['✅', '${d['pendingTasks']}', 'Tareas pend.'],
      ['📦', '${d['closedCycles']}', 'Cerrados'],
      ['💲', (d['totalCost'] as num).toStringAsFixed(0), 'Costo total'],
    ];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.15,
            children: [
              for (final k in kpis)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE6E9E3)),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(k[0], style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(k[1], style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                    Text(k[2], style: const TextStyle(color: Colors.black54, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ]),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _activeCycles(),
          _weatherCard(),
        ],
      ),
    );
  }

  Widget _activeCycles() {
    if (_active.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Cultivos activos', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 4),
          for (final c in _active)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(backgroundColor: Color(0x142F7A3A), child: Icon(Icons.eco, color: Color(0xFF2F7A3A))),
              title: Text(c.crop, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: c.variety != null ? Text(c.variety!) : null,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => CycleDetailScreen(cycle: c))),
            ),
        ]),
      ),
    );
  }

  Widget _weatherCard() {
    final w = _weather;
    if (w == null || w['current'] == null) {
      return const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('Clima no disponible (finca sin ubicación).')));
    }
    final cur = w['current'] as Map<String, dynamic>;
    final daily = w['daily'] as Map<String, dynamic>;
    final code = cur['weather_code'] as int;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Clima', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 10),
          Row(children: [
            Text(_desc(code)[1], style: const TextStyle(fontSize: 46)),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${(cur['temperature_2m'] as num).round()}°C', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
              Text(_desc(code)[0], style: const TextStyle(color: Colors.black54)),
            ]),
            const Spacer(),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('💧 ${cur['relative_humidity_2m']}%'),
              Text('🌧 ${cur['precipitation']} mm'),
              Text('💨 ${cur['wind_speed_10m']} km/h'),
            ]),
          ]),
          const Divider(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < (daily['time'] as List).length; i++)
                Column(children: [
                  Text(_weekday((daily['time'] as List)[i]), style: const TextStyle(fontSize: 12, color: Colors.black54)),
                  Text(_desc((daily['weather_code'] as List)[i] as int)[1], style: const TextStyle(fontSize: 20)),
                  Text('${((daily['temperature_2m_max'] as List)[i] as num).round()}°', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                  Text('${((daily['temperature_2m_min'] as List)[i] as num).round()}°', style: const TextStyle(fontSize: 11, color: Colors.black45)),
                ]),
            ],
          ),
          const SizedBox(height: 6),
          const Text('Datos: Open-Meteo', style: TextStyle(fontSize: 10, color: Colors.black38)),
        ]),
      ),
    );
  }

  String _weekday(String iso) {
    const days = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];
    return days[(DateTime.parse(iso).weekday - 1) % 7];
  }
}
