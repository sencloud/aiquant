import 'package:fincept_app/story/night_shell.dart';
import 'package:fincept_app/story/pixel_portrait.dart';
import 'package:fincept_app/story/story_content.dart';
import 'package:fincept_app/story/story_state.dart';
import 'package:fincept_app/story/story_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('vertical slice: intro → contacts → sheet → chat → night end',
      (tester) async {
    final state = StoryState(
      store: MemoryStoryStore(),
      replyDelay: Duration.zero,
    );
    await state.load();

    await tester.pumpWidget(MaterialApp(home: NightShell(state: state)));
    await tester.pumpAndSettle();

    expect(find.text('天亮以前'), findsOneWidget);
    expect(find.text('进入临海'), findsOneWidget);

    await tester.tap(find.text('进入临海'));
    await tester.pumpAndSettle();

    expect(find.text('通讯录'), findsWidgets);
    expect(find.text('林夏，27'), findsOneWidget);
    expect(find.text('苏予，29'), findsOneWidget);
    expect(find.text('陈野，28'), findsOneWidget);

    await tester.tap(find.text('林夏，27'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView).last, const Offset(0, -420));
    await tester.pumpAndSettle();

    expect(find.text('回拨这个号码'), findsOneWidget);
    await tester.tap(find.text('回拨这个号码'));
    await tester.pumpAndSettle();

    expect(find.text('你那边下雨了吗？'), findsOneWidget);
    expect(find.text('下了。没带伞。'), findsOneWidget);

    await tester.tap(find.text('下了。没带伞。'));
    await tester.pumpAndSettle();

    expect(find.text('别动。我带了。'), findsOneWidget);
    expect(find.text('你住几楼？'), findsOneWidget);

    await tester.tap(find.text('七楼，走廊尽头。'));
    await tester.pumpAndSettle();

    expect(find.text('第 1 夜 · 完'), findsOneWidget);
    expect(find.text('收下这一夜'), findsOneWidget);

    await tester.tap(find.text('收下这一夜'));
    await tester.pumpAndSettle();

    expect(find.text('今天拍到一张好看的。'), findsOneWidget);
    expect(find.text('第 2 夜 · 习惯'), findsWidgets);
  });

  testWidgets('all six characters have a distinct portrait and expression set',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: const Color(0xFF0E1118),
          body: SingleChildScrollView(
            child: Wrap(
              children: [
                for (final c in kNightSeason.characters)
                  for (final e in c.expressions)
                    SizedBox(
                      width: 72,
                      height: 99,
                      child: PixelPortrait(character: c, expression: e),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(kNightSeason.characters.length, 6);
    expect(kNightSeason.characters.map((c) => c.hairStyle).toSet().length, 6);
    expect(kNightSeason.characters.map((c) => c.accessory).toSet().length, 6);
    expect(kNightSeason.characters.map((c) => c.id).toSet().length, 6);
  });
}
