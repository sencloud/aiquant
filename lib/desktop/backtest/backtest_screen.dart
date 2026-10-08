import 'package:flutter/material.dart';

import '../../services/backtest/backtest_data_source.dart';
import '../../services/backtest/backtest_models.dart';
import '../../services/backtest/etf_rotation.dart'
    hide BacktestMetrics, NavPoint, HoldingRow;
import '../../services/backtest/etf_short_term.dart';
import '../../theme/app_theme.dart';
import 'widgets/metrics_cards.dart';
import 'widgets/nav_chart.dart';
import 'widgets/params_form.dart';
import 'widgets/short_term_form.dart';
import 'widgets/trade_log.dart';

/// 桌面端「策略调试」页：顶部策略切换 + 左参数区 + 右结果区。
///
/// 两个策略共用一个行情数据源（缓存互通，切策略不重拉）：
/// - 轮动（etf_rotation）：双动量 ETF 组合轮动，无摩擦权重模型
/// - 短线（etf_short_term）：深市 159 ETF，T+1/万3/100 份整数倍的实盘规则模拟
class BacktestScreen extends StatefulWidget {
  const BacktestScreen({super.key});

  @override
  State<BacktestScreen> createState() => _BacktestScreenState();
}

/// 策略类型。
enum BacktestStrategy { rotation, shortTerm }

/// 一次运行记录：参数摘要 + 结果视图，用于「最近运行」对比。
class BacktestRunRecord {
  BacktestRunRecord({
    required this.label,
    required this.strategy,
    required this.view,
    required this.time,
  });

  final String label;
  final BacktestStrategy strategy;
  final BacktestViewData view;
  final DateTime time;
}

class _BacktestScreenState extends State<BacktestScreen> {
  final BacktestDataSource _dataSource = BacktestDataSource();

  /// 当前策略。
  BacktestStrategy _strategy = BacktestStrategy.shortTerm;

  /// 正在运行（拉行情或计算中）。
  bool _running = false;

  /// 拉取进度文案。
  String _progress = '';

  /// 最近一次成功结果。
  BacktestViewData? _result;

  /// 短线策略的交易明细（轮动策略为 null）。
  ShortTermResult? _shortTermDetail;

  /// 最近运行记录（最新在前，最多 8 条）。
  final List<BacktestRunRecord> _runs = [];

  /// 错误提示。
  String? _error;

  Future<void> _runRotation(EtfRotationParams p) async {
    try {
      final resolved = previewResolved(p);
      final dataStart = resolved.start
          .subtract(Duration(days: resolved.longWindow * 2 + 30));
      final allCodes = [...resolved.symbols, resolved.benchmark];
      if (!allCodes.contains(resolved.defensive)) {
        allCodes.add(resolved.defensive);
      }
      final series = await _load(allCodes, dataStart, resolved.end);
      final r = runEtfRotationBacktest(params: p, series: series);
    // 轮动引擎的自有类型 → 统一视图类型（字段一一对应）
    final view = BacktestViewData(
      strategyLabel: '策略 · 双动量轮动',
      benchmarkLabel: '基准 · 买入持有',
      stats: [
        BacktestStatItem('区间',
            '${_ymd(r.periodStart)} ~ ${_ymd(r.periodEnd)}'),
        BacktestStatItem('交易日', '${r.observations}'),
        BacktestStatItem('再平衡', '${r.rebalances} 次'),
        BacktestStatItem('月胜率',
            '${r.monthlyWinRate.toStringAsFixed(1)}%'),
      ],
      strategyMetrics: BacktestMetrics(
        totalReturn: r.strategyMetrics.totalReturn,
        annReturn: r.strategyMetrics.annReturn,
        annVol: r.strategyMetrics.annVol,
        sharpe: r.strategyMetrics.sharpe,
        maxDrawdown: r.strategyMetrics.maxDrawdown,
      ),
      benchmarkMetrics: BacktestMetrics(
        totalReturn: r.benchmarkMetrics.totalReturn,
        annReturn: r.benchmarkMetrics.annReturn,
        annVol: r.benchmarkMetrics.annVol,
        sharpe: r.benchmarkMetrics.sharpe,
        maxDrawdown: r.benchmarkMetrics.maxDrawdown,
      ),
      alpha: r.alpha,
      finalHoldings: [
        for (final h in r.finalHoldings) HoldingRow(h.symbol, h.weight),
      ],
      navSeries: [
        for (final n in r.navSeries) NavPoint(n.date, n.nav),
      ],
      benchmarkNavSeries: [
        for (final n in r.benchmarkNavSeries) NavPoint(n.date, n.nav),
      ],
    );
      _finishRun(
        label: 'Top${p.topN ?? 3} · ${p.rebalanceDays ?? 20}日 · '
            '年化 ${(r.strategyMetrics.annReturn * 100).toStringAsFixed(1)}%',
        view: view,
        detail: null,
      );
    } catch (e) {
      _failRun(e);
    }
  }

  Future<void> _runShortTerm(EtfShortTermEngineConfig p) async {
    if (p.startDate == null || p.endDate == null) {
      _failRun(Exception('日期格式应为 yyyy-MM-dd'));
      return;
    }
    try {
      final engine = EtfShortTermEngine(
        symbols: p.symbols,
        initialCapital: p.initialCapital,
        momentumWindow: p.momentumWindow,
        buyThreshold: p.buyThreshold,
        firstBuyRatio: p.firstBuyRatio,
        addThreshold: p.addThreshold,
        addMaxRatio: p.addMaxRatio,
        stopLoss: p.stopLoss,
        maxHoldingDays: p.maxHoldingDays,
        maxPositions: p.maxPositions,
      );
      final dataStart = p.startDate!.subtract(
          Duration(days: p.momentumWindow * 2 + 30));
      final series = await _load(p.symbols, dataStart, p.endDate!);
      final r = engine.run(series: series);

      final view = BacktestViewData(
        strategyLabel: '策略 · 短线动量',
        benchmarkLabel: '基准 · 池等权持有',
        stats: [
          BacktestStatItem(
              '区间',
              r.navSeries.isEmpty
                  ? '-'
                  : '${_ymd(r.navSeries.first.date)} ~ '
                      '${_ymd(r.navSeries.last.date)}'),
          BacktestStatItem('期末资产', _money(r.finalEquity)),
          BacktestStatItem('交易笔数', '${r.trades.length}'),
          BacktestStatItem('现金→资产',
              '${(r.metrics.totalReturn * 100).toStringAsFixed(2)}%'),
        ],
        strategyMetrics: r.metrics,
        benchmarkMetrics: r.benchMetrics,
        alpha: r.metrics.annReturn - r.benchMetrics.annReturn,
        finalHoldings: const [],
        navSeries: r.navSeries,
        benchmarkNavSeries: r.benchNavSeries,
      );
      _finishRun(
        label: '短线 · ${p.momentumWindow}日动量 · '
            '年化 ${(r.metrics.annReturn * 100).toStringAsFixed(1)}%',
        view: view,
        detail: r,
      );
    } catch (e) {
      _failRun(e);
    }
  }

  /// 拉行情（缓存命中不打 API）。
  Future<Map<String, List<BacktestCandle>>> _load(
      List<String> codes, DateTime start, DateTime end) async {
    setState(() {
      _running = true;
      _error = null;
      _progress = '';
    });
    try {
      return await _dataSource.loadAll(
        codes,
        dataStart: start,
        end: end,
        onProgress: (done, total, code) {
          if (mounted) {
            setState(() => _progress = '拉取行情 $done/$total：$code');
          }
        },
      );
    } finally {
      if (mounted) setState(() => _progress = '计算中…');
    }
  }

  /// 运行完成（成功）回调：记录结果并解除运行态。
  void _finishRun({
    required String label,
    required BacktestViewData view,
    required ShortTermResult? detail,
  }) {
    if (!mounted) return;
    setState(() {
      _result = view;
      _shortTermDetail = detail;
      _running = false;
      _progress = '';
      _runs.insert(
        0,
        BacktestRunRecord(
          label: label,
          strategy: _strategy,
          view: view,
          time: DateTime.now(),
        ),
      );
      if (_runs.length > 8) _runs.removeLast();
    });
  }

  /// 运行失败：展示错误并解除运行态。
  void _failRun(Object e) {
    if (!mounted) return;
    setState(() {
      _running = false;
      _progress = '';
      _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgBase,
      child: Column(
        children: [
          _headerBar(),
          Container(height: 1, color: AppColors.borderDim),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 320,
                  child: _strategy == BacktestStrategy.rotation
                      ? ParamsForm(
                          running: _running,
                          progress: _progress,
                          onRun: _runRotation,
                        )
                      : ShortTermForm(
                          running: _running,
                          progress: _progress,
                          onRun: _runShortTerm,
                        ),
                ),
                Container(width: 1, color: AppColors.borderDim),
                Expanded(child: _resultPanel()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 顶栏：标题 + 策略切换 segmented control。
  Widget _headerBar() {
    return Container(
      height: 52,
      color: AppColors.bgSurface,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Text(
            'ETF 策略回测',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(width: 20),
          _strategySwitch(),
          const Spacer(),
          if (_runs.isNotEmpty)
            Text(
              '已运行 ${_runs.length} 次',
              style:
                  TextStyle(color: AppColors.textTertiary, fontSize: 11),
            ),
        ],
      ),
    );
  }

  Widget _strategySwitch() {
    Widget seg(String label, BacktestStrategy s) {
      final active = _strategy == s;
      return GestureDetector(
        onTap: _running
            ? null
            : () => setState(() {
                  _strategy = s;
                  // 切换策略清空当前结果，避免两策略视图混淆
                  _result = null;
                  _shortTermDetail = null;
                  _error = null;
                }),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: active
                ? AppColors.amber.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active
                  ? AppColors.amber.withValues(alpha: 0.5)
                  : AppColors.borderDim,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? AppColors.amber : AppColors.textSecondary,
              fontSize: 12,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgBase,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        seg('短线动量', BacktestStrategy.shortTerm),
        seg('双动量轮动', BacktestStrategy.rotation),
      ]),
    );
  }

  Widget _resultPanel() {
    if (_running) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(height: 14),
            Text(_progress.isEmpty ? '运行中…' : _progress,
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
      );
    }
    if (_error != null) {
      return _errorPanel();
    }
    final r = _result;
    if (r == null) {
      return _emptyPanel();
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (_runs.length > 1) ...[
          _recentRuns(),
          const SizedBox(height: 14),
        ],
        MetricsCards(view: r),
        const SizedBox(height: 14),
        NavChart(view: r),
        if (_shortTermDetail != null &&
            _shortTermDetail!.trades.isNotEmpty) ...[
          const SizedBox(height: 14),
          TradeLog(result: _shortTermDetail!),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _recentRuns() {
    return Row(
      children: [
        Text('最近运行',
            style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
        const SizedBox(width: 10),
        Expanded(
          child: DropdownButton<BacktestRunRecord>(
            isExpanded: true,
            value: null,
            hint: Text('选择历史记录回看（不重跑）',
                style:
                    TextStyle(color: AppColors.textTertiary, fontSize: 12)),
            items: [
              for (final rec in _runs)
                DropdownMenuItem(
                  value: rec,
                  child: Text(rec.label,
                      style: const TextStyle(fontSize: 12)),
                ),
            ],
            onChanged: (rec) {
              if (rec == null) return;
              setState(() {
                _result = rec.view;
                _shortTermDetail = null;
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _errorPanel() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 40, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyPanel() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.query_stats_outlined,
              size: 44, color: AppColors.textTertiary),
          const SizedBox(height: 12),
          Text(
            '左侧调整参数，点「运行回测」查看结果',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _money(double v) {
  final s = v.toStringAsFixed(2);
  // 千分位
  final rg = RegExp(r'\B(?=(\d{3})+(?!\d))');
  final parts = s.split('.');
  return '${parts[0].replaceAllMapped(rg, (m) => ',')}.${parts[1]}';
}
