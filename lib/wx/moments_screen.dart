import 'package:flutter/material.dart';

import '../models/resident.dart';
import '../theme/app_theme.dart';
import '../widgets/wk_kit.dart';
import 'character_portrait.dart';
import 'character_screen.dart';
import 'plaza_tab.dart';

/// 朋友圈：广场上六位居民的近况。
///
/// 版式照微信（头像 + 名字 + 正文 + 图 + 时间 + 赞 / 评论），内容全部来自
/// AI 居民、每一条都带 AI 标；照片是插画式的色块（没有写真素材）。
/// 赞是本地状态（只存在这台手机上），评论直接进和 TA 的对话。
class MomentsScreen extends StatefulWidget {
  const MomentsScreen({super.key, this.now});

  /// 测试 / 金图里固定「几分钟前」的参照时间。
  final DateTime? now;

  @override
  State<MomentsScreen> createState() => _MomentsScreenState();
}

class _MomentsScreenState extends State<MomentsScreen> {
  final Set<String> _liked = {};

  @override
  Widget build(BuildContext context) {
    final posts = <_Post>[
      for (final r in kResidents)
        for (final m in r.moments) _Post(r, m),
    ]..sort((a, b) => b.moment.at.compareTo(a.moment.at));

    return WkPage(
      title: '朋友圈',
      child: ListView(
        padding: const EdgeInsets.only(bottom: AppSpace.xxl),
        children: [
          _cover(),
          for (final p in posts) _post(p),
          const Padding(
            padding: EdgeInsets.fromLTRB(
                AppSpace.lg, AppSpace.lg, AppSpace.lg, 0),
            child: WkNote(
              text: '这些动态都是 AI 居民写的，名字旁的 AI 标说明身份；'
                  '赞只存在你自己的手机上，评论会直接进和 TA 的对话。',
            ),
          ),
        ],
      ),
    );
  }

  Widget _cover() {
    return Container(
      height: 168,
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A2118), Color(0xFF7A4A16), Color(0xFFC08A4A)],
        ),
      ),
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text('广场',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 13,
                letterSpacing: 2,
                fontFamilyFallback: AppType.sansFallback,
              )),
          const SizedBox(height: AppSpace.xs),
          const Text('六位居民的近况',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                height: 1.3,
                fontWeight: FontWeight.w600,
                fontFamilyFallback: AppType.sansFallback,
              )),
          const SizedBox(height: AppSpace.xs),
          Text('都在夜里更新 · 都是 AI',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 12,
                fontFamilyFallback: AppType.sansFallback,
              )),
        ],
      ),
    );
  }

  Widget _post(_Post p) {
    final r = p.resident;
    final key = '${r.id}:${p.moment.at.millisecondsSinceEpoch}';
    final liked = _liked.contains(key);
    final likeCount = p.moment.likes + (liked ? 1 : 0);
    return Container(
      color: AppColors.bgSurface,
      padding: const EdgeInsets.fromLTRB(
          AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.sm),
      margin: const EdgeInsets.only(bottom: 0.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => CharacterScreen(resident: r))),
            child: SizedBox(
              width: 42,
              height: 42,
              child: CharacterPortrait(resident: r),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(r.name,
                        style: AppType.body.copyWith(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    const WkTag('AI'),
                    const Spacer(),
                    Text(formatMomentTime(p.moment.at, now: widget.now),
                        style: AppType.micro
                            .copyWith(color: AppColors.textTertiary)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(p.moment.text,
                    style: AppType.read.copyWith(fontSize: 15, height: 1.55)),
                if (p.moment.hasPhoto) ...[
                  const SizedBox(height: AppSpace.sm),
                  MomentPhoto(moment: p.moment, color: r.colorA),
                ],
                const SizedBox(height: AppSpace.sm),
                Row(
                  children: [
                    _action(
                      icon: liked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      label: '$likeCount',
                      active: liked,
                      onTap: () => setState(() {
                        if (liked) {
                          _liked.remove(key);
                        } else {
                          _liked.add(key);
                        }
                      }),
                    ),
                    const SizedBox(width: AppSpace.md),
                    _action(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: '评论',
                      onTap: () => openResidentChat(context, r),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _action({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: active ? AppColors.amber : AppColors.textTertiary),
            const SizedBox(width: 4),
            Text(label,
                style: AppType.micro.copyWith(
                  color: active ? AppColors.amber : AppColors.textTertiary,
                )),
          ],
        ),
      ),
    );
  }
}

class _Post {
  const _Post(this.resident, this.moment);
  final Resident resident;
  final Moment moment;
}
