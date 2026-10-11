import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/topic/topic_pack.dart';
import 'core/topic/topic_picker_screen.dart';
import 'core/topic/topic_state.dart';
import 'desktop/desktop_shell.dart';
import 'screens/auth/auth_gate.dart';
import 'screens/splash/splash_screen.dart';
import 'state/settings_state.dart';
import 'theme/app_theme.dart';

/// 喜爱 · 喜爱什么，就有什么。
///
/// 启动顺序：开屏页（至少 1 秒，用于收尾初始化）→（全新安装且有多个主题时）
/// 选主题 → AuthGate（校验登录态）→ 当前主题的主界面。
///
/// 整个 App 随主题切换：以当前主题包的 id 作 key，在 `MaterialApp` 之上挂
/// 主题私有 Provider —— 切换主题时旧主题的状态整体销毁、新主题的状态重新
/// 创建，从页签 push 出去的页面也都在这层 Provider 之下。
class XiaiApp extends StatefulWidget {
  const XiaiApp({super.key});

  @override
  State<XiaiApp> createState() => _XiaiAppState();
}

class _XiaiAppState extends State<XiaiApp> {
  bool _splashDone = false;

  @override
  Widget build(BuildContext context) {
    return Consumer2<SettingsState, TopicState>(
      builder: (context, settings, topics, _) {
        final mode = settings.themeMode;
        final pack = topics.current;
        // Build a single ThemeData for the active mode + topic palette — also
        // pushes the matching palette into `AppColors` so widgets that
        // reference it pick up the new colours on this rebuild.
        final theme = AppTheme.build(mode, palette: pack.palette);
        return AnimatedSwitcher(
          // 切换主题：整屏淡出、换色、淡入。
          duration: const Duration(milliseconds: 300),
          child: MultiProvider(
            key: ValueKey('topic:${pack.id}'),
            providers: [
              Provider<TopicPack>.value(value: pack),
              ...pack.providers(),
            ],
            child: MaterialApp(
              title: '喜爱',
              debugShowCheckedModeBanner: false,
              theme: theme,
              // 桌面平台（Windows/macOS/Linux）进 DesktopShell：助理对话 + 策略回测
              // 两个页签；移动端 / Web 保持 HomeScreen。
              home: !_splashDone
                  ? SplashScreen(
                      onDone: () {
                        if (mounted) setState(() => _splashDone = true);
                      },
                    )
                  : topics.needsPick
                      ? const TopicPickerScreen()
                      : (_isDesktop
                          ? AuthGate(homeBuilder: (_) => const DesktopShell())
                          : const AuthGate()),
            ),
          ),
        );
      },
    );
  }
}

/// 仅供测试：强制按移动端 / 桌面端渲染（测试跑在 Linux 上默认会进桌面壳）。
@visibleForTesting
bool? debugDesktopOverride;

/// 是否运行在原生桌面平台。Web 上 kIsWeb=true，即使装在桌面浏览器也不算。
bool get _isDesktop {
  final o = debugDesktopOverride;
  if (o != null) return o;
  if (kIsWeb) return false;
  return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
}

/// 桌面端只保留喜爱钱（主题化不在桌面范围内）。
bool get isDesktopPlatform => _isDesktop;
