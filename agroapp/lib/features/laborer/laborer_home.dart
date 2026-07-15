import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers.dart';
import '../auth/login_screen.dart';

/// Pantalla del jornalero: solo sus tareas asignadas + registro de observaciones.
class LaborerHome extends ConsumerStatefulWidget {
  const LaborerHome({super.key});
  @override
  ConsumerState<LaborerHome> createState() => _LaborerHomeState();
}

class _LaborerHomeState extends ConsumerState<LaborerHome> {
  late Future<List<Map<String, dynamic>>> _tasks;
  static const _statusLabels = ['Por hacer', 'En progreso', 'Hecho'];
  static const _stageLabels = [
    'Planificación', 'Prep. suelo', 'Siembra', 'Manejo', 'Monitoreo', 'Cosecha', 'Poscosecha', 'Evaluación'
  ];

  @override
  void initState() {
    super.initState();
    _tasks = ref.read(taskRepoProvider).myTasks();
  }

  void _reload() => setState(() => _tasks = ref.read(taskRepoProvider).myTasks());

  Future<void> _setStatus(String taskId, int status) async {
    await ref.read(taskRepoProvider).setStatus(taskId, status);
    _reload();
  }

  Future<void> _logout() async {
    await ref.read(tokenStoreProvider).clear();
    if (mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  Future<void> _addObservation(String cycleId) async {
    final noteCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva observación'),
        content: TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'Nota'), maxLines: 3),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (result != true) return;

    try {
      final repo = ref.read(taskRepoProvider);
      final obsId = await repo.createObservation(cycleId, noteCtrl.text.trim());
      final photo = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 70);
      if (photo != null) await repo.uploadPhoto(obsId, photo.path);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Observación registrada')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo registrar')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis asignaciones'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _reload, tooltip: 'Actualizar'),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout, tooltip: 'Salir'),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _tasks,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          final tasks = snap.data ?? [];
          if (tasks.isEmpty) return const Center(child: Text('No tienes tareas asignadas.'));
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.separated(
              itemCount: tasks.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final t = tasks[i];
                final status = t['status'] as int;
                return ListTile(
                  title: Text(t['title'], style: TextStyle(
                    decoration: status == 2 ? TextDecoration.lineThrough : null, fontWeight: FontWeight.w600)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (t['description'] != null) Text(t['description']),
                      Text('${t['crop']} · ${_stageLabels[t['stageKind'] as int]}'
                          '${t['dueDate'] != null ? ' · 📅 ${t['dueDate']}' : ''}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      icon: const Icon(Icons.add_a_photo_outlined, color: Colors.green),
                      tooltip: 'Observación',
                      onPressed: () => _addObservation(t['cropCycleId']),
                    ),
                    DropdownButton<int>(
                      value: status,
                      underline: const SizedBox(),
                      items: [for (var s = 0; s < 3; s++) DropdownMenuItem(value: s, child: Text(_statusLabels[s]))],
                      onChanged: (v) => v == null ? null : _setStatus(t['id'], v),
                    ),
                  ]),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
