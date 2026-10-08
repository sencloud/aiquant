/// 回测公共数据模型：两个策略引擎（双动量轮动 / 短线动量）共用，
/// 并为结果区 UI（MetricsCards / NavChart / TradeLog）提供统一的展示视图。
library;

/// 绩效统计块（策略与基准各一份）。
class BacktestMetrics {
  const BacktestMetrics({
    required this.totalReturn,
    required this.annReturn,
    required this.annVol,
    required this.sharpe,
    required this.maxDrawdown,
  });

  final double totalReturn;
  final double annReturn;
  final double annVol;
  final double sharpe;
  final double maxDrawdown;
}

/// 净值曲线上的一个点。
class NavPoint {
  const NavPoint(this.date, this.nav);
  final DateTime date;
  final double nav;
}

/// 期末持仓行。
class HoldingRow {
  const HoldingRow(this.symbol, this.weight);
  final String symbol;
  final double weight;
}

/// 概览条上的一项（label + 展示值），由各策略引擎按语义生成。
class BacktestStatItem {
  const BacktestStatItem(this.label, this.value);
  final String label;
  final String value;
}

/// 结果区统一视图：两个策略都产出该结构，UI 组件只认它。
class BacktestViewData {
  const BacktestViewData({
    required this.strategyLabel,
    required this.benchmarkLabel,
    required this.stats,
    required this.strategyMetrics,
    required this.benchmarkMetrics,
    required this.alpha,
    required this.finalHoldings,
    required this.navSeries,
    required this.benchmarkNavSeries,
  });

  /// 策略名（对比表标题用）。
  final String strategyLabel;

  /// 基准名（对比表标题用）。
  final String benchmarkLabel;

  /// 概览条项目（区间 / 交易日 / 再平衡次数或交易笔数 / 胜率…）。
  final List<BacktestStatItem> stats;

  final BacktestMetrics strategyMetrics;
  final BacktestMetrics benchmarkMetrics;

  /// 年化超额收益（策略 - 基准）。
  final double alpha;

  final List<HoldingRow> finalHoldings;
  final List<NavPoint> navSeries;
  final List<NavPoint> benchmarkNavSeries;
}
