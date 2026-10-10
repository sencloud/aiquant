import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/require_login.dart';
import '../../models/falsification.dart';
import '../../services/analytics.dart';
import '../../services/falsification_service.dart';
import '../../state/auth_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import 'falsification_detail_screen.dart';
import 'live_strategy_screen.dart';

/// 证伪台 —— 「策略」页签的主内容。
///
/// 定位来自本机 alpha-radar 工程（策略证伪器）：**它不是策略生成器，是策略
/// 证伪器。** 量化研究里 90% 的工作量在否定而不是发现，所以第一屏不摆曲线，
/// 只回答一个问题：**这套策略能不能实盘。**
///
/// 版式顺序就是闸门顺序：先用「往返成本 ÷ 平均振幅」把尺度不对的直接淘汰
/// （这一步能省掉后面所有工作），再让策略去过样本 / 分年 / 回撤 / 参数稳健性
/// 四道闸门。任何一条不过，结论就写「不行」，并把「为什么不行」写清楚。
///
/// 本页不要求登录：证伪结论本身就是内容，没有理由藏在登录后面。
class StrategyScreen extends StatefulWidget {
  const StrategyScreen({super.key});

  @override
  State<StrategyScreen> createState() => _StrategyScreenState();
}

class _StrategyScreenState extends State<StrategyScreen> {
  final FalsificationService _svc = FalsificationService();

  FalsificationData? _data;
  String? _error;
  bool _loading = true;

  /// 成本尺当前选中的品种 / 周期；null 表示用数据里的第一项。
  String? _symbol;
  String? _freq;

  @override
  void initState() {
    super.initState();
    // ignore: unawaited_futures
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    try {
      final data = await _svc.load();
      if (!mounted) return;
      setState(() {
        _data = data;
        _error = null;
        _loading = false;
      });
      Analytics.instance
          .track(Analytics.evFalsificationView, {'origin': _svc.origin});
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
    final data = _data;
    return WkPage(
      title: '证伪台',
      actions: [
        IconButton(
          tooltip: '这个页面在做什么',
          icon: const Icon(Icons.help_outline, size: 20),
          onPressed: data == null ? null : () => _showAbout(data),
        ),
      ],
      child: _body(data),
    );
  }

  Widget _body(FalsificationData? data) {
    if (_loading && data == null) {
      return const Center(
        child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (data == null) {
      return RefreshIndicator(
        color: AppColors.amber,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.xl),
          children: [
            const SizedBox(height: 64),
            WkEmpty(
              icon: Icons.rule_folder_outlined,
              title: '证伪档案读取失败',
              hint: _error,
              action: OutlinedButton(onPressed: _load, child: const Text('重试')),
            ),
          ],
        ),
      );
    }

    final symbol = _currentSymbol(data);
    final rows = [for (final r in data.scales) if (r.symbol == symbol) r];
    final freq = _currentFreq(rows);
    final row = rows.firstWhere((r) => r.freq == freq, orElse: () => rows.first);

    return RefreshIndicator(
      color: AppColors.amber,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter, AppSpace.lg, AppSpace.gutter, AppSpace.xxl),
        children: [
          _VerdictHero(summary: data.summary, generatedAt: data.generatedAt),
          const SizedBox(height: AppSpace.lg),
          _CostRuler(
            symbols: _symbolsOf(data),
            names: _namesOf(data),
            symbol: symbol,
            rows: rows,
            freq: freq,
            row: row,
            onSymbol: (s) => setState(() {
              _symbol = s;
              _freq = null;
            }),
            onFreq: (f) {
              setState(() => _freq = f);
              Analytics.instance.track(Analytics.evCostRuler, {
                'symbol': row.symbol,
                'freq': f,
                'ratio_pct': ((rows.firstWhere((r) => r.freq == f,
                                orElse: () => row).ratio) *
                        100)
                    .toStringAsFixed(1),
                'verdict': rows
                    .firstWhere((r) => r.freq == f, orElse: () => row)
                    .verdict,
              });
            },
          ),
          const SizedBox(height: AppSpace.lg),
          _GateCard(gates: data.gates, onTap: _showGate),
          const SizedBox(height: AppSpace.lg),
          _ArchiveCard(entries: data.archive, onTap: _openEntry),
          const SizedBox(height: AppSpace.lg),
          _LiveEntry(
            onTap: () async {
              Analytics.instance.track(Analytics.evLiveEntry);
              if (!context.read<AuthState>().isAuthenticated) {
                final ok = await requireLogin(context);
                if (!ok || !mounted) return;
              }
              if (!mounted) return;
              await Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const LiveStrategyScreen(),
              ));
            },
          ),
          const SizedBox(height: AppSpace.lg),
          WkNote(
            title: '口径',
            text: '${data.source.costModel}\n\n数据：${data.source.data}'
                '\n生成时间：${data.generatedAt}',
          ),
          const SizedBox(height: AppSpace.md),
          const WkNote(
            text: '本页是研究结论，不是投资建议。回测不含冲击成本、涨跌停无法成交、'
                '盘中流动性枯竭等实盘约束；历史表现不代表未来收益。',
          ),
        ],
      ),
    );
  }

  // ── 选择逻辑 ─────────────────────────────────────────────────────────

  List<String> _symbolsOf(FalsificationData data) {
    final out = <String>[];
    for (final s in data.scales) {
      if (!out.contains(s.symbol)) out.add(s.symbol);
    }
    return out;
  }

  String _currentSymbol(FalsificationData data) {
    final all = _symbolsOf(data);
    return (_symbol != null && all.contains(_symbol)) ? _symbol! : all.first;
  }

  String _currentFreq(List<CostScale> rows) {
    if (_freq != null && rows.any((r) => r.freq == _freq)) return _freq!;
    return rows.first.freq;
  }

  /// 品种代码 → 中文名（同一品种的各周期行里取第一个非空名字）。
  Map<String, String> _namesOf(FalsificationData data) {
    final out = <String, String>{};
    for (final s in data.scales) {
      final n = out[s.symbol];
      if (n == null || n == s.symbol) {
        out[s.symbol] = s.name.isEmpty ? s.symbol : s.name;
      }
    }
    return out;
  }

  // ── 弹层 ─────────────────────────────────────────────────────────────

  void _showAbout(FalsificationData data) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.xl, 0, AppSpace.xl, AppSpace.xxl),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('这个页面在做什么',
                  style: AppType.title.copyWith(color: AppColors.textPrimary)),
              const SizedBox(height: AppSpace.md),
              Text(
                '${data.source.project}\n\n${data.source.what}\n\n'
                '${data.source.notWhat}',
                style: AppType.read.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpace.lg),
              Text('判定顺序',
                  style:
                      AppType.section.copyWith(color: AppColors.textPrimary)),
              const SizedBox(height: AppSpace.sm),
              for (final g in data.gates)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.sm),
                  child: Text('${g.name}：${g.rule}',
                      style: AppType.body
                          .copyWith(color: AppColors.textSecondary)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showGate(FalsificationGate gate) {
    Analytics.instance.track(Analytics.evGateOpen, {'gate': gate.id});
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.xl, 0, AppSpace.xl, AppSpace.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(gate.name,
                style: AppType.title.copyWith(color: AppColors.textPrimary)),
            const SizedBox(height: AppSpace.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.md, vertical: AppSpace.sm),
              decoration: BoxDecoration(
                color: AppColors.accentSoft,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(gate.rule,
                  style: AppType.body.copyWith(
                      color: AppColors.amberDim,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: AppSpace.lg),
            Text(gate.why,
                style: AppType.read.copyWith(color: AppColors.textSecondary)),
            if (gate.verdict.isNotEmpty) ...[
              const SizedBox(height: AppSpace.md),
              Text(gate.verdict,
                  style: AppType.body.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600)),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openEntry(ArchiveEntry e) async {
    Analytics.instance
        .track(Analytics.evArchiveOpen, {'id': e.id, 'verdict': e.verdict});
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FalsificationDetailScreen(entry: e),
    ));
  }
}

/// 第一屏的结论：一句话 + 一行计数。刻意不做「大数字 + 小标签 + 若干统计块」
/// 那套模板 —— 这里的结论是一句判断，不是一组指标。
class _VerdictHero extends StatelessWidget {
  const _VerdictHero({required this.summary, required this.generatedAt});

  final FalsificationSummary summary;
  final String generatedAt;

  static const _cn = ['零', '一', '二', '三', '四', '五', '六', '七', '八',
      '九', '十', '十一', '十二'];

  static String spell(int n) => n < _cn.length ? _cn[n] : '$n';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${spell(summary.archiveTotal)}条记录，'
            '${spell(summary.tradable)}条可以实盘。',
            style: AppType.display.copyWith(
                fontSize: 24, height: 1.35, color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            '${summary.archiveRejected} 条已证伪 · '
            '${summary.archivePending} 条方向对但样本不足 · '
            '${summary.findings} 条是单点结论',
            style: AppType.caption.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpace.md),
          const Divider(),
          const SizedBox(height: AppSpace.md),
          Text(
            '这个页面只做一件事：证明什么不行。'
            '样本不足就写样本不足，单年依赖就写单年依赖 —— 不把「可能有效」'
            '说成「有效」。',
            style: AppType.read.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpace.md),
          Text('档案生成于 $generatedAt',
              style: AppType.micro.copyWith(color: AppColors.textTertiary)),
        ],
      ),
    );
  }
}

/// 尺度闸门 · 成本尺：把「往返成本」和「平均振幅」画成两条可比的横杠。
///
/// 这是本页的签名交互：换品种、换周期，两条杠一起变，占比和判定立刻跟着变。
/// 它把一句话讲清楚 —— 周期越短，成本吃的比例越大，1 分钟直接吃掉一半以上。
class _CostRuler extends StatelessWidget {
  const _CostRuler({
    required this.symbols,
    required this.names,
    required this.symbol,
    required this.rows,
    required this.freq,
    required this.row,
    required this.onSymbol,
    required this.onFreq,
  });

  final List<String> symbols;
  final Map<String, String> names;
  final String symbol;
  final List<CostScale> rows;
  final String freq;
  final CostScale row;
  final ValueChanged<String> onSymbol;
  final ValueChanged<String> onFreq;

  Color get _tone => switch (row.verdict) {
        'pass' => AppColors.negative,
        'marginal' => AppColors.warning,
        _ => AppColors.danger,
      };

  String get _verdictLine => switch (row.verdict) {
        'pass' => '尺度这关过了，后面的闸门才轮得到它。',
        'marginal' => '留在观察名单，但别指望它。',
        _ => '直接淘汰：成本吃掉一半以上的振幅，等于给交易所打工。',
      };

  @override
  Widget build(BuildContext context) {
    final denom = row.amplitude <= 0 ? 1.0 : row.amplitude;
    final costFrac = (row.cost / denom).clamp(0.0, 1.0);

    return WkGroup(
      header: '尺度闸门 · 成本 ÷ 振幅',
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('一笔往返要付的成本，占这根 K 线平均振幅的多少。'
                  '超过 25% 不做。',
                  style:
                      AppType.caption.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: AppSpace.md),
              _ChoiceRow(
                values: symbols,
                selected: symbol,
                labels: names,
                onSelect: onSymbol,
              ),
              const SizedBox(height: AppSpace.sm),
              _ChoiceRow(
                values: [for (final r in rows) r.freq],
                selected: freq,
                labels: {for (final r in rows) r.freq: _freqLabel(r.freq)},
                onSelect: onFreq,
              ),
              const SizedBox(height: AppSpace.lg),
              _Bar(
                label: '往返成本',
                value: '${_fmt(row.cost)} 点',
                fraction: costFrac,
                color: _tone,
              ),
              const SizedBox(height: AppSpace.sm),
              _Bar(
                label: '平均振幅',
                value: '${_fmt(row.amplitude)} 点',
                fraction: 1,
                // 振幅是基准线，不是主角：用纸色的深一档，让成本那条跳出来。
                color: AppColors.borderMed,
              ),
              const SizedBox(height: AppSpace.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${(row.ratio * 100).toStringAsFixed(1)}%',
                      style: AppType.display.copyWith(
                          fontSize: 30, color: _tone)),
                  const SizedBox(width: AppSpace.md),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: WkTag(row.verdictLabel, tone: _tone, filled: true),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              Text(_verdictLine,
                  style: AppType.body.copyWith(color: AppColors.textPrimary)),
              const SizedBox(height: AppSpace.md),
              Text(
                row.note,
                style: AppType.micro
                    .copyWith(color: AppColors.textTertiary, height: 1.6),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _freqLabel(String f) =>
      f == '1d' ? '日线' : f.replaceAll('min', ' 分');

  static String _fmt(double v) =>
      v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
}

/// 可选中的一行 chip（横向滚动，不换行）。
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.values,
    required this.selected,
    required this.labels,
    required this.onSelect,
  });

  final List<String> values;
  final String selected;
  final Map<String, String> labels;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: values.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpace.sm),
        itemBuilder: (_, i) {
          final v = values[i];
          final active = v == selected;
          return GestureDetector(
            onTap: () => onSelect(v),
            child: Container(
              alignment: Alignment.center,
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpace.md),
              decoration: BoxDecoration(
                color: active ? AppColors.accentSoft : AppColors.bgRaised,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                    color: active
                        ? AppColors.amber.withValues(alpha: 0.35)
                        : Colors.transparent),
              ),
              child: Text(
                labels[v] ?? v,
                style: AppType.caption.copyWith(
                  color: active ? AppColors.amberDim : AppColors.textSecondary,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 一条比较横杠：底色是纸，长度按比例填主色。
class _Bar extends StatelessWidget {
  const _Bar({
    required this.label,
    required this.value,
    required this.fraction,
    required this.color,
  });

  final String label;
  final String value;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 60,
          child: Text(label,
              style: AppType.micro.copyWith(color: AppColors.textTertiary)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: Container(
              height: 10,
              color: AppColors.bgRaised,
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: fraction <= 0 ? 0.02 : fraction,
                child: Container(color: color),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 84,
          child: Text(value,
              textAlign: TextAlign.right,
              style: AppType.caption.copyWith(
                color: AppColors.textPrimary,
                fontFamilyFallback: AppType.numericFallback,
              )),
        ),
      ],
    );
  }
}

/// 五道闸门：方法本身就是内容，直接铺开，不折叠。
class _GateCard extends StatelessWidget {
  const _GateCard({required this.gates, required this.onTap});

  final List<FalsificationGate> gates;
  final ValueChanged<FalsificationGate> onTap;

  @override
  Widget build(BuildContext context) {
    return WkGroup(
      header: '五道闸门',
      footer: '任何一条不过，结论就写「不行」，并写清为什么不行 —— '
          '失败的结论比找到一个能用的更有价值。',
      children: [
        for (final g in gates)
          WkRow(
            title: g.name,
            subtitle: g.rule,
            onTap: () => onTap(g),
          ),
      ],
    );
  }
}

/// 证伪档案：一行一条结论。
class _ArchiveCard extends StatelessWidget {
  const _ArchiveCard({required this.entries, required this.onTap});

  final List<ArchiveEntry> entries;
  final ValueChanged<ArchiveEntry> onTap;

  Color _tone(String verdict) => switch (verdict) {
        'reject' => AppColors.danger,
        'pending' => AppColors.warning,
        _ => AppColors.textSecondary,
      };

  @override
  Widget build(BuildContext context) {
    return WkGroup(
      header: '证伪档案',
      footer: '每条都附了可复现命令。结论改口径重跑，数字要对得上。',
      children: [
        for (final e in entries)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onTap(e),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.lg, vertical: AppSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(e.strategy,
                              style: AppType.body.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: AppSpace.sm),
                        WkTag(e.verdictLabel,
                            tone: _tone(e.verdict), filled: true),
                        const SizedBox(width: AppSpace.xs),
                        Icon(Icons.chevron_right,
                            size: 20, color: AppColors.textTertiary),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(e.headline,
                        style: AppType.read.copyWith(
                            fontSize: 14,
                            height: 1.6,
                            color: AppColors.textSecondary)),
                    const SizedBox(height: 5),
                    Text(e.few,
                        style: AppType.micro.copyWith(
                            color: AppColors.textTertiary,
                            fontFamilyFallback: AppType.numericFallback)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 实盘策略入口：需要登录，所以放在证伪结论之后而不是之前。
class _LiveEntry extends StatelessWidget {
  const _LiveEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final authed = context.watch<AuthState>().isAuthenticated;
    return WkGroup(
      children: [
        WkRow(
          icon: Icons.account_balance_wallet_outlined,
          title: '在跑的实盘策略',
          subtitle: authed
              ? '上证50 九因子 · 月度调仓 · 本期要不要动手'
              : '上证50 九因子 · 月度调仓（登录后查看持仓与指令）',
          onTap: onTap,
        ),
      ],
    );
  }
}
