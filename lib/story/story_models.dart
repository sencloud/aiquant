import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

/// 《喜爱 · 天亮以前》的数据模型。
///
/// 这一版先把「通讯录 / 七夜 / 选项 / 结局」跑通：内容在 [story_content.dart]，
/// 状态机在 [story_engine.dart]。服务端 story 引擎接上之前，聊天回复由本地
/// 脚本兜底（见 `story_reply.dart`），接口形状按 PRD §9.4 预留。

enum PixelHairStyle { long, bob, curly, short, buzz, wavy }

enum PixelAccessory { catEars, mole, hairClips, watch, cameraStrap, apron }

enum PixelExpression { calm, soft, hurt, smile, smirk, away }

enum StoryRole { character, user, system }

enum StoryEndingKind { he, ne, be, trueEnd }

class StoryCharacter {
  const StoryCharacter({
    required this.id,
    required this.name,
    required this.age,
    required this.city,
    required this.job,
    required this.tags,
    required this.quote,
    required this.status,
    required this.nightWindow,
    required this.routeOpen,
    required this.routeNote,
    required this.hair,
    required this.skin,
    required this.jacket,
    required this.accent,
    required this.eye,
    required this.bgA,
    required this.bgB,
    required this.hairStyle,
    required this.accessory,
    required this.expressions,
    required this.order,
    this.artAsset,
  });

  final String id;
  final String name;
  final int age;
  final String city;
  final String job;
  final List<String> tags;
  final String quote;
  final String status;
  final String nightWindow;

  /// 本季是否开放完整路线。未开放的仍然有完整立绘，只是显示「未接来电」。
  final bool routeOpen;
  final String routeNote;

  final Color hair;
  final Color skin;
  final Color jacket;
  final Color accent;
  final Color eye;
  final Color bgA;
  final Color bgB;
  final PixelHairStyle hairStyle;
  final PixelAccessory accessory;
  final List<PixelExpression> expressions;
  final int order;

  /// 美术终稿目录前缀，例如 `assets/night/portraits/linxia`。
  /// 为空时使用代码绘制的试作；有值时按 `<前缀>_<表情>.png` 读图。
  final String? artAsset;

  String? artAssetFor(PixelExpression expression) =>
      artAsset == null ? null : '${artAsset!}_${expression.name}.png';

  String get title => '$age · $city · $job';
  String get nameWithAge => '$name，$age';
}

class StoryChoice {
  const StoryChoice({
    required this.id,
    required this.label,
    required this.reply,
    this.hearts = 0,
    this.flags = const [],
  });

  final String id;
  final String label;

  /// 选完之后角色回的那一句（作者写）。
  final String reply;
  final int hearts;
  final List<String> flags;
}

class StoryBeat {
  const StoryBeat({
    required this.id,
    required this.opening,
    required this.choices,
    this.note,
  });

  final String id;

  /// 进入这个 beat 时角色连发的 1–3 句。
  final List<String> opening;
  final List<StoryChoice> choices;

  /// 场景里的一句旁白，显示在选择上方。
  final String? note;
}

class StoryNight {
  const StoryNight({
    required this.number,
    required this.title,
    required this.time,
    required this.place,
    required this.scene,
    required this.beats,
    required this.closing,
  });

  final int number;
  final String title;
  final String time;
  final String place;
  final String scene;
  final List<StoryBeat> beats;

  /// 这一夜最后一句旁白，出现在夜终卡上。
  final String closing;
}

class StoryEnding {
  const StoryEnding({
    required this.id,
    required this.title,
    required this.quote,
    required this.kind,
    required this.hint,
  });

  final String id;
  final String title;
  final String quote;
  final StoryEndingKind kind;
  final String hint;
}

class StoryRoute {
  const StoryRoute({
    required this.characterId,
    required this.nights,
    required this.endings,
  });

  final String characterId;
  final List<StoryNight> nights;
  final List<StoryEnding> endings;
}

class StoryPost {
  const StoryPost({
    required this.id,
    required this.authorId,
    required this.text,
    required this.timeLabel,
    required this.unlockAfterNight,
    this.hearts = 0,
  });

  final String id;
  final String authorId;
  final String text;
  final String timeLabel;

  /// 0 = 一开始就在；N = 走完第 N 夜才出现。
  final int unlockAfterNight;
  final int hearts;
}

class StorySeason {
  const StorySeason({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.tagline,
    required this.characters,
    required this.routes,
    required this.posts,
    required this.endingSlots,
    required this.trueEnding,
  });

  final String id;
  final String title;
  final String subtitle;
  final String tagline;
  final List<StoryCharacter> characters;
  final Map<String, StoryRoute> routes;
  final List<StoryPost> posts;
  final int endingSlots;

  /// 三条线都走完后解锁的第十个结局。
  final StoryEnding trueEnding;

  StoryCharacter characterOf(String id) {
    for (final c in characters) {
      if (c.id == id) return c;
    }
    return characters.first;
  }

  StoryRoute? routeOf(String id) => routes[id];
}

class StoryMessage {
  StoryMessage({
    required this.role,
    required this.text,
    DateTime? at,
    this.safety = false,
  }) : at = at ?? DateTime.now();

  final StoryRole role;
  final String text;
  final DateTime at;

  /// 安全提示 / 系统提示：不按角色气泡画。
  final bool safety;

  Map<String, dynamic> toJson() => {
        'role': role.name,
        'text': text,
        'at': at.toIso8601String(),
        'safety': safety,
      };

  static StoryMessage fromJson(Map<String, dynamic> json) {
    return StoryMessage(
      role: StoryRole.values.firstWhere(
        (r) => r.name == json['role'],
        orElse: () => StoryRole.system,
      ),
      text: json['text'] as String? ?? '',
      at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
      safety: json['safety'] as bool? ?? false,
    );
  }
}

class StoryRun {
  StoryRun({
    String? id,
    required this.characterId,
    this.night = 1,
    this.beat = 0,
    this.hearts = 2,
    Set<String>? flags,
    List<StoryMessage>? messages,
    this.nightComplete = false,
    this.finished = false,
    this.endingId,
  })  : id = id ?? const Uuid().v4(),
        flags = flags ?? <String>{},
        messages = messages ?? <StoryMessage>[];

  /// 服务端 story_runs.id；客户端生成，服务端 upsert。
  final String id;
  String characterId;
  int night;
  int beat;
  int hearts;
  final Set<String> flags;
  final List<StoryMessage> messages;
  bool nightComplete;
  bool finished;
  String? endingId;

  Map<String, dynamic> toJson() => {
        'id': id,
        'character_id': characterId,
        'night': night,
        'beat': beat,
        'hearts': hearts,
        'flags': flags.toList(),
        'messages': messages.map((m) => m.toJson()).toList(),
        'night_complete': nightComplete,
        'finished': finished,
        'ending_id': endingId,
      };

  static StoryRun fromJson(Map<String, dynamic> json) {
    return StoryRun(
      id: json['id'] as String?,
      characterId: json['character_id'] as String? ?? 'linxia',
      night: (json['night'] as num?)?.toInt() ?? 1,
      beat: (json['beat'] as num?)?.toInt() ?? 0,
      hearts: (json['hearts'] as num?)?.toInt() ?? 2,
      flags: (json['flags'] as List?)?.cast<String>().toSet(),
      messages: (json['messages'] as List?)
              ?.map((e) =>
                  StoryMessage.fromJson((e as Map).cast<String, dynamic>()))
              .toList() ??
          <StoryMessage>[],
      nightComplete: json['night_complete'] as bool? ?? false,
      finished: json['finished'] as bool? ?? false,
      endingId: json['ending_id'] as String?,
    );
  }
}

class StorySave {
  StorySave({
    this.introSeen = false,
    this.run,
    Set<String>? unlockedEndings,
  }) : unlockedEndings = unlockedEndings ?? <String>{};

  bool introSeen;
  StoryRun? run;
  final Set<String> unlockedEndings;

  Map<String, dynamic> toJson() => {
        'intro_seen': introSeen,
        'run': run?.toJson(),
        'unlocked_endings': unlockedEndings.toList(),
      };

  static StorySave fromJson(Map<String, dynamic> json) {
    return StorySave(
      introSeen: json['intro_seen'] as bool? ?? false,
      run: json['run'] == null
          ? null
          : StoryRun.fromJson((json['run'] as Map).cast<String, dynamic>()),
      unlockedEndings:
          (json['unlocked_endings'] as List?)?.cast<String>().toSet(),
    );
  }
}

/// 夜终卡 / 结局页要用的「这一夜的变化」。
class NightResult {
  const NightResult({
    required this.heartsBefore,
    required this.heartsAfter,
    required this.closing,
    required this.night,
    required this.last,
  });

  final int heartsBefore;
  final int heartsAfter;
  final String closing;
  final int night;
  final bool last;
}
