import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:agroapp/features/auth/login_screen.dart';

void main() {
  testWidgets('La pantalla de login muestra el título y el botón', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: LoginScreen()),
    ));

    expect(find.text('AgroApp'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);
  });
}
