import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../state/nautilus_state.dart';
import '../../theme/app_theme.dart';

/// 邀请好友赚螺壳：我的邀请码 + 分享 + 填码兑换。
class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  final _codeController = TextEditingController();
  bool _redeeming = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) context.read<NautilusState>().refreshInvite();
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('邀请码已复制'),
      duration: Duration(seconds: 2),
    ));
  }

  Future<void> _share(String code, int rewardEach) async {
    await Share.share(
      '我在「喜宽」的鹦鹉螺玩预测市场，用螺壳押全球天气和金融行情。\n'
      '注册后填我的邀请码 $code，你我各得 $rewardEach 螺壳！\n'
      'App Store 搜索「喜宽」即可下载。',
    );
  }

  Future<void> _redeem() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;
    setState(() => _redeeming = true);
    final err = await context.read<NautilusState>().redeemInvite(code);
    if (!mounted) return;
    setState(() => _redeeming = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(err ?? '兑换成功，螺壳已到账！'),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final n = context.watch<NautilusState>();
    final info = n.inviteInfo;

    return Scaffold(
      appBar: AppBar(title: const Text('邀请好友')),
      body: info == null
          ? const Center(
              child: CircularProgressIndicator(
                  color: AppColors.amber, strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                // 邀请码大卡
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.amber, AppColors.amberDim],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      Image.asset('assets/branding/nautilus.png',
                          width: 36, height: 36, color: Colors.black),
                      const SizedBox(height: 10),
                      const Text('我的邀请码',
                          style: TextStyle(
                              color: Colors.black87,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onLongPress: () => _copyCode(info.code),
                        child: Text(
                          info.code,
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _copyCode(info.code),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.black,
                                side: const BorderSide(color: Colors.black54),
                              ),
                              icon: const Icon(Icons.copy, size: 14),
                              label: const Text('复制'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () =>
                                  _share(info.code, info.rewardEach),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black,
                                foregroundColor: AppColors.amber,
                              ),
                              icon: const Icon(Icons.ios_share, size: 14),
                              label: const Text('分享'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                // 统计
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.borderDim),
                  ),
                  child: Row(
                    children: [
                      _stat('成功邀请', '${info.invitedCount} 人'),
                      _stat('累计奖励', '${info.totalReward} 螺壳'),
                      _stat('每邀 1 人', '+${info.rewardEach} 螺壳'),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // 填码兑换
                if (!info.redeemed) ...[
                  const Text('填写好友的邀请码',
                      style: TextStyle(
                          color: AppColors.amber,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0)),
                  const SizedBox(height: 4),
                  Text('新用户注册 72 小时内可填，你和好友各得 ${info.rewardEach} 螺壳',
                      style: TextStyle(
                          color: AppColors.textTertiary, fontSize: 11)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _codeController,
                          textCapitalization: TextCapitalization.characters,
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2),
                          decoration:
                              const InputDecoration(hintText: '输入邀请码'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: _redeeming ? null : _redeem,
                        child: _redeeming
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.black))
                            : const Text('兑换'),
                      ),
                    ],
                  ),
                ] else
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.bgRaised,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.borderDim),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle,
                            size: 16, color: AppColors.positive),
                        const SizedBox(width: 8),
                        Text('你已兑换过好友的邀请码',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12)),
                      ],
                    ),
                  ),
                const SizedBox(height: 20),
                Text(
                  '· 螺壳是鹦鹉螺预测市场的下注道具，不可购买、不可兑换现金\n'
                  '· 邀请奖励实时到账，可在「螺壳钱包」查看流水\n'
                  '· 恶意刷邀请的账号将被回收奖励',
                  style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                      height: 1.8),
                ),
              ],
            ),
    );
  }

  Widget _stat(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(color: AppColors.textTertiary, fontSize: 10)),
        ],
      ),
    );
  }
}
