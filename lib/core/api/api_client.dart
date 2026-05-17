import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import 'auth_models.dart';
import 'token_storage.dart';

const _uuid = Uuid();

/// 统一构造一个"绕过系统代理"的 Dio 适配器。
///
/// 真机上常因用户安装过 ProxyMan / Surge / Shadowrocket / VPN，留下系统
/// HTTP 代理设置（`127.0.0.1:<端口>`），代理工具关闭后端口已无人监听，
/// 但 dart:io HttpClient 仍会读 CFNetwork 代理配置 → 所有请求挂到那条
/// 死代理上，报 `Connection refused, address = 127.0.0.1, port = ...`。
///
/// 本应用所有出网调用都强制走直连（findProxy = DIRECT），不依赖系统代理。
HttpClientAdapter buildNoProxyAdapter() {
  return IOHttpClientAdapter(
    createHttpClient: () => HttpClient()..findProxy = (uri) => 'DIRECT',
  );
}

/// 全局拦截 dart:io HttpClient 的创建，让任何代码（包括我们没控制的
/// 第三方包，例如 sign_in_with_apple、dotenv、shared_preferences 上报、
/// dio 自身的内部 client 等）一律走直连，不再受系统代理影响。
///
/// 必须在 runApp() 之前调用，否则插件可能已经创建了带代理的 HttpClient。
void installNoProxyHttpOverrides() {
  HttpOverrides.global = _NoProxyHttpOverrides();
}

class _NoProxyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.findProxy = (uri) => 'DIRECT';
    return client;
  }
}

/// ApiClient 是 Flutter 端访问 Finme Backend 的唯一入口。
///
/// 职责：
/// 1. 统一 baseUrl / timeout / 错误形态；
/// 2. 自动注入 Bearer access_token；
/// 3. access 过期 → 用 refresh_token 自动续签，并把当时 in-flight 的
///    请求挂起、续签成功后再放行（避免登录态短暂闪断）；
/// 4. refresh 也失效时，向上派发"需要重新登录"事件。
///
/// 使用：
/// ```dart
/// final api = ApiClient.instance;
/// final r = await api.dio.post('/v1/auth/sms/send', data: {'phone': p});
/// ```
class ApiClient {
  ApiClient._({required Dio dio, required TokenStorage storage})
      : _dio = dio,
        _storage = storage;

  static ApiClient? _instance;
  static ApiClient get instance {
    _instance ??= ApiClient._build();
    return _instance!;
  }

  factory ApiClient._build() {
    final storage = TokenStorage();
    final dio = Dio(BaseOptions(
      baseUrl: AppConfig.instance.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
      validateStatus: (s) => s != null && s < 500,
    ));
    dio.httpClientAdapter = buildNoProxyAdapter();
    final c = ApiClient._(dio: dio, storage: storage);
    dio.interceptors.add(_AuthInterceptor(c));
    dio.interceptors.add(_ErrorInterceptor());
    return c;
  }

  final Dio _dio;
  final TokenStorage _storage;
  final StreamController<void> _logoutEvents = StreamController.broadcast();

  Dio get dio => _dio;
  TokenStorage get storage => _storage;

  /// 当 refresh 也失效时触发；上层 AuthState 监听后清状态、跳登录页。
  Stream<void> get onForcedLogout => _logoutEvents.stream;

  // ── refresh 串行化 ──────────────────────────────────────────────────
  Future<void>? _refreshing;
  Future<bool> _ensureFreshAccess(TokenPair pair) async {
    if (!pair.accessNearlyExpired) return true;
    if (pair.refreshExpired) return false;

    if (_refreshing != null) {
      await _refreshing;
      return true;
    }
    final c = Completer<void>();
    _refreshing = c.future;
    try {
      final ok = await _doRefresh(pair.refreshToken);
      c.complete();
      return ok;
    } finally {
      _refreshing = null;
    }
  }

  Future<bool> _doRefresh(String refreshToken) async {
    try {
      final resp = await _dio.post<Map<String, dynamic>>(
        '/v1/auth/refresh',
        data: {'refresh_token': refreshToken},
        options: Options(extra: {_kSkipAuth: true}),
      );
      if (resp.statusCode == 200) {
        final body = resp.data!;
        final pair =
            TokenPair.fromJson(body['tokens'] as Map<String, dynamic>);
        await _storage.saveTokens(pair);
        return true;
      }
      // 4xx 视为永久失败 → 强制登出
      await _storage.clearAll();
      _logoutEvents.add(null);
      return false;
    } catch (_) {
      // 网络抖动等 → 不清空 token，让下次请求再试
      return false;
    }
  }

  /// 主动触发登出事件（业务层显式登出后调用，先 clear 再广播）。
  Future<void> notifyLogout() async {
    await _storage.clearAll();
    _logoutEvents.add(null);
  }

  static String newRequestId() => 'fl-${_uuid.v4()}';
}

/// 内部 extra key —— 跳过 _AuthInterceptor 重新进入循环。
const _kSkipAuth = '__skip_auth__';

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this.c);
  final ApiClient c;

  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    if (options.extra[_kSkipAuth] == true) {
      handler.next(options);
      return;
    }
    final pair = await c._storage.loadTokens();
    if (pair != null) {
      final ok = await c._ensureFreshAccess(pair);
      if (!ok) {
        handler.reject(DioException(
          requestOptions: options,
          type: DioExceptionType.cancel,
          error: ApiException(
            code: 'AUTH.REFRESH_FAILED',
            message: '登录已过期，请重新登录',
            statusCode: 401,
          ),
        ));
        return;
      }
      // 续签后重新读最新 token
      final fresh = await c._storage.loadTokens();
      if (fresh != null) {
        options.headers['Authorization'] = 'Bearer ${fresh.accessToken}';
      }
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final req = err.requestOptions;
    if (req.extra[_kSkipAuth] == true) {
      handler.next(err);
      return;
    }
    if (err.response?.statusCode == 401) {
      // access 被服务端判失效（被吊销 / 旋转）— 尝试一次强制 refresh 后重放
      final pair = await c._storage.loadTokens();
      if (pair == null || pair.refreshExpired) {
        await c._storage.clearAll();
        c._logoutEvents.add(null);
        handler.next(err);
        return;
      }
      final ok = await c._doRefresh(pair.refreshToken);
      if (!ok) {
        handler.next(err);
        return;
      }
      final fresh = await c._storage.loadTokens();
      if (fresh == null) {
        handler.next(err);
        return;
      }
      try {
        req.headers['Authorization'] = 'Bearer ${fresh.accessToken}';
        final resp = await c._dio.fetch<dynamic>(req);
        handler.resolve(resp);
        return;
      } catch (e) {
        if (e is DioException) {
          handler.next(e);
        } else {
          handler.next(err);
        }
        return;
      }
    }
    handler.next(err);
  }
}

class _ErrorInterceptor extends Interceptor {
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final s = response.statusCode ?? 0;
    if (s >= 400) {
      throw _toApiException(response);
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response != null) {
      err = err.copyWith(error: _toApiException(err.response!));
    }
    handler.next(err);
  }

  ApiException _toApiException(Response r) {
    String code = 'NETWORK.UNKNOWN';
    String message = 'unknown error';
    String? requestId;
    final data = r.data;
    if (data is Map) {
      code = (data['code'] as String?) ?? code;
      message = (data['message'] as String?) ?? message;
      requestId = data['request_id'] as String?;
    }
    return ApiException(
      code: code,
      message: message,
      statusCode: r.statusCode ?? 0,
      requestId: requestId,
    );
  }
}
