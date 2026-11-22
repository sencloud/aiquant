import 'package:flutter/material.dart';

import 'screens/shell/xiai_shell.dart';
import 'theme/app_theme.dart';

/// 嘻，AI：从成交记录里复盘交易逻辑、问题与改进措施。
class XiaiApp extends StatelessWidget {
  const XiaiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '嘻，AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      themeMode: ThemeMode.light,
      home: const XiaiShell(),
    );
  }
}
