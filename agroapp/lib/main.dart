import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

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
    // Paleta de marca AgroApp ("Sello")
    const leaf = Color(0xFF2F7A3A);
    const leafDark = Color(0xFF1F5A2A);
    final scheme = ColorScheme.fromSeed(seedColor: leaf, primary: leaf);
    final baseTheme = ThemeData(useMaterial3: true, colorScheme: scheme);
    return MaterialApp(
      title: 'AgroApp',
      debugShowCheckedModeBanner: false,
      theme: baseTheme.copyWith(
        textTheme: GoogleFonts.manropeTextTheme(baseTheme.textTheme),
        scaffoldBackgroundColor: const Color(0xFFF4F6F2),
        appBarTheme: AppBarTheme(
          backgroundColor: leafDark,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: GoogleFonts.manrope(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white),
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: Colors.white,
          unselectedLabelColor: Color(0xCCFFFFFF),
          indicatorColor: Colors.white,
          dividerColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: Colors.white,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE6E9E3)),
          ),
        ),
        listTileTheme: const ListTileThemeData(iconColor: leaf),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: leaf,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: leaf, foregroundColor: Colors.white,
        ),
        chipTheme: const ChipThemeData(showCheckmark: false),
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
