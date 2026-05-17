import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/api/api_client.dart';
import 'auth_service.dart';

/// PushRegistrationService 串通"原生 APNs token → 后端 /v1/devices"。
///
/// iOS：通过 MethodChannel 与 [AppDelegate] 通信。
///   - `requestAndRegister` 让原生申请通知权限并 `registerForRemoteNotifications`；
///   - `onApnsToken` 由原生主动回调，参数为 hex token（小写）。
///
/// Android：当前阶段不集成 firebase_messaging，预留入口；接 FCM 时填上即可。
class PushRegistrationService {
  PushRegistrationService._();

  static final PushRegistrationService instance = PushRegistrationService._();

  static const _channel = MethodChannel('cn.singzquant.aiquant/push');

  bool _handlerInstalled = false;
  bool _registering = false;
  String? _lastUploadedToken;

  final AuthService _auth = AuthService();

  void _ensureHandler() {
    if (_handlerInstalled) return;
    if (kIsWeb) return;
    if (!Platform.isIOS) return;
    _channel.setMethodCallHandler(_handleCall);
    _handlerInstalled = true;
  }

  /// 登录后调一次：申请权限 + 上送 token；用户拒绝时返回 false。
  Future<bool> registerIfPossible() async {
    if (_registering) return _lastUploadedToken != null;
    _registering = true;
    try {
      if (kIsWeb) return false;
      _ensureHandler();
      if (Platform.isIOS) {
        final granted = await _channel.invokeMethod<bool>('requestAndRegister');
        if (granted == true) {
          // 原生在 didRegister 后会主动 invokeMethod onApnsToken；
          // 这里同时尝试取缓存里的 token，覆盖热启动场景。
          final cached = await _channel.invokeMethod<String>('getCachedToken');
          if (cached != null && cached.isNotEmpty) {
            await _uploadToken(cached, 'ios');
            return true;
          }
        }
        return granted == true && _lastUploadedToken != null;
      }
      return false;
    } catch (e) {
      debugPrint('push register failed: $e');
      return false;
    } finally {
      _registering = false;
    }
  }

  /// 登出时清空，避免下次登录复用陈旧 token。
  void reset() {
    _lastUploadedToken = null;
  }

  Future<void> _handleCall(MethodCall call) async {
    switch (call.method) {
      case 'onApnsToken':
        final token = call.arguments as String?;
        if (token != null && token.isNotEmpty) {
          await _uploadToken(token, 'ios');
        }
        break;
      case 'onApnsError':
        debugPrint('apns register error: ${call.arguments}');
        break;
    }
  }

  Future<void> _uploadToken(String token, String platform) async {
    if (_lastUploadedToken == token) return;
    try {
      final deviceId = await ApiClient.instance.storage.readDeviceId();
      if (deviceId == null || deviceId.isEmpty) return;
      final pkg = await PackageInfo.fromPlatform();
      await _auth.upsertDevice(
        deviceId: deviceId,
        platform: platform,
        pushToken: token,
        appVersion: '${pkg.version}+${pkg.buildNumber}',
      );
      _lastUploadedToken = token;
    } catch (e) {
      debugPrint('upload push token failed: $e');
    }
  }
}
