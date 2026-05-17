import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../core/api/auth_models.dart';
import '../../state/auth_state.dart';
import '../../theme/app_theme.dart';

/// 登录页：仅 Apple Sign In（个人开发者完全免费、TestFlight 审核必须支持）。
///
/// 进入条件：AuthState.isAuthenticated == false。
/// 成功后由 AuthGate 切换到 HomeScreen。
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _busy = false;
  String? _error;

  bool get _canShowApple {
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isMacOS;
  }

  Future<void> _signInWithApple() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthState>().signInWithApple();
    } on SignInWithAppleAuthorizationException catch (e) {
      // 用户主动取消
      if (e.code == AuthorizationErrorCode.canceled) {
        // ignore
      } else {
        setState(() => _error = '登录失败：${e.message}');
      }
    } on ApiException catch (e) {
      setState(() => _error = '${e.code}\n${e.message}');
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  color: AppColors.amber,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.amber.withValues(alpha: 0.45),
                      blurRadius: 24,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(Icons.bolt, color: Colors.black, size: 56),
              ),
              const SizedBox(height: 22),
              const Text('AIQuant',
                  style: TextStyle(
                      color: AppColors.amber,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1)),
              const SizedBox(height: 8),
              Text('AI 量化研究助理 · A 股 / ETF / 期货',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
              const Spacer(flex: 3),
              if (_error != null) _errorBanner(_error!),
              if (_canShowApple)
                _AppleButton(busy: _busy, onPressed: _signInWithApple)
              else
                _PlatformUnavailable(),
              const SizedBox(height: 18),
              Text(
                '登录即表示同意《用户协议》与《隐私政策》',
                style: TextStyle(
                    color: AppColors.textTertiary, fontSize: 11),
              ),
              const SizedBox(height: 6),
              Text(
                '我们仅获取 Apple 提供的稳定匿名标识，\n不会读取你的 iCloud 通讯录或位置。',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.textTertiary, fontSize: 11, height: 1.6),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorBanner(String msg) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.12),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline,
              size: 16, color: AppColors.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(msg,
                style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _AppleButton extends StatelessWidget {
  const _AppleButton({required this.busy, required this.onPressed});
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0.3),
        ),
        onPressed: busy ? null : onPressed,
        icon: busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.apple, size: 22),
        label: Text(busy ? '登录中…' : '通过 Apple 账号登录'),
      ),
    );
  }
}

class _PlatformUnavailable extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgRaised,
        border: Border.all(color: AppColors.borderDim),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '当前平台不支持 Apple Sign In，请在 iOS 设备上登录。',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
      ),
    );
  }
}
