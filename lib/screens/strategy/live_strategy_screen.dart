import 'package:flutter/material.dart';

import '../../models/strategy_snapshot.dart';
import '../../services/strategy_service.dart';
import '../../theme/app_theme.dart';
import 'strategy_ask.dart';
import 'strategy_detail_screen.dart';
import 'widgets/strategy_cards.dart';

/// 策略详情页 —— 入口在「发现 → 组合管理」里的策略模拟组合（顶部「策略详情」）。
///
/// 回答：**本期策略结论是什么**（目标名单、调仓清单、问 AI）。数据来自后端
/// `/v1/strategy/primary`（上证50 九因子，月度调仓），需要登录。人工实盘账户
/// 不在这里展示——组合管理里呈现的是按策略结论模拟的资金，非实盘。
class LiveStrategyScreen extends StatefulWidget {
  const LiveStrategyScreen({super.key});

  @override
  State<LiveStrategyScreen> createState() => _LiveStrategyScreenState();
}

class _LiveStrategyScreenState extends State<LiveStrategyScreen> {
  final StrategyService _svc = StrategyService();

  StrategySnapshot? _snap;
  List<StrategyCatalogEntry> _catalog = const [];
  bool _loading = true;
  String? _error;
  DateTime? _loadedAt;

  @override
  void initState() {
    super.initState();
    // ignore: unawaited_futures
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _svc.fetchPrimary(),
        _svc.fetchCatalog(),
      ]);
      final snap = results[0] as StrategySnapshot?;
      if (!mounted) return;
      setState(() {
        _snap = snap;
        _catalog = (results[1] as List).cast<StrategyCatalogEntry>();
        _error = null;
        _loading = false;
        _loadedAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snap;
    // 数据每天最多变一次，10 分钟的容忍窗口足够，又能避免「早上打开还看着
    // 昨晚的旧数」。
    final loadedAt = _loadedAt;
    if (!_loading &&
        (loadedAt == null ||
            DateTime.now().difference(loadedAt) >
                const Duration(minutes: 10))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_loading) _load();
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('策略详情'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.amber,
        onRefresh: _load,
        child: _body(snap),
      ),
    );
  }

  Widget _body(StrategySnapshot? snap) {
    if (_loading && snap == null) {
      return const _Centered(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null && snap == null) {
      return _Centered(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!,
                textAlign: TextAlign.center,
                style: AppType.body.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpace.md),
            OutlinedButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (snap == null) {
      // 后端已接上、只是第一次同步还没跑完：不是错误，别吓用户。
      return _Centered(
        child: Text('策略数据同步中，稍后下拉刷新',
            style: AppType.body.copyWith(color: AppColors.textSecondary)),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter, AppSpace.md, AppSpace.gutter, AppSpace.xxl),
      children: [
        if (snap.stale) ...[
          StaleBanner(dataAsOf: snap.dataAsOf, staleDays: snap.staleDays),
          const SizedBox(height: AppSpace.md),
        ],
        StrategyHeaderCard(meta: snap.meta, dataAsOf: snap.dataAsOf),
        const SizedBox(height: AppSpace.md),
        ActionCard(
          action: snap.action,
          onAskAI: () => askStrategyAI(context, snap),
          onTapTarget: (t) =>
              askStrategyAI(context, snap, code: t.code, name: t.name),
        ),
        const SizedBox(height: AppSpace.md),
        _DetailEntry(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => StrategyDetailScreen(snapshot: snap),
          )),
        ),
        if (_catalog.length > 1) ...[
          const SizedBox(height: AppSpace.md),
          _CatalogSection(entries: _catalog, primaryId: snap.strategyId),
        ],
      ],
    );
  }
}

/// 多策略位：主策略之外还有哪些在排队。没有在跑的项如实标「即将上线」，
/// 不拿空壳功能充数。
class _CatalogSection extends StatelessWidget {
  const _CatalogSection({required this.entries, required this.primaryId});

  final List<StrategyCatalogEntry> entries;
  final String primaryId;

  @override
  Widget build(BuildContext context) {
    final others = [
      for (final e in entries)
        if (e.id != primaryId) e,
    ];
    if (others.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.sm),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('更多策略',
              style: AppType.section.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: AppSpace.sm),
          for (final e in others)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.name,
                            style: AppType.body
                                .copyWith(color: AppColors.textPrimary)),
                        const SizedBox(height: 2),
                        Text(e.subtitle,
                            style: AppType.micro.copyWith(
                                color: AppColors.textTertiary, height: 1.5)),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.sm, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.bgRaised,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text('即将上线',
                        style: AppType.micro
                            .copyWith(color: AppColors.textTertiary)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 「策略详情」入口：口径、绩效、逐年、因子检验、股票池对比都在里面。
class _DetailEntry extends StatelessWidget {
  const _DetailEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgSurface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.lg, vertical: AppSpace.lg),
          child: Row(
            children: [
              const Icon(Icons.receipt_long_rounded,
                  size: 20, color: AppColors.amber),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('策略详情',
                        style: AppType.body
                            .copyWith(color: AppColors.textPrimary)),
                    const SizedBox(height: 3),
                    Text('口径、绩效、逐年、因子检验与股票池对比',
                        style: AppType.caption
                            .copyWith(color: AppColors.textTertiary)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ListView(
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpace.xl, vertical: 80),
        children: [Center(child: child)],
      );
}
