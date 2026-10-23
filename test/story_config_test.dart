import 'package:fincept_app/story/night_shell.dart';
import 'package:fincept_app/story/story_api.dart';
import 'package:fincept_app/story/story_models.dart';
import 'package:fincept_app/story/story_state.dart';
import 'package:fincept_app/story/story_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeApi extends StoryApi {
  _FakeApi(this.config);

  final StoryConfig config;

  @override
  Future<StoryConfig> fetchConfig() async => config;

  @override
  Future<void> saveRun(StoryRun run) async {}
}

void main() {
  test('远程开关只放行配置里的角色', () async {
    final state = StoryState(
      store: MemoryStoryStore(),
      api: _FakeApi(const StoryConfig(
        enabled: true,
        characters: {'suyu'},
        shareEnabled: false,
        maxTurns: 10,
        notice: '',
      )),
    );
    await state.load();

    expect(state.config.shareEnabled, isFalse);
    expect(state.isCharacterEnabled('suyu'), isTrue);
    expect(state.isCharacterEnabled('linxia'), isFalse);
    await expectLater(state.startRoute('linxia'), throwsArgumentError);

    await state.startRoute('suyu');
    expect(state.run?.characterId, 'suyu');
    state.dispose();
  });

  test('总开关关闭时仍能读存档，但入口不可用', () async {
    final state = StoryState(
      store: MemoryStoryStore(),
      api: _FakeApi(const StoryConfig(
        enabled: false,
        characters: {'linxia', 'suyu', 'chenye'},
        shareEnabled: true,
        maxTurns: 40,
        notice: '今晚维护',
      )),
    );
    await state.load();
    expect(state.config.enabled, isFalse);
    expect(state.config.notice, '今晚维护');
    expect(state.isCharacterEnabled('linxia'), isFalse);
    state.dispose();
  });

  test('空 characters 表示全关，不会被默认值补回', () {
    final cfg = StoryConfig.fromJson({'characters': <String>[]});
    expect(cfg.characters, isEmpty);
  });

  testWidgets('总开关关闭时显示「今晚不营业」', (tester) async {
    final state = StoryState(
      store: MemoryStoryStore(),
      api: _FakeApi(const StoryConfig(
        enabled: false,
        characters: {'linxia', 'suyu', 'chenye'},
        shareEnabled: true,
        maxTurns: 40,
        notice: '今晚维护',
      )),
    );
    await state.load();
    await tester.pumpWidget(MaterialApp(home: NightShell(state: state)));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('今晚不营业。'), findsOneWidget);
    expect(find.text('今晚维护'), findsOneWidget);
    state.dispose();
  });
}
