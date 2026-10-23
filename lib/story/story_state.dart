import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../services/analytics.dart';
import 'story_api.dart';
import 'story_content.dart';
import 'story_engine.dart';
import 'story_models.dart';
import 'story_reply.dart';
import 'story_store.dart';

/// 故事运行态：存档、当前夜、心级、flag、消息。
///
/// 这一层只认内容与引擎，不认页面。页面通过 `watch` 读它，动作都走这里，
/// 这样以后把本地脚本换成 `/v1/story/chat` 时，UI 不用动。
class StoryState extends ChangeNotifier {
  StoryState({
    StoryStore? store,
    StorySeason season = kNightSeason,
    this.api,
    this.replyDelay = const Duration(milliseconds: 700),
  })  : _store = store ?? HiveStoryStore(),
        season = season,
        _engine = StoryEngine(season);

  final StorySeason season;
  final StoryEngine _engine;
  final StoryStore _store;

  /// 为空时纯本地（测试 / 未接后端）；非空时保存进度与 AI 聊天走服务端。
  final StoryApi? api;
  final Duration replyDelay;

  StorySave _save = StorySave();
  StoryConfig _config = StoryConfig.defaults;
  bool _loading = true;
  bool _typing = false;
  bool _safetyPaused = false;
  NightResult? _lastResult;
  String? _streamingReply;

  bool get loading => _loading;
  bool get typing => _typing;
  bool get safetyPaused => _safetyPaused;

  /// 服务端流式回复的中间态；页面用它画「正在说」的气泡。
  String? get streamingReply => _streamingReply;
  bool get introSeen => _save.introSeen;
  StoryRun? get run => _save.run;
  StoryCharacter? get activeCharacter =>
      run == null ? null : season.characterOf(run!.characterId);
  StoryNight? get currentNight => run == null ? null : _engine.nightOf(run!);
  StoryBeat? get currentBeat => run == null ? null : _engine.beatOf(run!);
  List<StoryMessage> get messages =>
      List.unmodifiable(run?.messages ?? const []);
  int get hearts => run?.hearts ?? 0;
  Set<String> get flags => Set.unmodifiable(run?.flags ?? const {});
  bool get nightComplete => run?.nightComplete ?? false;
  bool get finished => run?.finished ?? false;
  NightResult? get lastResult => _lastResult;
  StoryConfig get config => _config;
  Set<String> get unlockedEndings => Set.unmodifiable(_save.unlockedEndings);

  /// 静态 routeOpen 与远程开关的交集。
  bool isCharacterEnabled(String id) {
    final c = season.characterOf(id);
    return _config.enabled && c.routeOpen && _config.characters.contains(id);
  }

  /// 三条路线任意结局都拿到后，第十个结局才亮。
  bool get trueEndingUnlocked {
    for (final id in const ['linxia', 'suyu', 'chenye']) {
      final got = _save.unlockedEndings.any((e) => e.startsWith('${id}_'));
      if (!got) return false;
    }
    return true;
  }

  StoryEnding get trueEnding => season.trueEnding;

  bool get hasActiveRun => run != null && !finished;
  bool get canChoose =>
      run != null && !nightComplete && !finished && !_typing && !_safetyPaused;

  int get reachedNight {
    final r = run;
    if (r == null) return 0;
    if (r.finished) return 7;
    return r.night;
  }

  List<StoryPost> get unlockedPosts {
    return season.posts
        .where((p) =>
            p.unlockAfterNight == 0 || p.unlockAfterNight <= reachedNight)
        .toList(growable: false);
  }

  StoryEnding? get ending {
    final r = run;
    if (r?.endingId == null) return null;
    final route = season.routeOf(r!.characterId);
    if (route == null) return null;
    for (final e in route.endings) {
      if (e.id == r.endingId) return e;
    }
    return null;
  }

  Future<void> load() async {
    if (api != null) {
      _config = await api!.fetchConfig();
    }
    final raw = await _store.read();
    if (raw != null && raw.isNotEmpty) {
      try {
        _save = StorySave.fromJson(
            (jsonDecode(raw) as Map).cast<String, dynamic>());
      } catch (_) {
        _save = StorySave();
      }
    }
    final r = _save.run;
    if (r != null && r.endingId != null) {
      _save.unlockedEndings.add(r.endingId!);
    }
    final current = _save.run;
    if (current != null &&
        current.messages.isEmpty &&
        !current.finished &&
        !current.nightComplete) {
      _primeBeat(force: true);
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> acceptIntro() async {
    _save.introSeen = true;
    await _persist();
    notifyListeners();
  }

  Future<void> refreshConfig() async {
    if (api == null) return;
    _config = await api!.fetchConfig();
    notifyListeners();
  }

  Future<void> replayIntro() async {
    _save.introSeen = false;
    await _persist();
    notifyListeners();
  }

  Future<void> startRoute(String characterId) async {
    if (!isCharacterEnabled(characterId) ||
        season.routeOf(characterId) == null) {
      throw ArgumentError('route not open: $characterId');
    }
    _save.run = _engine.start(characterId);
    _lastResult = null;
    _safetyPaused = false;
    _typing = false;
    _primeBeat(force: true);
    await _persist();
    unawaited(_sync());
    Analytics.instance.track('story_start', {'character': characterId});
    notifyListeners();
  }

  Future<void> choose(String choiceId) async {
    final r = run;
    if (r == null || !canChoose) return;
    final night = r.night;
    final beat = r.beat;
    final choice = _engine.applyChoice(r, choiceId);
    r.messages.add(StoryMessage(role: StoryRole.user, text: choice.label));
    r.messages.add(StoryMessage(role: StoryRole.character, text: choice.reply));
    if (!r.nightComplete) {
      _primeBeat(force: true);
    }
    await _persist();
    unawaited(_sync());
    Analytics.instance.track('story_choice', {
      'character': r.characterId,
      'night': night,
      'beat': beat,
      'choice': choiceId,
    });
    notifyListeners();
  }

  Future<void> send(String text) async {
    final r = run;
    if (r == null ||
        r.nightComplete ||
        r.finished ||
        _typing ||
        _safetyPaused) {
      return;
    }
    final value = text.trim();
    if (value.isEmpty) return;
    r.messages.add(StoryMessage(role: StoryRole.user, text: value));
    _typing = true;
    _streamingReply = null;
    Analytics.instance.track('story_message_send', {
      'character': r.characterId,
      'night': r.night,
      'remote': api != null,
    });
    notifyListeners();

    if (api != null) {
      try {
        await api!.saveRun(r);
        final scene = _sceneOf(r);
        var gotDone = false;
        final buffer = StringBuffer();
        await for (final ev
            in api!.chat(run: r, message: value, scene: scene)) {
          if (ev.kind == StoryAiEventKind.delta) {
            buffer.write(ev.text);
            _streamingReply = buffer.toString();
            notifyListeners();
          } else if (ev.kind == StoryAiEventKind.done) {
            final reply = ev.text.trim().isEmpty ? buffer.toString() : ev.text;
            r.messages.add(StoryMessage(
              role: StoryRole.character,
              text: reply.trim().isEmpty ? '……（她没有说话。）' : reply,
              safety: ev.safety,
            ));
            if (ev.safety) _safetyPaused = true;
            gotDone = true;
            break;
          } else if (ev.kind == StoryAiEventKind.error) {
            throw StoryApiException(ev.code, ev.text);
          }
        }
        if (gotDone) {
          _typing = false;
          _streamingReply = null;
          await _persist();
          notifyListeners();
          return;
        }
      } catch (_) {
        // 服务端不可用 / 未登录：回落本地脚本，不打断这一夜。
      }
    }

    _streamingReply = null;
    if (replyDelay > Duration.zero) {
      await Future<void>.delayed(replyDelay);
    }

    final reply = localStoryReply(run: r, input: value);
    r.messages.add(StoryMessage(
      role: StoryRole.character,
      text: reply.text,
      safety: reply.safety,
    ));
    _typing = false;
    if (reply.safety) _safetyPaused = true;
    await _persist();
    notifyListeners();
  }

  StoryScene _sceneOf(StoryRun r) {
    final night = _engine.nightOf(r);
    final beat = _engine.beatOf(r);
    return StoryScene(
      night: r.night,
      beat: r.beat,
      beatId: beat.id,
      place: night.place,
      scene: night.scene,
      beatNote: beat.note ?? '',
      opening: beat.opening,
    );
  }

  Future<void> _sync() async {
    final r = run;
    if (r == null || api == null) return;
    try {
      await api!.saveRun(r);
    } catch (_) {
      // 本地存档仍是真相；下一次动作再试。
    }
  }

  Future<void> acknowledgeSafety() async {
    _safetyPaused = false;
    notifyListeners();
  }

  Future<NightResult?> endNight() async {
    final r = run;
    if (r == null || !r.nightComplete || r.finished) return null;
    final result = _engine.endNight(r);
    _lastResult = result;
    if (r.finished && r.endingId != null) {
      _save.unlockedEndings.add(r.endingId!);
    } else {
      _primeBeat(force: true);
    }
    await _persist();
    unawaited(_sync());
    Analytics.instance.track('story_night_end', {
      'character': r.characterId,
      'night': result.night,
      'hearts': result.heartsAfter,
      'finished': result.last,
    });
    if (result.last && r.endingId != null) {
      Analytics.instance.track('story_ending', {
        'character': r.characterId,
        'ending': r.endingId,
      });
    }
    notifyListeners();
    return result;
  }

  Future<void> archiveRun() async {
    final r = run;
    if (r?.endingId != null) {
      _save.unlockedEndings.add(r!.endingId!);
    }
    _save.run = null;
    _lastResult = null;
    _safetyPaused = false;
    await _persist();
    notifyListeners();
  }

  Future<void> restartRoute() async {
    final id = run?.characterId;
    if (id == null) return;
    await startRoute(id);
  }

  Future<void> resetAll() async {
    await _store.clear();
    _save = StorySave(introSeen: true);
    _lastResult = null;
    _safetyPaused = false;
    _typing = false;
    await _persist();
    notifyListeners();
  }

  void _primeBeat({bool force = false}) {
    final r = run;
    if (r == null || r.finished || r.nightComplete) return;
    if (!force && r.messages.isNotEmpty) return;
    final beat = _engine.beatOf(r);
    for (final line in beat.opening) {
      r.messages.add(StoryMessage(role: StoryRole.character, text: line));
    }
  }

  Future<void> _persist() async {
    await _store.write(jsonEncode(_save.toJson()));
  }
}
