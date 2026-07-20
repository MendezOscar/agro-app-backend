import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

class _Slide {
  const _Slide(this.icon, this.title, this.text);
  final IconData icon;
  final String title;
  final String text;
}

const _slides = [
  _Slide(Icons.agriculture_outlined, 'Bienvenido a AgroApp',
      'Gestiona tus fincas y cosechas desde el campo, incluso sin conexión.'),
  _Slide(Icons.timeline_outlined, 'Ciclo en 8 etapas',
      'Desde la planificación hasta la evaluación: registra tareas, costos e insumos en cada etapa.'),
  _Slide(Icons.camera_alt_outlined, 'Diagnóstico con IA',
      'Toma una foto de la planta y detecta plagas o enfermedades al instante.'),
  _Slide(Icons.eco_outlined, 'Agronomía inteligente',
      'Temperatura y humedad del suelo, riego recomendado, grados-día y riesgo de enfermedad con datos de clima.'),
];

/// Introducción de primera vez. Al terminar marca la bandera y refresca el arranque.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pc = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref.read(tokenStoreProvider).setOnboarded();
    ref.invalidate(onboardedProvider);
  }

  void _next() {
    if (_page < _slides.length - 1) {
      _pc.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    const leaf = Color(0xFF2F7A3A);
    const leafDark = Color(0xFF1F5A2A);
    final last = _page == _slides.length - 1;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [leafDark, leaf]),
        ),
        child: SafeArea(
          child: Column(children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: const Text('Saltar', style: TextStyle(color: Colors.white)),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pc,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) {
                  final s = _slides[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(28),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle),
                          child: Icon(s.icon, size: 72, color: Colors.white),
                        ),
                        const SizedBox(height: 32),
                        Text(s.title, textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 14),
                        Text(s.text, textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xE6FFFFFF), fontSize: 16, height: 1.4)),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _slides.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 22 : 8, height: 8,
                    decoration: BoxDecoration(
                      color: i == _page ? Colors.white : Colors.white54,
                      borderRadius: BorderRadius.circular(4)),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white, foregroundColor: leafDark,
                    padding: const EdgeInsets.symmetric(vertical: 16)),
                  onPressed: _next,
                  child: Text(last ? 'Comenzar' : 'Siguiente',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
