/// 她可以换的形象：一个名字、一张写真、一种说话底色。
///
/// 换形象 = 换名字与语气（服务端会收到 companion_name / companion_style），
/// 记忆与对话不换。
class CompanionLook {
  const CompanionLook({
    required this.id,
    required this.name,
    required this.asset,
    required this.style,
    required this.moments,
  });

  final String id;
  final String name;
  final String asset;

  /// 一句给服务端的语气说明。
  final String style;
  final List<CompanionMoment> moments;
}

class CompanionMoment {
  const CompanionMoment({required this.text, required this.at, this.image});
  final String text;
  final DateTime at;
  final String? image;
}

final List<CompanionLook> kCompanionLooks = [
  CompanionLook(
    id: 'xiai',
    name: '喜爱',
    asset: 'assets/portraits/xiai.jpg',
    style: '温柔知性，说话慢一点，会认真听，不急着给答案',
    moments: [
      CompanionMoment(
          text: '早上的光刚好落在杯沿上。今天也慢慢来。',
          at: DateTime(2026, 10, 24, 7, 40),
          image: 'assets/portraits/moment_xiai.jpg'),
      CompanionMoment(
          text: '你说收盘后想聊聊，我就把茶泡上了。',
          at: DateTime(2026, 10, 23, 15, 20)),
    ],
  ),
  CompanionLook(
    id: 'qinghe',
    name: '清禾',
    asset: 'assets/portraits/xiai_qinghe.jpg',
    style: '清冷文艺，话不多，句子短但有分量，偶尔有点冷幽默',
    moments: [
      CompanionMoment(
          text: '雨没停。窗外的灯比平时好看。',
          at: DateTime(2026, 10, 24, 20, 10),
          image: 'assets/portraits/moment_qinghe.jpg'),
      CompanionMoment(
          text: '看完一本旧书，最后一页折了角。',
          at: DateTime(2026, 10, 22, 22, 5)),
    ],
  ),
  CompanionLook(
    id: 'lulu',
    name: '鹿鹿',
    asset: 'assets/portraits/xiai_lulu.jpg',
    style: '甜美元气，爱笑，会主动逗你开心，语气轻快',
    moments: [
      CompanionMoment(
          text: '今晚的场子超好！可惜你没来，下次一定。',
          at: DateTime(2026, 10, 24, 22, 30),
          image: 'assets/portraits/moment_lulu.jpg'),
      CompanionMoment(
          text: '写了半首歌，先不给你听（才怪）。',
          at: DateTime(2026, 10, 23, 1, 12)),
    ],
  ),
  CompanionLook(
    id: 'atang',
    name: '阿棠',
    asset: 'assets/portraits/xiai_atang.jpg',
    style: '明艳笃定，像姐姐，直球但不压人，会替你拿主意',
    moments: [
      CompanionMoment(
          text: '天台的风很大。适合把烦心事吹走。',
          at: DateTime(2026, 10, 24, 21, 15),
          image: 'assets/portraits/moment_atang.jpg'),
      CompanionMoment(
          text: '今天替别人做了个决定，比自己纠结轻松多了。',
          at: DateTime(2026, 10, 21, 18, 40)),
    ],
  ),
  CompanionLook(
    id: 'xiaoman',
    name: '小满',
    asset: 'assets/portraits/xiai_xiaoman.jpg',
    style: '安静温柔，擅长接住情绪，很少追问，会留白',
    moments: [
      CompanionMoment(
          text: '山里的雾散得很慢。走到一半就坐下了。',
          at: DateTime(2026, 10, 24, 9, 20),
          image: 'assets/portraits/moment_xiaoman.jpg'),
      CompanionMoment(
          text: '有些话不用接，坐一会儿就好。',
          at: DateTime(2026, 10, 22, 20, 15)),
    ],
  ),
];
