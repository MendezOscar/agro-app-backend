import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/ui.dart';

/// Análisis de suelo/agua de un lote (online).
class PlotAnalysisScreen extends ConsumerStatefulWidget {
  const PlotAnalysisScreen({super.key, required this.plotId, required this.plotName});
  final String plotId;
  final String plotName;
  @override
  ConsumerState<PlotAnalysisScreen> createState() => _PlotAnalysisScreenState();
}

class _PlotAnalysisScreenState extends ConsumerState<PlotAnalysisScreen> {
  late Future<List<Map<String, dynamic>>> _items;
  late Future<Map<String, dynamic>?> _fert;
  static const _kindLabels = ['Suelo', 'Agua'];
  static const _fertColors = {'low': Color(0xFFDC2626), 'ok': Color(0xFF16A34A), 'high': Color(0xFFEA580C)};
  static const _fertLabels = {'low': 'Bajo', 'ok': 'Adecuado', 'high': 'Alto'};

  @override
  void initState() {
    super.initState();
    _items = ref.read(farmRepoProvider).loadAnalyses(widget.plotId);
    _fert = ref.read(farmRepoProvider).loadFertilization(widget.plotId);
  }

  void _reload() => setState(() {
        _items = ref.read(farmRepoProvider).loadAnalyses(widget.plotId);
        _fert = ref.read(farmRepoProvider).loadFertilization(widget.plotId);
      });

  Widget _fertCard() => FutureBuilder<Map<String, dynamic>?>(
        future: _fert,
        builder: (context, snap) {
          final d = snap.data;
          if (d == null || d['hasAnalysis'] != true) return const SizedBox.shrink();
          final items = ((d['items']) as List?)?.cast<Map<String, dynamic>>() ?? [];
          return Card(
            color: const Color(0xFFF6FAF6),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.eco, color: Color(0xFF2F7A3A), size: 20),
                  const SizedBox(width: 6),
                  const Expanded(child: Text('Plan de fertilización', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                  if (d['sampledAt'] != null) Text('muestra ${d['sampledAt']}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ]),
                const SizedBox(height: 8),
                for (final it in items) ...[
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 120, child: Text('${it['nutrient']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                    Builder(builder: (_) {
                      final st = it['status']?.toString() ?? 'ok';
                      final color = _fertColors[st] ?? Colors.grey;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                        child: Text(_fertLabels[st] ?? st, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 11)),
                      );
                    }),
                  ]),
                  Padding(
                    padding: const EdgeInsets.only(left: 0, top: 2, bottom: 8),
                    child: Text('${it['recommendation']}', style: const TextStyle(fontSize: 12.5, color: Colors.black87)),
                  ),
                ],
                if (d['note'] != null) Text('${d['note']}', style: const TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic)),
              ]),
            ),
          );
        },
      );

  Future<void> _add() async {
    final data = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const _AnalysisDialog());
    if (data == null) return;
    try {
      await ref.read(farmRepoProvider).createAnalysis(widget.plotId, data);
      _reload();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Análisis · ${widget.plotName}')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _items,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return ErrorState(error: snap.error, onRetry: _reload);
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return const EmptyState(icon: Icons.science_outlined, message: 'Sin análisis.\nToca "Análisis" para registrar el primero.');
          }
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 6),
            children: [
              _fertCard(),
              for (final a in items)
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFFDCFCE7),
                      child: Icon(a['kind'] == 1 ? Icons.water_drop : Icons.terrain, color: const Color(0xFF166534)),
                    ),
                    title: Text('${_kindLabels[a['kind'] as int]}${a['sampledAt'] != null ? ' · ${a['sampledAt']}' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text([
                      if (a['ph'] != null) 'pH: ${a['ph']}',
                      if (a['n'] != null) 'N: ${a['n']}',
                      if (a['p'] != null) 'P: ${a['p']}',
                      if (a['k'] != null) 'K: ${a['k']}',
                      if (a['organicMatter'] != null) 'M.O.: ${a['organicMatter']}%',
                      if (a['texture'] != null) 'Textura: ${a['texture']}',
                    ].join('  ·  ')),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add, icon: const Icon(Icons.add), label: const Text('Análisis'),
      ),
    );
  }
}

class _AnalysisDialog extends StatefulWidget {
  const _AnalysisDialog();
  @override
  State<_AnalysisDialog> createState() => _AnalysisDialogState();
}

class _AnalysisDialogState extends State<_AnalysisDialog> {
  int _kind = 0;
  DateTime? _date;
  final _ph = TextEditingController();
  final _n = TextEditingController();
  final _p = TextEditingController();
  final _k = TextEditingController();
  final _om = TextEditingController();
  final _texture = TextEditingController();

  double? _num(TextEditingController c) => c.text.trim().isEmpty ? null : double.tryParse(c.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo análisis'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<int>(
            initialValue: _kind,
            decoration: const InputDecoration(labelText: 'Tipo'),
            items: const [DropdownMenuItem(value: 0, child: Text('Suelo')), DropdownMenuItem(value: 1, child: Text('Agua'))],
            onChanged: (v) => setState(() => _kind = v ?? 0),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today, size: 20),
            title: Text(_date == null ? 'Fecha de muestreo' : _date!.toIso8601String().substring(0, 10)),
            onTap: () async {
              final picked = await showDatePicker(
                context: context, initialDate: DateTime(2026, 7, 14),
                firstDate: DateTime(2020), lastDate: DateTime(2035));
              if (picked != null) setState(() => _date = picked);
            },
          ),
          const SizedBox(height: 6),
          TextField(controller: _ph, decoration: const InputDecoration(labelText: 'pH'), keyboardType: TextInputType.number),
          const SizedBox(height: 14),
          TextField(controller: _n, decoration: const InputDecoration(labelText: 'Nitrógeno (N)'), keyboardType: TextInputType.number),
          const SizedBox(height: 14),
          TextField(controller: _p, decoration: const InputDecoration(labelText: 'Fósforo (P)'), keyboardType: TextInputType.number),
          const SizedBox(height: 14),
          TextField(controller: _k, decoration: const InputDecoration(labelText: 'Potasio (K)'), keyboardType: TextInputType.number),
          const SizedBox(height: 14),
          TextField(controller: _om, decoration: const InputDecoration(labelText: 'Materia orgánica (%)'), keyboardType: TextInputType.number),
          const SizedBox(height: 14),
          TextField(controller: _texture, decoration: const InputDecoration(labelText: 'Textura')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(context, {
            'kind': _kind,
            'ph': _num(_ph), 'n': _num(_n), 'p': _num(_p), 'k': _num(_k),
            'organicMatter': _num(_om),
            'texture': _texture.text.trim().isEmpty ? null : _texture.text.trim(),
            'sampledAt': _date?.toIso8601String().substring(0, 10),
          }),
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
