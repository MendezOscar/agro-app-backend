import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/labels.dart';
import '../../core/providers.dart';
import 'cycle_detail_screen.dart';

/// Lotes de una finca y, por lote, sus ciclos de cosecha.
class PlotsScreen extends ConsumerStatefulWidget {
  const PlotsScreen({super.key, required this.farm});
  final Farm farm;
  @override
  ConsumerState<PlotsScreen> createState() => _PlotsScreenState();
}

class _PlotsScreenState extends ConsumerState<PlotsScreen> {
  late Future<List<Plot>> _plots;

  @override
  void initState() {
    super.initState();
    _plots = ref.read(farmRepoProvider).loadPlots(widget.farm.id);
  }

  Future<void> _newCycle(Plot plot) async {
    final crop = await _promptCrop();
    if (crop == null || crop.isEmpty) return;
    await ref.read(farmRepoProvider).createCycle({'plotId': plot.id, 'crop': crop});
    await ref.read(syncServiceProvider).sync();
    setState(() {});
  }

  Future<String?> _promptCrop() {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo ciclo'),
        content: TextField(controller: c, decoration: const InputDecoration(labelText: 'Cultivo (ej. Maíz)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Crear')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.farm.name)),
      body: FutureBuilder<List<Plot>>(
        future: _plots,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final plots = snap.data ?? [];
          if (plots.isEmpty) return const Center(child: Text('Esta finca no tiene lotes.'));
          return ListView(
            children: [
              for (final plot in plots) _PlotTile(plot: plot, onNewCycle: () => _newCycle(plot)),
            ],
          );
        },
      ),
    );
  }
}

class _PlotTile extends ConsumerWidget {
  const _PlotTile({required this.plot, required this.onNewCycle});
  final Plot plot;
  final VoidCallback onNewCycle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cyclesFuture = ref.read(farmRepoProvider).loadCycles(plot.id);
    return ExpansionTile(
      leading: const Icon(Icons.grid_4x4, color: Colors.brown),
      title: Text(plot.name),
      subtitle: Text('${plot.areaHa.toStringAsFixed(2)} ha · ${plot.soilType ?? "—"}'),
      children: [
        FutureBuilder<List<Cycle>>(
          future: cyclesFuture,
          builder: (context, snap) {
            final cycles = snap.data ?? [];
            return Column(
              children: [
                for (final c in cycles)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.eco),
                    title: Text(c.crop),
                    subtitle: Text(cycleStatusLabels[c.status]),
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => CycleDetailScreen(cycle: c))),
                  ),
                ListTile(
                  leading: const Icon(Icons.add, color: Colors.green),
                  title: const Text('Nuevo ciclo'),
                  onTap: onNewCycle,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
