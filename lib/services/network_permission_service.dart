import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// NetworkPermissionService 监听 iOS「无线数据」授权状态。
///
/// 中国大陆 iOS 首次启动会弹「是否允许使用无线数据」系统弹窗。用户选择
/// 「WLAN 与蜂窝网络」或「仅蜂窝网络」后，原生 [AppDelegate] 通过
/// `cn.singzquant.aiquant/network` channel 回调 `onNetworkAvailable`，
/// 这里把它转成 [onNetworkAvailable] 广播流，供 UI 重新联网并刷新页面。
///
/// 仅 iOS 生效；其它平台 [onNetworkAvailable] 不会有事件。
class NetworkPermissionService {
  NetworkPermissionService._();

  static final NetworkPermissionService instance = NetworkPermissionService._();

  static const _channel = MethodChannel('cn.singzquant.aiquant/network');

  final StreamController<void> _controller = StreamController<void>.broadcast();
  bool _handlerInstalled = false;

  /// 网络由「受限/未知」变为「可用」时发出一次事件。
  Stream<void> get onNetworkAvailable => _controller.stream;

  /// 在 App 启动后调用一次，安装原生回调处理器。
  void install() {
    if (_handlerInstalled) return;
    if (kIsWeb || !Platform.isIOS) return;
    _channel.setMethodCallHandler(_handleCall);
    _handlerInstalled = true;
  }

  Future<void> _handleCall(MethodCall call) async {
    if (call.method == 'onNetworkAvailable') {
      if (!_controller.isClosed) _controller.add(null);
    }
  }
}
