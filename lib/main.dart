import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/api/api_client.dart' show installNoProxyHttpOverrides;
import 'core/config/app_config.dart';
import 'core/storage/hive_setup.dart';
import 'services/client_error_reporter.dart';
import 'services/tushare_service.dart';
import 'state/auth_state.dart';
import 'state/billing_state.dart';
import 'state/chat_state.dart';
import 'state/ding_state.dart';
import 'state/portfolio_state.dart';
import 'state/settings_state.dart';

Future<void> main() async {
  // 全局未捕获异常 → /v1/client/error 轻量上报。
  await runZonedGuarded(_bootstrap, (error, stack) {
    ClientErrorReporter.instance.report(
      type: 'zoned',
      message: error.toString(),
      stack: stack.toString(),
    );
  });
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 必须在任何插件 / 第三方库新建 HttpClient 之前安装：
  // 全局让所有 dart:io HttpClient.findProxy = DIRECT，避免设备上残留的
  // ProxyMan / Surge / Shadowrocket / VPN 监听端口劫持出站请求。
  installNoProxyHttpOverrides();
  await loadEnv();
  await Hive.initFlutter();
  await registerHiveAdapters();
  await openAppBoxes();
  await AppConfig.instance.load();

  ClientErrorReporter.instance.install();

  // 启动后立即发起一次 Tushare 轻量请求：触发 iOS 中国大陆首启的
  // "允许使用 Wi-Fi/蜂窝网络" 系统弹窗，并预热 DNS/TLS。
  // ignore: unawaited_futures
  TushareService().warmup();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsState()..bootstrap()),
        ChangeNotifierProvider(create: (_) => AuthState()..bootstrap()),
        ChangeNotifierProvider(create: (_) => BillingState()),
        ChangeNotifierProvider(create: (_) => PortfolioState()..bootstrap()),
        // ChatState / DingState 的 bootstrap() 由 AuthGate 在登录态切换时驱动，
        // 避免未登录就把上一个用户的本地缓存读出来。
        ChangeNotifierProvider(create: (_) => ChatState()),
        ChangeNotifierProvider(create: (_) => DingState()),
      ],
      child: const XikuanApp(),
    ),
  );
}
