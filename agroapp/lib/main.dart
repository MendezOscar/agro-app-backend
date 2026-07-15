import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_screen.dart';
import 'features/laborer/laborer_home.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: AgroApp()));
}

class AgroApp extends StatelessWidget {
  const AgroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AgroApp',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      home: const _Root(),
    );
  }
}

/// Decide pantalla inicial según haya sesión almacenada.
class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final startup = ref.watch(startupProvider);
    return startup.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => const LoginScreen(),
      data: (role) => role == null
          ? const LoginScreen()
          : role == 'Laborer'
              ? const LaborerHome()
              : const HomeScreen(),
    );
  }
}
