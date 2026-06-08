import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../screens/auth/login_screen.dart';
import '../../state/auth_state.dart';

/// 按需登录门控。
///
/// App 启动后默认进入主程序（未登录也能浏览）；只有在进入「我的」、DING 等
/// 需要账号的页面，或触发发送消息等需鉴权的功能时，才用这个把登录页以模态
/// 方式弹出。
///
/// 返回 true 表示当前已登录（本来就登录 / 弹窗里登录成功）；false 表示用户
/// 放弃登录，调用方应中止后续操作。
Future<bool> requireLogin(BuildContext context) async {
  final auth = context.read<AuthState>();
  if (auth.isAuthenticated) return true;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const LoginScreen(modal: true),
    ),
  );
  if (!context.mounted) return false;
  return context.read<AuthState>().isAuthenticated;
}
