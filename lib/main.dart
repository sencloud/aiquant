import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/storage/hive_setup.dart';
import 'services/tushare_service.dart';
import 'state/chat_state.dart';
import 'state/ding_state.dart';
import 'state/portfolio_state.dart';
import 'state/settings_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadEnv();
  await Hive.initFlutter();
  await registerHiveAdapters();
  await openAppBoxes();
  await AppConfig.instance.load();

  // 启动后立即发起一次 Tushare 轻量请求：触发 iOS 中国大陆首启的
  // "允许使用 Wi-Fi/蜂窝网络" 系统弹窗，并预热 DNS/TLS。
  // 不 await，避免阻塞 runApp。
  // ignore: unawaited_futures
  TushareService().warmup();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsState()..bootstrap()),
        ChangeNotifierProvider(create: (_) => PortfolioState()..bootstrap()),
        ChangeNotifierProvider(create: (_) => ChatState()..bootstrap()),
        // DingState 依赖 ChatState 的 executeOneShot
        ChangeNotifierProxyProvider<ChatState, DingState>(
          create: (ctx) => DingState(chat: ctx.read<ChatState>())..bootstrap(),
          update: (_, chat, prev) => prev ?? (DingState(chat: chat)..bootstrap()),
        ),
      ],
      child: const FinceptApp(),
    ),
  );
}
