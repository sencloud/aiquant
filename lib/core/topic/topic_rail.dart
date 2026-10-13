import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import 'topic_today.dart';

/// 时间轨：八格 + 「现在」一根细线 + 一行刻度。
///
/// 这是兴趣圈的签名交互：把「今天什么时候该去」压成一条不断行的轨道。
/// 换圈时它换色、换尺度（钓鱼按小时、咖啡与养猫按天）。首页与圈内「今天」页
/// 共用同一个组件，保证同一枚签名在两处完全一致。
class TopicRail extends StatelessWidget {
  const TopicRail({
    super.key,
    required this.cells,
    required this.nowPercent,
    this.legend,
    this.maxBar = 28,
  });

  final List<RailCell> cells;
  final double nowPercent;
  final List<String>? legend;
  final double maxBar;

  @override
  Widget build(BuildContext context) {
    final legendStyle = AppType.micro.copyWith(
      color: AppColors.textTertiary,
      fontFamilyFallback: AppType.numericFallback,
      fontWeight: FontWeight.w400,
    );
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: maxBar + 6,
            child: Stack(
              children: [
                Positioned.fill(
                  bottom: 6,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < cells.length; i++) ...[
                        Expanded(
                          child: Container(
                            height: 6 + cells[i].height * (maxBar - 6),
                            decoration: BoxDecoration(
                              color: cells[i].best
                                  ? AppColors.amber
                                  : cells[i].good
                                      ? AppColors.amber.withValues(alpha: 0.38)
                                      : AppColors.borderDim,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4),
                                  bottom: Radius.circular(2)),
                            ),
                          ),
                        ),
                        if (i != cells.length - 1) const SizedBox(width: 3),
                      ],
                    ],
                  ),
                ),
                Positioned(
                  left: nowPercent.clamp(0.0, 1.0) * (constraints.maxWidth - 1),
                  top: 0,
                  bottom: 0,
                  width: 1,
                  child: Container(
                      color: AppColors.textPrimary.withValues(alpha: 0.5)),
                ),
              ],
            ),
          ),
          if (legend != null && legend!.length == 3) ...[
            const SizedBox(height: AppSpace.sm),
            Row(
              children: [
                Text(legend![0], style: legendStyle),
                const Spacer(),
                Row(children: [
                  Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                          color: AppColors.amber, shape: BoxShape.circle)),
                  const SizedBox(width: 5),
                  Text(legend![1],
                      style:
                          legendStyle.copyWith(color: AppColors.textSecondary)),
                ]),
                const Spacer(),
                Text(legend![2], style: legendStyle),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
