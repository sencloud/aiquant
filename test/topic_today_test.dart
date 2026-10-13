import 'dart:io';

import 'package:fincept_app/core/storage/hive_setup.dart';
import 'package:fincept_app/core/topic/topic_log_screen.dart';
import 'package:fincept_app/core/topic/topic_registry.dart';
import 'package:fincept_app/core/topic/topic_today_service.dart';
import 'package:fincept_app/core/topic/topic_pack.dart';
import 'package:fincept_app/screens/hub/hub_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';

/// 首页那三个数不能是编的：这里钉住「起算日记录 → 今天的天数」这条通路，
/// 以及没有记录时必须照实写「还没有判断」。
void main() {
  setUpAll(() async {
    final dir = await Directory.systemTemp.createTemp('hive_today');
    Hive.init(dir.path);
    await registerHiveAdapters();
    await openAppBoxes();
  });

  setUp(() async {
    await prefsBox.clear();
  });

  test('没有起算日记录：不编数字，也不画轨道', () {
    final today = resolveToday(builtInTopicPacks().firstWhere((p) => p.id == 'coffee'));
    expect(today, isNotNull);
    expect(today!.hasValue, isFalse, reason: '没有记录时不能有数');
    expect(today.value, isNull);
    expect(today.rail, isNull, reason: '没有数就不该有轨道');
    expect(today.verdict, '还没有判断');
  });

  test('记了烘焙日：按 14 天窗口算出还剩几天，并带上可追溯的小票', () async {
    final coffee =
        builtInTopicPacks().firstWhere((p) => p.id == 'coffee');
    final at = DateTime.now().subtract(const Duration(days: 10));
    await saveTopicLog('coffee', [
      TopicLogEntry(title: '茉香日晒 200g', note: '烘焙 10-01', at: at, start: true),
    ]);

    final today = resolveToday(coffee)!;
    expect(today.value, '4', reason: '14 - 10 = 还剩 4 天');
    expect(today.unit, '天');
    expect(today.verdict, '这几天得喝完', reason: '剩 4/14 < 40%');
    expect(today.rail, isNotNull);
    expect(today.rail!.length, 8);
    expect(today.ticket, contains('烘焙日'));
    expect(today.ticket, contains('14 天'));

    // 新鲜的一条：判定词换成宽松档。
    await saveTopicLog('coffee', [
      TopicLogEntry(
          title: '新到的豆子',
          at: DateTime.now().subtract(const Duration(days: 1)),
          start: true),
    ]);
    final fresh = resolveToday(coffee)!;
    expect(fresh.value, '13');
    expect(fresh.verdict, '在最香的时候');
  });

  test('自由文本不算数：只有显式标了起算日的记录才参与计算', () async {
    final cat = builtInTopicPacks().firstWhere((p) => p.id == 'cat');
    await saveTopicLog('cat', [
      TopicLogEntry(
          title: '随手记一条',
          at: DateTime.now().subtract(const Duration(days: 20))),
    ]);
    expect(resolveToday(cat)!.hasValue, isFalse);
  });

  test('露营/汉服没有窗口：判断由 AI 在对话里给，首页不摆数字', () {
    for (final id in ['camping', 'hanfu', 'money', 'fishing']) {
      final pack = builtInTopicPacks().firstWhere((p) => p.id == id);
      expect(pack.window, isNull, reason: id);
      final today = resolveToday(pack);
      // 露营/汉服有静态模板（没有数）；钱与钓鱼的指数在圈内算，模板为空。
      if (today != null) expect(today.hasValue, isFalse, reason: id);
    }
  });

  testWidgets('记录页：记一条并标成起算日 → 这个圈今天就有数了', (tester) async {
    final coffee = builtInTopicPacks().firstWhere((p) => p.id == 'coffee');
    await tester.pumpWidget(MultiProvider(
      providers: [
        Provider<TopicPack>.value(value: coffee),
        ChangeNotifierProvider(create: (_) => HubState()),
      ],
      child: const MaterialApp(home: TopicLogScreen()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('还没有记录'), findsOneWidget);

    // 空状态里的主按钮 → 打开「记一条」。
    await tester.tap(find.text('记第一条'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('log-title')), '茉香日晒 200g');
    // 勾上「这条是烘焙日」。
    await tester.tap(find.byKey(const ValueKey('log-start')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final entries = loadTopicLog('coffee');
    expect(entries.length, 1);
    expect(entries.first.title, '茉香日晒 200g');
    expect(entries.first.start, isTrue, reason: '勾了起算日才算数');
    expect(resolveToday(coffee)!.hasValue, isTrue);
  });
}
