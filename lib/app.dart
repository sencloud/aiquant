import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'desktop/desktop_shell.dart';
import 'screens/auth/auth_gate.dart';
import 'state/settings_state.dart';
import 'theme/app_theme.dart';

class XikuanApp extends StatelessWidget {
  const XikuanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsState>(
      builder: (context, settings, _) {
        final mode = settings.themeMode;
        // Build a single ThemeData for the active mode — also pushes the
        // matching palette into `AppColors` so widgets that reference it
        // pick up the new colours on this rebuild.
        final theme = AppTheme.build(mode);
        return MaterialApp(
          title: '喜宽',
          debugShowCheckedModeBanner: false,
          theme: theme,
          // 桌面平台（Windows/macOS/Linux）进 DesktopShell：助理对话 + 策略回测
          // 两个页签；移动端 / Web 保持原有 HomeScreen 不变。
          home: _isDesktop
              ? AuthGate(homeBuilder: (_) => const DesktopShell())
              : const AuthGate(),
        );
      },
    );
  }
}

/// 是否运行在原生桌面平台。Web 上 kIsWeb=true，即使装在桌面浏览器也不算。
bool get _isDesktop {
  if (kIsWeb) return false;
  return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
}
