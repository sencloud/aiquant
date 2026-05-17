import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/auth_state.dart';
import '../../theme/app_theme.dart';

/// "我的"页面 — 包含喜点余额展示 + 充值套餐列表 + 账号管理。
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const List<_TopupPackage> _packages = [
    _TopupPackage(points: 100, priceYuan: 6, bonus: 0),
    _TopupPackage(points: 500, priceYuan: 28, bonus: 50),
    _TopupPackage(points: 1000, priceYuan: 58, bonus: 200),
    _TopupPackage(points: 5000, priceYuan: 288, bonus: 1500),
  ];

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final user = auth.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (user != null) _AccountTile(nickname: user.nickname, uuid: user.uuid),
          if (user != null) const SizedBox(height: 16),
          _BalanceCard(balance: user?.creditBalance ?? 0),
          const SizedBox(height: 24),
          _section('充值喜点'),
          const SizedBox(height: 8),
          for (final p in _packages) ...[
            _PackageTile(
              pkg: p,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('支付通道接入中，敬请期待'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 12),
          _section('喜点说明'),
          const SizedBox(height: 6),
          _bulletText('• 喜点是 App 内的虚拟资产，用于解锁高级 AI 助理与深度行情分析。'),
          _bulletText('• 每次深度模式（含推理过程）的 AI 回答消耗 5 喜点。'),
          _bulletText('• 每次工具调用（拉取行情/对比/筛选）消耗 1 喜点。'),
          _bulletText('• 喜点为虚拟商品，购买后不可退换、不可转让。'),
          if (user != null) ...[
            const SizedBox(height: 24),
            _section('账号管理'),
            const SizedBox(height: 6),
            _LogoutTile(),
          ],
          const SizedBox(height: 24),
          _section('关于'),
          ListTile(
            dense: true,
            leading: const Icon(Icons.info_outline, color: AppColors.amber),
            title: Text('喜宽 AIQuant',
                style: TextStyle(color: AppColors.textPrimary)),
            subtitle: Text('AI 量化助手',
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  static Widget _section(String t) => Text(
        t,
        style: const TextStyle(
          color: AppColors.amber,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.0,
        ),
      );

  static Widget _bulletText(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          t,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            height: 1.6,
          ),
        ),
      );
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance});
  final int balance;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.amber, AppColors.amberDim],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.stars_rounded, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text(
                '我的喜点',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$balance',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '喜点',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopupPackage {
  const _TopupPackage({
    required this.points,
    required this.priceYuan,
    required this.bonus,
  });
  final int points;
  final int priceYuan;
  final int bonus;

  int get totalPoints => points + bonus;

  /// 等效单价（每喜点折合多少元，用 0.001 精度）
  double get unitPriceYuan => priceYuan / totalPoints;
}

class _PackageTile extends StatelessWidget {
  const _PackageTile({required this.pkg, required this.onTap});
  final _TopupPackage pkg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasBonus = pkg.bonus > 0;
    return Material(
      color: AppColors.bgRaised,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppColors.borderDim),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.amber),
                ),
                child: const Icon(Icons.stars_rounded,
                    color: AppColors.amber, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${pkg.points} 喜点',
                          style: const TextStyle(
                            color: AppColors.amber,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (hasBonus) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.positive.withValues(alpha: 0.18),
                              border: Border.all(color: AppColors.positive),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              '送 ${pkg.bonus}',
                              style: const TextStyle(
                                color: AppColors.positive,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasBonus
                          ? '到账 ${pkg.totalPoints} 喜点 · 折合 ¥${pkg.unitPriceYuan.toStringAsFixed(3)}/喜点'
                          : '折合 ¥${pkg.unitPriceYuan.toStringAsFixed(3)}/喜点',
                      style: TextStyle(
                          color: AppColors.textTertiary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.amber,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '¥${pkg.priceYuan}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.nickname, required this.uuid});
  final String nickname;
  final String uuid;

  @override
  Widget build(BuildContext context) {
    final shortId = uuid.length > 8 ? uuid.substring(0, 8) : uuid;
    final display = nickname.isEmpty ? 'Apple 账号用户' : nickname;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.bgRaised,
        border: Border.all(color: AppColors.borderDim),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.amber.withValues(alpha: 0.18),
            child: const Icon(Icons.apple, color: AppColors.amber, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(display,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('UID · $shortId',
                    style: TextStyle(
                        color: AppColors.textTertiary, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LogoutTile extends StatelessWidget {
  Future<void> _confirmAndLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录？'),
        content: const Text('退出后本机的会话将清除，下次启动需要重新通过 Apple 登录。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await context.read<AuthState>().logout();
    if (context.mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgRaised,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppColors.borderDim),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: () => _confirmAndLogout(context),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.logout, color: AppColors.danger, size: 18),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('退出登录',
                    style: TextStyle(
                        color: AppColors.danger,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ),
              Icon(Icons.chevron_right,
                  color: AppColors.textTertiary, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
