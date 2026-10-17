import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/auth/require_login.dart';
import '../models/resident.dart';
import '../screens/assistant/assistant_screen.dart' show AssistantLaunch;
import '../screens/settings/invite_credits_screen.dart';
import '../state/chat_state.dart';
import '../theme/app_theme.dart';
import '../widgets/wk_kit.dart';
import 'character_portrait.dart';
import 'character_screen.dart';
import 'chat_list_tab.dart';
import 'wx_kit.dart';

/// 「广场」页签：今晚谁在这儿。
///
/// 这是交友那半边的门面：一排居民、各自的在线状态、一句「等你搭讪」的话。
/// 点一个人进资料页，或者摇一摇随机遇见一位。
///
/// **诚实线**：广场上现在全是标明的 AI 居民（每张卡、每个资料页都有 AI 标）。
/// 真人池还没接进来 —— 页面不摆假人，真人区照实写「内测中」。
class WxPlazaTab extends StatefulWidget {
  const WxPlazaTab({super.key, this.clockLabel});

  /// 测试 / 金图里固定顶部那行时间，避免金图随真实时间漂移。
  final String? clockLabel;

  @override
  State<WxPlazaTab> createState() => _WxPlazaTabState();
}

class _WxPlazaTabState extends State<WxPlazaTab> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        WxTopBar(
          title: '广场',
          actions: [
            IconButton(
              key: const ValueKey('plaza-shake-top'),
              tooltip: '摇一摇',
              icon: const Icon(Icons.auto_awesome_rounded, size: 24),
              color: AppColors.textPrimary,
              onPressed: () => showShakeSheet(context),
            ),
            const SizedBox(width: AppSpace.xs),
          ],
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.md, 0, AppSpace.md, AppSpace.xxl),
            children: [
              _hero(context),
              const SizedBox(height: AppSpace.lg),
              Row(
                children: [
                  const Text('在广场上', style: AppType.section),
                  const Spacer(),
                  Text('${kResidents.length} 位 · 都标了 AI',
                      style: AppType.micro
                          .copyWith(color: AppColors.textTertiary)),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              LayoutBuilder(builder: (context, box) {
                const gap = AppSpace.sm;
                final width = (box.maxWidth - gap) / 2;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final r in kResidents)
                      SizedBox(
                        width: width,
                        height: width * 1.34,
                        child: _ResidentCard(
                          resident: r,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) => CharacterScreen(resident: r)),
                          ),
                        ),
                      ),
                  ],
                );
              }),
              const SizedBox(height: AppSpace.lg),
              WkGroup(
                children: [
                  WkRow(
                    key: const ValueKey('plaza-real-people'),
                    leading: const WxIconTile(
                      icon: Icons.people_alt_rounded,
                      color: Color(0xFF576B95),
                    ),
                    title: '真人区 · 内测中',
                    subtitle: '真人还没进来。这里不摆假人；想第一批进来，先把朋友拉来。',
                    value: '0 人',
                    onTap: () async {
                      if (!await requireLogin(context)) return;
                      if (!context.mounted) return;
                      await Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => const InviteCreditsScreen()));
                    },
                  ),
                ],
              ),
              const WkNote(
                text: '广场上的居民都是 AI，名字旁带 AI 标；人设由「喜爱」这一侧维护。'
                    '认真聊天，不转账、不见面、不越界 —— 这是我们这里的规矩。',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _hero(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.lg, AppSpace.lg, AppSpace.lg, AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: AppColors.amber,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpace.xs),
              Text(widget.clockLabel ?? _nightLabel(),
                  style: AppType.micro.copyWith(color: AppColors.textSecondary)),
              const Spacer(),
              Text('${kResidents.length} 位在这儿',
                  style: AppType.micro.copyWith(color: AppColors.textTertiary)),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          const Text('先说话的人，不一定输。',
              style: TextStyle(
                fontSize: 22,
                height: 1.35,
                fontWeight: FontWeight.w600,
                fontFamilyFallback: AppType.sansFallback,
              )),
          const SizedBox(height: AppSpace.xs),
          Text('挑一个看着顺眼的，打个招呼。摇一摇也行 —— 今晚就六个人，没人会笑你。',
              style: AppType.caption
                  .copyWith(color: AppColors.textSecondary, height: 1.6)),
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              Expanded(
                child: WkPrimaryButton(
                  key: const ValueKey('plaza-shake'),
                  label: '摇一摇',
                  icon: Icons.auto_awesome_rounded,
                  onPressed: () => showShakeSheet(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _nightLabel() {
    final h = DateTime.now().hour;
    final phase = h >= 18 || h < 3
        ? '今晚'
        : (h < 11 ? '上午' : (h < 14 ? '中午' : '下午'));
    final now = DateTime.now();
    return '$phase ${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';
  }
}

/// 广场上的一张卡：插画半身像 + 名字 / 年龄 + 一句在线状态。
class _ResidentCard extends StatelessWidget {
  const _ResidentCard({required this.resident, required this.onTap});

  final Resident resident;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgSurface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('resident-${resident.id}'),
        onTap: onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CharacterPortrait(resident: resident, radius: 0),
            // 顶部两个角标：AI 标明身份，emoji 是这位此刻的情绪。
            Positioned(
              left: AppSpace.sm,
              top: AppSpace.sm,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.32),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Text('AI',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      fontFamilyFallback: AppType.sansFallback,
                    )),
              ),
            ),
            Positioned(
              right: AppSpace.sm,
              top: AppSpace.sm,
              child: Text(resident.emoji,
                  style: const TextStyle(fontSize: 16)),
            ),
            // 底部信息：名字 + 年龄 + 在线状态。
            Positioned(
              left: AppSpace.sm,
              right: AppSpace.sm,
              bottom: AppSpace.sm,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Color(0xFF3ED07A),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          resident.nameWithAge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            fontFamilyFallback: AppType.sansFallback,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    resident.status,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 11.5,
                      height: 1.35,
                      fontFamilyFallback: AppType.sansFallback,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 摇一摇：随机遇见一位居民。
Future<void> showShakeSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.bgSurface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (_) => const _ShakeSheet(),
  );
}

class _ShakeSheet extends StatefulWidget {
  const _ShakeSheet();

  @override
  State<_ShakeSheet> createState() => _ShakeSheetState();
}

class _ShakeSheetState extends State<_ShakeSheet> {
  late Resident _pick = _random();

  Resident _random() =>
      kResidents[math.Random(DateTime.now().microsecond).nextInt(kResidents.length)];

  @override
  Widget build(BuildContext context) {
    final r = _pick;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text('摇一摇', style: AppType.title),
                const Spacer(),
                Text('今晚遇见 · ${kResidents.length} 位分之一',
                    style:
                        AppType.micro.copyWith(color: AppColors.textTertiary)),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: SizedBox(
                height: 300,
                width: double.infinity,
                child: CharacterPortrait(resident: r),
              ),
            ),
            const SizedBox(height: AppSpace.md),
            Row(
              children: [
                Text(r.nameWithAge,
                    style: AppType.title.copyWith(fontSize: 20)),
                const SizedBox(width: AppSpace.sm),
                const WkTag('AI'),
                const Spacer(),
                Text(r.emoji, style: const TextStyle(fontSize: 18)),
              ],
            ),
            const SizedBox(height: AppSpace.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('${r.city} · ${r.job} · ${r.status}',
                  style: AppType.caption
                      .copyWith(color: AppColors.textSecondary)),
            ),
            const SizedBox(height: AppSpace.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(r.line,
                  style: AppType.read.copyWith(fontSize: 15, height: 1.6)),
            ),
            const SizedBox(height: AppSpace.lg),
            Row(
              children: [
                Expanded(
                  child: WkPrimaryButton(
                    label: '打个招呼',
                    icon: Icons.waving_hand_rounded,
                    onPressed: () {
                      Navigator.of(context).pop();
                      openResidentChat(context, r);
                    },
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                SizedBox(
                  width: 108,
                  child: OutlinedButton(
                    onPressed: () => setState(() => _pick = _random()),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 46),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppRadius.md)),
                    ),
                    child: const Text('再摇一次'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 和一位居民开一段新对话：topic=social，人设就是这位。
Future<void> openResidentChat(
  BuildContext context,
  Resident resident, {
  bool withOpener = true,
}) async {
  final chat = context.read<ChatState>();
  final session = await chat.newSession(
    topic: 'social',
    personaId: resident.id,
    title: resident.name,
  );
  if (!context.mounted) return;
  await openChatScreen(
    context,
    sessionId: session.id,
    launch: withOpener ? AssistantLaunch(initialMessage: resident.opener) : null,
  );
}
