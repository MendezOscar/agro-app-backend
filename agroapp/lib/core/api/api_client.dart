import 'package:dio/dio.dart';

import '../env.dart';
import '../auth/token_store.dart';

/// Cliente HTTP con inyección de JWT y refresh automático ante 401.
class ApiClient {
  ApiClient(this._tokens) {
    dio = Dio(BaseOptions(
      baseUrl: Env.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
    ));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _tokens.accessToken;
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        handler.next(options);
      },
      onError: (e, handler) async {
        if (e.response?.statusCode == 401 && !_retried(e)) {
          if (await _refresh()) {
            final clone = await _retry(e.requestOptions);
            return handler.resolve(clone);
          }
        }
        handler.next(e);
      },
    ));
  }

  late final Dio dio;
  final TokenStore _tokens;

  bool _retried(DioException e) => e.requestOptions.extra['retried'] == true;

  Future<bool> _refresh() async {
    final refresh = await _tokens.refreshToken;
    if (refresh == null) return false;
    try {
      final res = await Dio(BaseOptions(baseUrl: Env.apiBaseUrl))
          .post('/api/auth/refresh', data: {'refreshToken': refresh});
      await _tokens.updateAccess(res.data['accessToken'], res.data['refreshToken']);
      return true;
    } catch (_) {
      await _tokens.clear();
      return false;
    }
  }

  Future<Response> _retry(RequestOptions ro) async {
    final token = await _tokens.accessToken;
    return dio.request(
      ro.path,
      data: ro.data,
      queryParameters: ro.queryParameters,
      options: Options(
        method: ro.method,
        headers: {...ro.headers, 'Authorization': 'Bearer $token'},
        extra: {'retried': true},
      ),
    );
  }
}
