import 'package:fincept_app/screens/shell/xiai_shell.dart';
import 'package:fincept_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('三栏外壳、搭子动作与我的看盘入口可用', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: XiaiShell(
          watchPageBuilder: (_) => const Scaffold(
            body: Center(child: Text('看盘测试页')),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('搭子'), findsWidgets);
    expect(find.text('云搭子'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.textContaining('小桃 · 在线'), findsOneWidget);

    await tester.tap(find.text('换搭子'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('墨墨'), findsOneWidget);
    await tester.tap(find.text('墨墨'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('墨墨 · 在线'), findsOneWidget);

    await tester.tap(find.text('表演'));
    await tester.pump();
    await tester.tap(find.text('唱首歌'));
    await tester.pump();
    expect(find.text('啦啦啦～把烦恼都唱跑～'), findsOneWidget);

    await tester.tap(find.text('我的'));
    await tester.pump();
    expect(find.text('喜AI用户'), findsOneWidget);
    expect(find.text('看盘'), findsOneWidget);
    expect(find.text('我的搭子'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);

    await tester.tap(find.text('看盘'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('看盘测试页'), findsOneWidget);
  });

  testWidgets('云搭子明确展示待建设状态', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: const XiaiShell(),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('云搭子'));
    await tester.pump();
    expect(find.text('云搭子正在建设'), findsOneWidget);
    expect(find.text('待建设 · 暂未开放'), findsOneWidget);
  });
}
