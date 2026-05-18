import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config/app_config.dart';
import '../theme/app_theme.dart';

/// 用户协议 + 隐私政策可点击链接。
///
/// - 登录页：[LegalLinksFootnote] 单行小字提示式
/// - 设置页：[LegalLinksRow] 块状双按钮入口
class LegalLinksFootnote extends StatelessWidget {
  const LegalLinksFootnote({
    super.key,
    this.fontSize = 11,
    this.color,
  });

  final double fontSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textTertiary;
    final link = TextStyle(
      color: AppColors.amber,
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: AppColors.amber,
    );
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: TextStyle(color: c, fontSize: fontSize, height: 1.6),
        children: [
          const TextSpan(text: '登录即表示同意'),
          TextSpan(
            text: '《用户协议》',
            style: link,
            recognizer: TapGestureRecognizer()
              ..onTap = () => _openUrl(AppConfig.instance.termsUrl),
          ),
          const TextSpan(text: '与'),
          TextSpan(
            text: '《隐私政策》',
            style: link,
            recognizer: TapGestureRecognizer()
              ..onTap = () => _openUrl(AppConfig.instance.privacyUrl),
          ),
        ],
      ),
    );
  }
}

class LegalLinksRow extends StatelessWidget {
  const LegalLinksRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _LegalTile(
            icon: Icons.description_outlined,
            label: '用户协议',
            onTap: () => _openUrl(AppConfig.instance.termsUrl),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _LegalTile(
            icon: Icons.privacy_tip_outlined,
            label: '隐私政策',
            onTap: () => _openUrl(AppConfig.instance.privacyUrl),
          ),
        ),
      ],
    );
  }
}

class _LegalTile extends StatelessWidget {
  const _LegalTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgRaised,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppColors.borderDim),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 18, color: AppColors.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(Icons.open_in_new,
                  size: 14, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _openUrl(String url) async {
  final uri = Uri.parse(url);
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
