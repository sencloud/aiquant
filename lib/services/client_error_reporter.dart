import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/api/api_client.dart';

/// 把 Flutter / Dart 未捕获异常轻量上报到后端 /v1/client/error。
///
/// - 失败/限流/网络都视为静默跳过，绝不抛回上层；
/// - 单次上报最多 4KB stack；同一异常 60s 内合并去重避免风暴。
class ClientErrorReporter {
  ClientErrorReporter._();
  static final ClientErrorReporter instance = ClientErrorReporter._();

  String? _platform;
  String? _version;
  final Map<String, DateTime> _recent = {};

  Future<void> _ensurePlatform() async {
    if (_platform != null) return;
    if (Platform.isIOS) {
      _platform = 'ios';
    } else if (Platform.isAndroid) {
      _platform = 'android';
    } else {
      _platform = Platform.operatingSystem;
    }
    try {
      final info = await PackageInfo.fromPlatform();
      _version = '${info.version}+${info.buildNumber}';
    } catch (_) {
      _version = '';
    }
  }

  Future<void> report({
    required String type,
    required String message,
    String? stack,
    String? path,
  }) async {
    final key = '$type|$message';
    final now = DateTime.now();
    final last = _recent[key];
    if (last != null && now.difference(last) < const Duration(seconds: 60)) {
      return;
    }
    _recent[key] = now;
    _recent.removeWhere(
        (_, t) => now.difference(t) > const Duration(minutes: 5));

    await _ensurePlatform();
    try {
      await ApiClient.instance.dio.post(
        '/v1/client/error',
        data: {
          'type': type,
          'message': message,
          if (stack != null) 'stack': stack,
          if (path != null) 'path': path,
          'platform': _platform,
          'version': _version,
        },
      );
    } catch (_) {
      // 静默：上报失败不应再触发上报循环
    }
  }

  /// 安装全局错误捕获 — 由 main.dart 调用一次即可。
  void install() {
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.dumpErrorToConsole(details);
      report(
        type: 'flutter',
        message: details.exceptionAsString(),
        stack: details.stack?.toString(),
        path: details.library,
      );
    };
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      report(
        type: 'platform_dispatcher',
        message: error.toString(),
        stack: stack.toString(),
      );
      return true;
    };
  }
}
