import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/instrument.dart';
import '../../../services/tushare_service.dart';
import '../../../state/portfolio_state.dart';
import '../../../theme/app_theme.dart';
import '../widgets/sector_donut.dart';

/// "行业 / Sectors" tab — 在原本的行业市值/盈亏/资产类别基础上
/// 新增：
///   - 申万一级行业 1Y 涨跌幅排行（横向柱状图）
///   - Brinson 归因（持仓行业 vs 沪深 300 行业，配置/选股/交互效应）
class AnalyticsTab extends StatefulWidget {
  const AnalyticsTab({super.key});

  @override
  State<AnalyticsTab> createState() => _AnalyticsTabState();
}

class _AnalyticsTabState extends State<AnalyticsTab> {
  // 申万一级行业（28 个）
  static const List<List<String>> _swl1 = [
    ['801010.SI', '农林牧渔'],
    ['801020.SI', '采掘'],
    ['801030.SI', '化工'],
    ['801040.SI', '钢铁'],
    ['801050.SI', '有色金属'],
    ['801080.SI', '电子'],
    ['801110.SI', '家用电器'],
    ['801120.SI', '食品饮料'],
    ['801130.SI', '纺织服装'],
    ['801140.SI', '轻工制造'],
    ['801150.SI', '医药生物'],
    ['801160.SI', '公用事业'],
    ['801170.SI', '交通运输'],
    ['801180.SI', '房地产'],
    ['801200.SI', '商业贸易'],
    ['801210.SI', '休闲服务'],
    ['801230.SI', '综合'],
    ['801710.SI', '建筑材料'],
    ['801720.SI', '建筑装饰'],
    ['801730.SI', '电气设备'],
    ['801740.SI', '国防军工'],
    ['801750.SI', '计算机'],
    ['801760.SI', '传媒'],
    ['801770.SI', '通信'],
    ['801780.SI', '银行'],
    ['801790.SI', '非银金融'],
    ['801880.SI', '汽车'],
    ['801890.SI', '机械设备'],
  ];

  final TushareService _svc = TushareService();
  bool _loadingSw = true;
  String? _swError;
  List<_SwReturn> _swReturns = const [];

  // Brinson 归因
  bool _loadingBrinson = true;
  String? _brinsonError;
  _BrinsonResult? _brinson;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSw();
      _computeBrinson();
    });
  }

  Future<void> _loadSw() async {
    setState(() {
      _loadingSw = true;
      _swError = null;
    });
    try {
      final start = _ymd(DateTime.now().subtract(const Duration(days: 365)));
      final end = _ymd(DateTime.now());
      // 并发拉取
      final futs = _swl1
          .map((p) => _fetchSwReturn(p[0], p[1], start: start, end: end))
          .toList();
      final results = await Future.wait(futs);
      final out = [for (final r in results) if (r != null) r];
      out.sort((a, b) => b.ret.compareTo(a.ret));
      if (!mounted) return;
      setState(() {
        _swReturns = out;
        _loadingSw = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _swError = e.toString();
        _loadingSw = false;
      });
    }
  }

  Future<_SwReturn?> _fetchSwReturn(String tsCode, String name,
      {required String start, required String end}) async {
    try {
      final rows = await _svc.query(
        apiName: 'sw_daily',
        params: {'ts_code': tsCode, 'start_date': start, 'end_date': end},
        fields: 'trade_date,close',
      );
      if (rows.length < 2) return null;
      // tushare 默认按 trade_date 倒序：第一条最新，最后一条最旧
      final closes = <double>[];
      for (final r in rows) {
        final v = r['close'];
        double? d;
        if (v is num) {
          d = v.toDouble();
        } else {
          d = double.tryParse((v ?? '').toString());
        }
        if (d != null && d > 0) closes.add(d);
      }
      if (closes.length < 2) return null;
      final latest = closes.first;
      final oldest = closes.last;
      final ret = (latest - oldest) / oldest;
      return _SwReturn(code: tsCode, name: name, ret: ret);
    } catch (_) {
      return null;
    }
  }

  Future<void> _computeBrinson() async {
    setState(() {
      _loadingBrinson = true;
      _brinsonError = null;
      _brinson = null;
    });
    try {
      final ps = context.read<PortfolioState>();
      final s = ps.currentSummary;
      if (s == null || s.holdings.isEmpty) {
        setState(() => _loadingBrinson = false);
        return;
      }
      // 1) 拿持仓 252 日历史，计算每只持仓的累计收益
      final histories = await ps.ensureHistories(days: 252);
      // 2) 拿沪深 300 当前成分股 + 它们的行业（用 stock_basic 拿行业字段）
      //    使用 index_weight 取最近一期权重
      final iwRows = await _svc.query(
        apiName: 'index_weight',
        params: {
          'index_code': '000300.SH',
          'start_date':
              _ymd(DateTime.now().subtract(const Duration(days: 90))),
          'end_date': _ymd(DateTime.now()),
        },
        fields: 'index_code,con_code,trade_date,weight',
      );
      // 取最近一期：以 trade_date 最大的子集
      String? maxDate;
      for (final r in iwRows) {
        final d = (r['trade_date'] ?? '').toString();
        if (maxDate == null || d.compareTo(maxDate) > 0) maxDate = d;
      }
      final latestWeights = [
        for (final r in iwRows)
          if ((r['trade_date'] ?? '').toString() == maxDate) r,
      ];
      if (latestWeights.isEmpty) {
        throw Exception('无法获取沪深 300 最新成分股权重');
      }
      // 3) 用 stock_basic 拿全 A 行业映射（一次拉全量缓存）
      final all = await _svc.stockBasic();
      final industryMap = {
        for (final i in all) i.tsCode: i.industry.isEmpty ? '其它' : i.industry,
      };

      // 基准行业权重
      final benchSectorWeight = <String, double>{};
      double benchTotalW = 0;
      for (final r in latestWeights) {
        final code = (r['con_code'] ?? '').toString();
        final w = (r['weight'] is num)
            ? (r['weight'] as num).toDouble()
            : double.tryParse((r['weight'] ?? '').toString()) ?? 0;
        final sec = industryMap[code] ?? '其它';
        benchSectorWeight[sec] = (benchSectorWeight[sec] ?? 0) + w;
        benchTotalW += w;
      }
      if (benchTotalW > 0) {
        for (final k in benchSectorWeight.keys.toList()) {
          benchSectorWeight[k] = benchSectorWeight[k]! / benchTotalW * 100;
        }
      }

      // 组合行业权重（按市值）
      final portfolioSectorWeight = <String, double>{};
      double portfolioTotalMv = 0;
      for (final h in s.holdings) {
        final sec = h.sector.isEmpty ? '其它' : h.sector;
        portfolioSectorWeight[sec] =
            (portfolioSectorWeight[sec] ?? 0) + h.marketValue;
        portfolioTotalMv += h.marketValue;
      }
      if (portfolioTotalMv > 0) {
        for (final k in portfolioSectorWeight.keys.toList()) {
          portfolioSectorWeight[k] =
              portfolioSectorWeight[k]! / portfolioTotalMv * 100;
        }
      }

      // 行业收益率：组合内每行业用持仓加权累计收益；基准内每行业用基准成分加权累计收益
      double cumReturn(List<CandlePoint> cs) {
        if (cs.length < 2) return 0;
        final first = cs.first.close;
        final last = cs.last.close;
        if (first <= 0) return 0;
        return (last - first) / first;
      }

      // 组合每行业收益 = Σ(stock_mv × stock_return) / Σ stock_mv
      final portfolioSectorReturn = <String, double>{};
      final portfolioSectorMvByIdx = <String, double>{};
      for (final h in s.holdings) {
        final sec = h.sector.isEmpty ? '其它' : h.sector;
        final r = cumReturn(histories[h.symbol] ?? const []);
        portfolioSectorReturn[sec] =
            (portfolioSectorReturn[sec] ?? 0) + r * h.marketValue;
        portfolioSectorMvByIdx[sec] =
            (portfolioSectorMvByIdx[sec] ?? 0) + h.marketValue;
      }
      for (final k in portfolioSectorReturn.keys.toList()) {
        final mv = portfolioSectorMvByIdx[k] ?? 0;
        portfolioSectorReturn[k] = mv == 0 ? 0 : portfolioSectorReturn[k]! / mv;
      }

      // 基准每行业收益 ≈ 直接用申万一级行业指数对应行业的累计收益（更稳健）
      // 我们用 _swReturns 当前已加载的 1Y 数据（如已加载完毕）
      final benchSectorReturn = <String, double>{
        for (final r in _swReturns) r.name: r.ret
      };

      // 行业映射：tushare stock_basic 的 industry 命名 ≠ 申万一级名称，部分会缺失
      // 缺失的行业用 0 或所有行业平均替代
      final allSectors = <String>{
        ...benchSectorWeight.keys,
        ...portfolioSectorWeight.keys,
      };

      double allocation = 0, selection = 0, interaction = 0;
      final perSector = <_BrinsonSector>[];
      // 大盘（基准）整体收益（加权平均）
      double benchOverall = 0;
      for (final sec in benchSectorWeight.keys) {
        final wb = (benchSectorWeight[sec] ?? 0) / 100;
        final rb = benchSectorReturn[sec] ?? 0;
        benchOverall += wb * rb;
      }
      for (final sec in allSectors) {
        final wp = (portfolioSectorWeight[sec] ?? 0) / 100;
        final wb = (benchSectorWeight[sec] ?? 0) / 100;
        final rp = portfolioSectorReturn[sec] ?? 0;
        final rb = benchSectorReturn[sec] ?? 0;
        final alloc = (wp - wb) * (rb - benchOverall);
        final sel = wb * (rp - rb);
        final inter = (wp - wb) * (rp - rb);
        allocation += alloc;
        selection += sel;
        interaction += inter;
        perSector.add(_BrinsonSector(
          sector: sec,
          wp: wp,
          wb: wb,
          rp: rp,
          rb: rb,
          allocation: alloc,
          selection: sel,
          interaction: inter,
        ));
      }
      perSector.sort((a, b) => (b.allocation + b.selection + b.interaction)
          .compareTo(a.allocation + a.selection + a.interaction));

      if (!mounted) return;
      setState(() {
        _brinson = _BrinsonResult(
          allocation: allocation,
          selection: selection,
          interaction: interaction,
          perSector: perSector,
        );
        _loadingBrinson = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _brinsonError = e.toString();
        _loadingBrinson = false;
      });
    }
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}'
      '${d.month.toString().padLeft(2, '0')}'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final ps = context.watch<PortfolioState>();
    final s = ps.currentSummary;
    if (s == null || s.holdings.isEmpty) {
      return const _Empty(message: '加入品种后这里会展示行业分布和子板块的贡献。');
    }

    final fmt = NumberFormat('#,##0.00');
    final sectorWeights = s.sectorWeights;
    final pnlBySector = <String, double>{};
    for (final h in s.holdings) {
      pnlBySector.update(h.sector.isEmpty ? '其它' : h.sector,
          (v) => v + h.unrealizedPnl,
          ifAbsent: () => h.unrealizedPnl);
    }
    final pnlEntries = pnlBySector.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final byClass = <String, double>{};
    for (final h in s.holdings) {
      byClass.update(h.assetClass.isEmpty ? '其它' : h.assetClass,
          (v) => v + h.marketValue,
          ifAbsent: () => h.marketValue);
    }
    final classEntries = byClass.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([_loadSw(), _computeBrinson()]);
      },
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle('行业市值占比'),
                  const SizedBox(height: 8),
                  SectorDonut(weights: sectorWeights),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle('行业盈亏贡献'),
                  const SizedBox(height: 6),
                  for (final e in pnlEntries)
                    _BarRow(
                      label: e.key,
                      valueText:
                          '${e.value >= 0 ? "+" : "-"}${fmt.format(e.value.abs())}',
                      fraction: _scale(pnlBySector.values, e.value.abs()),
                      color: e.value >= 0
                          ? AppColors.positive
                          : AppColors.negative,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle('资产类别'),
                  const SizedBox(height: 6),
                  for (final e in classEntries)
                    _BarRow(
                      label: e.key,
                      valueText: fmt.format(e.value),
                      fraction: e.value /
                          (s.totalMarketValue == 0 ? 1 : s.totalMarketValue),
                      color: sectorColorFor(e.key),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _swCard(),
          const SizedBox(height: 12),
          _brinsonCard(),
        ],
      ),
    );
  }

  Widget _swCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle('申万一级行业 · 近 1 年累计涨跌幅'),
            const SizedBox(height: 8),
            if (_loadingSw)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_swError != null)
              Text('行业涨跌数据加载失败，请稍后再试',
                  style: TextStyle(
                      color: AppColors.textTertiary, fontSize: 11))
            else if (_swReturns.isEmpty)
              Text('暂无数据',
                  style: TextStyle(
                      color: AppColors.textTertiary, fontSize: 11))
            else
              _SwBars(items: _swReturns),
          ],
        ),
      ),
    );
  }

  Widget _brinsonCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SectionTitle('Brinson 归因（vs 沪深 300）'),
            const SizedBox(height: 6),
            if (_loadingBrinson)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_brinsonError != null)
              Text('归因数据加载失败，请稍后再试',
                  style: TextStyle(
                      color: AppColors.textTertiary, fontSize: 11))
            else if (_brinson == null)
              Text('暂无数据',
                  style: TextStyle(
                      color: AppColors.textTertiary, fontSize: 11))
            else
              _BrinsonView(b: _brinson!),
          ],
        ),
      ),
    );
  }

  static double _scale(Iterable<double> values, double v) {
    final maxAbs =
        values.fold<double>(0, (m, x) => x.abs() > m ? x.abs() : m);
    if (maxAbs == 0) return 0;
    return v / maxAbs;
  }
}

class _SwReturn {
  const _SwReturn({required this.code, required this.name, required this.ret});
  final String code;
  final String name;
  final double ret;
}

class _SwBars extends StatelessWidget {
  const _SwBars({required this.items});
  final List<_SwReturn> items;
  @override
  Widget build(BuildContext context) {
    final maxAbs =
        items.fold<double>(0, (m, e) => math.max(m, e.ret.abs()));
    return Column(
      children: [
        for (final i in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.5),
            child: Row(
              children: [
                SizedBox(
                  width: 70,
                  child: Text(i.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700)),
                ),
                Expanded(
                  child: _DivergeBar(value: i.ret, maxAbs: maxAbs),
                ),
                SizedBox(
                  width: 56,
                  child: Text(
                    '${i.ret >= 0 ? '+' : ''}${(i.ret * 100).toStringAsFixed(1)}%',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        color: i.ret >= 0
                            ? AppColors.positive
                            : AppColors.negative,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w800,
                        fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DivergeBar extends StatelessWidget {
  const _DivergeBar({required this.value, required this.maxAbs});
  final double value;
  final double maxAbs;

  @override
  Widget build(BuildContext context) {
    if (maxAbs == 0) return const SizedBox(height: 8);
    final fraction = value.abs() / maxAbs;
    return SizedBox(
      height: 10,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.center,
            child: Container(width: 1, color: AppColors.borderDim),
          ),
          Align(
            alignment:
                value >= 0 ? Alignment.centerLeft : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              alignment: value >= 0
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: fraction,
                alignment: value >= 0
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  height: 6,
                  color: value >= 0
                      ? AppColors.positive
                      : AppColors.negative,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrinsonResult {
  const _BrinsonResult({
    required this.allocation,
    required this.selection,
    required this.interaction,
    required this.perSector,
  });
  final double allocation;
  final double selection;
  final double interaction;
  final List<_BrinsonSector> perSector;

  double get total => allocation + selection + interaction;
}

class _BrinsonSector {
  const _BrinsonSector({
    required this.sector,
    required this.wp,
    required this.wb,
    required this.rp,
    required this.rb,
    required this.allocation,
    required this.selection,
    required this.interaction,
  });
  final String sector;
  final double wp; // 0..1
  final double wb;
  final double rp;
  final double rb;
  final double allocation;
  final double selection;
  final double interaction;
  double get contribution => allocation + selection + interaction;
}

class _BrinsonView extends StatelessWidget {
  const _BrinsonView({required this.b});
  final _BrinsonResult b;

  @override
  Widget build(BuildContext context) {
    String pct(double v) =>
        '${v >= 0 ? '+' : ''}${(v * 100).toStringAsFixed(2)}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            _kv('配置效应', pct(b.allocation),
                color: b.allocation >= 0
                    ? AppColors.positive
                    : AppColors.negative),
            _kv('选股效应', pct(b.selection),
                color: b.selection >= 0
                    ? AppColors.positive
                    : AppColors.negative),
            _kv('交互效应', pct(b.interaction),
                color: b.interaction >= 0
                    ? AppColors.positive
                    : AppColors.negative),
            _kv('合计超额', pct(b.total),
                color: b.total >= 0
                    ? AppColors.positive
                    : AppColors.negative),
          ],
        ),
        const SizedBox(height: 8),
        Text('行业拆解（按合计贡献排序）',
            style: TextStyle(
                color: AppColors.textTertiary, fontSize: 10)),
        const SizedBox(height: 4),
        Container(
          color: AppColors.bgBase,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Column(
            children: [
              const Row(
                children: [
                  SizedBox(width: 80, child: _Hd('行业')),
                  SizedBox(width: 50, child: _Hd('Wp')),
                  SizedBox(width: 50, child: _Hd('Wb')),
                  SizedBox(width: 56, child: _Hd('Rp')),
                  SizedBox(width: 56, child: _Hd('Rb')),
                  SizedBox(width: 56, child: _Hd('合计')),
                ],
              ),
              Divider(color: AppColors.borderDim, height: 6),
              for (final s in b.perSector.take(15))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(
                          width: 80,
                          child: Text(s.sector,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 10))),
                      SizedBox(
                          width: 50,
                          child: Text(
                              (s.wp * 100).toStringAsFixed(1),
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 10,
                                  fontFamily: 'monospace'))),
                      SizedBox(
                          width: 50,
                          child: Text(
                              (s.wb * 100).toStringAsFixed(1),
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 10,
                                  fontFamily: 'monospace'))),
                      SizedBox(
                          width: 56,
                          child: Text(
                              (s.rp * 100).toStringAsFixed(1),
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 10,
                                  fontFamily: 'monospace'))),
                      SizedBox(
                          width: 56,
                          child: Text(
                              (s.rb * 100).toStringAsFixed(1),
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 10,
                                  fontFamily: 'monospace'))),
                      SizedBox(
                          width: 56,
                          child: Text(
                              (s.contribution * 100).toStringAsFixed(2),
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  color: s.contribution >= 0
                                      ? AppColors.positive
                                      : AppColors.negative,
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w800))),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _kv(String label, String value, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label：',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
        Text(value,
            style: TextStyle(
                color: color ?? AppColors.textPrimary,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w800,
                fontSize: 12)),
      ],
    );
  }
}

class _Hd extends StatelessWidget {
  const _Hd(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      textAlign: TextAlign.right,
      style: TextStyle(
          color: AppColors.textTertiary,
          fontSize: 9.5,
          fontWeight: FontWeight.w800));
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: const TextStyle(
            color: AppColors.amber,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6));
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insights, color: AppColors.amber, size: 36),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.label,
    required this.valueText,
    required this.fraction,
    required this.color,
  });

  final String label;
  final String valueText;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final f = fraction.isNaN || fraction <= 0 ? 0.0 : fraction.clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: TextStyle(
                        color: AppColors.textPrimary, fontSize: 11)),
              ),
              Text(valueText,
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace')),
            ],
          ),
          const SizedBox(height: 4),
          Container(
            height: 4,
            color: AppColors.bgBase,
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: f.toDouble(),
              child: Container(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
