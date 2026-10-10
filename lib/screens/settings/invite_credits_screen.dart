import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/falsification_service.dart' show asApiException;
import '../../services/invite_service.dart';
import '../../state/billing_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';

/// 邀请好友：我的邀请码 + 分享 + 填码兑换。双方各得喜点。
///
/// 原来挂在鹦鹉螺下（奖励螺壳）；鹦鹉螺隐藏后入口移到「我的」，奖励改为喜点。
class InviteCreditsScreen extends StatefulWidget {
  const InviteCreditsScreen({super.key, InviteService? service})
      : _service = service;

  final InviteService? _service;

  @override
  State<InviteCreditsScreen> createState() => _InviteCreditsScreenState();
}

class _InviteCreditsScreenState extends State<InviteCreditsScreen> {
  late final InviteService _svc = widget._service ?? InviteService();
  final _codeController = TextEditingController();

  CreditInviteInfo? _info;
  String? _error;
  bool _redeeming = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final info = await _svc.info();
      if (!mounted) return;
      setState(() {
        _info = info;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = asApiException(e)?.message ?? '$e');
    }
  }

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('邀请码已复制')));
  }

  Future<void> _share(CreditInviteInfo info) async {
    await Share.share(
      '我在用「喜爱」—— 一个敢说「不行」的 AI 投研助理，每条策略都附证伪档案。\n'
      '注册后填我的邀请码 ${info.code}，你我各得 ${info.rewardEach} 喜点。\n'
      'App Store 搜索「喜爱」即可下载。',
    );
  }

  Future<void> _redeem() async {
    final code = _codeController.text.trim();
    if (code.isEmpty || _redeeming) return;
    setState(() => _redeeming = true);
    final messenger = ScaffoldMessenger.of(context);
    final billing = context.read<BillingState>();
    try {
      final r = await _svc.redeem(code);
      if (!mounted) return;
      setState(() => _info = r.info);
      // ignore: unawaited_futures
      billing.refreshBalance();
      messenger.showSnackBar(SnackBar(
          content: Text('兑换成功，${r.info.rewardEach} 喜点已到账')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(asApiException(e)?.message ?? '兑换失败，请稍后再试')));
    } finally {
      if (mounted) setState(() => _redeeming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return WkPage(
      title: '邀请好友',
      child: info == null
          ? (_error == null
              ? const Center(
                  child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2)))
              : WkEmpty(
                  icon: Icons.card_giftcard_rounded,
                  title: '邀请信息读取失败',
                  hint: _error,
                  action: OutlinedButton(
                      onPressed: _load, child: const Text('重试')),
                ))
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.gutter, AppSpace.lg, AppSpace.gutter, AppSpace.xxl),
              children: [
                WkGroup(
                  header: '我的邀请码',
                  footer: '好友注册后 72 小时内填写你的邀请码，'
                      '你们各得 ${info.rewardEach} 喜点，实时到账。',
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSpace.lg),
                      child: Column(
                        children: [
                          GestureDetector(
                            onLongPress: () => _copy(info.code),
                            child: Text(
                              info.code,
                              style: AppType.display.copyWith(
                                fontSize: 30,
                                letterSpacing: 4,
                                color: AppColors.textPrimary,
                                fontFamilyFallback: AppType.numericFallback,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpace.lg),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _copy(info.code),
                                  icon: const Icon(Icons.copy_rounded,
                                      size: 16),
                                  label: const Text('复制'),
                                ),
                              ),
                              const SizedBox(width: AppSpace.md),
                              Expanded(
                                child: WkPrimaryButton(
                                  label: '分享给好友',
                                  icon: Icons.ios_share_rounded,
                                  onPressed: () => _share(info),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                WkGroup(
                  header: '邀请成绩',
                  children: [
                    WkRow(title: '成功邀请', value: '${info.invitedCount} 人'),
                    WkRow(title: '累计获得', value: '${info.totalReward} 喜点'),
                    WkRow(title: '每邀 1 人', value: '双方各 ${info.rewardEach} 喜点'),
                  ],
                ),
                if (!info.redeemed)
                  WkGroup(
                    header: '填写好友的邀请码',
                    footer: '仅限注册 72 小时内的新用户，每人只能填一次。',
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(AppSpace.lg),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _codeController,
                                textCapitalization:
                                    TextCapitalization.characters,
                                decoration: const InputDecoration(
                                    hintText: '输入邀请码'),
                              ),
                            ),
                            const SizedBox(width: AppSpace.md),
                            FilledButton(
                              onPressed: _redeeming ? null : _redeem,
                              child: Text(_redeeming ? '兑换中…' : '兑换'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  const WkGroup(children: [
                    WkRow(
                      icon: Icons.check_circle_outline_rounded,
                      title: '你已填写过好友的邀请码',
                    ),
                  ]),
                const WkNote(
                  text: '喜点用于对话、解锁证伪档案详情和跑一次证伪。'
                      '恶意刷邀请的账号将被回收奖励。',
                ),
              ],
            ),
    );
  }
}
