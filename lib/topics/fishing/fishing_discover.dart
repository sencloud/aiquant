import 'package:flutter/material.dart';

import '../../screens/discover/discover_screen.dart';
import '../../widgets/wk_kit.dart';
import 'catches_screen.dart';

/// 喜爱钓鱼「发现」里的内置小应用：渔获（日记 + 私人钓点）。
///
/// 原来是底部页签，现在作为官方内置小应用放进「发现」（页签让位给发现）。
class FishingDiscoverBuiltins extends StatelessWidget {
  const FishingDiscoverBuiltins({super.key});

  @override
  Widget build(BuildContext context) {
    return WkGroup(
      header: '内置',
      children: [
        WkRow(
          key: const Key('discover-catches'),
          icon: Icons.set_meal_rounded,
          title: '渔获',
          subtitle: '渔获日记 · 私人钓点地图',
          onTap: () => openFromDiscover(context, const CatchesScreen(),
              event: 'catches'),
        ),
      ],
    );
  }
}
