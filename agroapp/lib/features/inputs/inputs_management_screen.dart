import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/ui.dart';

const _kindLabels = ['Semilla', 'Fertilizante', 'Plaguicida', 'Maquinaria', 'Mano de obra'];
const _leaf = Color(0xFF2F7A3A);

/// Catálogo de insumos (crear/editar/eliminar + entrada de stock).
class InputsManagementScreen extends ConsumerStatefulWidget {
  const InputsManagementScreen({super.key});
  @override
  ConsumerState<InputsManagementScreen> createState() => _InputsManagementScreenState();
}

class _InputsManagementScreenState extends ConsumerState<InputsManagementScreen> {
  late Future<List<Map<String, dynamic>>> _items;

  @override
  void initState() {
    super.initState();
    _items = ref.read(farmRepoProvider).loadInputs();
  }

  void _reload() => setState(() => _items = ref.read(farmRepoProvider).loadInputs());

  void _snack(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(m), backgroundColor: error ? Colors.red.shade700 : null));
  }

  Future<void> _createOrEdit([Map<String, dynamic>? existing]) async {
    final data = await showDialog<Map<String, dynamic>>(
      context: context, builder: (_) => _InputDialog(existing: existing));
    if (data == null) return;
    try {
      if (existing == null) {
        await ref.read(farmRepoProvider).createInput(data);
        _snack('Insumo creado');
      } else {
        await ref.read(farmRepoProvider).updateInput(existing['id'] as String, data);
        _snack('Insumo actualizado');
      }
      _reload();
    } catch (e) {
      _snack(friendlyError(e), error: true);
    }
  }

  Future<void> _restock(Map<String, dynamic> i) async {
    final qty = await showDialog<double>(context: context, builder: (_) => _RestockDialog(input: i));
    if (qty == null) return;
    try {
      await ref.read(farmRepoProvider).restockInput(i['id'] as String, qty);
      _snack('Entrada registrada');
      _reload();
    } catch (e) {
      _snack(friendlyError(e), error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar insumo'),
        content: Text('¿Eliminar "${i['name']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(farmRepoProvider).deleteInput(i['id'] as String);
      _snack('Insumo eliminado');
      _reload();
    } catch (e) {
      _snack(friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Catálogo de insumos')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createOrEdit(), icon: const Icon(Icons.add), label: const Text('Nuevo')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _items,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return ErrorState(error: snap.error, onRetry: _reload);
          final items = snap.data ?? [];
          if (items.isEmpty) {
            return const EmptyState(icon: Icons.inventory_2_outlined, message: 'Sin insumos.\nToca "Nuevo" para agregar el primero.');
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 6),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, idx) {
              final i = items[idx];
              final stock = (i['stockQty'] as num? ?? 0).toDouble();
              final min = (i['minStock'] as num? ?? 0).toDouble();
              final low = min > 0 && stock <= min;
              return ListTile(
                leading: CircleAvatar(backgroundColor: const Color(0x142F7A3A), child: Text('${i['name']}'.isNotEmpty ? '${i['name']}'[0].toUpperCase() : '?', style: const TextStyle(color: _leaf, fontWeight: FontWeight.bold))),
                title: Text(i['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${_kindLabels[i['kind'] as int]} · \$${(i['unitCost'] as num).toStringAsFixed(2)}/${i['unit']}\n'
                    'Stock: ${stock.toStringAsFixed(2)} ${i['unit']}${low ? '  ⚠️ bajo' : ''}',
                    style: TextStyle(color: low ? Colors.red.shade700 : Colors.black54)),
                isThreeLine: true,
                trailing: PopupMenuButton<String>(
                  onSelected: (v) => v == 'restock' ? _restock(i) : v == 'edit' ? _createOrEdit(i) : _delete(i),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'restock', child: ListTile(leading: Icon(Icons.add_box_outlined), title: Text('Entrada'))),
                    PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Editar'))),
                    PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline, color: Colors.red), title: Text('Eliminar'))),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _InputDialog extends StatefulWidget {
  const _InputDialog({this.existing});
  final Map<String, dynamic>? existing;
  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  late final _name = TextEditingController(text: widget.existing?['name'] ?? '');
  late final _unit = TextEditingController(text: widget.existing?['unit'] ?? '');
  late final _cost = TextEditingController(text: (widget.existing?['unitCost'] ?? 0).toString());
  late final _stock = TextEditingController(text: (widget.existing?['stockQty'] ?? 0).toString());
  late final _min = TextEditingController(text: (widget.existing?['minStock'] ?? 0).toString());
  late int _kind = (widget.existing?['kind'] as int?) ?? 1;
  String? _err;

  void _submit() {
    final cost = double.tryParse(_cost.text.trim());
    final stock = double.tryParse(_stock.text.trim());
    final min = double.tryParse(_min.text.trim());
    if (_name.text.trim().isEmpty) { setState(() => _err = 'El nombre es obligatorio.'); return; }
    if (_unit.text.trim().isEmpty) { setState(() => _err = 'La unidad es obligatoria (kg, L, hora…).'); return; }
    if (cost == null || cost < 0 || stock == null || stock < 0 || min == null || min < 0) {
      setState(() => _err = 'Los valores numéricos no pueden ser negativos.'); return;
    }
    Navigator.pop(context, {
      'name': _name.text.trim(), 'kind': _kind, 'unit': _unit.text.trim(),
      'unitCost': cost, 'stockQty': stock, 'minStock': min,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Nuevo insumo' : 'Editar insumo'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre')),
        const SizedBox(height: 14),
        DropdownButtonFormField<int>(
          initialValue: _kind,
          decoration: const InputDecoration(labelText: 'Tipo'),
          items: [for (var i = 0; i < _kindLabels.length; i++) DropdownMenuItem(value: i, child: Text(_kindLabels[i]))],
          onChanged: (v) => setState(() => _kind = v ?? 1),
        ),
        const SizedBox(height: 14),
        TextField(controller: _unit, decoration: const InputDecoration(labelText: 'Unidad (kg, L, hora…)')),
        const SizedBox(height: 14),
        TextField(controller: _cost, decoration: const InputDecoration(labelText: 'Costo unitario'), keyboardType: TextInputType.number),
        const SizedBox(height: 14),
        TextField(controller: _stock, decoration: const InputDecoration(labelText: 'Stock actual'), keyboardType: TextInputType.number),
        const SizedBox(height: 14),
        TextField(controller: _min, decoration: const InputDecoration(labelText: 'Stock mínimo (alerta)'), keyboardType: TextInputType.number),
        if (_err != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_err!, style: const TextStyle(color: Colors.red, fontSize: 13))),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _submit, child: Text(widget.existing == null ? 'Crear' : 'Guardar')),
      ],
    );
  }
}

class _RestockDialog extends StatefulWidget {
  const _RestockDialog({required this.input});
  final Map<String, dynamic> input;
  @override
  State<_RestockDialog> createState() => _RestockDialogState();
}

class _RestockDialogState extends State<_RestockDialog> {
  final _qty = TextEditingController();
  @override
  Widget build(BuildContext context) {
    final stock = (widget.input['stockQty'] as num? ?? 0).toDouble();
    final qty = double.tryParse(_qty.text.trim()) ?? 0;
    return AlertDialog(
      title: const Text('Entrada de inventario'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('${widget.input['name']} · ${widget.input['unit']}', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        TextField(controller: _qty, autofocus: true, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Cantidad a agregar'),
            onChanged: (_) => setState(() {})),
        const SizedBox(height: 8),
        Align(alignment: Alignment.centerLeft, child: Text('Stock: ${stock.toStringAsFixed(2)} → ${(stock + qty).toStringAsFixed(2)}', style: const TextStyle(color: Colors.black54))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () {
          final n = double.tryParse(_qty.text.trim());
          if (n == null || n == 0) return;
          Navigator.pop(context, n);
        }, child: const Text('Agregar')),
      ],
    );
  }
}
