import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

/// Traduce excepciones a un mensaje legible en español.
String friendlyError(Object? e) {
  if (e is DioException) {
    if (e.response?.statusCode == 401) return 'Sesión expirada. Vuelve a iniciar sesión.';
    if (e.response?.statusCode == 403) return 'No tienes permisos para esta acción.';
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.connectionError:
        return 'Sin conexión o el servidor está iniciando (puede tardar ~30 s). Reintenta.';
      default:
        if (e.response != null) return 'Error del servidor (${e.response!.statusCode}).';
        return 'No se pudo conectar. Verifica tu conexión.';
    }
  }
  return 'Ocurrió un error. Intenta de nuevo.';
}

/// Estado de error con opción de reintentar.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, this.onRetry});
  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off, size: 48, color: Colors.black26),
          const SizedBox(height: 12),
          Text(friendlyError(error), textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Reintentar')),
          ],
        ]),
      ),
    );
  }
}

/// Estado vacío con ícono y mensaje (y acción opcional).
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message, this.action});
  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 52, color: Colors.black26),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54, fontSize: 15)),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}
