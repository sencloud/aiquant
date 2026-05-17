import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_state.dart';
import '../../theme/app_theme.dart';
import '../home/home_screen.dart';
import 'login_screen.dart';

/// AuthGate 是 App 的根 widget。
/// - bootstrap 中：显示启动 splash；
/// - 已登录：HomeScreen；
/// - 未登录：LoginScreen。
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    if (auth.bootstrapping) return const _SplashScreen();
    return auth.isAuthenticated ? const HomeScreen() : const LoginScreen();
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
