import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../core/storage/hive_setup.dart';
import '../models/chat.dart';
import '../models/companion_look.dart';
import '../models/companion_mood.dart';
import 'chat_state.dart';

/// 「喜爱」——AI 伴侣的状态。
///
/// 三件事：
///   1. **她记得的喜欢**：炒股 / 期货 / 钓鱼 / 爬山（可改），存本机，
///      每一轮对话随请求发给服务端，拼进她的 system prompt。
///   2. **她会先开口**：一段时间没说话、又不在深夜，她往会话里放一句
///      和她记得的喜欢有关的开场。这是本地模板，不扣喜点、不调模型。
///   3. **不打扰**：夜间安静，刚聊过不插话，一天最多几次。
class CompanionState extends ChangeNotifier {
  CompanionState({DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  static const _kInterests = 'companion.interests';
  static const _kLastProactive = 'companion.last_proactive';
  static const _kLook = 'companion.look';
  static const _kVoice = 'companion.voice';
  static const _kMemories = 'companion.memories';

  /// 编辑页里的预设。
  static const presets = <String>[
    '炒股',
    '期货',
    '钓鱼',
    '爬山',
    '咖啡',
    '露营',
    '摄影',
    '跑步',
  ];

  /// 第一次打开时的默认喜欢（用户自己说的四件事）。
  static const defaults = <String>['炒股', '期货', '钓鱼', '爬山'];

  final DateTime Function() _now;

  List<String> _interests = defaults;
  int _lookIndex = 0;
  AvatarMood _mood = AvatarMood.calm;
  bool _voiceEnabled = true;
  List<String> _memories = const [];
  DateTime? _lastProactive;
  bool _loaded = false;

  List<String> get interests => List.unmodifiable(_interests);
  CompanionLook get look => kCompanionLooks[_lookIndex % kCompanionLooks.length];
  String get name => look.name;
  AvatarMood get mood => _mood;
  bool get voiceEnabled => _voiceEnabled;
  List<String> get memories => List.unmodifiable(_memories);
  bool get loaded => _loaded;

  /// 读本机记忆。盒子没打开（单测）时就用默认值，不抛。
  Future<void> load() async {
    try {
      if (Hive.isBoxOpen(kBoxPrefs)) {
        final raw = prefsBox.get(_kInterests);
        if (raw is String && raw.isNotEmpty) {
          final list = (jsonDecode(raw) as List).cast<String>();
          if (list.isNotEmpty) _interests = list;
        }
        final last = prefsBox.get(_kLastProactive);
        if (last is String) _lastProactive = DateTime.tryParse(last);
        final look = prefsBox.get(_kLook);
        if (look is String) {
          final i = kCompanionLooks.indexWhere((l) => l.id == look);
          if (i >= 0) _lookIndex = i;
        }
        final voice = prefsBox.get(_kVoice);
        if (voice is bool) _voiceEnabled = voice;
        final mem = prefsBox.get(_kMemories);
        if (mem is String && mem.isNotEmpty) {
          _memories = (jsonDecode(mem) as List).cast<String>();
        }
      }
    } catch (_) {
      // 记忆坏了不该让 App 起不来：用默认值继续。
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setInterests(List<String> next) async {
    final clean = <String>[];
    for (final v in next) {
      final t = v.trim();
      if (t.isEmpty || clean.contains(t)) continue;
      clean.add(t.length > 12 ? t.substring(0, 12) : t);
      if (clean.length == 8) break;
    }
    _interests = clean.isEmpty ? defaults : clean;
    try {
      if (Hive.isBoxOpen(kBoxPrefs)) {
        await prefsBox.put(_kInterests, jsonEncode(_interests));
      }
    } catch (_) {}
    notifyListeners();
  }

  /// 点一下头像：换下一个形象（名字与语气一起换），记住这次选择。
  Future<CompanionLook> nextLook() async {
    _lookIndex = (_lookIndex + 1) % kCompanionLooks.length;
    try {
      if (Hive.isBoxOpen(kBoxPrefs)) {
        await prefsBox.put(_kLook, look.id);
      }
    } catch (_) {}
    notifyListeners();
    return look;
  }

  void setMood(AvatarMood mood) {
    if (_mood == mood) return;
    _mood = mood;
    notifyListeners();
  }

  Future<void> setVoiceEnabled(bool on) async {
    _voiceEnabled = on;
    try {
      if (Hive.isBoxOpen(kBoxPrefs)) await prefsBox.put(_kVoice, on);
    } catch (_) {}
    notifyListeners();
  }

  /// 从你说的话里记住明确说过的事实（不猜、不推断）。
  ///
  /// 只收含「我喜欢 / 我最近 / 我住在 / 我习惯 …」这类第一人称陈述的句子，
  /// 每句 ≤ 60 字，最多 20 条。
  Future<void> rememberFrom(String text) async {
    const keys = [
      '我喜欢', '我不喜欢', '我最近', '我习惯', '我每天', '我周末',
      '我想去', '我在学', '我住在', '我讨厌', '我怕', '我准备',
    ];
    final parts = text.split(RegExp(r'[。！？!?\n]'));
    var changed = false;
    for (final part in parts) {
      final s = part.trim();
      if (s.isEmpty || s.length > 60) continue;
      if (!keys.any(s.contains)) continue;
      if (_memories.contains(s)) continue;
      _memories = [..._memories, s];
      if (_memories.length > 20) {
        _memories = _memories.sublist(_memories.length - 20);
      }
      changed = true;
    }
    if (!changed) return;
    try {
      if (Hive.isBoxOpen(kBoxPrefs)) {
        await prefsBox.put(_kMemories, jsonEncode(_memories));
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> removeMemory(String memory) async {
    _memories = _memories.where((m) => m != memory).toList();
    try {
      if (Hive.isBoxOpen(kBoxPrefs)) {
        await prefsBox.put(_kMemories, jsonEncode(_memories));
      }
    } catch (_) {}
    notifyListeners();
  }

  /// 她先开口。
  ///
  /// 返回 true 表示真的往会话里放了一句。规则：
  ///   * 23:30–07:30 不打扰；刚聊过（90 分钟内）不插话；
  ///   * 每 4 小时最多一次；
  ///   * 只在 companion 会话里说话。
  Future<bool> maybeSaySomething(
    ChatState chat, {
    bool force = false,
  }) async {
    if (!_loaded) await load();
    final now = _now();
    if (!force && (now.hour >= 23 || now.hour * 60 + now.minute < 7 * 60 + 30)) {
      return false;
    }
    if (!force &&
        _lastProactive != null &&
        now.difference(_lastProactive!) < const Duration(hours: 4)) {
      return false;
    }

    final session = _sessionOf(chat);
    if (session == null) return false;
    // 空会话交给「我是喜爱」那张欢迎页去说，别让第一屏直接变成气泡。
    if (session.messages.isEmpty) return false;
    final last = session.messages.isEmpty ? null : session.messages.last;
    if (!force &&
        last != null &&
        now.difference(last.timestamp) < const Duration(minutes: 90)) {
      return false;
    }

    final line = openerFor(now, _interests);
    await chat.addLocalMessage(line);
    _lastProactive = now;
    try {
      if (Hive.isBoxOpen(kBoxPrefs)) {
        await prefsBox.put(_kLastProactive, now.toIso8601String());
      }
    } catch (_) {}
    notifyListeners();
    return true;
  }

  ChatSession? _sessionOf(ChatState chat) {
    ChatSession? found;
    for (final s in chat.sessions) {
      if (s.topic == 'companion') found = s;
    }
    if (found != null) chat.selectSession(found.id);
    return found;
  }

  /// 她开口的那句话：跟着时间和你的喜欢走，不编造具体行情 / 天气。
  @visibleForTesting
  static String openerFor(DateTime now, List<String> interests) {
    final has = interests.contains;
    final weekend = now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;
    final minute = now.hour * 60 + now.minute;
    if (weekend && (has('钓鱼') || has('爬山'))) {
      if (has('钓鱼') && has('爬山')) {
        return '周末了。想去水边坐坐，还是上山走走？';
      }
      return has('钓鱼') ? '周末了。水边还是老地方？' : '周末了。要不要去山上走走？';
    }
    if (minute < 9 * 60 + 15) {
      if (has('炒股') || has('期货')) return '早。今天开盘前，想聊两句吗？';
      return '早。今天想怎么过？';
    }
    if (minute < 11 * 60 + 30) {
      if (has('炒股') || has('期货')) return '开盘了。你今天是想聊行情，还是先说说别的？';
      return '上午好。在想什么？';
    }
    if (minute < 13 * 60) {
      return '中午了。吃饭了吗？';
    }
    if (minute < 15 * 60) {
      if (has('炒股') || has('期货')) return '下午还有一会儿。你还好吗？';
      return '下午好。我在。';
    }
    if (minute < 18 * 60) {
      if (has('炒股') || has('期货')) return '收盘了。今天怎么样？';
      return '忙完了吗？';
    }
    return '今天过得怎么样？我在。';
  }
}
