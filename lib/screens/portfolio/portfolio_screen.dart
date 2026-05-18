import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/portfolio_state.dart';
import '../../theme/app_theme.dart';
import 'compare_screen.dart';
import 'dialogs/create_portfolio_dialog.dart';
import 'dialogs/instrument_picker_dialog.dart';
import 'tabs/analytics_tab.dart';
import 'tabs/economics_tab.dart';
import 'tabs/optimization_tab.dart';
import 'tabs/overview_tab.dart';
import 'tabs/performance_tab.dart';
import 'tabs/planning_tab.dart';
import 'tabs/quant_tab.dart';
import 'tabs/reports_tab.dart';
import 'tabs/risk_tab.dart';
import 'tabs/transactions_tab.dart';
import 'widgets/portfolio_command_bar.dart';
import 'widgets/portfolio_stats_ribbon.dart';

class PortfolioScreen extends StatelessWidget {
  const PortfolioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ps = context.watch<PortfolioState>();
    if (!ps.ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return DefaultTabController(
      length: 10,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('组合'),
          actions: [
            IconButton(
              tooltip: '刷新行情',
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: ps.activeId == null ? null : () => ps.refreshQuotes(),
            ),
            IconButton(
              tooltip: '组合对比',
              icon: const Icon(Icons.compare_arrows, size: 18),
              onPressed: ps.portfolios.length < 2
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const PortfolioCompareScreen())),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(172),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PortfolioCommandBar(
                  onCreate: () => _create(context),
                  onAddAsset:
                      ps.activeId == null ? null : () => _addAsset(context),
                  onDelete:
                      ps.activeId == null ? null : () => _delete(context),
                ),
                const PortfolioStatsRibbon(),
                const _PortfolioTabBar(),
              ],
            ),
          ),
        ),
        body: ps.activeId == null
            ? _emptyState(context)
            : const TabBarView(
                physics: ClampingScrollPhysics(),
                children: [
                  OverviewTab(),
                  AnalyticsTab(),
                  PerformanceTab(),
                  OptimizationTab(),
                  QuantTab(),
                  ReportsTab(),
                  TransactionsTab(),
                  RiskTab(),
                  PlanningTab(),
                  EconomicsTab(),
                ],
              ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inbox_outlined,
                  color: AppColors.amber, size: 56),
              const SizedBox(height: 16),
              Text('还没有任何组合',
                  style: TextStyle(
                      fontSize: 16,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                '新建一个组合，再把你关注的股票、ETF、期货或指数加进来。',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12, height: 1.5),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => _create(context),
                icon: const Icon(Icons.add),
                label: const Text('新建组合'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => const CreatePortfolioDialog(),
    );
  }

  Future<void> _addAsset(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (_) => const InstrumentPickerDialog(),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final ps = context.read<PortfolioState>();
    final p = ps.portfoliosForId(ps.activeId!);
    if (p == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除组合'),
        content: Text('确定要删除「${p.name}」吗？这会一并清掉它的持仓和交易记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ps.deletePortfolio(p.id);
    }
  }
}

class _PortfolioTabBar extends StatelessWidget {
  const _PortfolioTabBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgSurface,
      child: TabBar(
        isScrollable: true,
        indicatorColor: AppColors.amber,
        labelColor: AppColors.amber,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
        labelPadding: const EdgeInsets.symmetric(horizontal: 12),
        tabs: const [
          Tab(text: '总览'),
          Tab(text: '行业'),
          Tab(text: '绩效/风险'),
          Tab(text: '优化'),
          Tab(text: '量化统计'),
          Tab(text: '报告'),
          Tab(text: '交易'),
          Tab(text: '风控'),
          Tab(text: '规划'),
          Tab(text: '经济'),
        ],
      ),
    );
  }
}
