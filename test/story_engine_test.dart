import 'package:fincept_app/story/story_content.dart';
import 'package:fincept_app/story/story_state.dart';
import 'package:fincept_app/story/story_store.dart';
import 'package:flutter_test/flutter_test.dart';

const _suyuGood = [
  's1b1_honest',
  's1b2_place',
  's2b1_give',
  's2b2_flirt',
  's3b1_truth',
  's3b2_self',
  's4b1_echo',
  's4b2_wait',
  's5b1_want',
  's5b2_stay',
  's6b1_want',
  's6b2_stay',
  's7b1_down',
  's7b2_return',
];

const _chenyeGood = [
  'c1b1_yes',
  'c1b2_film',
  'c2b1_yes',
  'c2b2_admit',
  'c3b1_watch',
  'c3b2_self',
  'c4b1_go',
  'c4b2_come',
  'c5b1_stay',
  'c5b2_yes',
  'c6b1_stay',
  'c6b2_self',
  'c7b1_down',
  'c7b2_self',
];

const _linxiaGood = [
  'n1b1_rain',
  'n1b2_floor',
  'n2b1_photo',
  'n2b2_yes',
  'n3b1_see',
  'n3b2_why',
  'n4b1_echo',
  'n4b2_wait',
  'n5b1_return',
  'n5b2_yes',
  'n6b1_stay',
  'n6b2_stay',
  'n7b1_down',
  'n7b2_self',
];

Future<void> _play(StoryState state, List<String> choices) async {
  for (final id in choices) {
    if (state.nightComplete) {
      await state.endNight();
    }
    await state.choose(id);
  }
  if (state.nightComplete) await state.endNight();
}

void main() {
  test('season has six characters and three playable routes', () {
    expect(kNightSeason.characters.length, 6);
    expect(kNightSeason.routeOf('linxia'), isNotNull);
    expect(kNightSeason.routeOf('suyu'), isNotNull);
    expect(kNightSeason.routeOf('chenye'), isNotNull);
    expect(kNightSeason.characters.where((c) => c.routeOpen).length, 3);
  });

  test('good route reaches HE and unlocks the ending', () async {
    final state = StoryState(
      store: MemoryStoryStore(),
      replyDelay: Duration.zero,
    );
    await state.load();
    await state.acceptIntro();
    await state.startRoute('linxia');

    expect(state.run!.night, 1);
    expect(state.run!.hearts, 2);

    await _play(state, _linxiaGood);

    expect(state.finished, isTrue);
    expect(state.ending, isNotNull);
    expect(state.ending!.id, 'linxia_he');
    expect(state.unlockedEndings, contains('linxia_he'));
  });

  test('all three good routes unlock the true ending', () async {
    final state = StoryState(
      store: MemoryStoryStore(),
      replyDelay: Duration.zero,
    );
    await state.load();
    await state.acceptIntro();

    final routes = <(String, List<String>)>[
      ('linxia', _linxiaGood),
      ('suyu', _suyuGood),
      ('chenye', _chenyeGood),
    ];
    for (final (id, choices) in routes) {
      await state.startRoute(id);
      await _play(state, choices);
      expect(state.ending, isNotNull);
      expect(state.ending!.id, '${id}_he');
    }

    expect(state.trueEndingUnlocked, isTrue);
    expect(state.trueEnding.id, 'true_ending');
  });

  test('lying at night 6 reaches BE even with high hearts', () async {
    final state = StoryState(
      store: MemoryStoryStore(),
      replyDelay: Duration.zero,
    );
    await state.load();
    await state.acceptIntro();
    await state.startRoute('linxia');

    await _play(state, [
      ..._linxiaGood.take(10),
      'n6b1_home',
      'n6b2_lie',
      'n7b1_down',
      'n7b2_self',
    ]);

    expect(state.finished, isTrue);
    expect(state.ending!.id, 'linxia_be');
  });

  test('safety input pauses the story with a system message', () async {
    final state = StoryState(
      store: MemoryStoryStore(),
      replyDelay: Duration.zero,
    );
    await state.load();
    await state.acceptIntro();
    await state.startRoute('linxia');

    await state.send('我不想活了');

    expect(state.safetyPaused, isTrue);
    expect(state.messages.last.safety, isTrue);
    expect(state.messages.last.text, contains('心理援助'));

    await state.acknowledgeSafety();
    expect(state.safetyPaused, isFalse);
  });

  test('save round-trips through the store', () async {
    final store = MemoryStoryStore();
    final first = StoryState(store: store, replyDelay: Duration.zero);
    await first.load();
    await first.acceptIntro();
    await first.startRoute('linxia');
    await first.choose('n1b1_rain');
    first.dispose();

    final second = StoryState(store: store, replyDelay: Duration.zero);
    await second.load();

    expect(second.introSeen, isTrue);
    expect(second.run!.night, 1);
    expect(second.run!.beat, 1);
    expect(second.run!.hearts, 3);
    expect(second.run!.flags, contains('answered_rain'));
    expect(second.messages, isNotEmpty);
  });

  test('reset clears the run but keeps the intro seen', () async {
    final state = StoryState(
      store: MemoryStoryStore(),
      replyDelay: Duration.zero,
    );
    await state.load();
    await state.acceptIntro();
    await state.startRoute('linxia');
    await state.resetAll();

    expect(state.run, isNull);
    expect(state.introSeen, isTrue);
    expect(state.unlockedEndings, isEmpty);
  });
}
