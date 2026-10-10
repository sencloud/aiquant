import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/config/app_config.dart';
import '../theme/app_theme.dart';

/// 用户协议 + 隐私政策可点击链接。
///
/// - 登录页：[LegalLinksFootnote] 单行小字提示式
/// - 设置页：[LegalLinksRow] 两行静默入口（微信式：条款是文字，不是按钮）
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
    return Column(
      children: [
        _LegalLine(
          label: '用户协议',
          onTap: () => _openUrl(AppConfig.instance.termsUrl),
        ),
        _LegalLine(
          label: '隐私政策',
          onTap: () => _openUrl(AppConfig.instance.privacyUrl),
        ),
      ],
    );
  }
}

/// 一行条款入口：和分组卡里的行同一套节奏，只是没有图标、薄一点。
class _LegalLine extends StatelessWidget {
  const _LegalLine({
    required this.label,
    required this.onTap,
  });
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.lg, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: AppType.body.copyWith(color: AppColors.textPrimary)),
              ),
              Icon(Icons.open_in_new, size: 15, color: AppColors.textTertiary),
              const SizedBox(width: AppSpace.xs),
              Icon(Icons.chevron_right,
                  size: 20, color: AppColors.textTertiary),
            ],
          ),
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
