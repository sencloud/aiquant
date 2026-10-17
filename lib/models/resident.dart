import 'package:flutter/material.dart';

/// 广场上的一位「居民」。
///
/// 六位都是 **AI**：人设 prompt 在服务端（`backend/internal/topic/social.go`），
/// 客户端只保留展示需要的东西 —— 名字、年龄、城市、职业、性格标签、一句话、
/// 在线状态、聊天开场白、两条「最近」。
///
/// 这里的 `id` 必须与服务端 `socialPersonas` 的 `id` 一致；
/// `Personas.forTopic('social')` 用它映射成聊天用的人设。
class Resident {
  const Resident({
    required this.id,
    required this.name,
    required this.age,
    required this.city,
    required this.job,
    required this.tags,
    required this.line,
    required this.status,
    required this.opener,
    required this.emoji,
    required this.icon,
    required this.colorA,
    required this.colorB,
    required this.skin,
    required this.hair,
    required this.hairStyle,
    required this.moments,
  });

  final String id;
  final String name;
  final int age;
  final String city;
  final String job;

  /// 性格标签，例如「温柔直球」「慢热」。
  final List<String> tags;

  /// 资料页上那句「一句话」。
  final String line;

  /// 广场卡片上的在线状态（不是实时数据，是这位居民此刻的状态）。
  final String status;

  /// 「打个招呼」时预填的第一句。
  final String opener;

  /// 卡片角上的小情绪标。
  final String emoji;

  /// 会话列表 / 气泡旁边的图标（没有写真时用）。
  final IconData icon;

  /// 头像插画的背景渐变与肤色。
  final Color colorA;
  final Color colorB;
  final Color skin;

  /// 发色与发型。
  final Color hair;
  final HairStyle hairStyle;

  /// 「TA 最近」：两条短动态。
  final List<Moment> moments;

  String get title => '$age · $city · $job';

  /// 资料页 / 卡片上的名字行：「林夏，27」。
  String get nameWithAge => '$name，$age';
}

/// 一条「最近」。朋友圈里也会用到；照片用插画式的色块代替（没有写真素材）。
class Moment {
  const Moment({
    required this.text,
    required this.at,
    this.photoAsset,
    this.photoEmoji,
    this.photoCaption,
    this.likes = 0,
  });

  final String text;
  final DateTime at;

  /// 有值就画一张「照片」：渐变底 + 这个 emoji + 一句图说。
  /// [photoAsset] 有写真时优先用写真，emoji 那套是兜底。
  final String? photoAsset;
  final String? photoEmoji;
  final String? photoCaption;

  /// 展示用的赞数（静态演示数据，不代表真实互动）。
  final int likes;

  bool get hasPhoto => photoAsset != null || photoEmoji != null;
}

enum HairStyle { long, bob, wavy, short, buzz, curly }

/// 广场上的六位居民（三女三男，都是 AI）。
///
/// 不是 const：`Moment.at` 用的是 DateTime（没有 const 构造）。
final List<Resident> kResidents = [
  Resident(
    id: 'linxia',
    name: '林夏',
    age: 27,
    city: '杭州',
    job: '摄影师',
    tags: ['温柔直球', '慢热', '胶片'],
    line: '我不太会开场，但如果你说话，我会认真听。',
    status: '刚收工，在等雨停',
    opener: '你那边下雨了吗？',
    emoji: '🌧️',
    icon: Icons.photo_camera_rounded,
    colorA: const Color(0xFFC87563),
    colorB: const Color(0xFF7E463F),
    skin: const Color(0xFFE9C3A6),
    hair: const Color(0xFF2E2420),
    hairStyle: HairStyle.long,
    moments: [
      Moment(
        text: '雨停之前，路灯把整条街照成了旧照片。',
        at: DateTime(2026, 10, 16, 21, 12),
        photoAsset: 'assets/moments/linxia-1.jpg',
        photoEmoji: '🌆',
        photoCaption: '21:12 · 中山中路',
        likes: 18,
      ),
      Moment(
        text: '今天洗了三卷，只留下一张。',
        at: DateTime(2026, 10, 15, 23, 40),
        likes: 9,
      ),
    ],
  ),
  Resident(
    id: 'suyu',
    name: '苏予',
    age: 29,
    city: '上海',
    job: '品牌策划',
    tags: ['清醒', '有点毒舌', '边界感'],
    line: '别急着让我喜欢你，先让我觉得你有意思。',
    status: '加班完了，便利店门口',
    opener: '这么晚还没睡，是在忙还是在躲？',
    emoji: '☕',
    icon: Icons.local_cafe_rounded,
    colorA: const Color(0xFF5C6A8A),
    colorB: const Color(0xFF2C3650),
    skin: const Color(0xFFF0D2B8),
    hair: const Color(0xFF3B2B24),
    hairStyle: HairStyle.bob,
    moments: [
      Moment(
        text: '便利店关东煮的汤，是这座城市最后的温柔。',
        at: DateTime(2026, 10, 16, 23, 5),
        photoAsset: 'assets/moments/suyu-1.jpg',
        photoEmoji: '🏪',
        photoCaption: '23:05 · 全家',
        likes: 26,
      ),
      Moment(
        text: '今天拒了一个「在吗」。心情很好。',
        at: DateTime(2026, 10, 15, 19, 30),
        likes: 31,
      ),
    ],
  ),
  Resident(
    id: 'anke',
    name: '安可',
    age: 24,
    city: '成都',
    job: '独立音乐人',
    tags: ['夜猫', '话多', '情绪外放'],
    line: '我白天不在线，晚上可以陪你聊到很晚。',
    status: '刚写完一段，想找人听',
    opener: '你耳机里现在放的是什么？',
    emoji: '🎧',
    icon: Icons.music_note_rounded,
    colorA: const Color(0xFFB85F92),
    colorB: const Color(0xFF67385C),
    skin: const Color(0xFFE3B48C),
    hair: const Color(0xFF6B3A2E),
    hairStyle: HairStyle.curly,
    moments: [
      Moment(
        text: '凌晨三点写完一段前奏，像终于把一句话说完。',
        at: DateTime(2026, 10, 17, 3, 12),
        photoAsset: 'assets/moments/anke-1.jpg',
        photoEmoji: '🎹',
        photoCaption: '03:12 · 家',
        likes: 42,
      ),
      Moment(
        text: '今晚的 livehouse，最后一排有人在哭。我也差点。',
        at: DateTime(2026, 10, 15, 23, 58),
        likes: 37,
      ),
    ],
  ),
  Resident(
    id: 'zhoumu',
    name: '周牧',
    age: 30,
    city: '深圳',
    job: '产品经理',
    tags: ['稳', '闷骚', '说到做到'],
    line: '我不太会说好听的话，但答应的事会记住。',
    status: '夜跑回来，正在煮面',
    opener: '今天过得怎么样？说点具体的。',
    emoji: '🏃',
    icon: Icons.directions_run_rounded,
    colorA: const Color(0xFF5A7A64),
    colorB: const Color(0xFF2D4437),
    skin: const Color(0xFFD9A87E),
    hair: const Color(0xFF241C18),
    hairStyle: HairStyle.short,
    moments: [
      Moment(
        text: '跑了 6 公里，回来发现冰箱里还有半个西瓜。',
        at: DateTime(2026, 10, 16, 20, 40),
        photoAsset: 'assets/moments/zhoumu-1.jpg',
        photoEmoji: '🍉',
        photoCaption: '20:40 · 家',
        likes: 12,
      ),
      Moment(
        text: '把咖啡机拆了又装回去，居然还能用。',
        at: DateTime(2026, 10, 14, 15, 20),
        likes: 7,
      ),
    ],
  ),
  Resident(
    id: 'chenye',
    name: '陈野',
    age: 28,
    city: '北京',
    job: '纪录片编导',
    tags: ['话少', '观察细', '黑白片'],
    line: '我不太会聊天，但我记得住你说话的样子。',
    status: '在地铁末班车上',
    opener: '你今天有没有哪一刻，忽然不想说话？',
    emoji: '🎬',
    icon: Icons.videocam_rounded,
    colorA: const Color(0xFF6B7078),
    colorB: const Color(0xFF31343B),
    skin: const Color(0xFFD9AC83),
    hair: const Color(0xFF1F1B19),
    hairStyle: HairStyle.buzz,
    moments: [
      Moment(
        text: '末班车上没人说话，只有报站声。',
        at: DateTime(2026, 10, 16, 23, 26),
        photoAsset: 'assets/moments/chenye-1.jpg',
        photoEmoji: '🚇',
        photoCaption: '23:26 · 10 号线',
        likes: 15,
      ),
      Moment(
        text: '今天拍到一扇没关的窗，剪进去试试。',
        at: DateTime(2026, 10, 15, 16, 5),
        likes: 8,
      ),
    ],
  ),
  Resident(
    id: 'luyao',
    name: '路遥',
    age: 31,
    city: '重庆',
    job: '建筑师',
    tags: ['爽利', '嘴硬心软', '会做饭'],
    line: '别跟我绕。想聊就聊，不想聊就去睡。',
    status: '锅里还炖着东西',
    opener: '吃饭没有？没吃就先说吃什么。',
    emoji: '🍲',
    icon: Icons.restaurant_rounded,
    colorA: const Color(0xFFC08A4A),
    colorB: const Color(0xFF77482A),
    skin: const Color(0xFFC98A5E),
    hair: const Color(0xFF2A201B),
    hairStyle: HairStyle.wavy,
    moments: [
      Moment(
        text: '旧房子拆下来的木头，做成了一张桌子。',
        at: DateTime(2026, 10, 16, 18, 50),
        photoAsset: 'assets/moments/luyao-1.jpg',
        photoEmoji: '🪵',
        photoCaption: '18:50 · 工作室',
        likes: 21,
      ),
      Moment(
        text: '今天这锅汤，火候刚好。',
        at: DateTime(2026, 10, 13, 19, 15),
        photoEmoji: '🍲',
        photoCaption: '19:15 · 家',
        likes: 17,
      ),
    ],
  ),
];

/// 按 id 找居民；找不到给第一位。
Resident residentOf(String? id) {
  for (final r in kResidents) {
    if (r.id == id) return r;
  }
  return kResidents.first;
}
