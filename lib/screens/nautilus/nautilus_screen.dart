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
  String _sub = ''; // 当前子分类筛选；空=全部
  bool _bootstrapped = false;

  static const _categories = ['weather', 'finance'];
  static const _categoryLabels = ['全球天气', '金融市场'];

  // 各大类下的子分类筛选（key 与后端 subcategory 对齐，空=全部）。
  static const _subKeys = {
    'weather': ['', 'grain', 'soft', 'city'],
    'finance': ['', 'index', 'stock', 'forex'],
  };
  static const _subLabels = {
    'weather': ['全部', '谷物油籽', '软商品', '城市'],
    'finance': ['全部', '股指', '个股', '外汇'],
  };

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
    final cat = _categories[_tab];
    final all = n.byCategory(cat);
    final markets =
        _sub.isEmpty ? all : all.where((m) => m.subCategory == _sub).toList();

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
          _headerBanner(n, authed),
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
                    onSelected: (_) => setState(() {
                      _tab = i;
                      _sub = ''; // 切大类时重置子筛选
                    }),
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
          _subFilterRow(cat),
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

  /// 顶部横幅：登录后展示螺壳余额(渐变卡)+邀请行动点；未登录展示领螺壳引导。
  Widget _headerBanner(NautilusState n, bool authed) {
    if (authed && n.walletLoaded) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: InkWell(
          onTap: _openWallet,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.amber, AppColors.amberDim],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Image.asset('assets/branding/nautilus.png',
                    width: 30, height: 30, color: Colors.black),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('我的螺壳',
                        style: TextStyle(
                            color: Colors.black87,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('${n.balance}',
                        style: const TextStyle(
                            color: Colors.black,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                            height: 1.0)),
                  ],
                ),
                const Spacer(),
                _bannerButton(
                  icon: Icons.card_giftcard,
                  label: '邀请赚螺壳',
                  onTap: _openInvite,
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: InkWell(
        onTap: _openWallet,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.amber.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              const _ShellIcon(size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('登录领螺壳',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text('用螺壳押全球天气和金融行情，邀请好友还能赚更多',
                        style: TextStyle(
                            color: AppColors.textTertiary, fontSize: 11)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  size: 20, color: AppColors.amber),
            ],
          ),
        ),
      ),
    );
  }

  /// 子分类筛选条：天气(谷物油籽/软商品/城市) / 金融(股指/个股/外汇)。
  Widget _subFilterRow(String category) {
    final keys = _subKeys[category] ?? const [''];
    final labels = _subLabels[category] ?? const ['全部'];
    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
        itemCount: keys.length,
        itemBuilder: (_, i) {
          final active = _sub == keys[i];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(labels[i]),
              selected: active,
              onSelected: (_) => setState(() => _sub = keys[i]),
              labelStyle: TextStyle(
                color: active ? AppColors.amber : AppColors.textTertiary,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              selectedColor: AppColors.amber.withValues(alpha: 0.16),
              backgroundColor: AppColors.bgSurface,
              side: BorderSide(
                  color: active ? AppColors.amber : AppColors.borderDim),
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          );
        },
      ),
    );
  }

  Widget _bannerButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ],
        ),
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
                    if (market.totalBettors > 0) ...[
                      const SizedBox(width: 10),
                      Icon(Icons.people_alt_rounded,
                          size: 11, color: AppColors.textTertiary),
                      const SizedBox(width: 3),
                      Text(
                        '${market.totalBettors}',
                        style: TextStyle(
                            color: AppColors.textTertiary, fontSize: 11),
                      ),
                    ],
                    const Spacer(),
                    if (market.isOpen && market.closingSoon) ...[
                      const Icon(Icons.bolt, size: 12, color: AppColors.warning),
                      const SizedBox(width: 2),
                    ],
                    Text(
                      market.isOpen
                          ? '截止 ${formatCloseAt(market.closeAt)}'
                          : market.isSettled
                              ? '已结算'
                              : market.isCancelled
                                  ? '已取消'
                                  : '待开奖',
                      style: TextStyle(
                          color: market.isOpen && market.closingSoon
                              ? AppColors.warning
                              : AppColors.textTertiary,
                          fontSize: 11,
                          fontWeight: market.isOpen && market.closingSoon
                              ? FontWeight.w700
                              : FontWeight.w400),
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
