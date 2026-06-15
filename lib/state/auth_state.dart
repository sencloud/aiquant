import 'dart:async';
import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:uuid/uuid.dart';

import '../core/api/api_client.dart';
import '../core/api/auth_models.dart';
import '../services/auth_service.dart';
import '../services/push_registration_service.dart';

const _uuid = Uuid();

/// AuthState 是 Provider 管理的登录态：
/// - bootstrap()：启动时读本地 token，若存在则拉一次 /me 拿最新 profile + 余额。
/// - sendSMS / verifySMS / signInWithApple / logout：登录入口。
/// - currentUser：当前登录用户（null 即未登录）。
/// - creditBalance：便捷读，喜点余额。
///
/// 不会兜底为离线模式 — 网络错误抛 ApiException 让 UI 自己处理。
class AuthState extends ChangeNotifier {
  AuthState({AuthService? service})
      : _svc = service ?? AuthService(),
        _api = ApiClient.instance;

  final AuthService _svc;
  final ApiClient _api;
  StreamSubscription<void>? _logoutSub;

  UserPublic? _user;
  bool _bootstrapping = true;
  String? _deviceId;

  UserPublic? get currentUser => _user;
  bool get isAuthenticated => _user != null;
  bool get bootstrapping => _bootstrapping;
  int get creditBalance => _user?.creditBalance ?? 0;
  String? get deviceId => _deviceId;

  Future<void> bootstrap() async {
    _logoutSub = _api.onForcedLogout.listen((_) => _onForcedLogout());
    _deviceId = await _ensureDeviceId();

    final tokens = await _api.storage.loadTokens();
    final cached = await _api.storage.loadUser();
    if (tokens == null || tokens.refreshExpired) {
      _user = null;
      _bootstrapping = false;
      notifyListeners();
      return;
    }
    _user = cached;
    notifyListeners();

    try {
      final fresh = await _svc.me();
      _user = fresh;
      await _api.storage.saveUser(fresh);
      await _registerDevice();
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await _onForcedLogout();
      }
    } catch (_) {
      // 网络抖动：保留本地缓存进入 App，下次启动再拉
    }
    _bootstrapping = false;
    notifyListeners();
  }

  Future<void> sendSMS(String phone) async {
    await _svc.sendSMS(phone);
  }

  Future<UserPublic> verifySMS({required String phone, required String code}) async {
    final res = await _svc.verifySMS(
      phone: phone,
      code: code,
      deviceId: await _ensureDeviceId(),
    );
    await _persistLogin(res.tokens, res.user);
    return res.user;
  }

  Future<void> sendEmailCode(String email) async {
    await _svc.sendEmailCode(email);
  }

  Future<UserPublic> verifyEmail({
    required String email,
    required String code,
  }) async {
    final res = await _svc.verifyEmail(
      email: email,
      code: code,
      deviceId: await _ensureDeviceId(),
    );
    await _persistLogin(res.tokens, res.user);
    return res.user;
  }

  Future<UserPublic> signInWithApple() async {
    final cred = await SignInWithApple.getAppleIDCredential(
      scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
    );
    final idToken = cred.identityToken;
    if (idToken == null || idToken.isEmpty) {
      throw ApiException(
        code: 'AUTH.APPLE_NO_TOKEN',
        message: '未拿到 Apple identity_token',
        statusCode: 0,
      );
    }
    final nick = [cred.givenName, cred.familyName]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(' ');
    final res = await _svc.appleLogin(
      identityToken: idToken,
      nickname: nick,
      deviceId: await _ensureDeviceId(),
    );
    await _persistLogin(res.tokens, res.user);
    return res.user;
  }

  Future<void> updateNickname(String nick) async {
    final u = await _svc.updateNickname(nick);
    _user = u;
    await _api.storage.saveUser(u);
    notifyListeners();
  }

  Future<void> refreshProfile() async {
    if (!isAuthenticated) return;
    final u = await _svc.me();
    _user = u;
    await _api.storage.saveUser(u);
    notifyListeners();
  }

  Future<void> logout() async {
    await _svc.logout();
    _user = null;
    PushRegistrationService.instance.reset();
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    await _svc.deleteAccount();
    _user = null;
    PushRegistrationService.instance.reset();
    notifyListeners();
  }

  Future<void> _persistLogin(TokenPair t, UserPublic u) async {
    await _api.storage.saveTokens(t);
    await _api.storage.saveUser(u);
    _user = u;
    notifyListeners();
    await _registerDevice();
  }

  Future<void> _onForcedLogout() async {
    _user = null;
    await _api.storage.clearAll();
    PushRegistrationService.instance.reset();
    notifyListeners();
  }

  // ── 设备 ─────────────────────────────────────────────────────────────

  Future<String> _ensureDeviceId() async {
    final cached = await _api.storage.readDeviceId();
    if (cached != null && cached.isNotEmpty) return cached;
    final id = _uuid.v4();
    await _api.storage.writeDeviceId(id);
    return id;
  }

  Future<void> _registerDevice() async {
    final platform = _platformName();
    if (platform == null) return;
    final pkg = await PackageInfo.fromPlatform();
    try {
      await _svc.upsertDevice(
        deviceId: await _ensureDeviceId(),
        platform: platform,
        appVersion: '${pkg.version}+${pkg.buildNumber}',
      );
    } catch (_) {
      // 设备登记是非关键路径，失败下次启动再试
    }
    // 触发 APNs / FCM token 上送：iOS 调原生 channel；用户首次会弹通知权限。
    // 失败不阻塞登录链路。
    // ignore: unawaited_futures
    PushRegistrationService.instance.registerIfPossible();
  }

  String? _platformName() {
    if (kIsWeb) return null;
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return null;
  }

  // ignore: unused_element
  Future<String?> _readPlatformDeviceId() async {
    final di = DeviceInfoPlugin();
    if (Platform.isIOS) {
      final info = await di.iosInfo;
      return info.identifierForVendor;
    }
    if (Platform.isAndroid) {
      final info = await di.androidInfo;
      return info.id;
    }
    return null;
  }

  @override
  void dispose() {
    _logoutSub?.cancel();
    super.dispose();
  }
}
