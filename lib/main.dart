import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/storage/hive_setup.dart';
import 'state/chat_state.dart';
import 'state/portfolio_state.dart';
import 'state/settings_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadEnv();
  await Hive.initFlutter();
  await registerHiveAdapters();
  await openAppBoxes();
  await AppConfig.instance.load();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsState()..bootstrap()),
        ChangeNotifierProvider(create: (_) => PortfolioState()..bootstrap()),
        ChangeNotifierProvider(create: (_) => ChatState()..bootstrap()),
      ],
      child: const FinceptApp(),
    ),
  );
}
