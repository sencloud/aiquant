import 'package:flutter/material.dart';

import '../../core/app_profile.dart';
import '../../theme/app_theme.dart';

/// 喜爱的头像：写真（`assets/portraits/xiai.jpg`），缺图时回落到品牌字。
class CompanionAvatar extends StatelessWidget {
  const CompanionAvatar({super.key, this.size = 40, this.radius = 8});

  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.asset(
        'assets/portraits/xiai.jpg',
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          color: AppColors.amber,
          child: Text(
            kBrandMark,
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.44,
              fontWeight: FontWeight.w600,
              fontFamilyFallback: AppType.sansFallback,
            ),
          ),
        ),
      ),
    );
  }
}
