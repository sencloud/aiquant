import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/companion_look.dart';
import '../../state/companion_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import 'companion_avatar.dart';

/// 「看她」：她的朋友圈。
///
/// 版式照微信：封面 + 头像、作者行、正文、图、时间、赞/评论。
/// 发帖的人是她自己（当前选中的形象）；每一条都带 AI 标。
class CompanionMomentsScreen extends StatefulWidget {
  const CompanionMomentsScreen({super.key});

  @override
  State<CompanionMomentsScreen> createState() => _CompanionMomentsScreenState();
}

class _CompanionMomentsScreenState extends State<CompanionMomentsScreen> {
  final Set<int> _liked = {};

  @override
  Widget build(BuildContext context) {
    final look = context.watch<CompanionState>().look;
    final posts = look.moments;
    return WkPage(
      title: '朋友圈',
      child: ListView(
        padding: const EdgeInsets.only(bottom: AppSpace.xxl),
        children: [
          _cover(look),
          for (var i = 0; i < posts.length; i++) _post(look, posts[i], i),
          const Padding(
            padding: EdgeInsets.fromLTRB(AppSpace.lg, AppSpace.lg, AppSpace.lg, 0),
            child: WkNote(
              text: '这些动态是她写的；她是 AI 伴侣，不是真人。',
            ),
          ),
        ],
      ),
    );
  }

  Widget _cover(CompanionLook look) {
    return SizedBox(
      height: 220,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Image.asset(
              look.asset,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.35),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: AppSpace.lg,
            bottom: -22,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.bgSurface, width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: CompanionAvatar(
                  size: 64, radius: 9, asset: look.asset),
            ),
          ),
          Positioned(
            left: 96,
            bottom: AppSpace.sm,
            child: Text(
              look.name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
                fontFamilyFallback: AppType.sansFallback,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _post(CompanionLook look, CompanionMoment m, int i) {
    final liked = _liked.contains(i);
    return Container(
      color: AppColors.bgSurface,
      margin: EdgeInsets.only(top: i == 0 ? 34 : 6),
      padding: const EdgeInsets.fromLTRB(
          AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CompanionAvatar(size: 42, radius: 6, asset: look.asset),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(look.name,
                        style: AppType.body.copyWith(
                            fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    const WkTag('AI'),
                    const Spacer(),
                    Text(_time(m.at),
                        style: AppType.micro
                            .copyWith(color: AppColors.textTertiary)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(m.text,
                    style: AppType.read.copyWith(fontSize: 15, height: 1.6)),
                if (m.image != null) ...[
                  const SizedBox(height: AppSpace.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: Image.asset(
                      m.image!,
                      height: 220,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        height: 160,
                        color: AppColors.bgRaised,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpace.sm),
                Row(
                  children: [
                    InkWell(
                      onTap: () => setState(() {
                        if (liked) {
                          _liked.remove(i);
                        } else {
                          _liked.add(i);
                        }
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Icon(
                                liked
                                    ? Icons.favorite_rounded
                                    : Icons.favorite_border_rounded,
                                size: 15,
                                color: liked
                                    ? AppColors.amber
                                    : AppColors.textTertiary),
                            const SizedBox(width: 4),
                            Text('赞',
                                style: AppType.micro.copyWith(
                                    color: liked
                                        ? AppColors.amber
                                        : AppColors.textTertiary)),
                          ],
                        ),
                      ),
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

  String _time(DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inHours < 24) return '${diff.inHours.clamp(1, 23)} 小时前';
    return '${t.month}月${t.day}日';
  }
}
