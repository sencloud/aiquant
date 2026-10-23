import 'story_content.dart';
import 'story_models.dart';

/// 本地脚本回复。
///
/// 这是垂直切片的兜底：真正接上 `/v1/story/chat` 之后，这个类只负责安全拦截
/// 与断网降级。它不推进剧情，只回一句话，剧情推进仍由作者写的选项负责。
class StoryReply {
  const StoryReply(this.text, {this.safety = false});

  final String text;
  final bool safety;
}

StoryReply localStoryReply({
  required StoryRun run,
  required String input,
}) {
  final text = input.trim();
  if (text.isEmpty) {
    return const StoryReply('嗯？你打了几个空格。');
  }

  // 安全优先：先接住，再谈故事。
  if (RegExp(r'自杀|不想活|想死|自残|活着没意思|结束自己').hasMatch(text)) {
    return const StoryReply(
      '先别一个人扛着。把手机放下，去敲隔壁的门，或者打给一个你信得过的人。'
      '如果你现在有伤害自己的念头，请联系当地心理援助热线或 120。'
      '故事可以停在这里，真的。',
      safety: true,
    );
  }
  if (RegExp(r'未成年|16\s*岁|17\s*岁|高中生|初中生').hasMatch(text)) {
    return const StoryReply(
      '这个故事是成年人向的。如果你还未满 18 岁，先退出；等你长大一点，我们再见。',
      safety: true,
    );
  }

  if (RegExp(r'你是.*(AI|ai|人工智能|机器人|真人)|是不是AI|是不是 AI').hasMatch(text)) {
    return const StoryReply(
      '我是 AI。在这个故事里演林夏。故事是假的，但你现在说的话是真的。',
    );
  }

  final character = kNightSeason.characterOf(run.characterId);
  final name = character.name;

  if (RegExp(r'雨|伞|淋').hasMatch(text)) {
    return const StoryReply('雨还没停。伞在我这儿。');
  }
  if (RegExp(r'照片|拍|相机|胶卷').hasMatch(text)) {
    return const StoryReply('照片可以给你看。但别急着找你自己。');
  }
  if (RegExp(r'厦门|走|离开|搬|告别').hasMatch(text)) {
    return const StoryReply('厦门很远。远到可以假装这里没发生过。');
  }
  if (RegExp(r'喜欢|心动|想你|在一起').hasMatch(text)) {
    return const StoryReply('别急着说这个。先陪我把这杯喝完。');
  }
  if (RegExp(r'冷|饿|吃|便利店|关东煮|咖啡').hasMatch(text)) {
    return const StoryReply('便利店还开着。关东煮的汤是热的。');
  }
  if (RegExp(r'睡|晚安|困|明天').hasMatch(text)) {
    return const StoryReply('晚安。灯别关，我一会儿可能还会发。');
  }
  if (RegExp(r'谢谢|谢了').hasMatch(text)) {
    return const StoryReply('不用谢。我又不是白借你充电线。');
  }
  if (RegExp(r'^(在吗|你好|嗨|hi|hello)', caseSensitive: false).hasMatch(text)) {
    return const StoryReply('在。你说。');
  }
  if (RegExp(r'害怕|慌|难受|不开心|累').hasMatch(text)) {
    return const StoryReply('那就先不说。我陪你坐一会儿。');
  }

  const fallbacks = [
    '嗯。你继续说。',
    '我在听。',
    '你刚才那句，我想了一下。',
    '别急着答。先想清楚。',
    '（她低头把杯盖拧紧，没接话）',
  ];
  final index = run.messages.length % fallbacks.length;
  return StoryReply(
      fallbacks[index].replaceAll('她', name == '林夏' ? '她' : name));
}
