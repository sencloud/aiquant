import 'package:flutter/material.dart';

import 'screens/watch/market_theme.dart';
import 'screens/watch/watch_screen.dart';

/// 喜AI：应用只保留一个股票 / 期货 K 线工作台。
class XiaiApp extends StatelessWidget {
  const XiaiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '喜AI',
      debugShowCheckedModeBanner: false,
      theme: buildMarketTheme(),
      themeMode: ThemeMode.light,
      home: const WatchScreen(),
    );
  }
}
