import 'package:flutter/material.dart';

import '../../services/analytics.dart';
import '../../theme/app_theme.dart';
import '../settings/settings_screen.dart'
    show rechargeAvailable, showRechargeSheet;

/// 余额不足：说清楚差多少，iOS 直接拉起现有的内购充值面板；
/// 其他平台暂未开放充值，只提示。
Future<void> showInsufficientBalance(
  BuildContext context, {
  required int need,
  required String what,
}) async {
  Analytics.instance
      .track(Analytics.evPaywallInsufficient, {'need': need, 'what': what});
  final canPay = rechargeAvailable;
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('喜点不足'),
      content: Text(
        canPay
            ? '$what需要 $need 喜点，当前余额不够。充值后回到这里即可继续。'
            : '$what需要 $need 喜点，当前余额不够。目前仅 iPhone 端支持充值，'
                '请在 iPhone 上充值后再试。',
        style: AppType.body.copyWith(color: AppColors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('算了'),
        ),
        if (canPay)
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('去充值'),
          ),
      ],
    ),
  );
  if (go == true && context.mounted) await showRechargeSheet(context);
}
