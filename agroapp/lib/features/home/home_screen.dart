import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/providers.dart';
import '../auth/login_screen.dart';
import '../cycles/plots_screen.dart';
import '../map/map_screen.dart';

/// Lista de fincas de la organización. Botón de sincronización manual.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  late Future<List<Farm>> _farms;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _farms = ref.read(farmRepoProvider).loadFarms();
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      await ref.read(syncServiceProvider).sync();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sincronizado')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error de sincronización')));
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _logout() async {
    await ref.read(tokenStoreProvider).clear();
    if (mounted) {
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const LoginScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis fincas'),
        actions: [
          IconButton(
            icon: _syncing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
            onPressed: _syncing ? null : _sync,
            tooltip: 'Sincronizar',
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout, tooltip: 'Salir'),
        ],
      ),
      body: FutureBuilder<List<Farm>>(
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
                leading: const Icon(Icons.landscape, color: Colors.green),
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
      ),
    );
  }
}
