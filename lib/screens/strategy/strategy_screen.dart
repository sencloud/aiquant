import 'package:flutter/material.dart';

import '../../models/strategy_snapshot.dart';
import '../../services/strategy_service.dart';
import '../../theme/app_theme.dart';
import 'strategy_ask.dart';
import 'strategy_detail_screen.dart';
import 'widgets/strategy_cards.dart';

/// 主策略页 —— App 里除对话之外的另一个主入口。
///
/// P0 只回答两个问题：**本期要不要动手**、**实盘现在什么状态**。
/// 深色暗调 + 金黄主色，与助理页保持同一套视觉语言。
class StrategyScreen extends StatefulWidget {
  const StrategyScreen({super.key});

  @override
  State<StrategyScreen> createState() => _StrategyScreenState();
}

class _StrategyScreenState extends State<StrategyScreen> {
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
    // IndexedStack 会让本页常驻内存，切回 tab 时 build 会重跑。数据每天最多变
    // 一次，10 分钟的容忍窗口足够，又能避免"早上打开还看着昨晚的旧数"。
    final loadedAt = _loadedAt;
    if (!_loading &&
        (loadedAt == null ||
            DateTime.now().difference(loadedAt) > const Duration(minutes: 10))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_loading) _load();
      });
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('主策略'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh, size: 18),
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
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (snap == null) {
      // 后端已接上、只是第一次同步还没跑完：不是错误，别吓用户。
      return _Centered(
        child: Text('策略数据同步中，稍后下拉刷新',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
      children: [
        if (snap.stale) ...[
          StaleBanner(dataAsOf: snap.dataAsOf, staleDays: snap.staleDays),
          const SizedBox(height: 10),
        ],
        StrategyHeaderCard(
          meta: snap.meta,
          dataAsOf: snap.dataAsOf,
        ),
        const SizedBox(height: 12),
        ActionCard(
          action: snap.action,
          onAskAI: () => askStrategyAI(context, snap),
          onTapTarget: (t) =>
              askStrategyAI(context, snap, code: t.code, name: t.name),
        ),
        if (snap.live != null) ...[
          const SizedBox(height: 12),
          LiveCard(
            live: snap.live!,
            onTapPosition: (p) => askStrategyAI(context, snap,
                code: p.code, name: p.name, role: '持仓', cost: p.avgCost),
          ),
        ],
        const SizedBox(height: 12),
        _DetailEntry(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => StrategyDetailScreen(snapshot: snap),
          )),
        ),
        if (_catalog.length > 1) ...[
          const SizedBox(height: 12),
          _CatalogSection(
            entries: _catalog,
            primaryId: snap.strategyId,
          ),
        ],
      ],
    );
  }
}

/// 多策略位：主策略之外还有哪些在排队。没有在跑的项如实标"即将上线"，
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
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderDim),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('更多策略',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6)),
          const SizedBox(height: 8),
          for (final e in others)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.name,
                            style: TextStyle(
                                color: AppColors.textPrimary, fontSize: 13)),
                        const SizedBox(height: 2),
                        Text(e.subtitle,
                            style: TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 10.5,
                                height: 1.4)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.bgRaised,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.borderDim),
                    ),
                    child: Text('即将上线',
                        style: TextStyle(
                            color: AppColors.textTertiary, fontSize: 9.5)),
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
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderDim),
          ),
          child: Row(
            children: [
              const Icon(Icons.receipt_long_outlined,
                  size: 18, color: AppColors.amber),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('策略详情',
                        style: TextStyle(
                            color: AppColors.textPrimary, fontSize: 13.5)),
                    const SizedBox(height: 2),
                    Text('口径、绩效、逐年、因子检验与股票池对比',
                        style: TextStyle(
                            color: AppColors.textTertiary, fontSize: 10.5)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 18, color: AppColors.textTertiary),
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
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
        children: [Center(child: child)],
      );
}
