import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../watch/widgets/market_brand.dart';

class CloudBuddyScreen extends StatelessWidget {
  const CloudBuddyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.bgBase,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const SizedBox(
              height: 52,
              child: Center(child: Text('云搭子', style: AppType.title)),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 20, 28, 40),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              width: 148,
                              height: 148,
                              decoration: const BoxDecoration(
                                color: Color(0xFFE8EEFF),
                                shape: BoxShape.circle,
                              ),
                            ),
                            Container(
                              width: 92,
                              height: 92,
                              decoration: BoxDecoration(
                                color: AppColors.bgSurface,
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: AppColors.borderDim,
                                  width: 0.5,
                                ),
                              ),
                              child: const Icon(
                                Icons.cloud_queue_rounded,
                                size: 48,
                                color: Color(0xFF1C49C9),
                              ),
                            ),
                            const Positioned(
                              right: 24,
                              bottom: 18,
                              child: MarketBrandMark(size: 34),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text(
                          '云搭子正在建设',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamilyFallback: AppType.sansFallback,
                            fontSize: 24,
                            height: 1.25,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          '以后她会把记忆、工作习惯和状态带到每一台设备。'
                          '现在先把位置留给她。',
                          textAlign: TextAlign.center,
                          style: AppType.read.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 26),
                        const _RoadmapLine(
                          icon: Icons.devices_rounded,
                          title: '跨设备陪伴',
                          note: '手机、平板和桌面看到同一个搭子',
                        ),
                        const _RoadmapLine(
                          icon: Icons.auto_awesome_outlined,
                          title: '云端记忆',
                          note: '换设备也不会忘记一起工作的日子',
                        ),
                        const _RoadmapLine(
                          icon: Icons.people_alt_outlined,
                          title: '一起协作',
                          note: '搭子之间接力处理日常工作',
                        ),
                        const SizedBox(height: 22),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8EEFF),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            child: Text(
                              '待建设 · 暂未开放',
                              style: TextStyle(
                                fontFamilyFallback: AppType.sansFallback,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1C49C9),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoadmapLine extends StatelessWidget {
  const _RoadmapLine({
    required this.icon,
    required this.title,
    required this.note,
  });

  final IconData icon;
  final String title;
  final String note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borderDim, width: 0.5),
            ),
            child: Icon(icon, size: 20, color: const Color(0xFF1C49C9)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppType.body),
                const SizedBox(height: 2),
                Text(
                  note,
                  style: AppType.micro.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
