import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/billing_models.dart';
import '../../state/auth_state.dart';
import '../../state/billing_state.dart';
import '../../theme/app_theme.dart';

/// "我的"页面 — 喜点余额、充值套餐、流水、账号管理。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _bootstrapped = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_bootstrapped) {
      _bootstrapped = true;
      final billing = context.read<BillingState>();
      // 进页面拉一次：余额 + SKU
      Future.microtask(() => billing.refreshAll());
    }
  }

  Future<void> _onPackageTap(BillingState b, CreditSku sku) async {
    final ok = await b.purchase(sku);
    if (!mounted) return;
    final msg = ok
        ? '充值成功 +${sku.totalCredits} 喜点'
        : (b.lastError ?? '');
    if (msg.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final user = auth.currentUser;
    final billing = context.watch<BillingState>();
    final balance = billing.balance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        actions: [
          IconButton(
            tooltip: '流水',
            icon: const Icon(Icons.receipt_long, size: 20),
            onPressed: () => _showLedger(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => billing.refreshAll(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (user != null)
              _AccountTile(nickname: user.nickname, uuid: user.uuid),
            if (user != null) const SizedBox(height: 16),
            _BalanceCard(balance: balance, loading: billing.loadingBalance),
            const SizedBox(height: 24),
            _section('充值喜点'),
            const SizedBox(height: 8),
            if (billing.loadingSkus && billing.skus.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else if (billing.skus.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    billing.lastError ?? '暂无可用套餐',
                    style: TextStyle(
                        color: AppColors.textTertiary, fontSize: 12),
                  ),
                ),
              )
            else
              for (final sku in billing.skus) ...[
                _PackageTile(
                  sku: sku,
                  loading: billing.isPurchasingSku(sku.code),
                  // 当前正在买另一档 → 本档不可点，但不显示 loading
                  disabled: billing.purchasing &&
                      !billing.isPurchasingSku(sku.code),
                  onTap: () => _onPackageTap(billing, sku),
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
              title: Text('喜宽',
                  style: TextStyle(color: AppColors.textPrimary)),
              subtitle: Text('AI 量化助手',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }

  void _showLedger(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: AppColors.bgRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (_) => const _LedgerSheet(),
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
  const _BalanceCard({required this.balance, required this.loading});
  final int balance;
  final bool loading;

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
              const Spacer(),
              if (loading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
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

class _PackageTile extends StatelessWidget {
  const _PackageTile({
    required this.sku,
    required this.loading,
    required this.disabled,
    required this.onTap,
  });
  final CreditSku sku;
  final bool loading;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasBonus = sku.bonusCredits > 0;
    final unitPrice = sku.priceYuan / sku.totalCredits;
    final tappable = !loading && !disabled;
    return Material(
      color: AppColors.bgRaised,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppColors.borderDim),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: tappable ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
                          '${sku.baseCredits} 喜点',
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
                              color: AppColors.positive
                                  .withValues(alpha: 0.18),
                              border: Border.all(color: AppColors.positive),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              '送 ${sku.bonusCredits}',
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
                          ? '到账 ${sku.totalCredits} 喜点 · 折合 ¥${unitPrice.toStringAsFixed(3)}/喜点'
                          : '折合 ¥${unitPrice.toStringAsFixed(3)}/喜点',
                      style: TextStyle(
                          color: AppColors.textTertiary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.amber,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        sku.priceLabel,
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
        content:
            const Text('退出后本机的会话将清除，下次启动需要重新通过 Apple 登录。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await context.read<AuthState>().logout();
    if (context.mounted) {
      context.read<BillingState>().reset();
      Navigator.of(context).maybePop();
    }
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

class _LedgerSheet extends StatefulWidget {
  const _LedgerSheet();
  @override
  State<_LedgerSheet> createState() => _LedgerSheetState();
}

class _LedgerSheetState extends State<_LedgerSheet> {
  @override
  void initState() {
    super.initState();
    final billing = context.read<BillingState>();
    Future.microtask(() => billing.refreshLedger(reset: true));
  }

  @override
  Widget build(BuildContext context) {
    final billing = context.watch<BillingState>();
    final items = billing.ledger;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (ctx, controller) {
        return Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderDim,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('喜点流水',
                    style: TextStyle(
                        color: AppColors.amber,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0)),
              ),
            ),
            Expanded(
              child: items.isEmpty && billing.loadingLedger
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : items.isEmpty
                      ? Center(
                          child: Text('暂无流水',
                              style: TextStyle(
                                  color: AppColors.textTertiary, fontSize: 12)))
                      : NotificationListener<ScrollNotification>(
                          onNotification: (n) {
                            if (n.metrics.pixels >=
                                    n.metrics.maxScrollExtent - 100 &&
                                billing.ledgerHasMore &&
                                !billing.loadingLedger) {
                              billing.refreshLedger();
                            }
                            return false;
                          },
                          child: ListView.separated(
                            controller: controller,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount:
                                items.length + (billing.ledgerHasMore ? 1 : 0),
                            separatorBuilder: (_, __) => Divider(
                              color: AppColors.borderDim,
                              height: 1,
                            ),
                            itemBuilder: (_, i) {
                              if (i >= items.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Center(
                                      child: SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))),
                                );
                              }
                              return _LedgerRow(item: items[i]);
                            },
                          ),
                        ),
            ),
          ],
        );
      },
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.item});
  final CreditLedgerItem item;

  @override
  Widget build(BuildContext context) {
    final positive = item.delta >= 0;
    final dt = DateTime.fromMillisecondsSinceEpoch(item.createdAt);
    final ts =
        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.reasonLabel,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(ts,
                    style: TextStyle(
                        color: AppColors.textTertiary, fontSize: 11)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                item.deltaLabel,
                style: TextStyle(
                  color: positive ? AppColors.positive : AppColors.danger,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text('余 ${item.balanceAfter}',
                  style: TextStyle(
                      color: AppColors.textTertiary, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}
