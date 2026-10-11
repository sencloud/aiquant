import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../miniapp_icons.dart';
import '../miniapp_models.dart';
import '../render/components.dart';
import '../render/spec_runtime.dart';

/// 发现页上的一张小应用卡片：图标 + 标题 + card_view（只读，用最近一次取数）。
class MiniAppCard extends StatelessWidget {
  const MiniAppCard({
    super.key,
    required this.spec,
    required this.title,
    required this.icon,
    this.run,
    this.inputs = const {},
    this.loading = false,
    this.onTap,
    this.onLongPress,
    this.badge,
    this.now,
  });

  final Map<String, dynamic> spec;
  final String title;
  final String icon;
  final MiniAppRun? run;
  final Map<String, dynamic> inputs;
  final bool loading;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? badge;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final rt = SpecRuntime(spec);
    final clock = now ?? DateTime.now;
    final resolved = rt.resolveInputs(
        run?.inputs.isNotEmpty == true ? run!.inputs : inputs, clock());
    final needsData = rt.hasData;
    final env = rt.env(inputs: resolved, data: run?.data ?? const {}, now: clock);
    final failedAll = needsData &&
        run != null &&
        run!.errors.isNotEmpty &&
        run!.data.isEmpty;
    return Material(
      color: AppColors.bgSurface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: AppColors.accentSoft,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(miniAppIcon(icon), size: 14, color: AppColors.amber),
                ),
                const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.caption.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600)),
                ),
                if (badge != null)
                  Text(badge!,
                      style: AppType.micro.copyWith(color: AppColors.textTertiary)),
                if (loading)
                  SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: AppColors.textTertiary)),
              ]),
              const SizedBox(height: AppSpace.sm),
              if (needsData && run == null)
                _Skeleton()
              else if (failedAll)
                Text('数据暂时取不到',
                    style: AppType.caption.copyWith(color: AppColors.textTertiary))
              else
                MiniAppRenderer(
                  runtime: rt,
                  node: rt.cardView,
                  env: env,
                  compact: true,
                  errors: run?.errors ?? const {},
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget bar(double w) => Container(
          width: w,
          height: 12,
          margin: const EdgeInsets.only(bottom: 6),
          decoration: BoxDecoration(
            color: AppColors.bgRaised,
            borderRadius: BorderRadius.circular(4),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [bar(48), bar(96)],
    );
  }
}
