import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/api/api_client.dart' show installNoProxyHttpOverrides;
import 'core/config/app_config.dart';
import 'core/storage/hive_setup.dart';
import 'services/analytics.dart';
import 'services/client_error_reporter.dart';
import 'services/network_permission_service.dart';
import 'social/social_state.dart';
import 'state/auth_state.dart';
import 'state/billing_state.dart';
import 'state/chat_state.dart';
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

  // 埋点：未在 .env 里配 UMAMI_WEBSITE_ID 时整个服务是 no-op。
  await Analytics.instance.init();

  ClientErrorReporter.instance.install();

  // 安装「无线数据」授权状态监听：用户在首启弹窗授权后自动重连并刷新页面。
  NetworkPermissionService.instance.install();

  final auth = AuthState();
  final chat = ChatState();

  // 「启动即预热 Tushare（触发 iOS 首启联网授权弹窗）」在 AppProfile.onEnter 里，
  // 由外壳在首帧之后调用。

  runApp(
    MultiProvider(
      // 全 App 共享：设置、账号、喜点 / 内购、本机记录、对话。
      // 档案私有状态（组合、DING、直播、鹦鹉螺、自选……）由 AppProfile 在
      // app.dart 里装配。
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsState()..bootstrap()),
        ChangeNotifierProvider.value(value: auth..bootstrap()),
        ChangeNotifierProvider(create: (_) => BillingState()),
        // 本机记录：事、话、回声、见面礼、今晚不在。
        ChangeNotifierProvider(create: (_) => SocialState()..load()),
        // ChatState 的 bootstrap() 由 AuthGate 在登录态切换时驱动，
        // 避免未登录就把上一个用户的本地缓存读出来。
        ChangeNotifierProvider.value(value: chat),
      ],
      child: const XiaiApp(),
    ),
  );
}
