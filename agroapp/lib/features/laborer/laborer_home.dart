import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/notifications.dart';
import '../../core/providers.dart';
import '../../core/ui.dart';
import '../profile/profile_screen.dart';

/// Pantalla del jornalero: solo sus tareas asignadas + registro de observaciones.
class LaborerHome extends ConsumerStatefulWidget {
  const LaborerHome({super.key});
  @override
  ConsumerState<LaborerHome> createState() => _LaborerHomeState();
}

class _LaborerHomeState extends ConsumerState<LaborerHome> {
  late Future<List<Map<String, dynamic>>> _tasks;
  int _tab = 0;
  DateTime _day = DateTime(2026, 7, 15); // día seleccionado en el carrusel
  static const _statusLabels = ['Por hacer', 'En progreso', 'Hecho'];
  static const _stageLabels = [
    'Planificación', 'Prep. suelo', 'Siembra', 'Manejo', 'Monitoreo', 'Cosecha', 'Poscosecha', 'Evaluación'
  ];
  static const _weekdays = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
  static const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

  DateTime get _today => DateTime(2026, 7, 15);
  DateTime get _minDay => _today.subtract(const Duration(days: 30));
  DateTime get _maxDay => _today.add(const Duration(days: 30));
  String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _tasks = ref.read(taskRepoProvider).myTasks();
    // Programa recordatorios locales a partir de las tareas cargadas.
    _tasks.then((list) => NotificationService.instance.scheduleTaskReminders(list)).catchError((_) {});
  }

  void _reload() => setState(_load);

  Future<void> _setStatus(String taskId, int status) async {
    await ref.read(taskRepoProvider).setStatus(taskId, status);
    _reload();
  }

  void _shiftDay(int delta) {
    final next = _day.add(Duration(days: delta));
    if (next.isBefore(_minDay) || next.isAfter(_maxDay)) return;
    setState(() => _day = next);
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

  Widget _dayCarousel() {
    final wd = _weekdays[_day.weekday - 1];
    final label = _day == _today
        ? 'Hoy'
        : (_day == _today.subtract(const Duration(days: 1)) ? 'Ayer' : wd[0].toUpperCase() + wd.substring(1));
    final canPrev = !_day.subtract(const Duration(days: 1)).isBefore(_minDay);
    final canNext = !_day.add(const Duration(days: 1)).isAfter(_maxDay);
    Widget arrow(IconData icon, bool enabled, VoidCallback onTap) => Material(
          color: enabled ? Colors.white.withValues(alpha: 0.18) : Colors.transparent,
          shape: const CircleBorder(),
          child: IconButton(
            icon: Icon(icon, color: enabled ? Colors.white : Colors.white38),
            onPressed: enabled ? onTap : null,
          ),
        );
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF2F7A3A), Color(0xFF1F5A2A)]),
        boxShadow: [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3))],
      ),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
      child: Row(children: [
        arrow(Icons.chevron_left, canPrev, () => _shiftDay(-1)),
        Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              final p = await showDatePicker(context: context, initialDate: _day, firstDate: _minDay, lastDate: _maxDay);
              if (p != null) setState(() => _day = DateTime(p.year, p.month, p.day));
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 22, color: Colors.white)),
                const SizedBox(height: 2),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.event, size: 15, color: Colors.white70),
                  const SizedBox(width: 5),
                  Text('${_day.day} ${_months[_day.month - 1]} ${_day.year}',
                      style: const TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600)),
                ]),
              ]),
            ),
          ),
        ),
        arrow(Icons.chevron_right, canNext, () => _shiftDay(1)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tab == 0 ? 'Mis asignaciones' : 'Perfil'),
        actions: [
          if (_tab == 0) IconButton(icon: const Icon(Icons.refresh), onPressed: _reload, tooltip: 'Actualizar'),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment), label: 'Tareas'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Perfil'),
        ],
      ),
      body: IndexedStack(index: _tab, children: [
        _tasksTab(),
        const ProfileBody(),
      ]),
    );
  }

  Widget _tasksTab() {
    return Column(children: [
        _dayCarousel(),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _tasks,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) return ErrorState(error: snap.error, onRetry: _reload);
              final all = snap.data ?? [];
              final sel = _ymd(_day);
              // Tareas del día seleccionado + las sin fecha (siempre visibles).
              final tasks = all.where((t) => t['dueDate'] == sel || t['dueDate'] == null).toList();
              if (tasks.isEmpty) {
                return RefreshIndicator(
                  onRefresh: () async => _reload(),
                  child: ListView(children: const [
                    SizedBox(height: 120),
                    Center(child: Text('Sin tareas para este día.', style: TextStyle(color: Colors.black54))),
                  ]),
                );
              }
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
        ),
      ]);
  }
}
