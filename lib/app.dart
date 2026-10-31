import 'package:flutter/material.dart';

import 'screens/watch/market_theme.dart';
import 'screens/watch/watch_screen.dart';

/// 喜宽行情：应用只保留一个股票 / 期货 K 线工作台。
class XiaiApp extends StatelessWidget {
  const XiaiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '喜宽行情',
      debugShowCheckedModeBanner: false,
      theme: buildMarketTheme(),
      home: const WatchScreen(),
    );
  }
}
