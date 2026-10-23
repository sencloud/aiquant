import 'package:flutter/material.dart';

import '../night_kit.dart';
import '../night_theme.dart';
import '../pixel_portrait.dart';
import '../story_models.dart';
import '../story_state.dart';

class MomentsScreen extends StatelessWidget {
  const MomentsScreen({super.key, required this.state});

  final StoryState state;

  @override
  Widget build(BuildContext context) {
    final posts = state.unlockedPosts;
    return Column(
      children: [
        const NightBar(
          title: '动态',
          subtitle: '六个名字的深夜',
          actions: [PixelTag('AI · 虚构', color: NightColors.rain)],
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
            children: [
              Text('他们只在这个时间\n发东西。',
                  style:
                      NightType.display.copyWith(fontSize: 24, height: 1.35)),
              const SizedBox(height: 8),
              Text('走完一夜，才会多看到一条。没看到的，不编给你。',
                  style: NightType.read.copyWith(height: 1.7)),
              const SizedBox(height: 18),
              for (final p in posts) ...[
                _PostCard(post: p, state: state),
                const SizedBox(height: 10),
              ],
              const NightNote(
                '这些动态都是 AI 扮演的居民写的，每一条都带 AI 标；'
                '赞只存在这台手机上。',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post, required this.state});

  final StoryPost post;
  final StoryState state;

  @override
  Widget build(BuildContext context) {
    final c = state.season.characterOf(post.authorId);
    return Container(
      decoration: BoxDecoration(
        color: NightColors.surface,
        border: Border.all(color: NightColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Row(
              children: [
                PixelAvatar(character: c, size: 38),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(c.name,
                              style: NightType.title.copyWith(fontSize: 14)),
                          const SizedBox(width: 6),
                          const PixelTag('AI', color: NightColors.rain),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text('${post.timeLabel} · 临海', style: NightType.micro),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Text(post.text,
                style: NightType.body.copyWith(fontSize: 14, height: 1.7)),
          ),
          Container(
            height: 118,
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [c.bgA, c.bgB],
              ),
              border: Border.all(color: NightColors.border),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: NightSpark(size: 26, color: c.accent),
                ),
                Positioned(
                  left: 10,
                  bottom: 8,
                  child: Text('${c.name} · 临海 · 夜',
                      style: NightType.micro.copyWith(
                        color: Colors.white.withValues(alpha: 0.72),
                        letterSpacing: 1,
                      )),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                const Icon(Icons.favorite_border_rounded,
                    size: 14, color: NightColors.faint),
                const SizedBox(width: 4),
                Text('${post.hearts}', style: NightType.micro),
                const SizedBox(width: 18),
                const Icon(Icons.chat_bubble_outline_rounded,
                    size: 14, color: NightColors.faint),
                const SizedBox(width: 4),
                Text('评论在完整版里',
                    style: NightType.micro.copyWith(color: NightColors.faint)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
