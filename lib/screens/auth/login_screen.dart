import 'dart:async';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../core/api/auth_models.dart';
import '../../state/auth_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/legal_links.dart';

/// 登录页：邮箱验证码登录 + （仅 iOS）Apple 登录。
///
/// 个人开发者无法接入微信开放平台 / 国内短信，故主登录方式为邮箱验证码；
/// iOS 额外保留 Apple 登录（App Store 审核要求），安卓仅邮箱登录。
///
/// 两种进入方式：
/// - 根级（[modal] = false）：整页登录（非默认启动页）。
/// - 模态（[modal] = true）：由 requireLogin 在「我的」/ 发送消息等触点弹出，
///   左上角显示关闭按钮，登录成功后自动 pop 回原页面。
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.modal = false});

  /// 是否以模态弹窗形式打开（显示关闭按钮 + 成功后自动关闭）。
  final bool modal;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _codeCtrl = TextEditingController();

  bool _busy = false; // Apple 登录中
  bool _sendingCode = false; // 正在请求验证码
  bool _verifying = false; // 邮箱验证码登录中
  int _countdown = 0; // 重新获取验证码倒计时
  Timer? _timer;
  String? _error;

  bool get _canShowApple {
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isMacOS;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  bool _isValidEmail(String s) {
    final re = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return re.hasMatch(s);
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _countdown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _countdown--;
        if (_countdown <= 0) t.cancel();
      });
    });
  }

  Future<void> _sendCode() async {
    final email = _emailCtrl.text.trim();
    if (!_isValidEmail(email)) {
      setState(() => _error = '请输入有效的邮箱地址');
      return;
    }
    setState(() {
      _sendingCode = true;
      _error = null;
    });
    try {
      await context.read<AuthState>().sendEmailCode(email);
      _startCountdown();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } on DioException catch (_) {
      setState(() => _error = '网络连接失败，请检查网络后再试。');
    } catch (e) {
      setState(() => _error = '获取验证码失败：$e');
    } finally {
      if (mounted) setState(() => _sendingCode = false);
    }
  }

  Future<void> _verifyEmail() async {
    final email = _emailCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    if (!_isValidEmail(email)) {
      setState(() => _error = '请输入有效的邮箱地址');
      return;
    }
    if (code.length != 6) {
      setState(() => _error = '请输入 6 位验证码');
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await context.read<AuthState>().verifyEmail(email: email, code: code);
      if (mounted &&
          widget.modal &&
          context.read<AuthState>().isAuthenticated) {
        Navigator.of(context).maybePop();
        return;
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } on DioException catch (_) {
      setState(() => _error = '网络连接失败，请检查网络后再试。');
    } catch (e) {
      setState(() => _error = '登录失败：$e');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _signInWithApple() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AuthState>().signInWithApple();
      if (mounted &&
          widget.modal &&
          context.read<AuthState>().isAuthenticated) {
        Navigator.of(context).maybePop();
        return;
      }
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        // 用户主动取消
      } else {
        setState(() => _error = '登录失败：${e.message}');
      }
    } on ApiException catch (e) {
      setState(() => _error = '登录失败\n${e.message}');
    } on DioException catch (_) {
      setState(() => _error = '网络连接失败，请检查网络后再试。');
    } catch (e) {
      setState(() => _error = '登录失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final anyBusy = _busy || _verifying;
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: SafeArea(
        child: Stack(
          children: [
            if (widget.modal)
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: Icon(Icons.close, color: AppColors.textSecondary),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 40, 28, 24),
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.amber.withValues(alpha: 0.45),
                          blurRadius: 24,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(
                      'assets/branding/app_icon.png',
                      width: 84,
                      height: 84,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text('喜宽',
                      style: TextStyle(
                          color: AppColors.amber,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 6)),
                  const SizedBox(height: 6),
                  Text('AI 投资助手 · 聊行情、管组合、做日报',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 13)),
                  const SizedBox(height: 32),
                  if (_error != null) _errorBanner(_error!),
                  _emailField(enabled: !anyBusy),
                  const SizedBox(height: 12),
                  _codeField(enabled: !anyBusy),
                  const SizedBox(height: 18),
                  _LoginButton(busy: _verifying, onPressed: _verifyEmail),
                  if (_canShowApple) ...[
                    const SizedBox(height: 20),
                    _orDivider(),
                    const SizedBox(height: 20),
                    _AppleButton(busy: _busy, onPressed: _signInWithApple),
                  ],
                  const SizedBox(height: 18),
                  const LegalLinksFootnote(),
                  const SizedBox(height: 6),
                  Text(
                    '验证码 5 分钟内有效，仅用于登录验证。\n我们不会向第三方分享你的邮箱。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                        height: 1.6),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emailField({required bool enabled}) {
    return TextField(
      controller: _emailCtrl,
      enabled: enabled,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      textInputAction: TextInputAction.next,
      style: TextStyle(color: AppColors.textPrimary, fontSize: 15),
      decoration: _inputDecoration(
        hint: '请输入邮箱地址',
        icon: Icons.alternate_email,
      ),
    );
  }

  Widget _codeField({required bool enabled}) {
    final canSend = enabled && !_sendingCode && _countdown == 0;
    return TextField(
      controller: _codeCtrl,
      enabled: enabled,
      keyboardType: TextInputType.number,
      maxLength: 6,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: TextStyle(
          color: AppColors.textPrimary, fontSize: 15, letterSpacing: 4),
      decoration: _inputDecoration(
        hint: '6 位验证码',
        icon: Icons.lock_outline,
        counterText: '',
        suffix: Padding(
          padding: const EdgeInsets.only(right: 6),
          child: TextButton(
            onPressed: canSend ? _sendCode : null,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.amber,
              disabledForegroundColor: AppColors.textTertiary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              _sendingCode
                  ? '发送中…'
                  : _countdown > 0
                      ? '${_countdown}s'
                      : '获取验证码',
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    String? counterText,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      counterText: counterText,
      hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 14),
      prefixIcon: Icon(icon, size: 18, color: AppColors.textSecondary),
      suffixIcon: suffix,
      filled: true,
      fillColor: AppColors.bgRaised,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.borderDim),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.amber, width: 1.5),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.borderDim),
      ),
    );
  }

  Widget _orDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: AppColors.borderDim)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('或',
              style: TextStyle(color: AppColors.textTertiary, fontSize: 12)),
        ),
        Expanded(child: Divider(color: AppColors.borderDim)),
      ],
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
          const Icon(Icons.error_outline, size: 16, color: AppColors.danger),
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

class _LoginButton extends StatelessWidget {
  const _LoginButton({required this.busy, required this.onPressed});
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.amber,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.5),
        ),
        onPressed: busy ? null : onPressed,
        child: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.black),
              )
            : const Text('登录 / 注册'),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
        label: Text(busy ? '登录中…' : '使用 Apple 账号登录'),
      ),
    );
  }
}
