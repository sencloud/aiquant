import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_state.dart';
import '../../state/billing_state.dart';
import '../../state/chat_state.dart';
import '../../state/ding_state.dart';
import '../../theme/app_theme.dart';
import '../home/home_screen.dart';
import 'login_screen.dart';

/// AuthGate 是 App 的根 widget。
/// - bootstrap 中：显示启动 splash；
/// - 已登录：HomeScreen；
/// - 未登录：LoginScreen。
///
/// 在登录态切换时，统一驱动其它状态：
/// - 登录后：ChatState.bootstrap() + BillingState.refreshAll() + DingState.bootstrap()
/// - 登出后：ChatState.reset() + BillingState.reset() + DingState.reset()
/// 这样切换账号时不会把上一个用户的 chat / inbox 留给下一个用户。
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool? _wasAuthed;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();

    // bootstrap 期间不要触发任何 chat/inbox 的 reset/bootstrap，
    // 否则首次冷启动会把 Hive 里上次的会话清掉（#3）。
    if (auth.bootstrapping) return const _SplashScreen();

    final isAuthed = auth.isAuthenticated;

    if (_wasAuthed != isAuthed) {
      final wasAuthed = _wasAuthed;
      _wasAuthed = isAuthed;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (isAuthed) {
          // 切换账号：登录前若之前已登录过，先清掉旧用户的本地缓存。
          // wasAuthed == null 表示这是冷启动后第一次确认登录态，不要 reset。
          if (wasAuthed == true) {
            context.read<ChatState>().reset();
            context.read<DingState>().reset();
          }
          context.read<ChatState>().bootstrap();
          context.read<BillingState>().refreshAll();
          context.read<DingState>().bootstrap();
        } else if (wasAuthed == true) {
          // 仅在从已登录显式跳到未登录（登出 / 强制下线）时才清空本地缓存，
          // 避免冷启动 splash 阶段误把 Hive 清掉。
          context.read<ChatState>().reset();
          context.read<BillingState>().reset();
          context.read<DingState>().reset();
        }
      });
    }

    return isAuthed ? const HomeScreen() : const LoginScreen();
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.amber,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.bolt, color: Colors.black, size: 48),
            ),
            const SizedBox(height: 16),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.amber),
            ),
          ],
        ),
      ),
    );
  }
}
