import 'package:flutter/material.dart';

enum BuddyExpression {
  normal,
  blink,
  happy,
  talk,
  shy,
  surprised,
  sleepy,
  sad,
  angry,
}

extension BuddyExpressionAsset on BuddyExpression {
  String get assetName => name;
}

class WorkBuddyCharacter {
  const WorkBuddyCharacter({
    required this.id,
    required this.name,
    required this.title,
    required this.greeting,
    required this.accent,
  });

  final String id;
  final String name;
  final String title;
  final String greeting;
  final Color accent;

  String image(BuddyExpression expression) =>
      'assets/work_buddy/characters/$id/${expression.assetName}.webp';
}

const workBuddyCharacters = <WorkBuddyCharacter>[
  WorkBuddyCharacter(
    id: 'xiaotao',
    name: '小桃',
    title: '原创 · 元气打工人',
    greeting: '摸鱼五分钟，也要有人陪。',
    accent: Color(0xFFED8D89),
  ),
  WorkBuddyCharacter(
    id: 'momo',
    name: '墨墨',
    title: '原创 · 猫猫程序媛',
    greeting: '喵…代码跑通了吗？',
    accent: Color(0xFF8C8FA8),
  ),
];

WorkBuddyCharacter workBuddyById(String? id) {
  return workBuddyCharacters.firstWhere(
    (item) => item.id == id,
    orElse: () => workBuddyCharacters.first,
  );
}

enum BuddyMotion {
  none,
  bounce,
  sway,
  shake,
  lean,
  spin,
  sip,
  type,
  sleepy,
}

class BuddyAction {
  const BuddyAction({
    required this.id,
    required this.label,
    required this.category,
    required this.message,
    required this.expression,
    required this.motion,
    this.seconds = 2.4,
  });

  final String id;
  final String label;
  final String category;
  final String message;
  final BuddyExpression expression;
  final BuddyMotion motion;
  final double seconds;
}

const buddyActionCategories = <String>[
  '摸摸',
  '互动',
  '投喂',
  '表演',
  '日常',
  '情绪',
  '休息',
];

const workBuddyActions = <BuddyAction>[
  BuddyAction(
    id: 'pat',
    label: '摸摸头',
    category: '摸摸',
    message: '摸摸头，今天也做得很好～',
    expression: BuddyExpression.happy,
    motion: BuddyMotion.bounce,
  ),
  BuddyAction(
    id: 'stroke',
    label: '顺顺毛',
    category: '摸摸',
    message: '顺毛～舒服得想打呼噜',
    expression: BuddyExpression.happy,
    motion: BuddyMotion.sway,
    seconds: 3,
  ),
  BuddyAction(
    id: 'pinch',
    label: '捏捏脸',
    category: '摸摸',
    message: '呜…脸要被捏圆啦！',
    expression: BuddyExpression.angry,
    motion: BuddyMotion.shake,
  ),
  BuddyAction(
    id: 'poke',
    label: '戳戳脸',
    category: '摸摸',
    message: '戳…戳什么戳！',
    expression: BuddyExpression.surprised,
    motion: BuddyMotion.shake,
    seconds: 2.2,
  ),
  BuddyAction(
    id: 'tickle',
    label: '挠痒痒',
    category: '摸摸',
    message: '哈哈哈别挠了！要喘不过气啦～',
    expression: BuddyExpression.happy,
    motion: BuddyMotion.shake,
    seconds: 2.8,
  ),
  BuddyAction(
    id: 'hug',
    label: '贴贴',
    category: '互动',
    message: '贴贴！电量回满啦～',
    expression: BuddyExpression.shy,
    motion: BuddyMotion.lean,
    seconds: 2.8,
  ),
  BuddyAction(
    id: 'pull',
    label: '牵手手',
    category: '互动',
    message: '诶诶——要带我去哪儿呀？',
    expression: BuddyExpression.surprised,
    motion: BuddyMotion.sway,
    seconds: 2.8,
  ),
  BuddyAction(
    id: 'highfive',
    label: '击个掌',
    category: '互动',
    message: '耶！击掌成功！',
    expression: BuddyExpression.happy,
    motion: BuddyMotion.bounce,
    seconds: 2.2,
  ),
  BuddyAction(
    id: 'fistbump',
    label: '碰碰拳',
    category: '互动',
    message: '碰拳！今天的我们超强！',
    expression: BuddyExpression.talk,
    motion: BuddyMotion.bounce,
    seconds: 2.2,
  ),
  BuddyAction(
    id: 'lift',
    label: '举高高',
    category: '互动',
    message: '哇——好高好高！',
    expression: BuddyExpression.surprised,
    motion: BuddyMotion.bounce,
    seconds: 3,
  ),
  BuddyAction(
    id: 'coffee',
    label: '递咖啡',
    category: '投喂',
    message: '续命咖啡！谢谢你～',
    expression: BuddyExpression.happy,
    motion: BuddyMotion.sip,
    seconds: 3,
  ),
  BuddyAction(
    id: 'milktea',
    label: '喝奶茶',
    category: '投喂',
    message: '是奶茶！快乐水 +1',
    expression: BuddyExpression.happy,
    motion: BuddyMotion.sip,
    seconds: 3,
  ),
  BuddyAction(
    id: 'candy',
    label: '喂糖',
    category: '投喂',
    message: '啊——甜到心里去了～',
    expression: BuddyExpression.happy,
    motion: BuddyMotion.sip,
    seconds: 2.6,
  ),
  BuddyAction(
    id: 'icecream',
    label: '吃冰淇淋',
    category: '投喂',
    message: '冰冰凉凉，好幸福！',
    expression: BuddyExpression.happy,
    motion: BuddyMotion.sip,
    seconds: 3,
  ),
  BuddyAction(
    id: 'flower',
    label: '送花花',
    category: '投喂',
    message: '给、给我的吗？谢谢…',
    expression: BuddyExpression.shy,
    motion: BuddyMotion.sway,
    seconds: 2.8,
  ),
  BuddyAction(
    id: 'sing',
    label: '唱首歌',
    category: '表演',
    message: '啦啦啦～把烦恼都唱跑～',
    expression: BuddyExpression.talk,
    motion: BuddyMotion.sway,
    seconds: 4,
  ),
  BuddyAction(
    id: 'dance',
    label: '跳个舞',
    category: '表演',
    message: '动次打次～一起摇摆！',
    expression: BuddyExpression.happy,
    motion: BuddyMotion.spin,
    seconds: 3.5,
  ),
  BuddyAction(
    id: 'spin',
    label: '转圈圈',
    category: '表演',
    message: '转呀转～有点晕乎乎…',
    expression: BuddyExpression.sleepy,
    motion: BuddyMotion.spin,
    seconds: 2.6,
  ),
  BuddyAction(
    id: 'bow',
    label: '鞠个躬',
    category: '表演',
    message: '今天也请多多指教！',
    expression: BuddyExpression.normal,
    motion: BuddyMotion.lean,
  ),
  BuddyAction(
    id: 'cheer',
    label: '加油打气',
    category: '表演',
    message: '加油加油！你是最棒的！',
    expression: BuddyExpression.happy,
    motion: BuddyMotion.bounce,
    seconds: 2.8,
  ),
  BuddyAction(
    id: 'wave',
    label: '打招呼',
    category: '日常',
    message: '嗨～见到你真好！',
    expression: BuddyExpression.happy,
    motion: BuddyMotion.sway,
  ),
  BuddyAction(
    id: 'typing',
    label: '敲代码',
    category: '日常',
    message: '噼里啪啦…bug 退散！',
    expression: BuddyExpression.talk,
    motion: BuddyMotion.type,
    seconds: 3.5,
  ),
  BuddyAction(
    id: 'think',
    label: '想一想',
    category: '日常',
    message: '嗯…让我想想…有了！',
    expression: BuddyExpression.surprised,
    motion: BuddyMotion.lean,
    seconds: 3,
  ),
  BuddyAction(
    id: 'stretch',
    label: '伸懒腰',
    category: '日常',
    message: '嗯——伸个懒腰，继续营业！',
    expression: BuddyExpression.sleepy,
    motion: BuddyMotion.bounce,
    seconds: 2.8,
  ),
  BuddyAction(
    id: 'photo',
    label: '拍张照',
    category: '日常',
    message: '茄子～要把我拍可爱一点！',
    expression: BuddyExpression.happy,
    motion: BuddyMotion.sway,
    seconds: 2.8,
  ),
  BuddyAction(
    id: 'shy',
    label: '害羞',
    category: '情绪',
    message: '别、别一直盯着我看啦…',
    expression: BuddyExpression.shy,
    motion: BuddyMotion.sway,
    seconds: 2.6,
  ),
  BuddyAction(
    id: 'angry',
    label: '生气',
    category: '情绪',
    message: '哼！我生气了，要哄哄才好！',
    expression: BuddyExpression.angry,
    motion: BuddyMotion.shake,
    seconds: 2.6,
  ),
  BuddyAction(
    id: 'comfort',
    label: '安慰',
    category: '情绪',
    message: '呜…有你在就不难过了',
    expression: BuddyExpression.sad,
    motion: BuddyMotion.lean,
    seconds: 3.2,
  ),
  BuddyAction(
    id: 'surprise',
    label: '吓一跳',
    category: '情绪',
    message: '哇啊！吓我一跳！',
    expression: BuddyExpression.surprised,
    motion: BuddyMotion.bounce,
    seconds: 2,
  ),
  BuddyAction(
    id: 'love',
    label: '比心',
    category: '情绪',
    message: '比心！最喜欢你啦～',
    expression: BuddyExpression.shy,
    motion: BuddyMotion.bounce,
    seconds: 2.6,
  ),
  BuddyAction(
    id: 'yawn',
    label: '打哈欠',
    category: '休息',
    message: '哈啊——有点困了…',
    expression: BuddyExpression.sleepy,
    motion: BuddyMotion.sleepy,
    seconds: 2.6,
  ),
  BuddyAction(
    id: 'nap',
    label: '打个盹',
    category: '休息',
    message: 'Zzz…五分钟…就五分钟…',
    expression: BuddyExpression.sleepy,
    motion: BuddyMotion.sleepy,
    seconds: 4,
  ),
  BuddyAction(
    id: 'umbrella',
    label: '撑把伞',
    category: '休息',
    message: '下雨啦？有你撑伞就不怕～',
    expression: BuddyExpression.happy,
    motion: BuddyMotion.lean,
    seconds: 3.2,
  ),
  BuddyAction(
    id: 'fan',
    label: '扇扇风',
    category: '休息',
    message: '呼——好凉快～',
    expression: BuddyExpression.happy,
    motion: BuddyMotion.sway,
    seconds: 3,
  ),
  BuddyAction(
    id: 'goodnight',
    label: '晚安',
    category: '休息',
    message: '晚安，明天也要元气满满哦',
    expression: BuddyExpression.sleepy,
    motion: BuddyMotion.sleepy,
    seconds: 3.5,
  ),
];

List<BuddyAction> actionsInCategory(String category) => [
      for (final action in workBuddyActions)
        if (action.category == category) action,
    ];
