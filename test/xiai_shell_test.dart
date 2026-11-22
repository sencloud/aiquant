import 'dart:io';

import 'package:fincept_app/core/storage/hive_setup.dart';
import 'package:fincept_app/screens/shell/xiai_shell.dart';
import 'package:fincept_app/services/trade_review_repository.dart';
import 'package:fincept_app/state/auth_state.dart';
import 'package:fincept_app/state/billing_state.dart';
import 'package:fincept_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    dotenv.testLoad(fileInput: 'API_BASE_URL=http://127.0.0.1:9');
    tempDir = await Directory.systemTemp.createTemp('xiai-shell-test-');
    Hive.init(tempDir.path);
    await Hive.openBox(kBoxPrefs);
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    await TradeReviewStore.instance.clear();
  });

  Future<void> pumpShell(
    WidgetTester tester, {
    WidgetBuilder? watchPageBuilder,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthState>(create: (_) => AuthState()),
            ChangeNotifierProvider<BillingState>(create: (_) => BillingState()),
          ],
          child: XiaiShell(
            chatPageBuilder: (_) => const Scaffold(
              body: Center(child: Text('对话测试页')),
            ),
            watchPageBuilder: watchPageBuilder ??
                (_) => const Scaffold(
                      body: Center(child: Text('看盘测试页')),
                    ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('保留嘻，AI、对话与我的三个页签', (tester) async {
    await pumpShell(tester);

    expect(find.text('嘻，AI'), findsWidgets);
    expect(find.text('对话'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('搭子'), findsNothing);
    expect(find.text('云搭子'), findsNothing);
    expect(find.text('我的搭子'), findsNothing);
    expect(find.text('选择成交截图（可多选）'), findsOneWidget);

    await tester.tap(find.text('对话'));
    await tester.pump();
    expect(find.text('对话测试页'), findsOneWidget);

    await tester.tap(find.text('我的'));
    await tester.pump();

    expect(find.text('喜爱用户'), findsOneWidget);
    expect(find.text('最近复盘'), findsOneWidget);
    expect(find.text('交易记录'), findsOneWidget);
    expect(find.text('看盘'), findsOneWidget);
    expect(find.text('付费会员'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('电脑连接'), findsNothing);
    expect(find.text('数据与隐私'), findsNothing);
    expect(find.text('用户协议'), findsNothing);
    expect(find.text('隐私政策'), findsNothing);
    expect(find.text('关于喜爱'), findsNothing);
    expect(find.textContaining('从成交本身复盘'), findsNothing);
    expect(find.text('我的搭子'), findsNothing);

    final top = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('my-top-white')),
    );
    expect(top.color, AppColors.bgSurface);
    final surface = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('my-page-surface')),
    );
    expect(surface.color, AppColors.bgSurface);
    expect(
      tester.getCenter(find.text('行情终端')).dx,
      greaterThan(tester.getCenter(find.text('看盘')).dx),
    );
    expect(
      tester
          .getCenter(
            find.descendant(
              of: find.byKey(const ValueKey('my-recent-review')),
              matching: find.text('暂无'),
            ),
          )
          .dx,
      greaterThan(tester.getCenter(find.text('最近复盘')).dx),
    );
  });

  testWidgets('设置收纳隐私、协议与产品信息', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('我的'));
    await tester.pump();
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();

    expect(find.text('数据与隐私'), findsOneWidget);
    expect(find.text('用户协议'), findsOneWidget);
    expect(find.text('隐私政策'), findsOneWidget);
    expect(find.text('关于喜爱'), findsOneWidget);
  });

  testWidgets('付费会员入口沿用登录与充值流程', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('我的'));
    await tester.pump();
    await tester.tap(find.text('付费会员'));
    await tester.pumpAndSettle();

    expect(find.text('请输入邮箱地址'), findsOneWidget);
    expect(find.text('获取验证码'), findsOneWidget);
  });

  testWidgets('未登录时可从首页进入邮箱验证码登录', (tester) async {
    await pumpShell(tester);

    expect(find.byKey(const ValueKey('trade-review-login')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('trade-review-login')));
    await tester.pumpAndSettle();

    expect(find.text('请输入邮箱地址'), findsOneWidget);
    expect(find.text('获取验证码'), findsOneWidget);
  });

  testWidgets('我的页可以进入看盘与交易记录', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('看盘'));
    await tester.pumpAndSettle();
    expect(find.text('看盘测试页'), findsOneWidget);

    Navigator.of(
      tester.element(find.text('看盘测试页')),
    ).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('交易记录'));
    await tester.pumpAndSettle();
    expect(find.text('还没有保存过交易复盘'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
