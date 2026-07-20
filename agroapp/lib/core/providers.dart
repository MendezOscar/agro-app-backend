import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/api_client.dart';
import 'api/repositories.dart';
import 'auth/token_store.dart';
import 'db/database.dart';
import 'local_repository.dart';
import 'sync/sync_service.dart';

final tokenStoreProvider = Provider((_) => TokenStore());
final dbProvider = Provider((_) => AppDatabase());

final apiClientProvider = Provider((ref) => ApiClient(ref.read(tokenStoreProvider)));

final authRepoProvider = Provider((ref) {
  final tokens = ref.read(tokenStoreProvider);
  return AuthRepository(ref.read(apiClientProvider), (data) async {
    await tokens.save(
      access: data['accessToken'],
      refresh: data['refreshToken'],
      orgId: data['organizationId'],
      userId: data['userId'],
      role: data['role'] ?? '',
      fullName: data['fullName'],
      email: data['email'],
    );
  });
});

/// Rol del usuario en sesión (Owner/AgronomistManager/AgronomistWorker/Laborer).
final roleProvider = FutureProvider<String?>((ref) => ref.read(tokenStoreProvider).role);

final farmRepoProvider =
    Provider((ref) => FarmRepository(ref.read(apiClientProvider), ref.read(dbProvider)));

final taskRepoProvider = Provider((ref) => TaskRepository(ref.read(apiClientProvider)));

final syncServiceProvider =
    Provider((ref) => SyncService(ref.read(apiClientProvider), ref.read(dbProvider)));

final localRepoProvider = Provider((ref) => LocalRepository(ref.read(dbProvider)));

/// Estado de sesión: true si hay token almacenado.
final sessionProvider = FutureProvider<bool>((ref) async {
  final token = await ref.read(tokenStoreProvider).accessToken;
  return token != null;
});

/// Arranque: null si no hay sesión; si la hay, devuelve el rol ('' si no se guardó).
final startupProvider = FutureProvider<String?>((ref) async {
  final store = ref.read(tokenStoreProvider);
  if (await store.accessToken == null) return null;
  return (await store.role) ?? '';
});

/// Onboarding: true si el usuario ya vio la introducción de primera vez.
final onboardedProvider = FutureProvider<bool>((ref) => ref.read(tokenStoreProvider).onboarded);
