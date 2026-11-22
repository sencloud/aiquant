import 'package:fincept_app/screens/shell/xiai_shell.dart';
import 'package:fincept_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpShell(
    WidgetTester tester, {
    WidgetBuilder? watchPageBuilder,
  }) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: XiaiShell(
          watchPageBuilder: watchPageBuilder ??
              (_) => const Scaffold(
                    body: Center(child: Text('看盘测试页')),
                  ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('只保留嘻，AI 与我的两个页签', (tester) async {
    await pumpShell(tester);

    expect(find.text('嘻，AI'), findsWidgets);
    expect(find.text('我的'), findsOneWidget);
    expect(find.text('搭子'), findsNothing);
    expect(find.text('云搭子'), findsNothing);
    expect(find.text('我的搭子'), findsNothing);
    expect(find.text('从相册选择成交截图'), findsOneWidget);
    expect(find.text('最近复盘'), findsOneWidget);

    await tester.tap(find.text('我的'));
    await tester.pump();

    expect(find.text('嘻，AI 用户'), findsOneWidget);
    expect(find.text('最近复盘'), findsOneWidget);
    expect(find.text('我的交易记录'), findsOneWidget);
    expect(find.text('看盘'), findsOneWidget);
    expect(find.text('电脑连接'), findsOneWidget);
    expect(find.text('数据与隐私'), findsOneWidget);
    expect(find.text('我的搭子'), findsNothing);
  });

  testWidgets('我的页可以进入看盘与交易记录', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.text('我的'));
    await tester.pump();

    await tester.tap(find.text('看盘'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('看盘测试页'), findsOneWidget);

    Navigator.of(
      tester.element(find.text('看盘测试页')),
    ).pop();
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.text('我的交易记录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('还没有保存过交易复盘'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
