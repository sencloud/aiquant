import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../core/storage/hive_setup.dart';
import 'social_models.dart';

/// 新社交的本地状态：事、话、回声、见面礼、今晚不在。
///
/// 三件必须在代码里成立的事（其余都是 UI）：
///   1. **没有由头就没有话** —— [speak] 在 target 为空时返回 null，调用处
///      必须给出「这里没有『在吗』」的解释，而不是偷偷建一条无由头的话。
///   2. **回声到点才递出去**，在此之前可以撤回；「今晚不在」会把到达时间
///      顺延到明天早上九点，而不是把话丢掉。
///   3. **事只能来自真实记录**（你的渔获、你本机记下的事），App 不生成
///      「别人钓到了一条鱼」这类内容。
class SocialState extends ChangeNotifier {
  SocialState({SocialStore? store, DateTime Function()? clock})
      : _store = store ?? HiveSocialStore(),
        _now = clock ?? DateTime.now;

  static const _kPosts = 'social.posts';
  static const _kGifts = 'social.gifts';
  static const _kEvents = 'social.events';
  static const _kTonight = 'social.tonight_off';

  final SocialStore _store;
  final DateTime Function() _now;

  final List<SocialPost> _posts = [];
  final List<SocialGift> _gifts = [];
  final List<SocialEvent> _events = [];
  bool _tonightOff = false;
  bool _loaded = false;

  List<SocialPost> get posts => List.unmodifiable(_posts);
  List<SocialGift> get gifts => List.unmodifiable(_gifts);
  List<SocialEvent> get myEvents => List.unmodifiable(_events);
  bool get tonightOff => _tonightOff;
  bool get loaded => _loaded;

  /// 回声：投出去但还没到的。
  List<SocialPost> get inFlight =>
      _posts.where((p) => !p.delivered).toList(growable: false);

  /// 到了的（含挂在事上的话）。
  List<SocialPost> get arrived =>
      _posts.where((p) => p.delivered).toList(growable: false);

  Future<void> load() async {
    _posts
      ..clear()
      ..addAll(_decode(_kPosts, SocialPost.fromJson));
    _gifts
      ..clear()
      ..addAll(_decode(_kGifts, SocialGift.fromJson));
    _events
      ..clear()
      ..addAll(_decode(_kEvents, SocialEvent.fromJson));
    _tonightOff = _store.readString(_kTonight) == '1';
    _loaded = true;
    deliverDue();
    notifyListeners();
  }

  List<T> _decode<T>(String key, T Function(Map<String, dynamic>) fromJson) {
    final raw = _store.readString(key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    } catch (_) {
      // 本地缓存坏掉不该让 App 起不来：丢掉重来。
      return const [];
    }
  }

  void _savePosts() => _store.writeString(
      _kPosts, jsonEncode(_posts.map((p) => p.toJson()).toList()));
  void _saveGifts() => _store.writeString(
      _kGifts, jsonEncode(_gifts.map((g) => g.toJson()).toList()));
  void _saveEvents() => _store.writeString(
      _kEvents, jsonEncode(_events.map((e) => e.toJson()).toList()));

  /// 说一句：必须挂在一样东西上（规矩 02）。
  ///
  /// [deliverAt] 不为空 = 投一条回声；[deliveryNote] 是条件的人话。
  SocialPost? speak({
    SocialTarget? target,
    required String text,
    DateTime? deliverAt,
    String deliveryNote = '',
  }) {
    final body = text.trim();
    if (target == null || body.isEmpty) return null;
    final now = _now();
    final post = SocialPost(
      id: 'p${now.microsecondsSinceEpoch}',
      text: body,
      target: target,
      createdAt: now,
      deliverAt: deliverAt,
      // 挂在事上、现在就说的话，立刻就在那儿（不是「发给某人」）。
      delivered: deliverAt == null,
      deliveryNote: deliveryNote,
    );
    _posts.insert(0, post);
    _savePosts();
    notifyListeners();
    return post;
  }

  /// 撤回一条还没到的回声（规矩 07）。
  void withdraw(String id) {
    final before = _posts.length;
    _posts.removeWhere((p) => p.id == id && !p.delivered);
    if (_posts.length == before) return;
    _savePosts();
    notifyListeners();
  }

  /// 送一样东西出去（规矩 03）。
  SocialGift sendGift({
    required String title,
    required String toName,
    String note = '',
  }) {
    final now = _now();
    final gift = SocialGift(
      id: 'g${now.microsecondsSinceEpoch}',
      title: title.trim(),
      note: note.trim(),
      toName: toName,
      at: now,
    );
    _gifts.insert(0, gift);
    _saveGifts();
    notifyListeners();
    return gift;
  }

  /// 记一件事。事是话的由头，所以这一步必须能在三秒内做完。
  SocialEvent recordEvent({
    required String circleId,
    required String circleName,
    required String circleMark,
    required String title,
    String detail = '',
    List<String> facts = const [],
  }) {
    final now = _now();
    final event = SocialEvent(
      id: 'e${now.microsecondsSinceEpoch}',
      circleId: circleId,
      circleName: circleName,
      circleMark: circleMark,
      title: title.trim(),
      detail: detail.trim(),
      facts: facts,
      at: now,
      local: true,
    );
    _events.insert(0, event);
    _saveEvents();
    notifyListeners();
    return event;
  }

  void setTonightOff(bool value) {
    if (_tonightOff == value) return;
    _tonightOff = value;
    _store.writeString(_kTonight, value ? '1' : '0');
    notifyListeners();
  }

  /// 把到点的回声递出去。
  ///
  /// 「今晚不在」不下线内容，只把夜里到的东西挪到明天早上九点 ——
  /// 这条是规矩 04 的实现。
  int deliverDue() {
    final now = _now();
    var changed = 0;
    for (var i = 0; i < _posts.length; i++) {
      final p = _posts[i];
      final due = p.deliverAt;
      if (p.delivered || due == null || due.isAfter(now)) continue;
      if (_tonightOff && now.hour >= 18) {
        final next = DateTime(now.year, now.month, now.day, 9)
            .add(const Duration(days: 1));
        _posts[i] = SocialPost(
          id: p.id,
          text: p.text,
          target: p.target,
          createdAt: p.createdAt,
          deliverAt: next,
          delivered: false,
          deliveryNote: '今晚不在 · 明天早上 9:00 递出去',
        );
      } else {
        _posts[i] = p.copyWith(delivered: true);
      }
      changed++;
    }
    if (changed > 0) {
      _savePosts();
      notifyListeners();
    }
    return changed;
  }
}

/// 本地存一根 JSON 字符串。抽出来是为了测试能注入内存实现。
abstract class SocialStore {
  String? readString(String key);
  void writeString(String key, String value);
}

/// Hive 实现：复用 App 已有的 `prefs` 盒子。盒子没打开（例如单元测试）
/// 就退化成内存，不抛异常。
class HiveSocialStore implements SocialStore {
  @override
  String? readString(String key) {
    try {
      if (!Hive.isBoxOpen(kBoxPrefs)) return null;
      return prefsBox.get(key) as String?;
    } catch (_) {
      return null;
    }
  }

  @override
  void writeString(String key, String value) {
    try {
      if (!Hive.isBoxOpen(kBoxPrefs)) return;
      prefsBox.put(key, value);
    } catch (_) {
      // 存不进去也不能让用户的话消失在他眼前 —— 内存里还有一份。
    }
  }
}

/// 测试用。
class MemorySocialStore implements SocialStore {
  final Map<String, String> _data = {};

  @override
  String? readString(String key) => _data[key];

  @override
  void writeString(String key, String value) => _data[key] = value;
}
