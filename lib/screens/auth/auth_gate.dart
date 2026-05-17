import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_state.dart';
import '../../state/billing_state.dart';
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
/// - 登录后：BillingState.refreshAll() + DingState.bootstrap()
/// - 登出后：BillingState.reset() + DingState.reset()
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
    final isAuthed = auth.isAuthenticated;

    if (_wasAuthed != isAuthed) {
      _wasAuthed = isAuthed;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (isAuthed) {
          context.read<BillingState>().refreshAll();
          context.read<DingState>().bootstrap();
        } else {
          context.read<BillingState>().reset();
          context.read<DingState>().reset();
        }
      });
    }

    if (auth.bootstrapping) return const _SplashScreen();
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
