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

/// Perfil del usuario en sesión: datos básicos y cierre de sesión.
/// Se usa como pestaña inferior (sin Scaffold propio).
class ProfileBody extends ConsumerWidget {
  const ProfileBody({super.key});

  Future<Map<String, String?>> _load(WidgetRef ref) async {
    final store = ref.read(tokenStoreProvider);
    return {
      'name': await store.fullName,
      'role': await store.role,
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
          final roleLabel = _roleLabels[role] ?? role;
          final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: Column(children: [
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: const Color(0x142F7A3A),
                    child: Text(initial, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Color(0xFF2F7A3A))),
                  ),
                  const SizedBox(height: 14),
                  Text(name.isEmpty ? 'Usuario' : name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(color: const Color(0x142F7A3A), borderRadius: BorderRadius.circular(20)),
                    child: Text(roleLabel, style: const TextStyle(color: Color(0xFF1F5A2A), fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
              const SizedBox(height: 32),
              OutlinedButton.icon(
                onPressed: () => _logout(context, ref),
                icon: const Icon(Icons.logout, color: Colors.red),
                label: const Text('Cerrar sesión', style: TextStyle(color: Colors.red)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red), padding: const EdgeInsets.symmetric(vertical: 14)),
              ),
            ],
          );
        },
      );
  }
}
