import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/require_login.dart';
import '../../models/nautilus.dart';
import '../../state/auth_state.dart';
import '../../state/nautilus_state.dart';
import '../../theme/app_theme.dart';
import 'invite_screen.dart';
import 'market_detail_screen.dart';
import 'shell_wallet_screen.dart';

/// 鹦鹉螺 — 预测市场首页。
///
/// 顶部：螺壳余额(登录后) + 邀请入口；
/// 板块分段：全球天气 / 金融市场；
/// 列表：市场卡片(选项池占比 + 隐含赔率 + 截止时间)。
/// 浏览公开；下注等操作走 requireLogin。
class NautilusScreen extends StatefulWidget {
  const NautilusScreen({super.key});

  @override
  State<NautilusScreen> createState() => _NautilusScreenState();
}

class _NautilusScreenState extends State<NautilusScreen> {
  // 0 = 全球天气, 1 = 金融市场
  int _tab = 0;
  bool _bootstrapped = false;

  static const _categories = ['weather', 'finance'];
  static const _categoryLabels = ['全球天气', '金融市场'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bootstrapped) return;
    _bootstrapped = true;
    Future.microtask(() async {
      if (!mounted) return;
      final n = context.read<NautilusState>();
      await n.refreshMarkets();
      if (!mounted) return;
      if (context.read<AuthState>().isAuthenticated) {
        await n.refreshWallet();
      }
    });
  }

  Future<void> _openWallet() async {
    if (!await requireLogin(context)) return;
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ShellWalletScreen()),
    );
  }

  Future<void> _openInvite() async {
    if (!await requireLogin(context)) return;
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const InviteScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = context.watch<NautilusState>();
    final authed = context.watch<AuthState>().isAuthenticated;
    final markets = n.byCategory(_categories[_tab]);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/branding/nautilus.png',
                width: 18, height: 18, color: AppColors.amber),
            const SizedBox(width: 8),
            const Text('鹦鹉螺'),
          ],
        ),
        actions: [
          if (authed && n.walletLoaded)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: InkWell(
                onTap: _openWallet,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.bgRaised,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.borderDim),
                  ),
                  child: Row(
                    children: [
                      const _ShellIcon(size: 13),
                      const SizedBox(width: 5),
                      Text(
                        '${n.balance}',
                        style: const TextStyle(
                          color: AppColors.amber,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            IconButton(
              tooltip: '螺壳钱包',
              icon: const _ShellIcon(size: 18),
              onPressed: _openWallet,
            ),
          IconButton(
            tooltip: '邀请好友赚螺壳',
            icon: const Icon(Icons.card_giftcard, size: 18),
            color: AppColors.amber,
            onPressed: _openInvite,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              children: List.generate(_categories.length, (i) {
                final active = _tab == i;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(_categoryLabels[i]),
                    selected: active,
                    onSelected: (_) => setState(() => _tab = i),
                    labelStyle: TextStyle(
                      color: active ? Colors.black : AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    selectedColor: AppColors.amber,
                    backgroundColor: AppColors.bgRaised,
                    side: BorderSide(
                        color:
                            active ? AppColors.amber : AppColors.borderDim),
                    showCheckmark: false,
                  ),
                );
              }),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.amber,
              onRefresh: () async {
                final st = context.read<NautilusState>();
                await st.refreshMarkets();
                if (context.mounted &&
                    context.read<AuthState>().isAuthenticated) {
                  await st.refreshWallet();
                }
              },
              child: n.loadingMarkets && markets.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.amber, strokeWidth: 2))
                  : markets.isEmpty
                      ? _emptyView()
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                          itemCount: markets.length,
                          itemBuilder: (_, i) =>
                              _MarketCard(market: markets[i]),
                        ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyView() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(Icons.waves, size: 40, color: AppColors.textTertiary),
        const SizedBox(height: 12),
        Center(
          child: Text(
            '该板块暂无进行中的预测\n下拉刷新看看',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
          ),
        ),
      ],
    );
  }
}

/// 螺壳图标：复用鹦鹉螺线稿，琥珀着色。
class _ShellIcon extends StatelessWidget {
  const _ShellIcon({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset('assets/branding/nautilus.png',
        width: size, height: size, color: AppColors.amber);
  }
}

/// 市场卡片。
class _MarketCard extends StatelessWidget {
  const _MarketCard({required this.market});
  final PredictMarket market;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.bgSurface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: AppColors.borderDim),
          borderRadius: BorderRadius.circular(10),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => MarketDetailScreen(marketId: market.id)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        market.title,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    MarketStatusChip(market: market),
                  ],
                ),
                const SizedBox(height: 12),
                ...market.options.map((o) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OptionPoolBar(market: market, option: o),
                    )),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const _ShellIcon(size: 11),
                    const SizedBox(width: 4),
                    Text(
                      '奖池 ${market.totalPool}',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 11),
                    ),
                    const Spacer(),
                    Text(
                      market.isOpen
                          ? '截止 ${formatCloseAt(market.closeAt)}'
                          : market.isSettled
                              ? '已结算'
                              : market.isCancelled
                                  ? '已取消'
                                  : '待开奖',
                      style: TextStyle(
                          color: AppColors.textTertiary, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 市场状态角标（开放 / 待开奖 / 已结算 / 已取消）。
class MarketStatusChip extends StatelessWidget {
  const MarketStatusChip({super.key, required this.market});
  final PredictMarket market;

  @override
  Widget build(BuildContext context) {
    final (label, color) = market.isOpen
        ? ('进行中', AppColors.amber)
        : market.isSettled
            ? ('已结算', AppColors.info)
            : market.isCancelled
                ? ('已取消', AppColors.textTertiary)
                : ('待开奖', AppColors.warning);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style:
            TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// 选项池占比条：label + 占比进度 + 赔率。
class OptionPoolBar extends StatelessWidget {
  const OptionPoolBar({super.key, required this.market, required this.option});
  final PredictMarket market;
  final MarketOption option;

  @override
  Widget build(BuildContext context) {
    final share = market.shareFor(option);
    final odds = market.oddsFor(option);
    final isWinner =
        market.isSettled && market.resolvedOptionId == option.id;
    final barColor = isWinner
        ? AppColors.positive
        : (option.idx == 0 ? AppColors.amber : AppColors.info);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (isWinner)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.emoji_events,
                    size: 12, color: AppColors.positive),
              ),
            Expanded(
              child: Text(
                option.label,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontWeight: isWinner ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
            Text(
              odds > 0 ? '${odds.toStringAsFixed(2)}x' : '待定',
              style: TextStyle(
                color: barColor,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${(share * 100).toStringAsFixed(0)}%',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: share <= 0 ? 0.02 : share,
            minHeight: 5,
            backgroundColor: AppColors.bgRaised,
            valueColor: AlwaysStoppedAnimation(barColor),
          ),
        ),
      ],
    );
  }
}

/// 截止时间的相对/绝对展示。
String formatCloseAt(int ms) {
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  final now = DateTime.now();
  final diff = t.difference(now);
  if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟后';
  if (diff.inHours < 24) return '${diff.inHours} 小时后';
  if (diff.inDays < 7) return '${diff.inDays} 天后';
  return '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
