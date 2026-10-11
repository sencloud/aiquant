import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import 'fishing_locator.dart';

/// 定位授权流程：先讲清楚为什么要位置，再弹系统框；拒绝过就引导去设置或手动选地点。
///
/// 返回 true = 已经可以取位置。
Future<bool> ensureLocationAccess(
  BuildContext context,
  FishingLocator locator, {
  required String purpose,
}) async {
  var a = await locator.access();
  if (a == LocAccess.granted) return true;
  if (!context.mounted) return false;
  if (a == LocAccess.notDetermined) {
    final go = await showLocationExplainer(context, purpose: purpose);
    if (go != true) return false;
    a = await locator.request();
    if (a == LocAccess.granted) return true;
    if (!context.mounted) return false;
  }
  await showLocationUnavailable(context, locator, access: a);
  return false;
}

/// 申请前的说明（系统授权框只弹一次，先让用户知道用途和边界）。
Future<bool?> showLocationExplainer(BuildContext context,
    {required String purpose}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.bgSurface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => LocationExplainerSheet(purpose: purpose),
  );
}

class LocationExplainerSheet extends StatelessWidget {
  const LocationExplainerSheet({super.key, required this.purpose});
  final String purpose;

  @override
  Widget build(BuildContext context) {
    Widget point(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: AppSpace.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, size: 18, color: AppColors.amber),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: AppType.body.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(body,
                        style: AppType.caption.copyWith(
                            color: AppColors.textSecondary, height: 1.5)),
                  ],
                ),
              ),
            ],
          ),
        );
    return SafeArea(
      child: Padding(
        key: const Key('loc-explainer'),
        padding: const EdgeInsets.fromLTRB(
            AppSpace.xl, AppSpace.xl, AppSpace.xl, AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('开启定位',
                style: AppType.title.copyWith(color: AppColors.textPrimary)),
            const SizedBox(height: AppSpace.xs),
            Text(purpose,
                style: AppType.caption
                    .copyWith(color: AppColors.textSecondary, height: 1.5)),
            const SizedBox(height: AppSpace.lg),
            point(Icons.wb_twilight_rounded, '按你所在的位置算出钓指数',
                '不用再手动输入城市；查天气只发送约 1 公里精度的坐标。'),
            point(Icons.map_outlined, '在地图上标记私人钓点',
                '显示你在哪，一键把当前位置存成钓点；钓点只有你自己能看到。'),
            point(Icons.lock_outline_rounded, '只在使用时获取，不记录行踪',
                '不在后台定位，不保存你的位置历史；随时可以在系统设置里关闭。'),
            const SizedBox(height: AppSpace.sm),
            FilledButton(
              key: const Key('loc-allow'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('继续'),
            ),
            TextButton(
              key: const Key('loc-later'),
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('先不用，手动选地点'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 拒绝过 / 系统定位关闭时：给去设置的入口，同时说明可以手动选地点。
Future<void> showLocationUnavailable(
  BuildContext context,
  FishingLocator locator, {
  required LocAccess access,
}) {
  final off = access == LocAccess.serviceOff;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      key: const Key('loc-denied'),
      title: Text(off ? '系统定位已关闭' : '没有定位权限'),
      content: Text(off
          ? '在「设置 → 隐私与安全性 → 定位服务」打开后即可使用。不开也没关系，可以手动输入城市或水库名。'
          : '喜爱目前不能使用你的位置。可以去系统设置里改为「使用 App 期间」；不开也没关系，可以手动输入城市或水库名。'),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('手动选地点')),
        if (!off)
          TextButton(
            key: const Key('loc-open-settings'),
            onPressed: () {
              Navigator.pop(ctx);
              locator.openSettings();
            },
            child: const Text('去设置'),
          ),
      ],
    ),
  );
}
