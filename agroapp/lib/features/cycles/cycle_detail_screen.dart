import 'dart:convert';
import 'dart:math' show Point;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/db/database.dart';
import '../../core/env.dart';
import '../../core/labels.dart';
import '../../core/location.dart';
import '../../core/providers.dart';
import 'plot_analysis_screen.dart';

const _phenoStages = ['Germinación', 'Vegetativo', 'Floración', 'Cuajado', 'Maduración', 'Senescencia'];

/// Detalle del ciclo centrado en etapas (tabs horizontales). Cada etapa
/// ocupa toda la pantalla con sus tareas, costos y datos especializados.
/// Observaciones: acción del cabezal.
class CycleDetailScreen extends ConsumerWidget {
  const CycleDetailScreen({super.key, required this.cycle});
  final Cycle cycle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(localRepoProvider);
    return StreamBuilder<List<Stage>>(
      stream: repo.watchStages(cycle.id),
      builder: (context, snap) {
        final stages = snap.data ?? [];
        // Etapa actual: en progreso; si no, la primera sin completar; si no, la primera.
        var current = stages.indexWhere((s) => s.status == 1);
        if (current < 0) current = stages.indexWhere((s) => s.status != 2);
        if (current < 0) current = 0;
        return DefaultTabController(
          // El key fuerza recrear el controller cuando llegan las etapas del stream,
          // para que initialIndex (etapa actual) se aplique de verdad.
          key: ValueKey('tabs-${stages.length}-$current'),
          length: stages.isEmpty ? 1 : stages.length,
          initialIndex: stages.isEmpty ? 0 : current,
          child: Scaffold(
            appBar: AppBar(
              title: Text('${cycle.crop} · ${cycleStatusLabels[cycle.status]}'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.eco_outlined),
                  tooltip: 'Agronomía',
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => AgronomyScreen(cycleId: cycle.id))),
                ),
                IconButton(
                  icon: const Icon(Icons.map_outlined),
                  tooltip: 'Mapa del lote',
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => IncidentMapScreen(cycleId: cycle.id, plotId: cycle.plotId))),
                ),
                IconButton(
                  icon: const Icon(Icons.photo_library_outlined),
                  tooltip: 'Historial visual',
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => PlotGalleryScreen(plotId: cycle.plotId))),
                ),
                IconButton(
                  icon: const Icon(Icons.bar_chart_outlined),
                  tooltip: 'Rentabilidad',
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ProfitabilityScreen(plotId: cycle.plotId))),
                ),
                IconButton(
                  icon: const Icon(Icons.photo_camera_outlined),
                  tooltip: 'Observaciones',
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ObservationsScreen(cycleId: cycle.id))),
                ),
              ],
              bottom: stages.isEmpty
                  ? null
                  : TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      tabs: [for (final s in stages) Tab(text: '${s.kind + 1}. ${stageKindLabels[s.kind]}')],
                    ),
            ),
            body: stages.isEmpty
                ? const Center(child: Text('Sincroniza para ver las etapas.'))
                : TabBarView(children: [for (final s in stages) _StageTab(cycle: cycle, stage: s)]),
          ),
        );
      },
    );
  }
}

class _StageTab extends ConsumerWidget {
  const _StageTab({required this.cycle, required this.stage});
  final Cycle cycle;
  final Stage stage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(localRepoProvider);
    final statusColor = [Colors.grey, Colors.amber.shade700, const Color(0xFF2F7A3A)][stage.status];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Icon(Icons.circle, size: 12, color: statusColor),
          const SizedBox(width: 8),
          const Text('Estado de la etapa', style: TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          DropdownButton<int>(
            value: stage.status,
            items: [for (var i = 0; i < 3; i++) DropdownMenuItem(value: i, child: Text(stageStatusLabels[i]))],
            onChanged: (v) async {
              if (v == null) return;
              await repo.setStageStatus(stage.id, v); // refleja de inmediato
              try { await ref.read(farmRepoProvider).advanceStage(stage.id, v); } catch (_) {} // persiste si hay red
            },
          ),
        ]),
        const Divider(),
        _TasksSection(stageId: stage.id),
        const Divider(),
        _StageCostsSection(cycleId: cycle.id, stageId: stage.id),
        if (stage.kind == 4) ...[const Divider(), _PhenologyInline(cycleId: cycle.id)],
        if (stage.kind == 0 || stage.kind == 1) ...[
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.science_outlined),
            title: const Text('Análisis de suelo/agua'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => PlotAnalysisScreen(plotId: cycle.plotId, plotName: 'Lote'))),
          ),
        ],
      ],
    );
  }
}

// ---------------- Tareas ----------------
class _TasksSection extends ConsumerWidget {
  const _TasksSection({required this.stageId});
  final String stageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(localRepoProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SectionLabel('Tareas'),
      StreamBuilder<List<Task>>(
        stream: repo.watchTasks(stageId),
        builder: (context, snap) {
          final tasks = snap.data ?? [];
          return Column(children: [
            for (final t in tasks)
              _TaskRow(task: t, onSet: (s) => repo.setTaskStatus(t.id, s)),
            if (tasks.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Text('Sin tareas.', style: TextStyle(color: Colors.black54))),
          ]);
        },
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Agregar tarea'),
          onPressed: () async {
            final team = await ref.read(farmRepoProvider).loadTeam();
            if (!context.mounted) return;
            final data = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _TaskDialog(team: team));
            if (data != null) {
              await repo.createTask(stageId, data['title'],
                  description: data['description'], assignedToUserId: data['assignedToUserId'], dueDate: data['dueDate']);
            }
          },
        ),
      ),
    ]);
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task, required this.onSet});
  final Task task;
  final void Function(int) onSet;

  @override
  Widget build(BuildContext context) {
    final done = task.status == 2;
    final color = done ? const Color(0xFF2F7A3A) : (task.status == 1 ? Colors.amber.shade700 : Colors.grey);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        InkWell(onTap: () => onSet((task.status + 1) % 3), child: Icon(
          done ? Icons.check_circle : (task.status == 1 ? Icons.timelapse : Icons.radio_button_unchecked), color: color)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(task.title, style: TextStyle(fontWeight: FontWeight.w600, decoration: done ? TextDecoration.lineThrough : null)),
          if (task.description != null && task.description!.isNotEmpty)
            Text(task.description!, style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
          if (task.dueDate != null)
            Text('📅 ${task.dueDate!.toIso8601String().substring(0, 10)}', style: const TextStyle(fontSize: 12, color: Colors.black45)),
        ])),
        PopupMenuButton<int>(
          onSelected: onSet,
          itemBuilder: (_) => [
            for (var s = 0; s < 3; s++) PopupMenuItem(value: s, child: Text(taskStatusLabels[s])),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
            child: Text(taskStatusLabels[task.status], style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }
}

class _TaskDialog extends StatefulWidget {
  const _TaskDialog({required this.team});
  final List<Map<String, dynamic>> team;
  @override
  State<_TaskDialog> createState() => _TaskDialogState();
}

class _TaskDialogState extends State<_TaskDialog> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  String? _assignee;
  DateTime? _due;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nueva tarea'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: _title, decoration: const InputDecoration(labelText: 'Título')),
        const SizedBox(height: 14),
        TextField(controller: _desc, decoration: const InputDecoration(labelText: 'Descripción')),
        const SizedBox(height: 14),
        if (widget.team.isNotEmpty) ...[
          DropdownButtonFormField<String?>(
            initialValue: _assignee,
            decoration: const InputDecoration(labelText: 'Responsable'),
            items: [
              const DropdownMenuItem(value: null, child: Text('— sin asignar —')),
              for (final u in widget.team) DropdownMenuItem(value: u['id'] as String, child: Text(u['fullName'])),
            ],
            onChanged: (v) => setState(() => _assignee = v),
          ),
          const SizedBox(height: 6),
        ],
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.calendar_today, size: 20),
          title: Text(_due == null ? 'Fecha límite (opcional)' : _due!.toIso8601String().substring(0, 10)),
          onTap: () async {
            final p = await showDatePicker(context: context, initialDate: DateTime(2026, 7, 15), firstDate: DateTime(2020), lastDate: DateTime(2035));
            if (p != null) setState(() => _due = p);
          },
        ),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () {
          if (_title.text.trim().isEmpty) return;
          Navigator.pop(context, {
            'title': _title.text.trim(),
            'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
            'assignedToUserId': _assignee, 'dueDate': _due,
          });
        }, child: const Text('Crear')),
      ],
    );
  }
}

// ---------------- Costos de la etapa ----------------
class _StageCostsSection extends ConsumerWidget {
  const _StageCostsSection({required this.cycleId, required this.stageId});
  final String cycleId;
  final String stageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(localRepoProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SectionLabel('Costos de la etapa'),
      StreamBuilder<List<Cost>>(
        stream: repo.watchCosts(cycleId),
        builder: (context, snap) {
          final costs = (snap.data ?? []).where((c) => c.stageId == stageId).toList();
          final sub = costs.fold<double>(0, (s, c) => s + c.total);
          return Column(children: [
            for (final c in costs)
              ListTile(
                dense: true, contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.payments_outlined),
                title: Text(c.description?.isNotEmpty == true ? c.description! : costKindLabels[c.kind]),
                subtitle: Text('${costKindLabels[c.kind]} · ${c.quantity} × ${c.unitCost}'),
                trailing: Text(c.total.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            if (costs.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 4), child: Align(alignment: Alignment.centerLeft, child: Text('Sin costos.', style: TextStyle(color: Colors.black54)))),
            if (costs.isNotEmpty) Align(alignment: Alignment.centerRight, child: Text('Subtotal: ${sub.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w700))),
          ]);
        },
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Agregar costo'),
          onPressed: () async {
            final inputs = await ref.read(farmRepoProvider).loadInputs();
            if (!context.mounted) return;
            final data = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _CostDialog(inputs: inputs));
            if (data != null) {
              await repo.createCost(
                cycleId: cycleId, kind: data['kind'], description: data['description'],
                inputId: data['inputId'], stageId: stageId,
                quantity: data['quantity'], unitCost: data['unitCost']);
            }
          },
        ),
      ),
    ]);
  }
}

class _CostDialog extends StatefulWidget {
  const _CostDialog({required this.inputs});
  final List<Map<String, dynamic>> inputs;
  @override
  State<_CostDialog> createState() => _CostDialogState();
}

class _CostDialogState extends State<_CostDialog> {
  int _kind = 1;
  String? _inputId;
  final _desc = TextEditingController();
  final _qty = TextEditingController(text: '1');
  final _unit = TextEditingController(text: '0');
  String? _err;

  void _submit() {
    final qty = double.tryParse(_qty.text.trim());
    final unit = double.tryParse(_unit.text.trim());
    if (qty == null || qty <= 0) { setState(() => _err = 'La cantidad debe ser mayor que 0.'); return; }
    if (unit == null || unit < 0) { setState(() => _err = 'El costo unitario no puede ser negativo.'); return; }
    Navigator.pop(context, {
      'kind': _kind, 'inputId': _inputId,
      'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      'quantity': qty, 'unitCost': unit,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo costo'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<int>(
          initialValue: _kind,
          decoration: const InputDecoration(labelText: 'Tipo'),
          items: [for (var i = 0; i < costKindLabels.length; i++) DropdownMenuItem(value: i, child: Text(costKindLabels[i]))],
          onChanged: (v) => setState(() => _kind = v ?? 1),
        ),
        const SizedBox(height: 14),
        if (widget.inputs.isNotEmpty) ...[
          DropdownButtonFormField<String?>(
            initialValue: _inputId,
            decoration: const InputDecoration(labelText: 'Insumo (opcional)'),
            items: [
              const DropdownMenuItem(value: null, child: Text('— manual —')),
              for (final i in widget.inputs)
                DropdownMenuItem(
                  value: i['id'] as String,
                  child: Text('${i['name']} (${i['unit']}) · stock ${(i['stockQty'] as num? ?? 0).toStringAsFixed(0)}'),
                ),
            ],
            onChanged: (v) => setState(() {
              _inputId = v;
              final m = widget.inputs.where((i) => i['id'] == v);
              if (m.isNotEmpty) _unit.text = (m.first['unitCost'] as num).toString();
            }),
          ),
          const SizedBox(height: 14),
        ],
        TextField(controller: _qty, decoration: const InputDecoration(labelText: 'Cantidad'), keyboardType: TextInputType.number),
        const SizedBox(height: 14),
        TextField(controller: _unit, decoration: const InputDecoration(labelText: 'Costo unitario'), keyboardType: TextInputType.number),
        const SizedBox(height: 14),
        TextField(controller: _desc, decoration: const InputDecoration(labelText: 'Descripción')),
        if (_err != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_err!, style: const TextStyle(color: Colors.red, fontSize: 13))),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _submit, child: const Text('Agregar')),
      ],
    );
  }
}

// ---------------- Monitoreo (etapa 5) ----------------
class _PhenologyInline extends ConsumerStatefulWidget {
  const _PhenologyInline({required this.cycleId});
  final String cycleId;
  @override
  ConsumerState<_PhenologyInline> createState() => _PhenologyInlineState();
}

class _PhenologyInlineState extends ConsumerState<_PhenologyInline> {
  late Future<List<Map<String, dynamic>>> _recs;
  @override
  void initState() {
    super.initState();
    _recs = ref.read(farmRepoProvider).loadPhenology(widget.cycleId);
  }

  void _reload() => setState(() => _recs = ref.read(farmRepoProvider).loadPhenology(widget.cycleId));

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const _SectionLabel('Monitoreo fenológico'),
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _recs,
        builder: (context, snap) {
          final recs = snap.data ?? [];
          return Column(children: [
            for (final r in recs)
              ListTile(
                dense: true, contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.eco, color: Color(0xFF2F7A3A)),
                title: Text('${_phenoStages[r['stage'] as int]} · ${r['recordedAt']}'),
                subtitle: Text([
                  if (r['plantHeightCm'] != null) 'Altura ${r['plantHeightCm']}cm',
                  if (r['pestIncidencePct'] != null) 'Plagas ${r['pestIncidencePct']}%',
                  if (r['diseaseIncidencePct'] != null) 'Enf. ${r['diseaseIncidencePct']}%',
                ].join(' · ')),
              ),
            if (recs.isEmpty) const Align(alignment: Alignment.centerLeft, child: Text('Sin registros.', style: TextStyle(color: Colors.black54))),
          ]);
        },
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Registrar monitoreo'),
          onPressed: () async {
            final data = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const _PhenologyDialog());
            if (data == null) return;
            try {
              await ref.read(farmRepoProvider).createPhenology(widget.cycleId, data);
              _reload();
            } catch (_) {
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo guardar')));
            }
          },
        ),
      ),
    ]);
  }
}

class _PhenologyDialog extends StatefulWidget {
  const _PhenologyDialog();
  @override
  State<_PhenologyDialog> createState() => _PhenologyDialogState();
}

class _PhenologyDialogState extends State<_PhenologyDialog> {
  int _stage = 0;
  DateTime _date = DateTime(2026, 7, 15);
  final _h = TextEditingController();
  final _pest = TextEditingController();
  final _dis = TextEditingController();
  final _notes = TextEditingController();
  double? _num(TextEditingController c) => c.text.trim().isEmpty ? null : double.tryParse(c.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Monitoreo fenológico'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          contentPadding: EdgeInsets.zero, leading: const Icon(Icons.calendar_today, size: 20),
          title: Text('Fecha: ${_date.toIso8601String().substring(0, 10)}'),
          onTap: () async {
            final p = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime(2035));
            if (p != null) setState(() => _date = p);
          },
        ),
        DropdownButtonFormField<int>(
          initialValue: _stage,
          decoration: const InputDecoration(labelText: 'Etapa fenológica'),
          items: [for (var i = 0; i < _phenoStages.length; i++) DropdownMenuItem(value: i, child: Text(_phenoStages[i]))],
          onChanged: (v) => setState(() => _stage = v ?? 0),
        ),
        const SizedBox(height: 14),
        TextField(controller: _h, decoration: const InputDecoration(labelText: 'Altura (cm)'), keyboardType: TextInputType.number),
        const SizedBox(height: 14),
        TextField(controller: _pest, decoration: const InputDecoration(labelText: 'Plagas (%)'), keyboardType: TextInputType.number),
        const SizedBox(height: 14),
        TextField(controller: _dis, decoration: const InputDecoration(labelText: 'Enfermedad (%)'), keyboardType: TextInputType.number),
        const SizedBox(height: 14),
        TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Notas')),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, {
          'recordedAt': _date.toIso8601String().substring(0, 10), 'stage': _stage,
          'plantHeightCm': _num(_h), 'pestIncidencePct': _num(_pest), 'diseaseIncidencePct': _num(_dis),
          'notes': _notes.text.trim(),
        }), child: const Text('Guardar')),
      ],
    );
  }
}

// ---------------- Observaciones (nivel ciclo) ----------------
class ObservationsScreen extends ConsumerStatefulWidget {
  const ObservationsScreen({super.key, required this.cycleId});
  final String cycleId;

  @override
  ConsumerState<ObservationsScreen> createState() => _ObservationsScreenState();
}

class _ObservationsScreenState extends ConsumerState<ObservationsScreen> {
  late Future<List<dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<dynamic>> _load() async {
    final dio = ref.read(apiClientProvider).dio;
    final res = await dio.get('/api/cycles/${widget.cycleId}/observations');
    return (res.data as List?) ?? [];
  }

  void _refresh() => setState(() => _future = _load());

  Future<void> _add() async {
    final photo = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600);
    if (!mounted) return;
    final note = await _prompt(context, 'Observación', 'Nota (opcional)');
    final userId = await ref.read(tokenStoreProvider).userId ?? '';
    final loc = await currentLngLat();
    await ref.read(localRepoProvider).createObservation(
        cycleId: widget.cycleId,
        userId: userId,
        note: note,
        lng: loc?[0],
        lat: loc?[1],
        photoLocalPath: photo?.path);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Observación guardada. Se sincroniza y analiza en segundo plano; usa ↻ para actualizar.')));
    }
  }

  // El diagnóstico a veces llega como JSON anidado; extrae el texto legible.
  String _diag(String raw) {
    final t = raw.trim();
    if (t.startsWith('{')) {
      try {
        final m = jsonDecode(t) as Map<String, dynamic>;
        return (m['diagnosis'] ?? raw).toString();
      } catch (_) {}
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Observaciones'),
        actions: [IconButton(icon: const Icon(Icons.refresh), tooltip: 'Actualizar', onPressed: _refresh)],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: FutureBuilder<List<dynamic>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return ListView(children: const [
                Padding(padding: EdgeInsets.all(24), child: Text('No se pudieron cargar las observaciones. Desliza para reintentar.')),
              ]);
            }
            final obs = snap.data ?? [];
            if (obs.isEmpty) {
              return ListView(children: const [
                Padding(padding: EdgeInsets.all(24), child: Text('Sin observaciones. Toca + para agregar una con foto.')),
              ]);
            }
            return ListView(padding: const EdgeInsets.all(8), children: [
              for (final o in obs) _obsCard(o as Map<String, dynamic>),
            ]);
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(onPressed: _add, child: const Icon(Icons.add_a_photo)),
    );
  }

  Widget _obsCard(Map<String, dynamic> o) {
    final a = o['analysis'] as Map<String, dynamic>?;
    final photoUrl = o['photoUrl'] as String?;
    final sev = a?['severity'] as String?;
    final sevColor = {
      'high': Colors.red,
      'medium': Colors.orange,
      'low': Colors.amber[700],
      'none': Colors.green,
    }[sev] ?? Colors.grey;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (photoUrl != null)
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Image.network(photoUrl, height: 180, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox(height: 60, child: Center(child: Icon(Icons.broken_image)))),
          ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(o['note']?.toString().isNotEmpty == true ? o['note'].toString() : '(sin nota)',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            if (a == null)
              Row(children: const [
                SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('Análisis IA en proceso…', style: TextStyle(color: Colors.grey)),
              ])
            else ...[
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: sevColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                  child: Text('Severidad: ${_sevLabel(sev)}', style: TextStyle(color: sevColor, fontWeight: FontWeight.w600, fontSize: 12)),
                ),
                const Spacer(),
                if (a['confidence'] != null)
                  Text('Confianza ${((a['confidence'] as num) * 100).round()}%', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ]),
              const SizedBox(height: 8),
              Text(_diag((a['diagnosis'] ?? '').toString())),
              if ((a['recommendations'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Recomendaciones: ${a['recommendations']}', style: const TextStyle(fontSize: 13, color: Colors.black87)),
              ],
            ],
          ]),
        ),
      ]),
    );
  }

  String _sevLabel(String? s) => {
        'high': 'Alta',
        'medium': 'Media',
        'low': 'Baja',
        'none': 'Sin incidencia',
      }[s] ?? '—';
}

/// Mapa del lote con el polígono + un pin por observación geolocalizada.
/// El color del pin refleja la severidad del análisis IA; al tocarlo abre el detalle.
class IncidentMapScreen extends ConsumerStatefulWidget {
  const IncidentMapScreen({super.key, required this.cycleId, required this.plotId});
  final String cycleId;
  final String plotId;
  @override
  ConsumerState<IncidentMapScreen> createState() => _IncidentMapScreenState();
}

class _IncidentMapScreenState extends ConsumerState<IncidentMapScreen> {
  MapLibreMapController? _controller;
  List<LatLng> _boundary = [];
  List<Map<String, dynamic>> _obs = [];
  final Map<String, Map<String, dynamic>> _byCircle = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final dio = ref.read(apiClientProvider).dio;
      final results = await Future.wait([
        dio.get('/api/plots/${widget.plotId}'),
        dio.get('/api/cycles/${widget.cycleId}/observations'),
      ]);
      final ring = (results[0].data as Map<String, dynamic>)['boundary'] as List?;
      _boundary = ring == null
          ? []
          : ring.map((p) => LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble())).toList();
      _obs = ((results[1].data as List?) ?? [])
          .cast<Map<String, dynamic>>()
          .where((o) => o['location'] is List && (o['location'] as List).length == 2)
          .toList();
      if (mounted) setState(() => _loading = false);
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'No se pudo cargar el mapa.'; });
    }
  }

  Color _sevColor(String? s) => {
        'high': Colors.red,
        'medium': Colors.orange,
        'low': Colors.amber[700]!,
        'none': Colors.green,
      }[s] ?? Colors.grey;

  String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  LatLng get _center => _boundary.isNotEmpty
      ? _boundary.first
      : (_obs.isNotEmpty
          ? LatLng((_obs.first['location'][1] as num).toDouble(), (_obs.first['location'][0] as num).toDouble())
          : const LatLng(14.0818, -87.2068));

  Future<void> _draw() async {
    final c = _controller;
    if (c == null) return;
    if (_boundary.isNotEmpty) {
      await c.addFill(FillOptions(
        geometry: [_boundary], fillColor: '#22c55e', fillOpacity: 0.1));
      await c.addLine(LineOptions(geometry: _boundary, lineColor: '#22c55e', lineWidth: 2.5, lineOpacity: 0.9));
    }
    for (final o in _obs) {
      final loc = o['location'] as List;
      final a = o['analysis'] as Map<String, dynamic>?;
      final circle = await c.addCircle(CircleOptions(
        geometry: LatLng((loc[1] as num).toDouble(), (loc[0] as num).toDouble()),
        circleRadius: 9,
        circleColor: _hex(_sevColor(a?['severity'] as String?)),
        circleStrokeColor: '#ffffff',
        circleStrokeWidth: 2,
      ));
      _byCircle[circle.id] = o;
    }
    if (_obs.isNotEmpty || _boundary.isNotEmpty) {
      await c.animateCamera(CameraUpdate.newLatLngZoom(_center, 15));
    }
  }

  // Toque directo sobre el pin: iOS enruta a feature#onTap (onCircleTapped) y
  // no a onMapClick. Por eso se manejan ambos.
  void _onCircleTapped(Circle circle) {
    final o = _byCircle[circle.id];
    if (o != null) _showDetail(o);
  }

  /// Toque cercano (no exactamente sobre el pin): llega por onMapClick; elige el
  /// incidente más próximo en píxeles. Cubre lo que el hit-target del círculo no atrapa.
  Future<void> _handleClick(Point<double> point) async {
    final c = _controller;
    if (c == null || _obs.isEmpty) return;
    final locs = await c.toScreenLocationBatch(_obs.map((o) {
      final l = o['location'] as List;
      return LatLng((l[1] as num).toDouble(), (l[0] as num).toDouble());
    }));
    double best = double.infinity;
    Map<String, dynamic>? bestO;
    for (var i = 0; i < locs.length; i++) {
      final dx = locs[i].x - point.x, dy = locs[i].y - point.y;
      final d = dx * dx + dy * dy;
      if (d < best) { best = d; bestO = _obs[i]; }
    }
    if (bestO != null && best <= 44 * 44) _showDetail(bestO);
  }

  void _showDetail(Map<String, dynamic> o) {
    final a = o['analysis'] as Map<String, dynamic>?;
    final sev = a?['severity'] as String?;
    showModalBottomSheet(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (o['photoUrl'] != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(o['photoUrl'].toString(), height: 160, width: double.infinity, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(height: 60, child: Center(child: Icon(Icons.broken_image)))),
            ),
          const SizedBox(height: 10),
          Text(o['note']?.toString().isNotEmpty == true ? o['note'].toString() : '(sin nota)',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          const SizedBox(height: 8),
          if (a == null)
            const Text('Análisis IA en proceso…', style: TextStyle(color: Colors.grey))
          else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: _sevColor(sev).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
              child: Text('Severidad: ${_sevLabelText(sev)}',
                  style: TextStyle(color: _sevColor(sev), fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 8),
            Text(_diagText((a['diagnosis'] ?? '').toString())),
          ],
        ]),
      ),
    );
  }

  String _sevLabelText(String? s) =>
      {'high': 'Alta', 'medium': 'Media', 'low': 'Baja', 'none': 'Sin incidencia'}[s] ?? '—';

  String _diagText(String raw) {
    final t = raw.trim();
    if (t.startsWith('{')) {
      try {
        final m = jsonDecode(t) as Map<String, dynamic>;
        if (m['diagnosis'] != null) return m['diagnosis'].toString();
      } catch (_) {}
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    if (Env.maptilerKey.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mapa del lote')),
        body: const Center(
          child: Padding(padding: EdgeInsets.all(24),
            child: Text('Falta la key de MapTiler.\nEjecuta con --dart-define=MAPTILER_KEY=...', textAlign: TextAlign.center)),
        ),
      );
    }
    if (_loading) {
      return Scaffold(appBar: AppBar(title: const Text('Mapa del lote')), body: const Center(child: CircularProgressIndicator()));
    }
    if (_error != null || (_boundary.isEmpty && _obs.isEmpty)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Mapa del lote')),
        body: Center(child: Padding(padding: const EdgeInsets.all(24),
          child: Text(_error ?? 'Sin incidentes geolocalizados ni límite del lote.\nRegistra observaciones con el GPS activo.',
              textAlign: TextAlign.center))),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa del lote'),
        actions: [Padding(padding: const EdgeInsets.only(right: 12), child: Center(child: Text('${_obs.length} incidente(s)')))],
      ),
      body: MapLibreMap(
        styleString: 'https://api.maptiler.com/maps/hybrid/style.json?key=${Env.maptilerKey}',
        initialCameraPosition: CameraPosition(target: _center, zoom: 15),
        onMapClick: (point, latLng) => _handleClick(point),
        onMapCreated: (c) {
          _controller = c;
          c.onCircleTapped.add(_onCircleTapped);
        },
        onStyleLoadedCallback: _draw,
        compassEnabled: true,
      ),
    );
  }
}

Future<String?> _prompt(BuildContext context, String title, String label) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, decoration: InputDecoration(labelText: label)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('OK')),
      ],
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 6),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      );
}

// ---------------- Agronomía (suelo, riego, GDD, riesgo — Open-Meteo vía backend) ----------------
class AgronomyScreen extends ConsumerStatefulWidget {
  const AgronomyScreen({super.key, required this.cycleId});
  final String cycleId;

  @override
  ConsumerState<AgronomyScreen> createState() => _AgronomyScreenState();
}

class _AgronomyScreenState extends ConsumerState<AgronomyScreen> {
  late Future<Map<String, dynamic>?> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(farmRepoProvider).loadAgronomy(widget.cycleId);
  }

  void _refresh() => setState(() => _future = ref.read(farmRepoProvider).loadAgronomy(widget.cycleId));

  static const _sevColors = {
    'high': Color(0xFFDC2626),
    'medium': Color(0xFFEA580C),
    'low': Color(0xFFCA8A04),
    'none': Color(0xFF16A34A),
  };
  static const _diseaseLabels = {'high': 'Alto', 'medium': 'Medio', 'low': 'Bajo', 'none': 'Sin riesgo'};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Agronomía'),
        actions: [IconButton(icon: const Icon(Icons.refresh), tooltip: 'Actualizar', onPressed: _refresh)],
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snap.data;
          if (data == null) {
            return const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No se pudieron cargar los indicadores. Toca ↻ para reintentar.')));
          }
          final msg = data['message'] as String?;
          if (msg != null) {
            return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(msg)));
          }
          return ListView(padding: const EdgeInsets.all(12), children: [
            _soilCard(data['soil'] as List? ?? []),
            _waterCard(data['water'] as Map<String, dynamic>?),
            _gddCard(data['gdd'] as Map<String, dynamic>?),
            _diseaseCard(data['disease'] as Map<String, dynamic>?),
            const Padding(padding: EdgeInsets.only(top: 8),
                child: Text('Datos: Open-Meteo · se recalcula al abrir o con ↻',
                    style: TextStyle(fontSize: 11, color: Colors.grey))),
          ]);
        },
      ),
    );
  }

  Widget _card(String title, String validity, List<Widget> children) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            Text(validity, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 8),
            ...children,
          ]),
        ),
      );

  String _n(dynamic v, String suffix) => v == null ? '—' : '${(v as num).toStringAsFixed(1)}$suffix';

  Widget _soilCard(List soil) {
    if (soil.isEmpty) return const SizedBox.shrink();
    return _card('Suelo por profundidad', 'Lectura actual (hora)', [
      for (final l in soil.cast<Map<String, dynamic>>())
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(width: 60, child: Text(l['depthLabel']?.toString() ?? '')),
            Expanded(child: Text('Temp: ${_n(l['tempC'], ' °C')}')),
            Expanded(child: Text('Humedad: ${l['moisturePct'] == null ? '—' : '${(l['moisturePct'] as num).toStringAsFixed(0)} %'}')),
          ]),
        ),
    ]);
  }

  Widget _waterCard(Map<String, dynamic>? w) {
    if (w == null) return const SizedBox.shrink();
    final suggested = w['irrigationSuggested'] == true;
    return _card('Riego (balance hídrico)', 'Últimos 7 días + 7 de pronóstico', [
      Text('ET0: ${_n(w['et0Mm7d'], ' mm')}   ·   Lluvia: ${_n(w['precipMm7d'], ' mm')}'),
      Text('Déficit: ${_n(w['deficitMm'], ' mm')}'),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: (suggested ? const Color(0xFFEA580C) : const Color(0xFF16A34A)).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20)),
        child: Text(
          suggested ? 'Riego recomendado ~${(w['suggestedMm'] as num).toStringAsFixed(0)} mm' : 'Sin déficit relevante',
          style: TextStyle(
            color: suggested ? const Color(0xFFEA580C) : const Color(0xFF16A34A),
            fontWeight: FontWeight.w600, fontSize: 13)),
      ),
    ]);
  }

  Widget _gddCard(Map<String, dynamic>? g) {
    if (g == null || (g['days'] as num? ?? 0) == 0) return const SizedBox.shrink();
    return _card('Grados-día (GDD)', 'Desde el inicio del ciclo', [
      Text('${(g['accumulated'] as num).toStringAsFixed(0)} °C·día',
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
      Text('Base ${(g['baseTempC'] as num).toStringAsFixed(0)} °C · ${g['days']} días acumulados',
          style: const TextStyle(color: Colors.grey)),
    ]);
  }

  Widget _diseaseCard(Map<String, dynamic>? d) {
    if (d == null) return const SizedBox.shrink();
    final level = d['level']?.toString() ?? 'none';
    final color = _sevColors[level] ?? Colors.grey;
    return _card('Riesgo de enfermedad', 'Últimas 48 h', [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
        child: Text(_diseaseLabels[level] ?? level, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
      ),
      const SizedBox(height: 6),
      Text(d['reason']?.toString() ?? '', style: const TextStyle(fontSize: 12, color: Colors.black87)),
    ]);
  }
}

// ---------------- Historial visual del lote (fotos de todos sus ciclos) ----------------
class PlotGalleryScreen extends ConsumerStatefulWidget {
  const PlotGalleryScreen({super.key, required this.plotId});
  final String plotId;

  @override
  ConsumerState<PlotGalleryScreen> createState() => _PlotGalleryScreenState();
}

class _PlotGalleryScreenState extends ConsumerState<PlotGalleryScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(farmRepoProvider).loadPlotPhotos(widget.plotId);
  }

  static const _sevColors = {
    'high': Color(0xFFDC2626), 'medium': Color(0xFFEA580C), 'low': Color(0xFFCA8A04), 'none': Color(0xFF16A34A),
  };
  static const _sevLabels = {'high': 'Alta', 'medium': 'Media', 'low': 'Baja', 'none': 'Sin incidencia'};

  String _fecha(String? iso) {
    final dt = DateTime.tryParse(iso ?? '');
    if (dt == null) return '';
    const mo = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    return '${dt.day} ${mo[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial visual')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final list = snap.data ?? [];
          if (list.isEmpty) {
            return const Center(child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('Aún no hay fotos de este lote. Se registran desde las observaciones.')));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            itemBuilder: (_, i) {
              final o = list[i];
              final a = o['analysis'] as Map<String, dynamic>?;
              final sev = a?['severity']?.toString();
              final color = _sevColors[sev] ?? Colors.grey;
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (o['photoUrl'] != null)
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      child: Image.network(o['photoUrl'], height: 200, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox(height: 60, child: Center(child: Icon(Icons.broken_image)))),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(_fecha(o['createdAt'] as String?), style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        Text('· ${o['crop'] ?? ''}', style: const TextStyle(color: Colors.grey)),
                        const Spacer(),
                        if (sev != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                            child: Text(_sevLabels[sev] ?? sev, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
                          ),
                      ]),
                      if ((o['note'] ?? '').toString().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(o['note'].toString(), style: const TextStyle(fontSize: 13)),
                      ],
                    ]),
                  ),
                ]),
              );
            },
          );
        },
      ),
    );
  }
}

// ---------------- Rentabilidad del lote / comparación de temporadas ----------------
class ProfitabilityScreen extends ConsumerStatefulWidget {
  const ProfitabilityScreen({super.key, required this.plotId});
  final String plotId;

  @override
  ConsumerState<ProfitabilityScreen> createState() => _ProfitabilityScreenState();
}

class _ProfitabilityScreenState extends ConsumerState<ProfitabilityScreen> {
  late Future<Map<String, dynamic>?> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(farmRepoProvider).loadProfitability(widget.plotId);
  }

  String _money(dynamic v) => (v as num? ?? 0).toStringAsFixed(2);

  Future<void> _shareWhatsApp(Map<String, dynamic> d, List<Map<String, dynamic>> cycles) async {
    final b = StringBuffer()
      ..writeln('📊 *Rentabilidad — ${d['plotName'] ?? 'Lote'}*')
      ..writeln('Área: ${(d['areaHa'] as num? ?? 0).toStringAsFixed(2)} ha · ${d['seasons'] ?? cycles.length} temporada(s)')
      ..writeln('Margen acumulado: ${_money(d['totalMargin'])}')
      ..writeln('Rend. promedio: ${(d['avgYieldPerHa'] as num? ?? 0).toStringAsFixed(1)} kg/ha')
      ..writeln('');
    for (final s in cycles) {
      b.writeln('• ${s['crop']}${s['start'] != null ? ' (${s['start']})' : ''}: '
          '${(s['yieldKg'] as num? ?? 0).toStringAsFixed(0)} kg · margen ${_money(s['margin'])}');
    }
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(b.toString())}');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rentabilidad del lote'),
        actions: [
          FutureBuilder<Map<String, dynamic>?>(
            future: _future,
            builder: (context, snap) {
              final d = snap.data;
              final cycles = ((d?['cycles']) as List?)?.cast<Map<String, dynamic>>() ?? [];
              if (d == null || cycles.isEmpty) return const SizedBox.shrink();
              return IconButton(
                icon: const Icon(Icons.share_outlined),
                tooltip: 'Compartir por WhatsApp',
                onPressed: () => _shareWhatsApp(d, cycles),
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final d = snap.data;
          final cycles = ((d?['cycles']) as List?)?.cast<Map<String, dynamic>>() ?? [];
          if (d == null || cycles.isEmpty) {
            return const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('Sin datos de temporadas para este lote.')));
          }
          final margin = (d['totalMargin'] as num?) ?? 0;
          return ListView(padding: const EdgeInsets.all(12), children: [
            Card(child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${d['plotName'] ?? 'Lote'} · ${(d['areaHa'] as num? ?? 0).toStringAsFixed(2)} ha',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 8),
                Wrap(spacing: 18, runSpacing: 8, children: [
                  _metric('Temporadas', '${d['seasons'] ?? cycles.length}'),
                  _metric('Margen acum.', _money(margin), color: margin >= 0 ? const Color(0xFF16A34A) : Colors.red.shade700),
                  _metric('Rend. prom.', '${(d['avgYieldPerHa'] as num? ?? 0).toStringAsFixed(1)} kg/ha'),
                  _metric('Costo prom.', '${(d['avgCostPerKg'] as num? ?? 0).toStringAsFixed(2)} /kg'),
                ]),
              ]),
            )),
            for (final s in cycles) _seasonCard(s),
          ]);
        },
      ),
    );
  }

  Widget _metric(String label, String value, {Color? color}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color)),
        ],
      );

  Widget _seasonCard(Map<String, dynamic> s) {
    final m = (s['margin'] as num?) ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(
              '${s['crop'] ?? ''}${s['variety'] != null ? ' · ${s['variety']}' : ''}',
              style: const TextStyle(fontWeight: FontWeight.w700))),
            Text(cycleStatusLabels[(s['status'] as num?)?.toInt() ?? 0],
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ]),
          if (s['start'] != null) Text(s['start'].toString(), style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 8),
          Wrap(spacing: 16, runSpacing: 6, children: [
            _metric('Rend.', '${(s['yieldKg'] as num? ?? 0).toStringAsFixed(0)} kg'),
            _metric('kg/ha', (s['yieldPerHa'] as num? ?? 0).toStringAsFixed(1)),
            _metric('Costo', _money(s['totalCost'])),
            _metric('Ingreso', _money(s['revenueEst'])),
            _metric('Margen', _money(m), color: m >= 0 ? const Color(0xFF16A34A) : Colors.red.shade700),
            _metric('\$/kg', (s['costPerKg'] as num? ?? 0).toStringAsFixed(2)),
          ]),
        ]),
      ),
    );
  }
}
