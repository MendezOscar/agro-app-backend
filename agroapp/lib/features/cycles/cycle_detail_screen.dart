import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/db/database.dart';
import '../../core/labels.dart';
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
    await ref.read(localRepoProvider).createObservation(
        cycleId: widget.cycleId, userId: userId, note: note, photoLocalPath: photo?.path);
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
