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
        return DefaultTabController(
          length: stages.isEmpty ? 1 : stages.length,
          child: Scaffold(
            appBar: AppBar(
              title: Text('${cycle.crop} · ${cycleStatusLabels[cycle.status]}'),
              actions: [
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
              for (final i in widget.inputs) DropdownMenuItem(value: i['id'] as String, child: Text('${i['name']} (${i['unit']})')),
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
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, {
          'kind': _kind, 'inputId': _inputId,
          'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
          'quantity': double.tryParse(_qty.text) ?? 1, 'unitCost': double.tryParse(_unit.text) ?? 0,
        }), child: const Text('Agregar')),
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
class ObservationsScreen extends ConsumerWidget {
  const ObservationsScreen({super.key, required this.cycleId});
  final String cycleId;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final photo = await ImagePicker().pickImage(source: ImageSource.camera, maxWidth: 1600);
    if (!context.mounted) return;
    final note = await _prompt(context, 'Observación', 'Nota (opcional)');
    final userId = await ref.read(tokenStoreProvider).userId ?? '';
    await ref.read(localRepoProvider).createObservation(cycleId: cycleId, userId: userId, note: note, photoLocalPath: photo?.path);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(localRepoProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Observaciones')),
      body: StreamBuilder<List<Observation>>(
        stream: repo.watchObservations(cycleId),
        builder: (context, snap) {
          final obs = snap.data ?? [];
          if (obs.isEmpty) return const Center(child: Text('Sin observaciones. Toca + para agregar.'));
          return ListView(children: [
            for (final o in obs)
              Card(child: ListTile(
                leading: Icon(o.photoKey != null || o.photoLocalPath != null ? Icons.photo : Icons.note),
                title: Text(o.note ?? '(sin nota)'),
                subtitle: Text(o.dirty ? 'Pendiente de sincronizar' : 'Sincronizada'),
                trailing: Icon(o.dirty ? Icons.cloud_off : Icons.cloud_done, size: 18),
              )),
          ]);
        },
      ),
      floatingActionButton: FloatingActionButton(onPressed: () => _add(context, ref), child: const Icon(Icons.add_a_photo)),
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
