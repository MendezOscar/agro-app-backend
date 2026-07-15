import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../auth/login_screen.dart';

const _roleLabels = {
  'Owner': 'Dueño',
  'AgronomistManager': 'Ingeniero agrónomo',
  'AgronomistWorker': 'Técnico de campo',
  'Laborer': 'Jornalero',
};
const _leaf = Color(0xFF2F7A3A);
const _leafDark = Color(0xFF1F5A2A);

/// Perfil del usuario en sesión. Se usa como pestaña inferior (sin Scaffold propio).
class ProfileBody extends ConsumerWidget {
  const ProfileBody({super.key});

  Future<Map<String, String?>> _load(WidgetRef ref) async {
    final store = ref.read(tokenStoreProvider);
    return {
      'name': await store.fullName,
      'role': await store.role,
      'email': await store.email,
    };
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    await ref.read(tokenStoreProvider).clear();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<Map<String, String?>>(
      future: _load(ref),
      builder: (context, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final name = (snap.data!['name'] ?? '').trim();
        final role = snap.data!['role'] ?? '';
        final email = (snap.data!['email'] ?? '').trim();
        final roleLabel = _roleLabels[role] ?? role;
        final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
        final canManage = role == 'Owner' || role == 'AgronomistManager';

        return ListView(
          padding: EdgeInsets.zero,
          children: [
            // Cabecera con degradado
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [_leaf, _leafDark], begin: Alignment.topLeft, end: Alignment.bottomRight),
              ),
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
              child: Column(children: [
                CircleAvatar(
                  radius: 46,
                  backgroundColor: Colors.white,
                  child: Text(initial, style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: _leaf)),
                ),
                const SizedBox(height: 14),
                Text(name.isEmpty ? 'Usuario' : name,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(email, style: const TextStyle(color: Colors.white70, fontSize: 14)),
                ],
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.22), borderRadius: BorderRadius.circular(20)),
                  child: Text(roleLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ]),
            ),
            const SizedBox(height: 12),

            // Opciones
            _tile(
              icon: Icons.lock_outline, color: _leaf,
              title: 'Cambiar contraseña',
              subtitle: 'Actualiza tu clave de acceso',
              onTap: () => showDialog(context: context, builder: (_) => const _ChangePasswordDialog()),
            ),
            if (canManage)
              _tile(
                icon: Icons.group_outlined, color: const Color(0xFF2C89C9),
                title: 'Gestión de usuarios',
                subtitle: 'Equipo de tu organización',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UsersManagementScreen())),
              ),
            _tile(
              icon: Icons.logout, color: Colors.red,
              title: 'Cerrar sesión',
              onTap: () => _logout(context, ref),
            ),
          ],
        );
      },
    );
  }

  Widget _tile({required IconData icon, required Color color, required String title, String? subtitle, required VoidCallback onTap}) {
    return Card(
      margin: const EdgeInsets.fromLTRB(14, 6, 14, 0),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, color: color)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: subtitle != null ? Text(subtitle) : null,
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

// ---------------- Cambiar contraseña ----------------
class _ChangePasswordDialog extends ConsumerStatefulWidget {
  const _ChangePasswordDialog();
  @override
  ConsumerState<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<_ChangePasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (_current.text.isEmpty || _next.text.length < 6) {
      setState(() => _error = 'La nueva contraseña debe tener al menos 6 caracteres.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(authRepoProvider).changePassword(_current.text, _next.text);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Contraseña actualizada')));
      }
    } catch (_) {
      setState(() { _busy = false; _error = 'No se pudo cambiar (verifica la contraseña actual).'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cambiar contraseña'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: _current, obscureText: true, decoration: const InputDecoration(labelText: 'Contraseña actual')),
        const SizedBox(height: 14),
        TextField(controller: _next, obscureText: true, decoration: const InputDecoration(labelText: 'Nueva contraseña')),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13))),
      ]),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Guardar'),
        ),
      ],
    );
  }
}

// ---------------- Gestión de usuarios (Owner/Manager) ----------------
class UsersManagementScreen extends ConsumerStatefulWidget {
  const UsersManagementScreen({super.key});
  @override
  ConsumerState<UsersManagementScreen> createState() => _UsersManagementScreenState();
}

class _UsersManagementScreenState extends ConsumerState<UsersManagementScreen> {
  late Future<List<Map<String, dynamic>>> _users;
  static const _roleNames = ['Dueño', 'Ingeniero agrónomo', 'Técnico de campo', 'Jornalero'];

  @override
  void initState() {
    super.initState();
    _users = ref.read(farmRepoProvider).loadTeam();
  }

  void _reload() => setState(() => _users = ref.read(farmRepoProvider).loadTeam());

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      duration: Duration(seconds: error ? 5 : 2),
      backgroundColor: error ? Colors.red.shade700 : null));
  }

  Future<void> _create() async {
    final data = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const _CreateUserDialog());
    if (data == null) return;
    try {
      await ref.read(farmRepoProvider).createUser(data['email'], data['fullName'], data['password'], data['role']);
      _snack('Usuario creado');
      _reload();
    } catch (e) {
      _snack(e.toString(), error: true);
    }
  }

  Future<void> _edit(Map<String, dynamic> u) async {
    final data = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _EditUserDialog(fullName: (u['fullName'] as String?) ?? '', role: u['role'] as int),
    );
    if (data == null) return;
    try {
      await ref.read(farmRepoProvider).updateUser(u['id'] as String, data['fullName'], data['role']);
      _snack('Usuario actualizado');
      _reload();
    } catch (e) {
      _snack(e.toString(), error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> u) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar usuario'),
        content: Text('¿Eliminar a ${u['fullName']}? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(farmRepoProvider).deleteUser(u['id'] as String);
      _snack('Usuario eliminado');
      _reload();
    } catch (e) {
      _snack(e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Gestión de usuarios')),
      floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.person_add), label: const Text('Nuevo')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _users,
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final users = snap.data!;
          if (users.isEmpty) return const Center(child: Text('Sin usuarios. Toca "Nuevo" para agregar.'));
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: users.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final u = users[i];
              final role = u['role'] as int;
              final name = (u['fullName'] as String?)?.trim() ?? '';
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0x142F7A3A),
                  child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: _leaf, fontWeight: FontWeight.bold)),
                ),
                title: Text(name.isEmpty ? '(sin nombre)' : name, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${u['email'] ?? ''}\n${_roleNames[role]}'),
                isThreeLine: true,
                trailing: role == 0
                    ? const Chip(label: Text('Dueño', style: TextStyle(fontSize: 12)), visualDensity: VisualDensity.compact)
                    : PopupMenuButton<String>(
                        onSelected: (v) => v == 'edit' ? _edit(u) : _delete(u),
                        itemBuilder: (_) => const [
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

class _CreateUserDialog extends StatefulWidget {
  const _CreateUserDialog();
  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _email = TextEditingController();
  final _name = TextEditingController();
  final _pass = TextEditingController();
  int _role = 3; // Jornalero por defecto

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nuevo usuario'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre completo')),
        const SizedBox(height: 14),
        TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
        const SizedBox(height: 14),
        TextField(
          controller: _pass, obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Contraseña',
            helperText: 'Mín. 8, con mayúscula, minúscula, número y símbolo',
            helperMaxLines: 2,
          ),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<int>(
          initialValue: _role,
          decoration: const InputDecoration(labelText: 'Rol'),
          items: const [
            DropdownMenuItem(value: 1, child: Text('Ingeniero agrónomo')),
            DropdownMenuItem(value: 2, child: Text('Técnico de campo')),
            DropdownMenuItem(value: 3, child: Text('Jornalero')),
          ],
          onChanged: (v) => setState(() => _role = v ?? 3),
        ),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () {
          if (_name.text.trim().isEmpty || _email.text.trim().isEmpty || _pass.text.length < 8) return;
          Navigator.pop(context, {
            'fullName': _name.text.trim(), 'email': _email.text.trim(), 'password': _pass.text, 'role': _role,
          });
        }, child: const Text('Crear')),
      ],
    );
  }
}

class _EditUserDialog extends StatefulWidget {
  const _EditUserDialog({required this.fullName, required this.role});
  final String fullName;
  final int role;
  @override
  State<_EditUserDialog> createState() => _EditUserDialogState();
}

class _EditUserDialogState extends State<_EditUserDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.fullName);
  late int _role = widget.role;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar usuario'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre completo')),
        const SizedBox(height: 14),
        DropdownButtonFormField<int>(
          initialValue: _role,
          decoration: const InputDecoration(labelText: 'Rol'),
          items: const [
            DropdownMenuItem(value: 1, child: Text('Ingeniero agrónomo')),
            DropdownMenuItem(value: 2, child: Text('Técnico de campo')),
            DropdownMenuItem(value: 3, child: Text('Jornalero')),
          ],
          onChanged: (v) => setState(() => _role = v ?? _role),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () {
          if (_name.text.trim().isEmpty) return;
          Navigator.pop(context, {'fullName': _name.text.trim(), 'role': _role});
        }, child: const Text('Guardar')),
      ],
    );
  }
}
