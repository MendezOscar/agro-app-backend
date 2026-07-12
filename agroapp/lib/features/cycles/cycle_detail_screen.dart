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
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${cycle.crop} · ${cycleStatusLabels[cycle.status]}'),
          bottom: const TabBar(tabs: [
            Tab(text: 'Etapas'),
            Tab(text: 'Observaciones'),
            Tab(text: 'Costos'),
          ]),
        ),
        body: TabBarView(children: [
          _StagesTab(cycleId: cycle.id),
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
