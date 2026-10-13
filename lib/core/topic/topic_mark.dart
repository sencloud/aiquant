import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// 圈徽记：一个汉字压在主题色上（喜爱钓鱼 → 「钓」）。
///
/// 兴趣圈首页与圈内「今天」页共用，保证同一个圈在两处的记号完全一致。
class TopicMark extends StatelessWidget {
  const TopicMark(this.text, {super.key, this.size = 22});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.amber,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.onAccent,
          fontSize: size * 0.55,
          fontWeight: FontWeight.w600,
          height: 1.0,
        ),
      ),
    );
  }
}
