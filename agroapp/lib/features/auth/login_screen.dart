import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../home/home_screen.dart';
import '../laborer/laborer_home.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController(text: 'owner@demo.com');
  final _password = TextEditingController(text: 'Demo1234!');
  bool _loading = false;
  String? _error;

  String _mapError(Object e) {
    if (e is DioException) {
      if (e.response?.statusCode == 401) return 'Credenciales inválidas. Revisa tu correo y contraseña.';
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.connectionError:
          return 'Sin conexión o el servidor está iniciando (puede tardar ~30 s). Reintenta.';
        default:
          if (e.response != null) return 'Error del servidor (${e.response!.statusCode}). Intenta más tarde.';
          return 'No se pudo conectar. Verifica tu conexión y reintenta.';
      }
    }
    return 'No se pudo iniciar sesión. Intenta de nuevo.';
  }

  Future<void> _login() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'Ingresa tu correo y contraseña.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await ref.read(authRepoProvider).login(_email.text.trim(), _password.text);
      final role = await ref.read(tokenStoreProvider).role;
      if (mounted) {
        final Widget home = role == 'Laborer' ? const LaborerHome() : const HomeScreen();
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => home));
      }
    } catch (e) {
      setState(() => _error = _mapError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/brand/mark-color-512.png', height: 110),
              const SizedBox(height: 12),
              Text('AgroApp',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
              const Text('Gestión de cultivos', style: TextStyle(color: Colors.black54)),
              const SizedBox(height: 24),
              TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email'), keyboardType: TextInputType.emailAddress),
              const SizedBox(height: 12),
              TextField(controller: _password, decoration: const InputDecoration(labelText: 'Contraseña'), obscureText: true),
              const SizedBox(height: 20),
              if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _loading ? null : _login,
                  child: _loading
                      ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : const Text('Iniciar sesión'),
                ),
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('Conectando… si el servidor estaba inactivo puede tardar unos segundos.',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.black54, fontSize: 12.5)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
