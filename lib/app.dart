import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'desktop/desktop_shell.dart';
import 'screens/auth/auth_gate.dart';
import 'screens/splash/splash_screen.dart';
import 'state/settings_state.dart';
import 'theme/app_theme.dart';

/// 喜爱 · 喜 AI 的策略证伪台。
///
/// 启动顺序：开屏页（至少 1 秒，用于收尾初始化）→ AuthGate（校验登录态）→
/// 主界面。开屏页不只是一个门面：它把「首屏之前必须完成的事」停顿显性化。
class XiaiApp extends StatefulWidget {
  const XiaiApp({super.key});

  @override
  State<XiaiApp> createState() => _XiaiAppState();
}

class _XiaiAppState extends State<XiaiApp> {
  bool _splashDone = false;

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
          title: '喜爱',
          debugShowCheckedModeBanner: false,
          theme: theme,
          // 桌面平台（Windows/macOS/Linux）进 DesktopShell：助理对话 + 策略回测
          // 两个页签；移动端 / Web 保持 HomeScreen。
          home: _splashDone
              ? (_isDesktop
                  ? AuthGate(homeBuilder: (_) => const DesktopShell())
                  : const AuthGate())
              : SplashScreen(
                  onDone: () {
                    if (mounted) setState(() => _splashDone = true);
                  },
                ),
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
