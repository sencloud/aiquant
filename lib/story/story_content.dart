import 'package:flutter/material.dart';

import 'story_models.dart';

/// 第一季「临海七日」的内容包。
///
/// 三条路线都已跑通：林夏 / 苏予 / 陈野，各 7 夜、3 个结局；
/// 三条线任意结局都拿到后，解锁第 10 个结局「天亮以前」。
/// 所有文案都是原创，不使用参考作品的名称、角色、剧情或美术。
const StorySeason kNightSeason = StorySeason(
  id: 'before_dawn_s1',
  title: '天亮以前',
  subtitle: '临海 · 七日',
  tagline: '天亮以前，把话说完。',
  characters: _characters,
  routes: {
    'linxia': _linxiaRoute,
    'suyu': _suyuRoute,
    'chenye': _chenyeRoute,
  },
  posts: _posts,
  endingSlots: 10,
  trueEnding: _trueEnding,
);

const List<StoryCharacter> _characters = [
  StoryCharacter(
    id: 'linxia',
    name: '林夏',
    age: 27,
    city: '杭州',
    job: '摄影师',
    tags: ['温柔直球', '慢热', '胶片'],
    quote: '我不太会开场，但如果你说话，我会认真听。',
    status: '刚收工，在等雨停',
    nightWindow: '雨停前后 · 便利店',
    routeOpen: true,
    routeNote: '第 1 夜 · 雨',
    hair: Color(0xFF3B2A22),
    skin: Color(0xFFE9C3A6),
    jacket: Color(0xFFC87563),
    accent: Color(0xFFE8B36A),
    eye: Color(0xFF8A5A3C),
    bgA: Color(0xFF2A1D1A),
    bgB: Color(0xFF6B3A32),
    hairStyle: PixelHairStyle.long,
    accessory: PixelAccessory.catEars,
    expressions: [
      PixelExpression.calm,
      PixelExpression.soft,
      PixelExpression.hurt
    ],
    order: 0,
  ),
  StoryCharacter(
    id: 'suyu',
    name: '苏予',
    age: 29,
    city: '上海',
    job: '品牌策划',
    tags: ['清醒', '有点毒舌', '边界感'],
    quote: '别急着让我喜欢你，先让我觉得你有意思。',
    status: '加班完了，便利店门口',
    nightWindow: '23:00–01:00 · 便利店楼上',
    routeOpen: true,
    routeNote: '第 1 夜 · 便利店',
    hair: Color(0xFF2C2A33),
    skin: Color(0xFFF0D2B8),
    jacket: Color(0xFF3D4A66),
    accent: Color(0xFF9FB4D8),
    eye: Color(0xFF6F7F9E),
    bgA: Color(0xFF171C28),
    bgB: Color(0xFF3A4660),
    hairStyle: PixelHairStyle.bob,
    accessory: PixelAccessory.mole,
    expressions: [
      PixelExpression.calm,
      PixelExpression.smirk,
      PixelExpression.away
    ],
    order: 1,
  ),
  StoryCharacter(
    id: 'chenye',
    name: '陈野',
    age: 28,
    city: '北京',
    job: '纪录片编导',
    tags: ['话少', '观察细', '黑白片'],
    quote: '我不太会聊天，但我记得住你说话的样子。',
    status: '在地铁末班车上',
    nightWindow: '22:30–00:30 · 末班车',
    routeOpen: true,
    routeNote: '第 1 夜 · 末班车',
    hair: Color(0xFF1F1B19),
    skin: Color(0xFFD9AC83),
    jacket: Color(0xFF3A3D44),
    accent: Color(0xFFAEB4BF),
    eye: Color(0xFF4E545E),
    bgA: Color(0xFF17191E),
    bgB: Color(0xFF3A3E47),
    hairStyle: PixelHairStyle.buzz,
    accessory: PixelAccessory.cameraStrap,
    expressions: [
      PixelExpression.calm,
      PixelExpression.away,
      PixelExpression.soft
    ],
    order: 2,
  ),
  StoryCharacter(
    id: 'anke',
    name: '安可',
    age: 24,
    city: '成都',
    job: '独立音乐人',
    tags: ['夜猫', '话多', '情绪外放'],
    quote: '我白天不在线，晚上可以陪你聊到很晚。',
    status: '刚写完一段，想找人听',
    nightWindow: '01:00–04:00 · 电台 / livehouse',
    routeOpen: false,
    routeNote: '第二季',
    hair: Color(0xFF6B3A2E),
    skin: Color(0xFFE3B48C),
    jacket: Color(0xFF7A3E63),
    accent: Color(0xFFE58BB6),
    eye: Color(0xFFB4764A),
    bgA: Color(0xFF2A1524),
    bgB: Color(0xFF5E2F4C),
    hairStyle: PixelHairStyle.curly,
    accessory: PixelAccessory.hairClips,
    expressions: [
      PixelExpression.smile,
      PixelExpression.soft,
      PixelExpression.hurt
    ],
    order: 3,
  ),
  StoryCharacter(
    id: 'zhoumu',
    name: '周牧',
    age: 30,
    city: '深圳',
    job: '产品经理',
    tags: ['稳', '闷骚', '说到做到'],
    quote: '我不太会说好听的话，但答应的事会记住。',
    status: '夜跑回来，正在煮面',
    nightWindow: '22:00–23:30 · 24h 便利店',
    routeOpen: false,
    routeNote: '第二季',
    hair: Color(0xFF241C18),
    skin: Color(0xFFD9A87E),
    jacket: Color(0xFF3E5145),
    accent: Color(0xFF9DB8A4),
    eye: Color(0xFF4D6B58),
    bgA: Color(0xFF18211C),
    bgB: Color(0xFF35483D),
    hairStyle: PixelHairStyle.short,
    accessory: PixelAccessory.watch,
    expressions: [
      PixelExpression.calm,
      PixelExpression.soft,
      PixelExpression.hurt
    ],
    order: 4,
  ),
  StoryCharacter(
    id: 'luyao',
    name: '路遥',
    age: 31,
    city: '重庆',
    job: '建筑师',
    tags: ['爽利', '嘴硬心软', '会做饭'],
    quote: '别跟我绕。想聊就聊，不想聊就去睡。',
    status: '锅里还炖着东西',
    nightWindow: '18:00–21:00 · 旧公寓',
    routeOpen: false,
    routeNote: '第二季',
    hair: Color(0xFF2A201B),
    skin: Color(0xFFC98A5E),
    jacket: Color(0xFF7A4A2A),
    accent: Color(0xFFE0A45E),
    eye: Color(0xFFA9743E),
    bgA: Color(0xFF261A12),
    bgB: Color(0xFF5C3820),
    hairStyle: PixelHairStyle.wavy,
    accessory: PixelAccessory.apron,
    expressions: [
      PixelExpression.smile,
      PixelExpression.smirk,
      PixelExpression.soft
    ],
    order: 5,
  ),
];

const StoryRoute _linxiaRoute = StoryRoute(
  characterId: 'linxia',
  nights: _linxiaNights,
  endings: _linxiaEndings,
);

const List<StoryEnding> _linxiaEndings = [
  StoryEnding(
    id: 'linxia_he',
    title: '雨停之后',
    quote: '照片洗出来了。你没在里面，但那天你在。',
    kind: StoryEndingKind.he,
    hint: '把伞递过去，也把真话说完。',
  ),
  StoryEnding(
    id: 'linxia_ne',
    title: '未冲洗的胶卷',
    quote: '胶卷还在包里。我们都没提那天。',
    kind: StoryEndingKind.ne,
    hint: '靠近过，但没有留下。',
  ),
  StoryEnding(
    id: 'linxia_be',
    title: '把伞留下',
    quote: '伞我放在楼下。你走的时候，雨已经停了。',
    kind: StoryEndingKind.be,
    hint: '有些话，说晚了一步。',
  ),
];

const List<StoryNight> _linxiaNights = [
  StoryNight(
    number: 1,
    title: '落地',
    time: '00:47',
    place: '旧公寓 · 七楼',
    scene: '雨',
    beats: [
      StoryBeat(
        id: 'n1b1',
        note: '屏幕亮起来的时候，窗外的雨正敲在空调外机上。',
        opening: ['你那边下雨了吗？', '我是今天在大堂借你充电线的人。'],
        choices: [
          StoryChoice(
            id: 'n1b1_rain',
            label: '下了。没带伞。',
            reply: '别动。我带了。',
            hearts: 1,
            flags: ['answered_rain'],
          ),
          StoryChoice(
            id: 'n1b1_who',
            label: '你是？',
            reply: '林夏。摄影的，今天穿米色风衣。',
            hearts: 0,
            flags: ['asked_who'],
          ),
        ],
      ),
      StoryBeat(
        id: 'n1b2',
        note: '她回得很快，像是一直站在楼下。',
        opening: ['你住几楼？'],
        choices: [
          StoryChoice(
            id: 'n1b2_floor',
            label: '七楼，走廊尽头。',
            reply: '我送到楼下。不上去了。',
            hearts: 1,
            flags: ['gave_floor'],
          ),
          StoryChoice(
            id: 'n1b2_no',
            label: '不用麻烦。',
            reply: '……好。那明天呢？',
            hearts: -1,
            flags: ['refused_first'],
          ),
        ],
      ),
    ],
    closing: '那天晚上，雨到两点才停。',
  ),
  StoryNight(
    number: 2,
    title: '习惯',
    time: '23:10',
    place: '便利店门口',
    scene: '雨停',
    beats: [
      StoryBeat(
        id: 'n2b1',
        note: '她把相机挎在肩上，站在自动门旁边，没有进来。',
        opening: ['今天拍到一张好看的。', '你要看吗？'],
        choices: [
          StoryChoice(
            id: 'n2b1_photo',
            label: '发我看看。',
            reply: '只给你看一张。',
            hearts: 1,
            flags: ['asked_photo'],
          ),
          StoryChoice(
            id: 'n2b1_habit',
            label: '你每天都拍吗？',
            reply: '不一定。有光就拍。',
            hearts: 0,
            flags: ['asked_habit'],
          ),
        ],
      ),
      StoryBeat(
        id: 'n2b2',
        note: '冰柜的嗡鸣声比人声大。',
        opening: ['明天有空吗？', '我想去旧码头。'],
        choices: [
          StoryChoice(
            id: 'n2b2_yes',
            label: '有。几点？',
            reply: '下午四点。退潮的时候。',
            hearts: 1,
            flags: ['made_plan'],
          ),
          StoryChoice(
            id: 'n2b2_busy',
            label: '要加班。',
            reply: '哦。那算了。',
            hearts: -1,
            flags: ['busy'],
          ),
        ],
      ),
    ],
    closing: '她把相机抱在怀里，像抱着一只猫。',
  ),
  StoryNight(
    number: 3,
    title: '裂缝',
    time: '23:40',
    place: '便利店 · 靠窗',
    scene: '冷白灯',
    beats: [
      StoryBeat(
        id: 'n3b1',
        note: '她发来一张 contact sheet。最后一行，有一个你。',
        opening: ['今天洗了一卷。', '里面有张照片，你可能不想看。'],
        choices: [
          StoryChoice(
            id: 'n3b1_see',
            label: '发我。',
            reply: '……那你别生气。',
            hearts: 1,
            flags: ['saw_photo'],
          ),
          StoryChoice(
            id: 'n3b1_accuse',
            label: '你偷拍我？',
            reply: '不算偷拍。你站在光里。',
            hearts: -1,
            flags: ['accused'],
          ),
        ],
      ),
      StoryBeat(
        id: 'n3b2',
        note: '照片里的你正低头看手机，背后是那盏坏了半边的路灯。',
        opening: ['我本来想删掉的。'],
        choices: [
          StoryChoice(
            id: 'n3b2_why',
            label: '为什么没删？',
            reply: '因为那天你笑了一下。',
            hearts: 1,
            flags: ['why_kept'],
          ),
          StoryChoice(
            id: 'n3b2_delete',
            label: '删了吧。',
            reply: '好。',
            hearts: -1,
            flags: ['delete_photo'],
          ),
        ],
      ),
    ],
    closing: '屏幕那头很久没有动。',
  ),
  StoryNight(
    number: 4,
    title: '缺席',
    time: '00:47',
    place: '旧公寓',
    scene: '雨',
    beats: [
      StoryBeat(
        id: 'n4b1',
        note: '00:47。通讯录里那个名字没有亮。',
        opening: [],
        choices: [
          StoryChoice(
            id: 'n4b1_echo',
            label: '发一句：我在便利店。',
            reply: '（01:20）刚看到。',
            hearts: 1,
            flags: ['left_echo'],
          ),
          StoryChoice(
            id: 'n4b1_silent',
            label: '什么都不发。',
            reply: '（01:20）你睡了吗？',
            hearts: -1,
            flags: ['silent'],
          ),
        ],
      ),
      StoryBeat(
        id: 'n4b2',
        note: '便利店的关东煮锅，咕嘟了一声。',
        opening: ['刚看到。', '便利店还开着吗？'],
        choices: [
          StoryChoice(
            id: 'n4b2_wait',
            label: '我等你。',
            reply: '别等。我十分钟到。',
            hearts: 1,
            flags: ['waited'],
          ),
          StoryChoice(
            id: 'n4b2_sleep',
            label: '没事，早点睡。',
            reply: '好。晚安。',
            hearts: 0,
            flags: ['let_go'],
          ),
        ],
      ),
    ],
    closing: '她来的时候，伞还在滴水。',
  ),
  StoryNight(
    number: 5,
    title: '靠近',
    time: '23:20',
    place: '旧码头',
    scene: '退潮',
    beats: [
      StoryBeat(
        id: 'n5b1',
        note: '海风把她的头发吹到一边，她没有去拨。',
        opening: ['我下个月去厦门。', '票已经买了。'],
        choices: [
          StoryChoice(
            id: 'n5b1_howlong',
            label: '去多久？',
            reply: '不知道。可能很久。',
            hearts: 0,
            flags: ['asked_duration'],
          ),
          StoryChoice(
            id: 'n5b1_return',
            label: '还回来吗？',
            reply: '你想我回来吗？',
            hearts: 1,
            flags: ['asked_return'],
          ),
        ],
      ),
      StoryBeat(
        id: 'n5b2',
        note: '远处有船进港，灯一盏一盏亮起来。',
        opening: ['你会来送我吗？'],
        choices: [
          StoryChoice(
            id: 'n5b2_yes',
            label: '会。',
            reply: '那我给你留一张照片。',
            hearts: 1,
            flags: ['will_see_off'],
          ),
          StoryChoice(
            id: 'n5b2_no',
            label: '我不喜欢送人。',
            reply: '嗯。我懂。',
            hearts: -1,
            flags: ['hate_goodbye'],
          ),
        ],
      ),
    ],
    closing: '她把伞收起来，水滴在脚边积成一小片。',
  ),
  StoryNight(
    number: 6,
    title: '选择',
    time: '23:55',
    place: '便利店 · 靠窗',
    scene: '雨',
    beats: [
      StoryBeat(
        id: 'n6b1',
        note: '窗外的雨又下起来了，像第一夜。',
        opening: ['最后一晚。', '你想怎么过？'],
        choices: [
          StoryChoice(
            id: 'n6b1_stay',
            label: '在便利店坐到天亮。',
            reply: '好。我去买两杯热的。',
            hearts: 1,
            flags: ['stay'],
          ),
          StoryChoice(
            id: 'n6b1_home',
            label: '各自回家吧。',
            reply: '……好。',
            hearts: -1,
            flags: ['leave_early'],
          ),
        ],
      ),
      StoryBeat(
        id: 'n6b2',
        note: '她把热咖啡推到你面前，自己那杯没动。',
        opening: ['如果我说，别走呢？'],
        choices: [
          StoryChoice(
            id: 'n6b2_stay',
            label: '那我留下。',
            reply: '你别骗我。',
            hearts: 1,
            flags: ['stay'],
          ),
          StoryChoice(
            id: 'n6b2_go',
            label: '我明天必须走。',
            reply: '我知道。',
            hearts: 0,
            flags: ['must_go'],
          ),
          StoryChoice(
            id: 'n6b2_lie',
            label: '（说谎）我留下。',
            reply: '你看着我的时候，不像在说真话。',
            hearts: -1,
            flags: ['lied'],
          ),
        ],
      ),
    ],
    closing: '她笑了一下，像早就知道答案。',
  ),
  StoryNight(
    number: 7,
    title: '天亮以前',
    time: '05:10',
    place: '旧公寓楼下',
    scene: '天快亮',
    beats: [
      StoryBeat(
        id: 'n7b1',
        note: '天边有一条很细的亮线。第一班车还有二十分钟。',
        opening: ['天快亮了。', '你窗外的灯还亮着。'],
        choices: [
          StoryChoice(
            id: 'n7b1_down',
            label: '我在楼下。',
            reply: '我看见了。',
            hearts: 1,
            flags: ['came_down'],
          ),
          StoryChoice(
            id: 'n7b1_pack',
            label: '我在收拾行李。',
            reply: '……那我不上去了。',
            hearts: -1,
            flags: ['packing'],
          ),
        ],
      ),
      StoryBeat(
        id: 'n7b2',
        note: '她把一个牛皮纸袋递过来，边角被雨打湿了一点。',
        opening: ['照片洗出来了。', '你要看吗？'],
        choices: [
          StoryChoice(
            id: 'n7b2_self',
            label: '有我吗？',
            reply: '有。只有一张。',
            hearts: 1,
            flags: ['asked_self'],
          ),
          StoryChoice(
            id: 'n7b2_keep',
            label: '你留一张吧。',
            reply: '好。',
            hearts: 0,
            flags: ['kept_one'],
          ),
        ],
      ),
    ],
    closing: '第一班车进站的时候，雨已经停了。',
  ),
];

const StoryRoute _suyuRoute = StoryRoute(
  characterId: 'suyu',
  nights: _suyuNights,
  endings: _suyuEndings,
);

const List<StoryEnding> _suyuEndings = [
  StoryEnding(
    id: 'suyu_he',
    title: '关东煮的汤',
    quote: '最后一颗鱼丸，她留给了你。',
    kind: StoryEndingKind.he,
    hint: '给她空间，也接住她的真话。',
  ),
  StoryEnding(
    id: 'suyu_ne',
    title: '最后一个在吗',
    quote: '你们都没说真话。',
    kind: StoryEndingKind.ne,
    hint: '靠近过，但没让她放心。',
  ),
  StoryEnding(
    id: 'suyu_be',
    title: '准时下班',
    quote: '她回到自己的轨道。',
    kind: StoryEndingKind.be,
    hint: '有些边界，不该用试探去撞。',
  ),
];

const List<StoryNight> _suyuNights = [
  StoryNight(
    number: 1,
    title: '便利店',
    time: '23:05',
    place: '便利店门口',
    scene: '冷白灯',
    beats: [
      StoryBeat(
        id: 's1b1',
        note: '自动门开了一下又合上。她拎着两杯黑咖啡，没有进来。',
        opening: ['这么晚还没睡，是在忙还是在躲？'],
        choices: [
          StoryChoice(
            id: 's1b1_honest',
            label: '在躲。',
            reply: '诚实。加分。',
            hearts: 1,
            flags: ['honest'],
          ),
          StoryChoice(
            id: 's1b1_busy',
            label: '在忙。',
            reply: '忙什么？别说是工作。',
            hearts: 0,
            flags: ['busy'],
          ),
        ],
      ),
      StoryBeat(
        id: 's1b2',
        note: '她把其中一杯推过来，杯壁上的水汽沾了手指。',
        opening: ['我住楼上。', '你呢？'],
        choices: [
          StoryChoice(
            id: 's1b2_place',
            label: '七楼，旧公寓。',
            reply: '那不远。',
            hearts: 1,
            flags: ['gave_place'],
          ),
          StoryChoice(
            id: 's1b2_private',
            label: '不方便说。',
            reply: '行。边界感，我懂。',
            hearts: 0,
            flags: ['private'],
          ),
        ],
      ),
    ],
    closing: '她买了两杯黑咖啡，一杯推给你。',
  ),
  StoryNight(
    number: 2,
    title: '关东煮',
    time: '23:20',
    place: '便利店 · 靠窗',
    scene: '热气',
    beats: [
      StoryBeat(
        id: 's2b1',
        note: '锅里的汤咕嘟了一声。她夹起最后一颗鱼丸。',
        opening: ['最后一颗鱼丸。', '你要吗？'],
        choices: [
          StoryChoice(
            id: 's2b1_give',
            label: '给你。',
            reply: '……谢了。',
            hearts: 1,
            flags: ['gave_fishball'],
          ),
          StoryChoice(
            id: 's2b1_take',
            label: '我要。',
            reply: '真不客气。',
            hearts: 0,
            flags: ['took_fishball'],
          ),
        ],
      ),
      StoryBeat(
        id: 's2b2',
        note: '她托着腮看你，像在看一份还没写完的提案。',
        opening: ['你今天看起来，比昨天松一点。'],
        choices: [
          StoryChoice(
            id: 's2b2_flirt',
            label: '因为你在。',
            reply: '少来。',
            hearts: 1,
            flags: ['flirt'],
          ),
          StoryChoice(
            id: 's2b2_deflect',
            label: '可能睡好了。',
            reply: '嗯。',
            hearts: 0,
            flags: ['deflect'],
          ),
        ],
      ),
    ],
    closing: '她把关东煮的汤喝完了，连汤都没剩。',
  ),
  StoryNight(
    number: 3,
    title: '裂缝',
    time: '23:50',
    place: '便利店楼上',
    scene: '冷白灯',
    beats: [
      StoryBeat(
        id: 's3b1',
        note: '楼上的窗户开着一条缝，风把她的衬衫吹得鼓起来。',
        opening: ['你昨天问我为什么来临海。', '我没说实话。'],
        choices: [
          StoryChoice(
            id: 's3b1_truth',
            label: '那现在说。',
            reply: '我辞职了。',
            hearts: 1,
            flags: ['asked_truth'],
          ),
          StoryChoice(
            id: 's3b1_space',
            label: '不想说就不说。',
            reply: '……你这个人，有点麻烦。',
            hearts: 1,
            flags: ['gave_space'],
          ),
          StoryChoice(
            id: 's3b1_family',
            label: '你家里知道吗？',
            reply: '这不在今晚的范围里。',
            hearts: -1,
            flags: ['asked_family'],
          ),
        ],
      ),
      StoryBeat(
        id: 's3b2',
        note: '她低头转着杯子，指甲在杯壁上敲了两下。',
        opening: ['我本来在上海有个很好的位置。', '说出去，别人会觉得我疯了。'],
        choices: [
          StoryChoice(
            id: 's3b2_self',
            label: '你自己觉得呢？',
            reply: '我觉得我终于睡了个好觉。',
            hearts: 1,
            flags: ['asked_self'],
          ),
          StoryChoice(
            id: 's3b2_judge',
            label: '确实挺疯的。',
            reply: '……你倒是直接。',
            hearts: -1,
            flags: ['judged'],
          ),
        ],
      ),
    ],
    closing: '她第一次没有回嘴。',
  ),
  StoryNight(
    number: 4,
    title: '缺席',
    time: '00:20',
    place: '便利店门口',
    scene: '雨',
    beats: [
      StoryBeat(
        id: 's4b1',
        note: '00:20。她没出现。便利店的灯还亮着。',
        opening: [],
        choices: [
          StoryChoice(
            id: 's4b1_echo',
            label: '发一句：我在楼下。',
            reply: '（00:47）刚看到。',
            hearts: 1,
            flags: ['left_echo'],
          ),
          StoryChoice(
            id: 's4b1_silent',
            label: '什么都不发。',
            reply: '（00:47）你睡了吗？',
            hearts: -1,
            flags: ['silent'],
          ),
        ],
      ),
      StoryBeat(
        id: 's4b2',
        note: '她穿着拖鞋下来，头发没扎。',
        opening: ['刚看到。', '你还在吗？'],
        choices: [
          StoryChoice(
            id: 's4b2_wait',
            label: '在。',
            reply: '我下来。',
            hearts: 1,
            flags: ['waited'],
          ),
          StoryChoice(
            id: 's4b2_sleep',
            label: '准备睡了。',
            reply: '好。晚安。',
            hearts: 0,
            flags: ['let_go'],
          ),
        ],
      ),
    ],
    closing: '她站在门口，拖鞋边沾了一点雨水。',
  ),
  StoryNight(
    number: 5,
    title: '靠近',
    time: '23:30',
    place: '旧码头',
    scene: '退潮',
    beats: [
      StoryBeat(
        id: 's5b1',
        note: '海风很硬。她把外套裹紧，还是没有回去。',
        opening: ['我后天回上海。', '快闪结束了。'],
        choices: [
          StoryChoice(
            id: 's5b1_want',
            label: '你想回去吗？',
            reply: '不知道。',
            hearts: 1,
            flags: ['asked_want'],
          ),
          StoryChoice(
            id: 's5b1_go',
            label: '那就回去。',
            reply: '你倒是干脆。',
            hearts: 0,
            flags: ['let_go'],
          ),
        ],
      ),
      StoryBeat(
        id: 's5b2',
        note: '远处有船进港，灯一盏一盏亮起来。',
        opening: ['如果我不回去呢？'],
        choices: [
          StoryChoice(
            id: 's5b2_stay',
            label: '那就别回。',
            reply: '你说得轻巧。',
            hearts: 1,
            flags: ['stay'],
          ),
          StoryChoice(
            id: 's5b2_family',
            label: '你家里会担心。',
            reply: '别拿家里压我。',
            hearts: -1,
            flags: ['family'],
          ),
        ],
      ),
    ],
    closing: '海风把她的头发吹乱，她这次没有拨。',
  ),
  StoryNight(
    number: 6,
    title: '选择',
    time: '23:55',
    place: '便利店 · 靠窗',
    scene: '雨',
    beats: [
      StoryBeat(
        id: 's6b1',
        note: '最后一晚，她把两张车票放在桌上，一张上海，一张临海。',
        opening: ['最后一晚。', '你想我留下吗？'],
        choices: [
          StoryChoice(
            id: 's6b1_want',
            label: '想。',
            reply: '想就想，别拐弯。',
            hearts: 1,
            flags: ['stay'],
          ),
          StoryChoice(
            id: 's6b1_decide',
            label: '你自己决定。',
            reply: '……行。',
            hearts: 0,
            flags: ['let_her_decide'],
          ),
        ],
      ),
      StoryBeat(
        id: 's6b2',
        note: '她没有看票，只看你。',
        opening: ['我要是留下，可能什么都没有。'],
        choices: [
          StoryChoice(
            id: 's6b2_stay',
            label: '我陪你从头来。',
            reply: '你最好记住这句话。',
            hearts: 1,
            flags: ['stay'],
          ),
          StoryChoice(
            id: 's6b2_back',
            label: '那还是回去吧。',
            reply: '嗯。安全。',
            hearts: -1,
            flags: ['leave_early'],
          ),
          StoryChoice(
            id: 's6b2_lie',
            label: '（说谎）我跟你去上海。',
            reply: '你连自己都骗。',
            hearts: -1,
            flags: ['lied'],
          ),
        ],
      ),
    ],
    closing: '她把黑咖啡喝完，杯底有一圈没化的糖。',
  ),
  StoryNight(
    number: 7,
    title: '天亮以前',
    time: '05:40',
    place: '便利店门口',
    scene: '天快亮',
    beats: [
      StoryBeat(
        id: 's7b1',
        note: '第一班车还有二十分钟。便利店的灯还亮着。',
        opening: ['天快亮了。', '我买了第一班车的票。'],
        choices: [
          StoryChoice(
            id: 's7b1_down',
            label: '我在便利店。',
            reply: '我看见你了。',
            hearts: 1,
            flags: ['came_down'],
          ),
          StoryChoice(
            id: 's7b1_pack',
            label: '我不去了。',
            reply: '……好。',
            hearts: -1,
            flags: ['packing'],
          ),
        ],
      ),
      StoryBeat(
        id: 's7b2',
        note: '她手里还拎着那两杯黑咖啡，一杯已经凉了。',
        opening: ['以后还会来吗？'],
        choices: [
          StoryChoice(
            id: 's7b2_return',
            label: '会。',
            reply: '那我给你留一盏灯。',
            hearts: 1,
            flags: ['asked_return'],
          ),
          StoryChoice(
            id: 's7b2_unknown',
            label: '不知道。',
            reply: '诚实。',
            hearts: 0,
            flags: ['kept_one'],
          ),
        ],
      ),
    ],
    closing: '第一班车进站时，她把店门口的灯关了。',
  ),
];

const StoryRoute _chenyeRoute = StoryRoute(
  characterId: 'chenye',
  nights: _chenyeNights,
  endings: _chenyeEndings,
);

const List<StoryEnding> _chenyeEndings = [
  StoryEnding(
    id: 'chenye_he',
    title: '片尾字幕',
    quote: '片尾没有你的名字，但每一帧都有。',
    kind: StoryEndingKind.he,
    hint: '让他拍，也让他把镜头放下。',
  ),
  StoryEnding(
    id: 'chenye_ne',
    title: '没剪进去的镜头',
    quote: '那段素材还在，他没剪。',
    kind: StoryEndingKind.ne,
    hint: '你们都没有演，但也都留了退路。',
  ),
  StoryEnding(
    id: 'chenye_be',
    title: '末班车',
    quote: '你上了车，他没追。',
    kind: StoryEndingKind.be,
    hint: '有些镜头，错过就是错过。',
  ),
];

const List<StoryNight> _chenyeNights = [
  StoryNight(
    number: 1,
    title: '末班车',
    time: '22:30',
    place: '末班车 · 车窗',
    scene: '车窗起雾',
    beats: [
      StoryBeat(
        id: 'c1b1',
        note: '车厢里只有三个人。他把相机放在膝盖上，没有开机。',
        opening: ['你今天有没有哪一刻，忽然不想说话？'],
        choices: [
          StoryChoice(
            id: 'c1b1_yes',
            label: '有。',
            reply: '哪一刻？',
            hearts: 1,
            flags: ['honest'],
          ),
          StoryChoice(
            id: 'c1b1_no',
            label: '没有。',
            reply: '挺好。',
            hearts: 0,
            flags: ['deflect'],
          ),
        ],
      ),
      StoryBeat(
        id: 'c1b2',
        note: '车窗上有一层雾，他用手背擦了一小块。',
        opening: ['我拍纪录片。', '在拍一个关于离开的片子。'],
        choices: [
          StoryChoice(
            id: 'c1b2_film',
            label: '拍到了吗？',
            reply: '还差一个结尾。',
            hearts: 1,
            flags: ['asked_film'],
          ),
          StoryChoice(
            id: 'c1b2_why',
            label: '为什么要拍离开？',
            reply: '因为留下来的人更难拍。',
            hearts: 1,
            flags: ['asked_why'],
          ),
        ],
      ),
    ],
    closing: '到站的时候，他没有动。',
  ),
  StoryNight(
    number: 2,
    title: '镜头',
    time: '22:40',
    place: '末班车 · 车窗',
    scene: '车窗起雾',
    beats: [
      StoryBeat(
        id: 'c2b1',
        note: '他把镜头盖打开，又合上。',
        opening: ['我想拍你。', '只拍背影。'],
        choices: [
          StoryChoice(
            id: 'c2b1_yes',
            label: '可以。',
            reply: '谢谢。',
            hearts: 1,
            flags: ['let_film'],
          ),
          StoryChoice(
            id: 'c2b1_no',
            label: '不行。',
            reply: '好。我不勉强。',
            hearts: -1,
            flags: ['refused_film'],
          ),
        ],
      ),
      StoryBeat(
        id: 'c2b2',
        note: '他说完就看向窗外，像在给你留退路。',
        opening: ['你不想被拍，是因为怕被看见吗？'],
        choices: [
          StoryChoice(
            id: 'c2b2_admit',
            label: '是。',
            reply: '我不拍脸。',
            hearts: 1,
            flags: ['admitted'],
          ),
          StoryChoice(
            id: 'c2b2_deny',
            label: '不是。',
            reply: '嗯。',
            hearts: 0,
            flags: ['denied'],
          ),
        ],
      ),
    ],
    closing: '他把镜头盖扣上，又打开。',
  ),
  StoryNight(
    number: 3,
    title: '裂缝',
    time: '23:10',
    place: '末班车 · 车窗',
    scene: '黑白色',
    beats: [
      StoryBeat(
        id: 'c3b1',
        note: '监视器里是你的背影，站台，和一盏坏了半边的灯。',
        opening: ['今天拍了一段。', '你可能会不舒服。'],
        choices: [
          StoryChoice(
            id: 'c3b1_watch',
            label: '放给我看。',
            reply: '……好。',
            hearts: 1,
            flags: ['saw_footage'],
          ),
          StoryChoice(
            id: 'c3b1_delete',
            label: '删了吧。',
            reply: '可以。',
            hearts: -1,
            flags: ['delete'],
          ),
        ],
      ),
      StoryBeat(
        id: 'c3b2',
        note: '屏幕里的你一动不动，像在等一个不会来的人。',
        opening: ['你站在站台上的样子，很像在等一个不会来的人。'],
        choices: [
          StoryChoice(
            id: 'c3b2_self',
            label: '你拍的是我，还是你自己？',
            reply: '……都有。',
            hearts: 1,
            flags: ['asked_self'],
          ),
          StoryChoice(
            id: 'c3b2_shut',
            label: '别分析了。',
            reply: '好。',
            hearts: -1,
            flags: ['shut_down'],
          ),
        ],
      ),
    ],
    closing: '他把监视器转过来，屏幕里只有你的背影。',
  ),
  StoryNight(
    number: 4,
    title: '缺席',
    time: '23:30',
    place: '末班车 · 站台',
    scene: '末班车',
    beats: [
      StoryBeat(
        id: 'c4b1',
        note: '23:30。末班车进站，他没有发消息。',
        opening: [],
        choices: [
          StoryChoice(
            id: 'c4b1_go',
            label: '去站台。',
            reply: '（23:52）你在哪。',
            hearts: 1,
            flags: ['went_to_bus'],
          ),
          StoryChoice(
            id: 'c4b1_wait',
            label: '等。',
            reply: '（23:52）今天不拍了。',
            hearts: 0,
            flags: ['waited'],
          ),
        ],
      ),
      StoryBeat(
        id: 'c4b2',
        note: '站台的灯把两个人的影子拉得很长。',
        opening: ['我在站台。', '最后一班。'],
        choices: [
          StoryChoice(
            id: 'c4b2_come',
            label: '我过来。',
            reply: '我等你。',
            hearts: 1,
            flags: ['came'],
          ),
          StoryChoice(
            id: 'c4b2_go',
            label: '你先回吧。',
            reply: '……好。',
            hearts: 0,
            flags: ['let_go'],
          ),
        ],
      ),
    ],
    closing: '他没有上车。',
  ),
  StoryNight(
    number: 5,
    title: '靠近',
    time: '23:50',
    place: '旧码头',
    scene: '退潮',
    beats: [
      StoryBeat(
        id: 'c5b1',
        note: '他把相机放下，第一次没有看取景器。',
        opening: ['片子拍不下去了。', '因为我也不知道怎么告别。'],
        choices: [
          StoryChoice(
            id: 'c5b1_stay',
            label: '那就别告别。',
            reply: '你说得轻巧。',
            hearts: 1,
            flags: ['stay'],
          ),
          StoryChoice(
            id: 'c5b1_leave',
            label: '因为你要走吗？',
            reply: '可能。',
            hearts: 1,
            flags: ['asked_leave'],
          ),
        ],
      ),
      StoryBeat(
        id: 'c5b2',
        note: '远处有船进港，灯一盏一盏亮起来。',
        opening: ['你愿意让我拍最后一个镜头吗？', '不演。就站着。'],
        choices: [
          StoryChoice(
            id: 'c5b2_yes',
            label: '愿意。',
            reply: '谢谢。',
            hearts: 1,
            flags: ['will_film', 'let_film'],
          ),
          StoryChoice(
            id: 'c5b2_no',
            label: '不。',
            reply: '好。',
            hearts: -1,
            flags: ['refused_last'],
          ),
        ],
      ),
    ],
    closing: '他把镜头盖合上，没有再打开。',
  ),
  StoryNight(
    number: 6,
    title: '选择',
    time: '00:10',
    place: '末班车 · 车窗',
    scene: '雨',
    beats: [
      StoryBeat(
        id: 'c6b1',
        note: '最后一晚。车厢里只剩你们两个人。',
        opening: ['最后一晚。', '明天之后，这卷就结束了。'],
        choices: [
          StoryChoice(
            id: 'c6b1_stay',
            label: '那就拍完。',
            reply: '好。',
            hearts: 1,
            flags: ['stay'],
          ),
          StoryChoice(
            id: 'c6b1_stop',
            label: '到此为止吧。',
            reply: '……行。',
            hearts: -1,
            flags: ['leave_early'],
          ),
        ],
      ),
      StoryBeat(
        id: 'c6b2',
        note: '他把场记板合上，声音很轻。',
        opening: ['如果片尾要写一句话，你想写什么？'],
        choices: [
          StoryChoice(
            id: 'c6b2_self',
            label: '写「他来过渡口」。',
            reply: '好。',
            hearts: 1,
            flags: ['stay'],
          ),
          StoryChoice(
            id: 'c6b2_him',
            label: '你决定。',
            reply: '那我写「末班车」。',
            hearts: 0,
            flags: ['let_him'],
          ),
          StoryChoice(
            id: 'c6b2_lie',
            label: '（说谎）写我们。',
            reply: '我们没到那儿。',
            hearts: -1,
            flags: ['lied'],
          ),
        ],
      ),
    ],
    closing: '他把场记板放进包里，拉链拉到一半停住。',
  ),
  StoryNight(
    number: 7,
    title: '天亮以前',
    time: '05:50',
    place: '站台',
    scene: '天快亮',
    beats: [
      StoryBeat(
        id: 'c7b1',
        note: '第一班车还有十分钟。站台的风把广告纸吹得贴在栏杆上。',
        opening: ['天快亮了。', '第一班车还有十分钟。'],
        choices: [
          StoryChoice(
            id: 'c7b1_down',
            label: '我在站台。',
            reply: '我看见你了。',
            hearts: 1,
            flags: ['came_down'],
          ),
          StoryChoice(
            id: 'c7b1_pack',
            label: '我在检票口。',
            reply: '……好。',
            hearts: -1,
            flags: ['packing'],
          ),
        ],
      ),
      StoryBeat(
        id: 'c7b2',
        note: '他把相机背带收进包里，又拿出来。',
        opening: ['片子剪完了。', '你想看吗？'],
        choices: [
          StoryChoice(
            id: 'c7b2_self',
            label: '有我吗？',
            reply: '有。每一帧。',
            hearts: 1,
            flags: ['asked_self'],
          ),
          StoryChoice(
            id: 'c7b2_keep',
            label: '你留着吧。',
            reply: '好。',
            hearts: 0,
            flags: ['kept_one'],
          ),
        ],
      ),
    ],
    closing: '第一班车进站时，他把相机背带收进了包里。',
  ),
];

const StoryEnding _trueEnding = StoryEnding(
  id: 'true_ending',
  title: '天亮以前',
  quote: '你没有留住任何人，但你把每一句话都说完了。',
  kind: StoryEndingKind.trueEnd,
  hint: '三条线都走完。',
);

const List<StoryPost> _posts = [
  StoryPost(
    id: 'p_linxia_1',
    authorId: 'linxia',
    text: '雨停之前，路灯把整条街照成了旧照片。',
    timeLabel: '21:12',
    unlockAfterNight: 1,
    hearts: 18,
  ),
  StoryPost(
    id: 'p_linxia_2',
    authorId: 'linxia',
    text: '今天洗了三卷，只留下一张。',
    timeLabel: '23:40',
    unlockAfterNight: 2,
    hearts: 9,
  ),
  StoryPost(
    id: 'p_suyu_1',
    authorId: 'suyu',
    text: '便利店关东煮的汤，是这座城市最后的温柔。',
    timeLabel: '23:05',
    unlockAfterNight: 0,
    hearts: 26,
  ),
  StoryPost(
    id: 'p_chenye_1',
    authorId: 'chenye',
    text: '末班车上没人说话，只有报站声。',
    timeLabel: '23:26',
    unlockAfterNight: 0,
    hearts: 15,
  ),
  StoryPost(
    id: 'p_anke_1',
    authorId: 'anke',
    text: '凌晨三点写完一段前奏，像终于把一句话说完。',
    timeLabel: '03:12',
    unlockAfterNight: 0,
    hearts: 42,
  ),
  StoryPost(
    id: 'p_luyao_1',
    authorId: 'luyao',
    text: '旧房子拆下来的木头，做成了一张桌子。',
    timeLabel: '18:50',
    unlockAfterNight: 0,
    hearts: 21,
  ),
  StoryPost(
    id: 'p_zhoumu_1',
    authorId: 'zhoumu',
    text: '跑了 6 公里，回来发现冰箱里还有半个西瓜。',
    timeLabel: '20:40',
    unlockAfterNight: 0,
    hearts: 12,
  ),
];
