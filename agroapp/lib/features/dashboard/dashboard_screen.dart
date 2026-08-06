import 'dart:math' show Point;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/db/database.dart';
import '../../core/env.dart';
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
  Map<String, dynamic>? _dashWind;
  Map<String, Color> _plotRiskColor = {};
  List<Map<String, dynamic>> _agroAlerts = [];
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
      Map<String, dynamic>? weather;
      final farms = (data['farmsList'] as List).cast<Map<String, dynamic>>();
      final withLoc = farms.where((f) => f['lat'] != null && f['lng'] != null);
      Map<String, dynamic>? wind;
      if (withLoc.isNotEmpty) {
        final f = withLoc.first;
        final lat = (f['lat'] as num).toDouble(), lng = (f['lng'] as num).toDouble();
        weather = await repo.loadWeather(lat, lng);
        wind = await repo.loadWind(lat, lng);
      }
      if (mounted) setState(() { _data = data; _weather = weather; _dashWind = wind; _loading = false; });
      _loadAgroAlerts(data);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Alertas agronómicas (Open-Meteo desde el dispositivo) por ciclo activo.
  Future<void> _loadAgroAlerts(Map<String, dynamic> data) async {
    final repo = ref.read(farmRepoProvider);
    final cycles = ((data['activeCyclesList']) as List?)?.cast<Map<String, dynamic>>() ?? [];
    final out = <Map<String, dynamic>>[];
    final riskByPlot = <String, Color>{};
    const rank = {0xFF4CAF50: 0, 0xFFFF9800: 1, 0xFFF44336: 2}; // verde<naranja<rojo
    for (final c in cycles) {
      final a = await repo.loadAgronomy(c['id'] as String);
      if (a == null) continue;
      final crop = c['crop'] ?? 'Cultivo';
      final plotId = c['plotId'] as String?;
      if (plotId != null) {
        final rc = _riskColorFromAgro(a);
        final prev = riskByPlot[plotId];
        if (prev == null || (rank[rc.toARGB32()] ?? 0) > (rank[prev.toARGB32()] ?? 0)) riskByPlot[plotId] = rc;
      }
      final water = a['water'] as Map<String, dynamic>?;
      if (water?['irrigationSuggested'] == true) {
        out.add({'level': 'warning', 'message': '💧 Riego recomendado en $crop: ~${(water!['suggestedMm'] as num).toStringAsFixed(0)} mm (déficit 7 días).'});
      }
      final disease = a['disease'] as Map<String, dynamic>?;
      final lvl = disease?['level'];
      if (lvl == 'high' || lvl == 'medium') {
        out.add({'level': lvl == 'high' ? 'danger' : 'warning', 'message': '🍄 Riesgo de enfermedad ${lvl == 'high' ? 'alto' : 'medio'} en $crop (humedad/temperatura favorables a hongos).'});
      }
      for (final w in ((a['alerts'] as List?) ?? [])) {
        final wm = w as Map<String, dynamic>;
        out.add({'level': wm['level'], 'message': '${wm['message']} ($crop)'});
      }
    }
    if (mounted) setState(() { _agroAlerts = out; _plotRiskColor = riskByPlot; });
  }

  Color _riskColorFromAgro(Map<String, dynamic> a) {
    final disease = (a['disease'] as Map<String, dynamic>?)?['level'];
    final water = a['water'] as Map<String, dynamic>?;
    final alerts = (a['alerts'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    final danger = disease == 'high' || alerts.any((x) => x['level'] == 'danger');
    final warn = disease == 'medium' || water?['irrigationSuggested'] == true || alerts.any((x) => x['level'] == 'warning');
    if (danger) return Colors.red;
    if (warn) return Colors.orange;
    return Colors.green;
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
          _alerts(),
          _IncidentsMap(
            incidents: ((_data?['incidents']) as List?)?.cast<Map<String, dynamic>>() ?? const [],
            activeCycles: ((_data?['activeCyclesList']) as List?)?.cast<Map<String, dynamic>>() ?? const [],
            plotBoundaries: ((_data?['plotBoundaries']) as List?)?.cast<Map<String, dynamic>>() ?? const [],
            plotRiskColor: _plotRiskColor,
            wind: _dashWind,
          ),
          _activeCycles(),
          _upcomingTasks(),
          _costByKind(),
          _weatherCard(),
        ],
      ),
    );
  }

  Widget _activeCycles() {
    final list = ((_data?['activeCyclesList']) as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (list.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Avance de cultivos activos', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          for (final c in list)
            InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => CycleDetailScreen(cycle: Cycle(
                        id: c['id'], plotId: c['plotId'], crop: c['crop'],
                        variety: c['variety'], status: 1, updatedAt: DateTime.now(),
                      )))),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(
                      c['variety'] != null ? '${c['crop']} · ${c['variety']}' : c['crop'],
                      style: const TextStyle(fontWeight: FontWeight.w700))),
                    Text('\$${(c['totalCost'] as num? ?? 0).toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF2F7A3A))),
                    const SizedBox(width: 6),
                    const Icon(Icons.chevron_right, color: Colors.black38),
                  ]),
                  const SizedBox(height: 8),
                  _Timeline(stages: (c['stages'] as List).cast<Map<String, dynamic>>()),
                ]),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _alerts() {
    final base = ((_data?['alerts']) as List?)?.cast<Map<String, dynamic>>() ?? [];
    final list = [...base, ..._agroAlerts];
    if (list.isEmpty) return const SizedBox.shrink();
    Color color(String l) => l == 'danger' ? Colors.red.shade700 : (l == 'warning' ? const Color(0xFFD99A00) : const Color(0xFF2C89C9));
    String emoji(Map<String, dynamic> a) {
      final m = a['message']?.toString() ?? '';
      // Si el mensaje ya empieza con un emoji propio, no anteponer icono.
      if (m.isNotEmpty && m.runes.first > 0x2000) return '';
      return a['level'] == 'danger' ? '⚠️' : (a['level'] == 'warning' ? '🪲' : 'ℹ️');
    }
    return Column(children: [
      for (final a in list)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border(left: BorderSide(color: color(a['level']), width: 4)),
            boxShadow: const [BoxShadow(color: Color(0x11000000), blurRadius: 6, offset: Offset(0, 2))],
          ),
          child: Row(children: [
            Text(emoji(a), style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(child: Text(a['message'], style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
        ),
    ]);
  }

  Widget _upcomingTasks() {
    final list = ((_data?['upcomingTasks']) as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (list.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Tareas por vencer', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          for (final t in list)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(
                    color: t['overdue'] == true ? Colors.red.shade700 : const Color(0xFF2F7A3A), shape: BoxShape.circle)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t['title'], style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(t['crop'], style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ])),
                Text('${t['overdue'] == true ? 'Vencida · ' : ''}${_fmtDue(t['dueDate'])}',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600,
                        color: t['overdue'] == true ? Colors.red.shade700 : Colors.black54)),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _costByKind() {
    final list = ((_data?['costByKind']) as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (list.isEmpty) return const SizedBox.shrink();
    const labels = ['Mano de obra', 'Insumo', 'Maquinaria', 'Otro'];
    final total = (_data?['totalCost'] as num?)?.toDouble() ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Costo por tipo', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          for (final s in list) ...[
            Row(children: [
              Expanded(child: Text(labels[s['kind'] as int])),
              Text('\$${(s['total'] as num).toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: total > 0 ? (s['total'] as num) / total : 0,
                minHeight: 8, backgroundColor: const Color(0xFFEEF1EA),
                valueColor: const AlwaysStoppedAnimation(Color(0xFF2F7A3A)),
              ),
            ),
            const SizedBox(height: 12),
          ],
          const Divider(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Total', style: TextStyle(fontWeight: FontWeight.w800)),
            Text('\$${total.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.w800)),
          ]),
        ]),
      ),
    );
  }

  String _fmtDue(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    const m = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    return '${d.day} ${m[d.month - 1]}';
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

const _stageShort = ['Planif.', 'Prep. suelo', 'Siembra', 'Manejo', 'Monitoreo', 'Cosecha', 'Poscosecha', 'Evaluación'];
Color _stageColor(int status) => const [Color(0xFFC8CCC4), Color(0xFFD99A00), Color(0xFF2F7A3A)][status];

Color _incSevColor(String? s) => {
      'high': Colors.red,
      'medium': Colors.orange,
      'low': Colors.amber[700]!,
      'none': Colors.green,
    }[s] ?? Colors.grey;
String _incHex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
String _incSevLabel(String? s) =>
    {'high': 'Alta', 'medium': 'Media', 'low': 'Baja', 'none': 'Sin incidencia'}[s] ?? '—';

/// Aptitud de aspersión según viento (km/h). Aplicar bajo ~15 km/h.
({Color color, String label})? _driftOf(Map<String, dynamic>? w) {
  if (w == null) return null;
  final s = (w['speed'] as num).toDouble(), g = (w['gust'] as num).toDouble();
  final m = s > g ? s : g;
  if (m > 25) return (color: Colors.red, label: 'No aplicar');
  if (m > 15) return (color: Colors.orange, label: 'Precaución');
  return (color: Colors.green, label: 'Apta');
}

/// Recuadro flotante con viento y aptitud de aspersión (deriva).
Widget _windHud(Map<String, dynamic> w) {
  final d = _driftOf(w);
  final gust = (w['gust'] as num).toDouble(), speed = (w['speed'] as num).toDouble();
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(10),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8)],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Transform.rotate(
          angle: ((w['dir'] as num).toDouble() + 180) * 3.1415926 / 180,
          child: const Icon(Icons.arrow_upward, size: 15, color: Color(0xFF14532D)),
        ),
        const SizedBox(width: 7),
        Text('Viento ${speed.round()} km/h${gust > speed + 3 ? ' · ráfagas ${gust.round()}' : ''}',
            style: const TextStyle(fontSize: 12.5)),
      ]),
      if (d != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 11, height: 11, decoration: BoxDecoration(color: d.color, shape: BoxShape.circle)),
            const SizedBox(width: 7),
            Text.rich(TextSpan(children: [
              const TextSpan(text: 'Aspersión: '),
              TextSpan(text: d.label, style: TextStyle(fontWeight: FontWeight.w700, color: d.color)),
            ]), style: const TextStyle(fontSize: 12.5)),
          ]),
        ),
    ]),
  );
}

/// Dibuja los límites de lote (relleno) y un pin por incidente sobre [c], y encuadra
/// la cámara al conjunto. Devuelve el mapa circleId → incidente para resolver el tap.
Future<Map<String, Map<String, dynamic>>> _drawIncidents(
    MapLibreMapController c,
    List<Map<String, dynamic>> incidents,
    List<Map<String, dynamic>> boundaries,
    {Map<String, Color> riskByPlot = const {}}) async {
  final byCircle = <String, Map<String, dynamic>>{};
  double? minLat, maxLat, minLng, maxLng;
  void extend(double lat, double lng) {
    minLat = minLat == null ? lat : (lat < minLat! ? lat : minLat);
    maxLat = maxLat == null ? lat : (lat > maxLat! ? lat : maxLat);
    minLng = minLng == null ? lng : (lng < minLng! ? lng : minLng);
    maxLng = maxLng == null ? lng : (lng > maxLng! ? lng : maxLng);
  }

  for (final p in boundaries) {
    final ring = p['boundary'] as List?;
    if (ring == null) continue;
    final pts = ring.map((pt) => LatLng((pt[1] as num).toDouble(), (pt[0] as num).toDouble())).toList();
    // Semáforo: color por estado agronómico del lote (verde si no hay dato).
    final rc = _incHex(riskByPlot[p['id']] ?? const Color(0xFF22C55E));
    await c.addFill(FillOptions(geometry: [pts], fillColor: rc, fillOpacity: 0.12));
    await c.addLine(LineOptions(geometry: pts, lineColor: rc, lineWidth: 2.5, lineOpacity: 0.9));
    for (final pt in pts) {
      extend(pt.latitude, pt.longitude);
    }
  }
  for (final o in incidents) {
    final lat = (o['lat'] as num).toDouble(), lng = (o['lng'] as num).toDouble();
    final circle = await c.addCircle(CircleOptions(
      geometry: LatLng(lat, lng),
      circleRadius: 10,
      circleColor: _incHex(_incSevColor(o['severity'] as String?)),
      circleStrokeColor: '#ffffff',
      circleStrokeWidth: 2,
    ));
    byCircle[circle.id] = o;
    extend(lat, lng);
  }
  if (minLat != null) {
    await c.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(southwest: LatLng(minLat!, minLng!), northeast: LatLng(maxLat!, maxLng!)),
      left: 30, right: 30, top: 30, bottom: 30));
  }
  return byCircle;
}

/// Vista previa (no interactiva) del mapa de incidentes en el dashboard.
/// Al tocar abre el mapa a pantalla completa, donde sí se pueden seleccionar los pines.
class _IncidentsMap extends StatefulWidget {
  const _IncidentsMap({
    required this.incidents,
    required this.activeCycles,
    required this.plotBoundaries,
    this.plotRiskColor = const {},
    this.wind,
  });
  final List<Map<String, dynamic>> incidents;
  final List<Map<String, dynamic>> activeCycles;
  final List<Map<String, dynamic>> plotBoundaries;
  final Map<String, Color> plotRiskColor;
  final Map<String, dynamic>? wind;
  @override
  State<_IncidentsMap> createState() => _IncidentsMapState();
}

class _IncidentsMapState extends State<_IncidentsMap> {
  MapLibreMapController? _controller;

  LatLng get _center {
    final f = widget.incidents.first;
    return LatLng((f['lat'] as num).toDouble(), (f['lng'] as num).toDouble());
  }

  void _openFull() => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => IncidentsMapScreen(
          incidents: widget.incidents,
          activeCycles: widget.activeCycles,
          plotBoundaries: widget.plotBoundaries,
          plotRiskColor: widget.plotRiskColor,
          wind: widget.wind,
        ),
      ));

  @override
  Widget build(BuildContext context) {
    if (widget.incidents.isEmpty || Env.maptilerKey.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Incidentes en el mapa · ${widget.incidents.length}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            TextButton.icon(onPressed: _openFull, icon: const Icon(Icons.fullscreen, size: 18), label: const Text('Explorar')),
          ]),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 260,
              // Vista previa: gestos desactivados y overlay que captura el toque
              // para abrir el mapa a pantalla completa (evita el conflicto con el scroll).
              child: Stack(children: [
                MapLibreMap(
                  styleString: 'https://api.maptiler.com/maps/hybrid/style.json?key=${Env.maptilerKey}',
                  initialCameraPosition: CameraPosition(target: _center, zoom: 12),
                  onMapCreated: (c) => _controller = c,
                  onStyleLoadedCallback: () {
                    final c = _controller;
                    if (c != null) _drawIncidents(c, widget.incidents, widget.plotBoundaries, riskByPlot: widget.plotRiskColor);
                  },
                  compassEnabled: false,
                  rotateGesturesEnabled: false,
                  scrollGesturesEnabled: false,
                  zoomGesturesEnabled: false,
                  tiltGesturesEnabled: false,
                ),
                if (widget.wind != null)
                  Positioned(top: 8, left: 8, child: _windHud(widget.wind!)),
                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(onTap: _openFull),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          const Text('El contorno de cada lote colorea su estado agronómico. Toca el mapa para explorar y seleccionar un incidente.',
              style: TextStyle(fontSize: 12, color: Colors.black54)),
        ]),
      ),
    );
  }
}

/// Mapa de incidentes a pantalla completa: límites de lote + pines por severidad.
/// Al tocar un pin muestra el detalle y permite abrir el ciclo.
class IncidentsMapScreen extends StatefulWidget {
  const IncidentsMapScreen({
    super.key,
    required this.incidents,
    required this.activeCycles,
    required this.plotBoundaries,
    this.plotRiskColor = const {},
    this.wind,
  });
  final List<Map<String, dynamic>> incidents;
  final List<Map<String, dynamic>> activeCycles;
  final List<Map<String, dynamic>> plotBoundaries;
  final Map<String, Color> plotRiskColor;
  final Map<String, dynamic>? wind;
  @override
  State<IncidentsMapScreen> createState() => _IncidentsMapScreenState();
}

class _IncidentsMapScreenState extends State<IncidentsMapScreen> {
  MapLibreMapController? _controller;
  Map<String, Map<String, dynamic>> _byCircle = {};

  // Toque directo sobre el pin: iOS enruta a feature#onTap (onCircleTapped),
  // no a onMapClick. Por eso se manejan ambos: aquí el impacto exacto...
  void _onCircleTap(Circle circle) {
    final o = _byCircle[circle.id];
    if (o != null) _showDetail(o);
  }

  LatLng get _center {
    final f = widget.incidents.first;
    return LatLng((f['lat'] as num).toDouble(), (f['lng'] as num).toDouble());
  }

  /// Selección robusta: al tocar el mapa busca el incidente cuyo pin esté más
  /// cerca del punto tocado (en píxeles). Evita depender del hit-target del círculo
  /// (onCircleTapped en maplibre_gl casi nunca dispara).
  Future<void> _handleClick(Point<double> point) async {
    final c = _controller;
    if (c == null || widget.incidents.isEmpty) return;
    final locs = await c.toScreenLocationBatch(widget.incidents
        .map((o) => LatLng((o['lat'] as num).toDouble(), (o['lng'] as num).toDouble())));
    double best = double.infinity;
    Map<String, dynamic>? bestO;
    for (var i = 0; i < locs.length; i++) {
      final dx = locs[i].x - point.x, dy = locs[i].y - point.y;
      final d = dx * dx + dy * dy;
      if (d < best) { best = d; bestO = widget.incidents[i]; }
    }
    if (bestO != null && best <= 44 * 44) _showDetail(bestO);
  }

  void _showDetail(Map<String, dynamic> o) {
    final sev = o['severity'] as String?;
    final cycleId = o['cycleId']?.toString();
    final active = widget.activeCycles.where((c) => c['id'] == cycleId).toList();
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(o['crop']?.toString() ?? 'Cultivo', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 6),
          if (o['note']?.toString().isNotEmpty == true) Text(o['note'].toString()),
          const SizedBox(height: 8),
          if (sev == null)
            const Text('Análisis IA en proceso…', style: TextStyle(color: Colors.grey))
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: _incSevColor(sev).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
              child: Text('Severidad: ${_incSevLabel(sev)}', style: TextStyle(color: _incSevColor(sev), fontWeight: FontWeight.w600)),
            ),
          if (active.isNotEmpty) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Ver ciclo'),
              onPressed: () {
                final c = active.first;
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => CycleDetailScreen(cycle: Cycle(
                          id: c['id'], plotId: c['plotId'], crop: c['crop'],
                          variety: c['variety'], status: 1, updatedAt: DateTime.now(),
                        ))));
              },
            ),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Incidentes en el mapa'),
        actions: [Padding(padding: const EdgeInsets.only(right: 12), child: Center(child: Text('${widget.incidents.length} incidente(s)')))],
      ),
      body: Stack(children: [
        MapLibreMap(
          styleString: 'https://api.maptiler.com/maps/hybrid/style.json?key=${Env.maptilerKey}',
          initialCameraPosition: CameraPosition(target: _center, zoom: 14),
          onMapClick: (point, latLng) => _handleClick(point),
          onMapCreated: (c) {
            _controller = c;
            c.onCircleTapped.add(_onCircleTap);
          },
          onStyleLoadedCallback: () async {
            final c = _controller;
            if (c == null) return;
            final byCircle = await _drawIncidents(c, widget.incidents, widget.plotBoundaries, riskByPlot: widget.plotRiskColor);
            if (mounted) setState(() => _byCircle = byCircle);
          },
          compassEnabled: true,
        ),
        if (widget.wind != null)
          Positioned(top: 10, left: 10, child: _windHud(widget.wind!)),
      ]),
    );
  }
}

/// Timeline horizontal de las 8 etapas del ciclo, coloreado por estado.
/// `stages`: lista de mapas {kind,status} provenientes del dashboard del servidor.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.stages});
  final List<Map<String, dynamic>> stages;

  int _kind(int i) => stages[i]['kind'] as int;
  int _status(int i) => stages[i]['status'] as int;

  @override
  Widget build(BuildContext context) {
    if (stages.isEmpty) {
      return const Text('Sin etapas.', style: TextStyle(color: Colors.black45, fontSize: 12));
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < stages.length; i++)
            SizedBox(
              width: 62,
              child: Column(children: [
                Row(children: [
                  Expanded(child: Container(height: 3, color: i == 0 ? Colors.transparent : _stageColor(_status(i - 1)))),
                  Container(
                    width: 26, height: 26,
                    decoration: BoxDecoration(color: _stageColor(_status(i)), shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: _status(i) == 2
                        ? const Icon(Icons.check, size: 15, color: Colors.white)
                        : Text('${_kind(i) + 1}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  Expanded(child: Container(height: 3, color: i == stages.length - 1 ? Colors.transparent : _stageColor(_status(i)))),
                ]),
                const SizedBox(height: 5),
                Text(_stageShort[_kind(i)], textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Colors.black54), maxLines: 2),
              ]),
            ),
        ],
      ),
    );
  }
}
