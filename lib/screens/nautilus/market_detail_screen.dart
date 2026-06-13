import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/require_login.dart';
import '../../models/nautilus.dart';
import '../../services/nautilus_service.dart';
import '../../state/auth_state.dart';
import '../../state/nautilus_state.dart';
import '../../theme/app_theme.dart';
import 'nautilus_screen.dart' show MarketStatusChip, OptionPoolBar, formatCloseAt;

/// 市场详情：完整描述 + 选项池 + 我的下注 + 下注操作。
class MarketDetailScreen extends StatefulWidget {
  const MarketDetailScreen({super.key, required this.marketId});
  final int marketId;

  @override
  State<MarketDetailScreen> createState() => _MarketDetailScreenState();
}

class _MarketDetailScreenState extends State<MarketDetailScreen> {
  List<ShellBet> _myBets = [];
  bool _loadedBets = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_refresh);
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    final n = context.read<NautilusState>();
    await n.loadMarket(widget.marketId);
    if (!mounted) return;
    if (context.read<AuthState>().isAuthenticated) {
      try {
        final bets = await NautilusService().myMarketBets(widget.marketId);
        if (mounted) setState(() => _myBets = bets);
      } catch (_) {/* 未登录/网络抖动忽略 */}
    }
    if (mounted) setState(() => _loadedBets = true);
  }

  PredictMarket? get _market {
    final list = context.watch<NautilusState>().markets;
    for (final m in list) {
      if (m.id == widget.marketId) return m;
    }
    return null;
  }

  Future<void> _openBetSheet(PredictMarket market, MarketOption option) async {
    if (!await requireLogin(context)) return;
    if (!mounted) return;
    final n = context.read<NautilusState>();
    if (!n.walletLoaded) await n.refreshWallet();
    if (!mounted) return;
    final placed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (_) => _BetSheet(market: market, option: option),
    );
    if (placed == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final market = _market;
    return Scaffold(
      appBar: AppBar(title: const Text('预测详情')),
      body: market == null
          ? const Center(
              child: CircularProgressIndicator(
                  color: AppColors.amber, strokeWidth: 2))
          : RefreshIndicator(
              color: AppColors.amber,
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 32),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          market.title,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      MarketStatusChip(market: market),
                    ],
                  ),
                  if (market.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      market.description,
                      style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          height: 1.5),
                    ),
                  ],
                  if (market.isSettled) ...[
                    const SizedBox(height: 12),
                    _resultBanner(market),
                  ],
                  const SizedBox(height: 10),
                  _metaRow(market),
                  const SizedBox(height: 16),
                  const Text('选项与赔率',
                      style: TextStyle(
                          color: AppColors.amber,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0)),
                  const SizedBox(height: 10),
                  ...market.options.map((o) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            OptionPoolBar(market: market, option: o),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Text(
                                  '${o.poolShells} 螺壳 · ${o.bettorCount} 人',
                                  style: TextStyle(
                                      color: AppColors.textTertiary,
                                      fontSize: 10),
                                ),
                                const Spacer(),
                                if (market.isOpen)
                                  SizedBox(
                                    height: 28,
                                    child: ElevatedButton(
                                      onPressed: () =>
                                          _openBetSheet(market, o),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 16),
                                        textStyle: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800),
                                      ),
                                      child: Text('押「${o.label}」'),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      )),
                  if (_loadedBets && _myBets.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    const Text('我的下注',
                        style: TextStyle(
                            color: AppColors.amber,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.0)),
                    const SizedBox(height: 8),
                    ..._myBets.map((b) => _myBetRow(market, b)),
                  ],
                  const SizedBox(height: 16),
                  _rulesCard(market),
                ],
              ),
            ),
    );
  }

  /// 已结算结果横幅：高亮获胜选项。
  Widget _resultBanner(PredictMarket market) {
    final winner =
        market.options.where((o) => o.id == market.resolvedOptionId).firstOrNull;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.positive.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.positive.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_events, size: 18, color: AppColors.positive),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('已开奖',
                    style: TextStyle(
                        color: AppColors.textTertiary, fontSize: 10)),
                const SizedBox(height: 2),
                Text(
                  winner != null ? '结果：${winner.label}' : '本场流局，已退款',
                  style: const TextStyle(
                      color: AppColors.positive,
                      fontSize: 14,
                      fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _metaRow(PredictMarket market) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderDim),
      ),
      child: Row(
        children: [
          _metaItem('总奖池', '${market.totalPool}'),
          _metaItem('下注截止', formatCloseAt(market.closeAt)),
          _metaItem(
              '结算方式',
              market.resolveKind == 'auto'
                  ? (market.isWeatherAuto ? '天气自动' : '行情自动')
                  : '官方公布'),
        ],
      ),
    );
  }

  Widget _metaItem(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(color: AppColors.textTertiary, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _myBetRow(PredictMarket market, ShellBet b) {
    final option = market.options.where((o) => o.id == b.optionId).firstOrNull;
    final (statusLabel, statusColor) = switch (b.status) {
      'won' => ('+${b.payout}', AppColors.positive),
      'lost' => ('未押中', AppColors.textTertiary),
      'refunded' => ('已退款', AppColors.info),
      _ => ('待开奖', AppColors.warning),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.bgRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderDim),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '押「${option?.label ?? '-'}」 ${b.amount} 螺壳',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 12),
            ),
          ),
          Text(statusLabel,
              style: TextStyle(
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _rulesCard(PredictMarket market) {
    final rake = market.rakeBps / 100;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.bgRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderDim),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('玩法说明',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            '· 奖池瓜分制：所有人的螺壳进同一奖池，按选项分边\n'
            '· 结算时押中一方按下注比例瓜分全部奖池${rake > 0 ? '（平台收取 ${rake.toStringAsFixed(1)}% 手续费）' : ''}\n'
            '· 赔率随下注实时变化，以结算时各选项池子为准\n'
            '· 无人押中时全员退款；市场取消时全额退款\n'
            '· 螺壳为虚拟道具，仅用于娱乐预测，不可兑换现金',
            style: TextStyle(
                color: AppColors.textTertiary, fontSize: 11, height: 1.7),
          ),
        ],
      ),
    );
  }
}

/// 下注弹层：金额输入 + 快捷筹码 + 预估回报。
class _BetSheet extends StatefulWidget {
  const _BetSheet({required this.market, required this.option});
  final PredictMarket market;
  final MarketOption option;

  @override
  State<_BetSheet> createState() => _BetSheetState();
}

class _BetSheetState extends State<_BetSheet> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.text =
        context.read<NautilusState>().minBet.toString();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _amount => int.tryParse(_controller.text.trim()) ?? 0;

  /// 按当前池子估算回报（自己这笔加入后的稀释后赔率）。
  double get _estimatedReturn {
    final amt = _amount;
    if (amt <= 0) return 0;
    final m = widget.market;
    final total = m.totalPool + amt;
    final winPool = widget.option.poolShells + amt;
    final distributable = total * (1 - m.rakeBps / 10000);
    return amt * distributable / winPool;
  }

  Future<void> _submit() async {
    final n = context.read<NautilusState>();
    final amt = _amount;
    if (amt < n.minBet) {
      setState(() => _error = '最低下注 ${n.minBet} 螺壳');
      return;
    }
    if (amt > n.balance) {
      setState(() => _error = '螺壳不足（当前 ${n.balance}），邀请好友可获得更多螺壳');
      return;
    }
    final err = await n.placeBet(
      marketId: widget.market.id,
      optionId: widget.option.id,
      amount: amt,
    );
    if (!mounted) return;
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.of(context).pop(true);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('已押「${widget.option.label}」 $amt 螺壳'),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final n = context.watch<NautilusState>();
    final quick = [n.minBet, 50, 100, 500]
        .where((v) => v <= n.balance)
        .toSet()
        .toList()
      ..sort();

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.market.title,
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 11, height: 1.4),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          Text(
            '押「${widget.option.label}」',
            style: const TextStyle(
                color: AppColors.amber,
                fontSize: 15,
                fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              hintText: '输入螺壳数量',
              suffixText: '螺壳',
              errorText: _error,
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              for (final v in quick)
                ActionChip(
                  label: Text('$v'),
                  labelStyle: TextStyle(
                      color: AppColors.textPrimary, fontSize: 11),
                  backgroundColor: AppColors.bgRaised,
                  side: BorderSide(color: AppColors.borderDim),
                  onPressed: () =>
                      setState(() => _controller.text = '$v'),
                ),
              if (n.balance > 0)
                ActionChip(
                  label: const Text('全部'),
                  labelStyle: TextStyle(
                      color: AppColors.textPrimary, fontSize: 11),
                  backgroundColor: AppColors.bgRaised,
                  side: BorderSide(color: AppColors.borderDim),
                  onPressed: () =>
                      setState(() => _controller.text = '${n.balance}'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('余额 ${n.balance} 螺壳',
                  style: TextStyle(
                      color: AppColors.textTertiary, fontSize: 11)),
              const Spacer(),
              if (_amount > 0)
                Text(
                  '押中预估可得 ${_estimatedReturn.toStringAsFixed(0)} 螺壳',
                  style: const TextStyle(
                      color: AppColors.amber,
                      fontSize: 11,
                      fontWeight: FontWeight.w700),
                ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: n.betting ? null : _submit,
              child: n.betting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : const Text('确认下注'),
            ),
          ),
        ],
      ),
    );
  }
}
