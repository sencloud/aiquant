import 'package:fincept_app/screens/settings/settings_screen.dart';
import 'package:fincept_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 「我的」页面展示层的视觉基线：把新世界的部件用固定数据拼成整页渲染成图，
/// 供人眼核对（`flutter test --update-goldens test/profile_page_golden_test.dart`）。
/// 它不替代真机检查，但能在改版时第一时间抓出布局崩坏。
void main() {
  testWidgets('我的页视觉基线', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(ThemeMode.dark),
        home: Scaffold(
          backgroundColor: AppColors.bgBase,
          appBar: AppBar(title: const Text('我的')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 36),
            children: [
              const ProfileFolderHead(nickname: '盈盈3895', uid: '8c1cc2a4-1527'),
              const SizedBox(height: 22),
              ProfileCreditBureau(
                balance: 150,
                loading: false,
                onRecharge: () {},
                onLedger: () {},
              ),
              const SizedBox(height: 30),
              const ProfileRule('随身工具'),
              ProfileIndexRow(
                icon: Icons.star_outline,
                title: '我的自选',
                note: '股票 / ETF / 期货',
                onTap: () {},
              ),
              ProfileIndexRow(
                icon: Icons.alarm,
                title: '定时提醒',
                note: '按点让 AI 执行任务',
                badge: 3,
                onTap: () {},
              ),
              ProfileIndexRow(
                icon: Icons.receipt_long_outlined,
                title: '喜点流水',
                note: '每一笔消耗与充值',
                onTap: () {},
              ),
              const SizedBox(height: 30),
              const ProfileRule('账号与条款'),
              ProfileIndexRow(
                icon: Icons.logout,
                title: '退出登录',
                note: '',
                danger: true,
                onTap: () {},
              ),
              const SizedBox(height: 26),
              const ProfileColophon(version: 'v1.0.6'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/profile_page.png'),
    );
  });
}
