import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/notifications.dart';
import '../../core/providers.dart';
import '../cycles/plots_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../map/map_screen.dart';
import '../profile/profile_screen.dart';

/// Shell principal (no jornalero): Inicio (dashboard) + Fincas, con navegación inferior.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _index = 0;
  late Future<List<Farm>> _farms;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _farms = ref.read(farmRepoProvider).loadFarms();
    _scheduleReminders();
  }

  /// Programa recordatorios locales de las tareas asignadas al usuario.
  Future<void> _scheduleReminders() async {
    try {
      await NotificationService.instance.init();
      final tasks = await ref.read(taskRepoProvider).myTasks();
      await NotificationService.instance.scheduleTaskReminders(tasks);
    } catch (_) {/* sin red o sin permiso: se reintenta al sincronizar */}
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      await ref.read(syncServiceProvider).sync();
      _farms = ref.read(farmRepoProvider).loadFarms();
      _scheduleReminders();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sincronizado')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error de sincronización')));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(const ['Inicio', 'Mis fincas', 'Perfil'][_index]),
        actions: [
          if (_index != 2)
            IconButton(
              icon: _syncing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.sync),
              onPressed: _syncing ? null : _sync,
              tooltip: 'Sincronizar',
            ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [const DashboardBody(), _farmsBody(), const ProfileBody()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Inicio'),
          NavigationDestination(icon: Icon(Icons.landscape_outlined), selectedIcon: Icon(Icons.landscape), label: 'Fincas'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Perfil'),
        ],
      ),
    );
  }

  Widget _farmsBody() {
    return FutureBuilder<List<Farm>>(
      future: _farms,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        final farms = snap.data ?? [];
        if (farms.isEmpty) return const Center(child: Text('Aún no hay fincas.'));
        return ListView.separated(
          itemCount: farms.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final f = farms[i];
            return ListTile(
              leading: const Icon(Icons.landscape, color: Color(0xFF2F7A3A)),
              title: Text(f.name),
              subtitle: Text('${f.areaHa.toStringAsFixed(2)} ha'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  icon: const Icon(Icons.map_outlined),
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => MapScreen(farm: f))),
                ),
                const Icon(Icons.chevron_right),
              ]),
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => PlotsScreen(farm: f))),
            );
          },
        );
      },
    );
  }
}
