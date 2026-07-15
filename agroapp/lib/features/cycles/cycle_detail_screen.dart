import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/db/database.dart';
import '../../core/labels.dart';
import '../../core/providers.dart';

class CycleDetailScreen extends ConsumerWidget {
  const CycleDetailScreen({super.key, required this.cycle});
  final Cycle cycle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${cycle.crop} · ${cycleStatusLabels[cycle.status]}'),
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Etapas'),
            Tab(text: 'Monitoreo'),
            Tab(text: 'Observaciones'),
            Tab(text: 'Costos'),
          ]),
        ),
        body: TabBarView(children: [
          _StagesTab(cycleId: cycle.id),
          _PhenologyTab(cycleId: cycle.id),
          _ObservationsTab(cycleId: cycle.id),
          _CostsTab(cycleId: cycle.id),
        ]),
      ),
    );
  }
}

class _StagesTab extends ConsumerWidget {
  const _StagesTab({required this.cycleId});
  final String cycleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(localRepoProvider);
    return StreamBuilder<List<Stage>>(
      stream: repo.watchStages(cycleId),
      builder: (context, snap) {
        final stages = snap.data ?? [];
        if (stages.isEmpty) return const Center(child: Text('Sincroniza para ver las etapas.'));
        return ListView(
          children: [
            for (final s in stages)
              ExpansionTile(
                leading: CircleAvatar(child: Text('${s.kind + 1}')),
                title: Text(stageKindLabels[s.kind]),
                subtitle: Text(stageStatusLabels[s.status]),
                children: [_TasksList(stageId: s.id)],
              ),
          ],
        );
      },
    );
  }
}

class _TasksList extends ConsumerWidget {
  const _TasksList({required this.stageId});
  final String stageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(localRepoProvider);
    return StreamBuilder<List<Task>>(
      stream: repo.watchTasks(stageId),
      builder: (context, snap) {
        final tasks = snap.data ?? [];
        return Column(children: [
          for (final t in tasks)
            CheckboxListTile(
              dense: true,
              value: t.status == 2,
              title: Text(t.title),
              subtitle: Text(taskStatusLabels[t.status]),
              onChanged: (v) => repo.setTaskStatus(t.id, v == true ? 2 : 0),
            ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.add_task, color: Colors.green),
            title: const Text('Nueva tarea'),
            onTap: () async {
              final title = await _prompt(context, 'Nueva tarea', 'Título');
              if (title != null && title.isNotEmpty) await repo.createTask(stageId, title);
            },
          ),
        ]);
      },
    );
  }
}

const _phenoStages = ['Germinación', 'Vegetativo', 'Floración', 'Cuajado', 'Maduración', 'Senescencia'];

class _PhenologyTab extends ConsumerStatefulWidget {
  const _PhenologyTab({required this.cycleId});
  final String cycleId;
  @override
  ConsumerState<_PhenologyTab> createState() => _PhenologyTabState();
}

class _PhenologyTabState extends ConsumerState<_PhenologyTab> {
  late Future<List<Map<String, dynamic>>> _records;

  @override
  void initState() {
    super.initState();
    _records = ref.read(farmRepoProvider).loadPhenology(widget.cycleId);
  }

  void _reload() => setState(() => _records = ref.read(farmRepoProvider).loadPhenology(widget.cycleId));

  Future<void> _add() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _PhenologyDialog(),
    );
    if (result == null) return;
    try {
      await ref.read(farmRepoProvider).createPhenology(widget.cycleId, result);
      _reload();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo guardar')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _records,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final recs = snap.data ?? [];
          if (recs.isEmpty) return const Center(child: Text('Sin registros de monitoreo. Toca + para agregar.'));
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 6),
            children: [
              for (final r in recs)
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFFDCFCE7),
                      child: const Icon(Icons.eco, color: Color(0xFF166534)),
                    ),
                    title: Text('${_phenoStages[r['stage'] as int]} · ${r['recordedAt']}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text([
                      if (r['plantHeightCm'] != null) 'Altura: ${r['plantHeightCm']} cm',
                      if (r['pestIncidencePct'] != null) 'Plagas: ${r['pestIncidencePct']}%',
                      if (r['diseaseIncidencePct'] != null) 'Enfermedad: ${r['diseaseIncidencePct']}%',
                      if (r['notes'] != null && (r['notes'] as String).isNotEmpty) r['notes'],
                    ].join('  ·  ')),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Registrar'),
      ),
    );
  }
}

class _PhenologyDialog extends StatefulWidget {
  const _PhenologyDialog();
  @override
  State<_PhenologyDialog> createState() => _PhenologyDialogState();
}

class _PhenologyDialogState extends State<_PhenologyDialog> {
  int _stage = 0;
  DateTime _date = DateTime(2026, 7, 14);
  final _height = TextEditingController();
  final _pest = TextEditingController();
  final _disease = TextEditingController();
  final _notes = TextEditingController();

  double? _num(TextEditingController c) => c.text.trim().isEmpty ? null : double.tryParse(c.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Monitoreo fenológico'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today, size: 20),
            title: Text('Fecha: ${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}'),
            onTap: () async {
              final picked = await showDatePicker(
                context: context, initialDate: _date,
                firstDate: DateTime(2020), lastDate: DateTime(2035),
              );
              if (picked != null) setState(() => _date = picked);
            },
          ),
          DropdownButtonFormField<int>(
            initialValue: _stage,
            decoration: const InputDecoration(labelText: 'Etapa fenológica'),
            items: [for (var i = 0; i < _phenoStages.length; i++) DropdownMenuItem(value: i, child: Text(_phenoStages[i]))],
            onChanged: (v) => setState(() => _stage = v ?? 0),
          ),
          const SizedBox(height: 8),
          TextField(controller: _height, decoration: const InputDecoration(labelText: 'Altura (cm)'), keyboardType: TextInputType.number),
          TextField(controller: _pest, decoration: const InputDecoration(labelText: 'Incidencia de plagas (%)'), keyboardType: TextInputType.number),
          TextField(controller: _disease, decoration: const InputDecoration(labelText: 'Incidencia de enfermedad (%)'), keyboardType: TextInputType.number),
          TextField(controller: _notes, decoration: const InputDecoration(labelText: 'Notas')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(context, {
            'recordedAt': '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
            'stage': _stage,
            'plantHeightCm': _num(_height),
            'pestIncidencePct': _num(_pest),
            'diseaseIncidencePct': _num(_disease),
            'notes': _notes.text.trim(),
          }),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}

class _ObservationsTab extends ConsumerWidget {
  const _ObservationsTab({required this.cycleId});
  final String cycleId;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final picker = ImagePicker();
    final photo = await picker.pickImage(source: ImageSource.camera, maxWidth: 1600);
    if (!context.mounted) return;
    final note = await _prompt(context, 'Observación', 'Nota (opcional)');
    final userId = await ref.read(tokenStoreProvider).userId ?? '';
    await ref.read(localRepoProvider).createObservation(
          cycleId: cycleId,
          userId: userId,
          note: note,
          photoLocalPath: photo?.path,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(localRepoProvider);
    return Scaffold(
      body: StreamBuilder<List<Observation>>(
        stream: repo.watchObservations(cycleId),
        builder: (context, snap) {
          final obs = snap.data ?? [];
          if (obs.isEmpty) return const Center(child: Text('Sin observaciones. Toca + para agregar.'));
          return ListView(
            children: [
              for (final o in obs)
                ListTile(
                  leading: Icon(o.photoKey != null || o.photoLocalPath != null ? Icons.photo : Icons.note),
                  title: Text(o.note ?? '(sin nota)'),
                  subtitle: Text(o.dirty ? 'Pendiente de sincronizar' : 'Sincronizada'),
                  trailing: o.dirty ? const Icon(Icons.cloud_off, size: 18) : const Icon(Icons.cloud_done, size: 18),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _add(context, ref),
        child: const Icon(Icons.add_a_photo),
      ),
    );
  }
}

class _CostsTab extends ConsumerWidget {
  const _CostsTab({required this.cycleId});
  final String cycleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(localRepoProvider);
    return Scaffold(
      body: StreamBuilder<List<Cost>>(
        stream: repo.watchCosts(cycleId),
        builder: (context, snap) {
          final costs = snap.data ?? [];
          final total = costs.fold<double>(0, (s, c) => s + c.total);
          return Column(children: [
            if (costs.isNotEmpty)
              ListTile(title: const Text('Total'), trailing: Text(total.toStringAsFixed(2))),
            const Divider(height: 1),
            Expanded(
              child: ListView(children: [
                for (final c in costs)
                  ListTile(
                    leading: const Icon(Icons.attach_money),
                    title: Text(c.description ?? costKindLabels[c.kind]),
                    subtitle: Text('${c.quantity} × ${c.unitCost}'),
                    trailing: Text(c.total.toStringAsFixed(2)),
                  ),
              ]),
            ),
          ]);
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addCost(context, ref),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _addCost(BuildContext context, WidgetRef ref) async {
    final desc = TextEditingController();
    final qty = TextEditingController(text: '1');
    final unit = TextEditingController(text: '0');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo costo'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: desc, decoration: const InputDecoration(labelText: 'Descripción')),
          TextField(controller: qty, decoration: const InputDecoration(labelText: 'Cantidad'), keyboardType: TextInputType.number),
          TextField(controller: unit, decoration: const InputDecoration(labelText: 'Costo unitario'), keyboardType: TextInputType.number),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Agregar')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(localRepoProvider).createCost(
            cycleId: cycleId,
            kind: 3,
            description: desc.text.trim(),
            quantity: double.tryParse(qty.text) ?? 1,
            unitCost: double.tryParse(unit.text) ?? 0,
          );
    }
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
