import 'package:flutter/material.dart';

import 'screens/shell/xiai_shell.dart';
import 'theme/app_theme.dart';

/// 喜AI：搭子、云搭子和一个收在「我的」里的专业看盘终端。
class XiaiApp extends StatelessWidget {
  const XiaiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '喜AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      themeMode: ThemeMode.light,
      home: const XiaiShell(),
    );
  }
}
