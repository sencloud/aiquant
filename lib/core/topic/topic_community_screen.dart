import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';

/// 圈内「动态圈」：同好晒记录、经验问答。
///
/// 第一版**不做假内容**：没有话题就没有帖子，这里是空状态 + 冷启动的实话。
/// 真做起来的产品形态是「登记处 + 问答」——发帖是登记事实，AI 先答、达人实名
/// 补充，按时间倒序不做算法排序（与小红书式内容流是两条路）。
class TopicCommunityScreen extends StatelessWidget {
  const TopicCommunityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return WkPage(
      title: '动态圈',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter, AppSpace.lg, AppSpace.gutter, AppSpace.xxl),
        children: const [
          WkEmpty(
            icon: Icons.forum_outlined,
            title: '这个圈还没有内容',
            hint: '冷启动不造假帖子：先是官方档案（可核对的公开数据），再是达人的实名回答，'
                '最后由同好把自己的记录发上来。',
          ),
          SizedBox(height: AppSpace.md),
          WkNote(
            title: '为什么先空着',
            text: '没有帖子就写没有帖子 —— 一个圈子被信任的原因是它不说假话。'
                '等这个圈的人与记录攒起来，这里按时间倒序显示，不做算法排序。',
          ),
        ],
      ),
    );
  }
}
