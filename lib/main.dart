import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/api/api_client.dart' show installNoProxyHttpOverrides;
import 'core/api/token_storage.dart';
import 'core/config/app_config.dart';
import 'core/storage/hive_setup.dart';
import 'core/topic/topic_registry.dart';
import 'core/topic/topic_state.dart';
import 'services/analytics.dart';
import 'services/client_error_reporter.dart';
import 'services/network_permission_service.dart';
import 'screens/hub/hub_state.dart';
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

  // 主题：在 runApp 之前读出上次的主题并换色（冷启动不闪色）。
  // 桌面端只保留喜爱钱。本机切换主题时，已登录则同步到服务端（换机恢复）。
  final auth = AuthState();
  final topics = TopicState(
    packs: builtInTopicPacks(
      fishing: isDesktopPlatform ? false : null,
      circles: isDesktopPlatform ? false : null,
    ),
    // ignore: unawaited_futures
    onSwitched: (id) => auth.syncPreferredTopic(id),
  );
  await topics.bootstrap(
    hasLocalAccount: () async => await TokenStorage().loadTokens() != null,
  );
  // 对话会话按主题过滤（会话列表、默认人设、请求里的 topic）。
  final chat = ChatState()..setTopic(topics.currentId);
  topics.addListener(() => chat.setTopic(topics.currentId));

  // 「启动即预热 Tushare（触发 iOS 首启联网授权弹窗）」挪到了喜爱钱主题包的
  // onEnter：钓鱼主题不初始化任何量化状态、不请求 Tushare。

  runApp(
    MultiProvider(
      // 全主题共享：设置、账号、喜点 / 内购、主题、对话（按主题过滤）。
      // 主题私有状态（组合、DING、直播、鹦鹉螺、自选……）由主题包在
      // app.dart 里按需创建。
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsState()..bootstrap()),
        ChangeNotifierProvider(create: (_) => HubState()),
        ChangeNotifierProvider.value(value: auth..bootstrap()),
        ChangeNotifierProvider(create: (_) => BillingState()),
        ChangeNotifierProvider.value(value: topics),
        // ChatState 的 bootstrap() 由 AuthGate 在登录态切换时驱动，
        // 避免未登录就把上一个用户的本地缓存读出来。
        ChangeNotifierProvider.value(value: chat),
      ],
      child: const XiaiApp(),
    ),
  );
}
