import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/nautilus.dart';
import '../../state/nautilus_state.dart';
import '../../theme/app_theme.dart';
import 'invite_screen.dart';

/// 螺壳钱包：余额 + 我的下注 + 流水。
class ShellWalletScreen extends StatefulWidget {
  const ShellWalletScreen({super.key});

  @override
  State<ShellWalletScreen> createState() => _ShellWalletScreenState();
}

class _ShellWalletScreenState extends State<ShellWalletScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) context.read<NautilusState>().refreshWallet();
    });
  }

  @override
  Widget build(BuildContext context) {
    final n = context.watch<NautilusState>();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: const Text('螺壳钱包')),
        body: RefreshIndicator(
          color: AppColors.amber,
          onRefresh: () => context.read<NautilusState>().refreshWallet(),
          child: Column(
            children: [
              // 余额头
              Container(
                margin: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                padding: const EdgeInsets.all(16),
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.amber, AppColors.amberDim],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Image.asset('assets/branding/nautilus.png',
                            width: 16, height: 16, color: Colors.black),
                        const SizedBox(width: 6),
                        const Text('螺壳余额',
                            style: TextStyle(
                                color: Colors.black87,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                        const Spacer(),
                        InkWell(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const InviteScreen()),
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text('邀请好友赚螺壳',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '${n.balance}',
                      style: const TextStyle(
                          color: Colors.black,
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          height: 1.0),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              TabBar(
                labelColor: AppColors.amber,
                unselectedLabelColor: AppColors.textTertiary,
                indicatorColor: AppColors.amber,
                labelStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800),
                tabs: const [Tab(text: '我的下注'), Tab(text: '螺壳流水')],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _betsTab(n.myBets),
                    _ledgerTab(n.ledger),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _betsTab(List<ShellBet> bets) {
    if (bets.isEmpty) {
      return _empty('还没有下注记录\n去「鹦鹉螺」选个预测试试');
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
      itemCount: bets.length,
      itemBuilder: (_, i) {
        final b = bets[i];
        final (statusLabel, statusColor) = switch (b.status) {
          'won' => ('+${b.payout}', AppColors.positive),
          'lost' => ('未押中', AppColors.textTertiary),
          'refunded' => ('已退款', AppColors.info),
          _ => ('待开奖', AppColors.warning),
        };
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderDim),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(b.marketTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      height: 1.4)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text('押「${b.optionLabel}」 ${b.amount} 螺壳',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 11)),
                  const Spacer(),
                  Text(statusLabel,
                      style: TextStyle(
                          color: statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _ledgerTab(List<ShellLedgerEntry> entries) {
    if (entries.isEmpty) {
      return _empty('暂无流水');
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final e = entries[i];
        final positive = e.delta > 0;
        final t = DateTime.fromMillisecondsSinceEpoch(e.createdAt);
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderDim),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.remark.isNotEmpty
                          ? '${e.reasonLabel} · ${e.remark}'
                          : e.reasonLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: AppColors.textPrimary, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${t.year}/${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(
                          color: AppColors.textTertiary, fontSize: 10),
                    ),
                  ],
                ),
              ),
              Text(
                '${positive ? '+' : ''}${e.delta}',
                style: TextStyle(
                  color:
                      positive ? AppColors.positive : AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _empty(String text) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Center(
          child: Text(text,
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: AppColors.textTertiary, fontSize: 12)),
        ),
      ],
    );
  }
}
