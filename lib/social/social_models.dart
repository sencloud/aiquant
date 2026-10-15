/// 新社交的领域模型。
///
/// 一句话的规矩：**事是真的，话是有由头的，居民是标明的。**
///   * [SocialEvent]（事）只来自真实记录 —— 你的渔获、你记下的豆单、你回复的
///     回声。App 不生成「别人钓到了一条鱼」这种内容（方案里第七条之外的硬线：
///     冷启动不做假帖子）。
///   * [SocialPost]（话）必须挂在一样东西上（[SocialTarget]），并且可以投给
///     「以后」（[deliverAt] 不为空 <-> 回声）。没有由头的话，产品里没有入口。
///   * [SocialResident]（AI 居民）是标明身份的参与者，[SocialAuthorKind.resident]
///     会在每一处露出的地方显示「AI 居民」标。
library;

/// 由头：一条话挂在什么上。
enum SocialTargetKind {
  /// 今天的事（你自己登记的记录）。
  event('今天的事'),

  /// 一件东西（竿、豆子、猫）。
  thing('一件东西'),

  /// 一个地方（钓点、营地）。
  place('一个地方'),

  /// 一个时间（还没到时候要说的话 —— 回声）。
  time('一个时间');

  const SocialTargetKind(this.label);

  final String label;
}

/// 话挂靠的对象。
class SocialTarget {
  const SocialTarget({
    required this.id,
    required this.kind,
    required this.title,
    this.subtitle = '',
    this.circleId = '',
    this.circleName = '',
    this.circleMark = '',
  });

  /// 稳定 id：`event:<uuid>` / `thing:<topic>:<name>` / `place:<name>` / `time:<iso>`。
  final String id;
  final SocialTargetKind kind;
  final String title;
  final String subtitle;
  final String circleId;
  final String circleName;
  final String circleMark;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'title': title,
        'subtitle': subtitle,
        'circle_id': circleId,
        'circle_name': circleName,
        'circle_mark': circleMark,
      };

  static SocialTarget fromJson(Map<String, dynamic> json) => SocialTarget(
        id: json['id'] as String,
        kind: SocialTargetKind.values.firstWhere(
          (k) => k.name == json['kind'],
          orElse: () => SocialTargetKind.event,
        ),
        title: json['title'] as String? ?? '',
        subtitle: json['subtitle'] as String? ?? '',
        circleId: json['circle_id'] as String? ?? '',
        circleName: json['circle_name'] as String? ?? '',
        circleMark: json['circle_mark'] as String? ?? '',
      );
}

/// 事从谁那里来。
enum SocialAuthorKind {
  /// 你自己。
  me('你'),

  /// 真人（同一个圈里的人）。
  human(''),

  /// AI 居民：每一处露出都必须带「AI 居民」标。
  resident('AI 居民');

  const SocialAuthorKind(this.label);

  final String label;
}

/// 一件事：今天发生过的、能挂话的真实记录。
///
/// 事本身不带正文 —— 它是一个**锚点**，不是一个帖子。话挂在它上面。
class SocialEvent {
  const SocialEvent({
    required this.id,
    required this.circleId,
    required this.circleName,
    required this.circleMark,
    required this.title,
    this.detail = '',
    this.facts = const [],
    required this.at,
    this.authorKind = SocialAuthorKind.me,
    this.authorName = '你',
    this.local = false,
  });

  final String id;
  final String circleId;
  final String circleName;
  final String circleMark;

  /// 一句话说清发生了什么，例：「登记了一条渔获：翘嘴 42cm」。
  final String title;
  final String detail;

  /// 票根上的几个数：`['水温 24℃', '北岸支流']`。
  final List<String> facts;
  final DateTime at;
  final SocialAuthorKind authorKind;
  final String authorName;

  /// 由本机「记一件事」写下的事（相对 topic 包上报的记录）。
  final bool local;

  /// 这条事作为由头时的样子。
  SocialTarget get target => SocialTarget(
        id: 'event:$id',
        kind: SocialTargetKind.event,
        title: title,
        subtitle: facts.isEmpty ? '' : facts.join(' · '),
        circleId: circleId,
        circleName: circleName,
        circleMark: circleMark,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'circle_id': circleId,
        'circle_name': circleName,
        'circle_mark': circleMark,
        'title': title,
        'detail': detail,
        'facts': facts,
        'at': at.toIso8601String(),
        'author_kind': authorKind.name,
        'author_name': authorName,
      };

  static SocialEvent fromJson(Map<String, dynamic> json) => SocialEvent(
        id: json['id'] as String,
        circleId: json['circle_id'] as String? ?? '',
        circleName: json['circle_name'] as String? ?? '',
        circleMark: json['circle_mark'] as String? ?? '',
        title: json['title'] as String? ?? '',
        detail: json['detail'] as String? ?? '',
        facts: (json['facts'] as List?)?.cast<String>() ?? const [],
        at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
        authorKind: SocialAuthorKind.values.firstWhere(
          (k) => k.name == json['author_kind'],
          orElse: () => SocialAuthorKind.me,
        ),
        authorName: json['author_name'] as String? ?? '你',
        local: true,
      );
}

/// 一句话。
///
/// [deliverAt] 为空 = 现在就在那儿；不为空 = **回声**，条件到了才递出去
/// （在此之间可以被撤回）。回声等的不是定时器，是一个条件 —— 第一版只支持
/// 「明天早上」这类时间条件，`等他下次来` 那种行为条件要等服务端的投递器。
class SocialPost {
  const SocialPost({
    required this.id,
    required this.text,
    required this.target,
    required this.createdAt,
    this.deliverAt,
    this.delivered = false,
    this.deliveryNote = '',
  });

  final String id;
  final String text;
  final SocialTarget target;
  final DateTime createdAt;
  final DateTime? deliverAt;
  final bool delivered;

  /// 条件的人话，例：「明天早上 9:00 递出去」。
  final String deliveryNote;

  bool get isEcho => deliverAt != null;
  bool get inFlight => !delivered;

  SocialPost copyWith({bool? delivered}) => SocialPost(
        id: id,
        text: text,
        target: target,
        createdAt: createdAt,
        deliverAt: deliverAt,
        delivered: delivered ?? this.delivered,
        deliveryNote: deliveryNote,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'text': text,
        'target': target.toJson(),
        'created_at': createdAt.toIso8601String(),
        'deliver_at': deliverAt?.toIso8601String(),
        'delivered': delivered,
        'delivery_note': deliveryNote,
      };

  static SocialPost fromJson(Map<String, dynamic> json) => SocialPost(
        id: json['id'] as String,
        text: json['text'] as String? ?? '',
        target: SocialTarget.fromJson(
            (json['target'] as Map).cast<String, dynamic>()),
        createdAt:
            DateTime.tryParse(json['created_at'] as String? ?? '') ??
                DateTime.now(),
        deliverAt: DateTime.tryParse(json['deliver_at'] as String? ?? ''),
        delivered: json['delivered'] as bool? ?? false,
        deliveryNote: json['delivery_note'] as String? ?? '',
      );
}

/// 见面礼：认识一个人，先送一样东西。
class SocialGift {
  const SocialGift({
    required this.id,
    required this.title,
    required this.note,
    required this.toName,
    required this.at,
    this.received = false,
  });

  final String id;
  final String title;
  final String note;
  final String toName;
  final DateTime at;
  final bool received;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'note': note,
        'to_name': toName,
        'at': at.toIso8601String(),
        'received': received,
      };

  static SocialGift fromJson(Map<String, dynamic> json) => SocialGift(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        note: json['note'] as String? ?? '',
        toName: json['to_name'] as String? ?? '',
        at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
        received: json['received'] as bool? ?? false,
      );
}

/// 一个 AI 居民。人设 prompt 在服务端（`backend/internal/topic`），
/// 客户端只保留 id、名字、一句话与所属圈。
class SocialResident {
  const SocialResident({
    required this.id,
    required this.name,
    required this.blurb,
    required this.circleId,
    required this.circleMark,
  });

  final String id;
  final String name;
  final String blurb;
  final String circleId;
  final String circleMark;
}

/// 通信宪法：七条。任何新功能跟它们冲突，改功能。
const List<String> kSocialRules = [
  '不读你的通讯录，也不推「你可能认识的人」。这里的人，是你和他们一起做过事之后才认识的。',
  '每句话都要有个由头：挂在今天的事、一件东西、一个地方，或者一个时间上。这里没有「在吗」。',
  '想跟一个人开始，先送一样东西。收到了才算认识 —— 对方可以只收下、不回复。',
  '没有在线状态、没有已读、没有「正在输入」。今晚不想被打扰，就说一声「今晚不在」。',
  '不互动的关系会慢慢回到圈里：不删除、不通知。想再聊，一句话就能回去。',
  'AI 居民和真人守同一套规矩，资料上写明他是 AI —— 他也得先送东西，才能跟你说话。',
  '投出去的回声、送出去的东西，在对方看到之前都能收回。',
];
