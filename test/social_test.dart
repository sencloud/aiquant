import 'package:fincept_app/social/social_models.dart';
import 'package:fincept_app/social/social_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// 新社交的三条硬规矩，用测试钉住：
///   1. 没有由头就没有话（规矩 02）；
///   2. 回声到点才递出去，到点之前能撤回（规矩 07）；
///   3. 「今晚不在」只把话挪到明天早上，不吞掉（规矩 04）。
void main() {
  const target = SocialTarget(
    id: 'event:e1',
    kind: SocialTargetKind.event,
    title: '登记了一条渔获：翘嘴 42cm',
    circleId: 'fishing',
    circleName: '喜爱钓鱼',
    circleMark: '钓',
  );

  SocialState build({DateTime? now}) => SocialState(
        store: MemorySocialStore(),
        clock: now == null ? null : () => now,
      );

  group('说话必须有由头', () {
    test('没有由头 → 不产生任何话', () {
      final s = build();
      expect(s.speak(target: null, text: '在吗'), isNull);
      expect(s.posts, isEmpty);
    });

    test('空文本 → 不产生任何话', () {
      final s = build();
      expect(s.speak(target: target, text: '   '), isNull);
      expect(s.posts, isEmpty);
    });

    test('有由头 → 立刻挂在那件事上', () {
      final s = build();
      final p = s.speak(target: target, text: '水稳的时候你用多重的铅？');
      expect(p, isNotNull);
      expect(p!.delivered, isTrue);
      expect(p.target.id, 'event:e1');
      expect(s.arrived.length, 1);
      expect(s.inFlight, isEmpty);
    });
  });

  group('回声', () {
    test('投给以后：在路上，不立刻到', () {
      final now = DateTime(2026, 10, 16, 21, 30);
      final s = build(now: now);
      final p = s.speak(
        target: target,
        text: '等你下次去北岸',
        deliverAt: DateTime(2026, 10, 17, 9),
        deliveryNote: '明天早上 9:00 递出去',
      );
      expect(p!.isEcho, isTrue);
      expect(p.delivered, isFalse);
      expect(s.inFlight.length, 1);
      expect(s.arrived, isEmpty);
    });

    test('到点才递出去', () {
      var now = DateTime(2026, 10, 16, 21, 30);
      final s = SocialState(store: MemorySocialStore(), clock: () => now);
      s.speak(
        target: target,
        text: '等你下次去北岸',
        deliverAt: DateTime(2026, 10, 17, 9),
      );
      expect(s.deliverDue(), 0, reason: '还没到点');
      now = DateTime(2026, 10, 17, 9, 1);
      expect(s.deliverDue(), 1);
      expect(s.arrived.length, 1);
    });

    test('到点之前能撤回（规矩 07）', () {
      final s = build(now: DateTime(2026, 10, 16, 21, 30));
      final p = s.speak(
        target: target,
        text: '等你下次去北岸',
        deliverAt: DateTime(2026, 10, 17, 9),
      );
      s.withdraw(p!.id);
      expect(s.posts, isEmpty);
    });

    test('「今晚不在」把夜里的回声挪到明天早上，而不是丢掉', () {
      var now = DateTime(2026, 10, 16, 22, 0);
      final s = SocialState(store: MemorySocialStore(), clock: () => now);
      s.setTonightOff(true);
      final p = s.speak(
        target: target,
        text: '晚上突然想说的话',
        deliverAt: DateTime(2026, 10, 16, 22, 30),
      );
      now = DateTime(2026, 10, 16, 23, 0);
      s.deliverDue();
      final kept = s.posts.single;
      expect(p!.id, kept.id);
      expect(kept.delivered, isFalse, reason: '今晚不在：不递，但也不丢');
      expect(kept.deliverAt!.day, 17);
      expect(kept.deliverAt!.hour, 9);
      expect(kept.deliveryNote, contains('今晚不在'));
    });
  });

  group('事与见面礼', () {
    test('记一件事：事是话的由头', () {
      final s = build(now: DateTime(2026, 10, 16, 9, 12));
      final e = s.recordEvent(
        circleId: 'fishing',
        circleName: '喜爱钓鱼',
        circleMark: '钓',
        title: '登记了一条渔获：翘嘴 42cm',
        facts: ['水温 24℃', '水域 北岸支流'],
      );
      expect(s.myEvents.length, 1);
      expect(e.target.id, 'event:${e.id}');
      expect(e.target.kind, SocialTargetKind.event);
      // 事记下来之后，话就有地方落了。
      expect(s.speak(target: e.target, text: '这条是在坝下钓的吗？'), isNotNull);
    });

    test('送一样东西：记录在「你送出去的」里', () {
      final s = build();
      s.sendGift(title: '一个钓点', toName: '老周', note: '北岸那个湾');
      expect(s.gifts.length, 1);
      expect(s.gifts.single.toName, '老周');
    });
  });

  group('本地留得住', () {
    test('话、事、礼物、今晚不在都能落盘再读回来', () async {
      final store = MemorySocialStore();
      final first = SocialState(store: store, clock: () => DateTime(2026, 10, 16, 9));
      first.speak(target: target, text: '水稳的时候你用多重的铅？');
      first.recordEvent(
        circleId: 'fishing',
        circleName: '喜爱钓鱼',
        circleMark: '钓',
        title: '登记了一条渔获',
      );
      first.sendGift(title: '一支豆子', toName: '小满');
      first.setTonightOff(true);

      final second = SocialState(store: store);
      await second.load();
      expect(second.posts.length, 1);
      expect(second.posts.single.text, '水稳的时候你用多重的铅？');
      expect(second.myEvents.length, 1);
      expect(second.gifts.length, 1);
      expect(second.tonightOff, isTrue);
    });

    test('本地缓存坏掉不该让 App 起不来', () async {
      final store = MemorySocialStore();
      store.writeString('social.posts', '{ 这不是 JSON');
      final s = SocialState(store: store);
      await s.load();
      expect(s.posts, isEmpty);
    });
  });

  test('通信宪法是七条', () {
    expect(kSocialRules.length, 7);
    expect(kSocialRules[1], contains('没有「在吗」'));
  });
}
