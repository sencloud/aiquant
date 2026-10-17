import 'package:flutter/material.dart';

import '../models/resident.dart';
import '../theme/app_theme.dart';
import '../widgets/wk_kit.dart';
import 'character_portrait.dart';
import 'plaza_tab.dart';

/// 一位居民的资料页：头像、身世、性格、两句「最近」，以及打招呼。
class CharacterScreen extends StatelessWidget {
  const CharacterScreen({super.key, required this.resident, this.now});

  final Resident resident;

  /// 测试 / 金图里固定「几小时前」的参照时间。
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    return WkPage(
      title: resident.name,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xxl),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: SizedBox(
              height: 340,
              width: double.infinity,
              child: CharacterPortrait(resident: resident),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              Flexible(
                child: Text(resident.nameWithAge,
                    style: AppType.title.copyWith(fontSize: 22)),
              ),
              const SizedBox(width: AppSpace.sm),
              const WkTag('AI'),
              const Spacer(),
              Text(resident.emoji, style: const TextStyle(fontSize: 18)),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Text('${resident.city} · ${resident.job}',
              style: AppType.caption.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: AppSpace.md),
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: [
              for (final t in resident.tags)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: resident.colorA.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(t,
                      style: AppType.micro.copyWith(
                          color: resident.colorB,
                          fontWeight: FontWeight.w500)),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Container(
            padding: const EdgeInsets.all(AppSpace.md),
            decoration: BoxDecoration(
              color: AppColors.bgRaised,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Text('「${resident.line}」',
                style: AppType.read.copyWith(fontSize: 15, height: 1.7)),
          ),
          const SizedBox(height: AppSpace.lg),
          const Text('TA 最近', style: AppType.section),
          const SizedBox(height: AppSpace.sm),
          for (final m in resident.moments) ...[
            _MomentCard(moment: m, color: resident.colorA, now: now),
            const SizedBox(height: AppSpace.sm),
          ],
          const SizedBox(height: AppSpace.md),
          WkPrimaryButton(
            key: const ValueKey('character-greet'),
            label: '打个招呼',
            icon: Icons.waving_hand_rounded,
            onPressed: () => openResidentChat(context, resident),
          ),
          const SizedBox(height: AppSpace.sm),
          Center(
            child: TextButton(
              onPressed: () => showShakeSheet(context),
              child: const Text('摇下一位'),
            ),
          ),
          const SizedBox(height: AppSpace.md),
          const WkNote(
            text: 'TA 是 AI 居民：性格与说话方式由「喜爱」这边维护，不是真人。'
                '聊得来就多聊两句，不用有压力 —— 这里没有已读，也没有在线状态。',
          ),
        ],
      ),
    );
  }
}

/// 一条「最近」：一句话，有图就再画一张色块「照片」。
class _MomentCard extends StatelessWidget {
  const _MomentCard({
    required this.moment,
    required this.color,
    this.now,
  });

  final Moment moment;
  final Color color;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(moment.text, style: AppType.read.copyWith(fontSize: 15)),
          if (moment.hasPhoto) ...[
            const SizedBox(height: AppSpace.sm),
            MomentPhoto(moment: moment, color: color),
          ],
          const SizedBox(height: AppSpace.sm),
          Text(formatMomentTime(moment.at, now: now),
              style: AppType.micro.copyWith(color: AppColors.textTertiary)),
        ],
      ),
    );
  }
}

/// 朋友圈 / 资料页共用的「照片」：渐变底 + 一个 emoji + 图说。
class MomentPhoto extends StatelessWidget {
  const MomentPhoto({super.key, required this.moment, required this.color});

  final Moment moment;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: AspectRatio(
        aspectRatio: 16 / 10,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (moment.photoAsset != null)
              Image.asset(
                moment.photoAsset!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _fallback(),
              )
            else
              _fallback(),
            if (moment.photoAsset == null)
              Center(
                child: Text(moment.photoEmoji ?? '',
                    style: const TextStyle(fontSize: 46)),
              ),
            if (moment.photoCaption != null)
              Positioned(
                left: AppSpace.sm,
                bottom: AppSpace.sm,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(moment.photoCaption!,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 11,
                        fontFamilyFallback: AppType.sansFallback,
                      )),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _fallback() => DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              color.withValues(alpha: 0.85),
              color.withValues(alpha: 0.45),
            ],
          ),
        ),
      );
}

/// 「3 小时前 / 昨天 21:12 / 10月14日」。
String formatMomentTime(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final diff = n.difference(t);
  if (diff.inMinutes < 60) return '${diff.inMinutes.clamp(1, 59)} 分钟前';
  if (diff.inHours < 24) return '${diff.inHours} 小时前';
  final yesterday = DateTime(n.year, n.month, n.day)
      .subtract(const Duration(days: 1));
  final that = DateTime(t.year, t.month, t.day);
  final hm = '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
  if (that == yesterday) return '昨天 $hm';
  if (t.year == n.year) return '${t.month}月${t.day}日 $hm';
  return '${t.year}年${t.month}月${t.day}日';
}
