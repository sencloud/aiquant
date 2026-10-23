import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_profile.dart';
import 'core/config/features.dart';
import 'desktop/desktop_shell.dart';
import 'screens/auth/auth_gate.dart';
import 'screens/splash/splash_screen.dart';
import 'story/night_shell.dart';
import 'theme/app_theme.dart';
import 'wx/wx_shell.dart';

/// 喜爱 · 喜爱，并不是一定要得到。
///
/// 启动顺序：开屏页（至少 1 秒，用于收尾初始化 + 等登录态）→ AuthGate →
/// 主界面（移动端 [WxShell]，桌面端 [DesktopShell]）。
///
/// 2026-10 这次重构拿掉了「多主题」：不再有选主题页、不再有整屏换色、也不再
/// 有圈子首页。[AppProfile] 是唯一的一份档案（见 `core/app_profile.dart`），
/// 它只负责装配状态，不参与外观切换。
class XiaiApp extends StatefulWidget {
  const XiaiApp({super.key});

  @override
  State<XiaiApp> createState() => _XiaiAppState();
}

class _XiaiAppState extends State<XiaiApp> {
  bool _splashDone = false;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppProfile>.value(value: appProfile),
        ...appProfile.providers(),
      ],
      child: MaterialApp(
        title: '喜爱',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(),
        home: !_splashDone
            ? SplashScreen(
                onDone: () {
                  if (mounted) setState(() => _splashDone = true);
                },
              )
            : kStoryTrialHome
                ? const NightShell()
                : AuthGate(
                    homeBuilder: (_) =>
                        _isDesktop ? const DesktopShell() : const WxShell(),
                  ),
      ),
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

/// 桌面端与移动端共用同一份应用档案；这个 getter 留给桌面 shell 的调用点。
bool get isDesktopPlatform => _isDesktop;
