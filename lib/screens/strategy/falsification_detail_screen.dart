import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/auth/require_login.dart';
import '../../models/falsification.dart';
import '../../services/analytics.dart';
import '../../services/falsification_service.dart';
import '../../state/auth_state.dart';
import '../../state/billing_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import 'archive_widgets.dart';
import 'falsify_run_screen.dart';
import 'paywall.dart';

/// 一条证伪记录的详情。
///
/// 免费层：结论 → 死在哪一关 → 关键数字 → 五道闸门结果。证伪结论本身就是
/// 内容，不藏。
/// 付费层（每条 5 喜点，解锁一次永久可看）：分年盈亏、为什么是这个结论
/// （手写机制）、怎么复现（命令）。扣费在服务端完成，幂等，重复点不重复扣。
class FalsificationDetailScreen extends StatefulWidget {
  const FalsificationDetailScreen({
    super.key,
    required this.entry,
    this.service,
  });

  final ArchiveEntry entry;
  final FalsificationService? service;

  @override
  State<FalsificationDetailScreen> createState() =>
      _FalsificationDetailScreenState();
}

class _FalsificationDetailScreenState extends State<FalsificationDetailScreen> {
  late final FalsificationService _svc =
      widget.service ?? FalsificationService.shared;
  late ArchiveEntry _entry = widget.entry;

  /// 服务端确认过已解锁。本地打包的档案里即使带了付费字段，也只在解锁后展示。
  bool _unlocked = false;
  bool _checking = false;
  bool _busy = false;

  int get _price => _svc.cached?.prices.unlock ?? 5;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkUnlocked());
  }

  Future<void> _checkUnlocked() async {
    if (!mounted || !context.read<AuthState>().isAuthenticated) return;
    if (!_entry.hasPaidContent) return;
    setState(() => _checking = true);
    try {
      final full = await _svc.detail(_entry.id);
      if (!mounted) return;
      setState(() {
        if (!full.locked) {
          _entry = _entry.mergedWith(full);
          _unlocked = true;
        }
      });
    } catch (_) {
      // 查不到就按未解锁处理：点解锁时服务端会幂等判断，不会重复扣费。
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _unlock() async {
    if (_busy) return;
    if (!context.read<AuthState>().isAuthenticated) {
      final ok = await requireLogin(context);
      if (!ok || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final r = await _svc.unlock(_entry.id);
      if (!mounted) return;
      Analytics.instance.track(
          Analytics.evArchiveUnlock, {'id': _entry.id, 'charged': r.charged});
      setState(() {
        _entry = _entry.mergedWith(r.entry);
        _unlocked = true;
      });
      // ignore: unawaited_futures
      context.read<BillingState>().refreshBalance();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.charged > 0
            ? '已解锁，扣 ${r.charged} 喜点${r.balance == null ? '' : '，余额 ${r.balance}'}'
            : '之前已解锁，未重复扣费'),
      ));
    } catch (e) {
      if (!mounted) return;
      final api = asApiException(e);
      if (api?.code == 'FALSIFICATION.INSUFFICIENT_BALANCE') {
        await showInsufficientBalance(context, need: _price, what: '解锁这条档案');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(api?.message ?? '解锁失败，请稍后再试'),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rerun() async {
    if (!context.read<AuthState>().isAuthenticated) {
      final ok = await requireLogin(context);
      if (!ok || !mounted) return;
    }
    if (!mounted) return;
    Analytics.instance.track(Analytics.evFalsifyRunOpen, {'from': _entry.id});
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          FalsifyRunScreen(service: _svc, strategy: _entry.strategy),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    final tone = verdictColor(entry.verdict);
    final gates = _svc.cached?.gates ?? const <FalsificationGate>[];
    final failed = entry.failedGateName(gates);
    final showPaid = _unlocked;

    return WkPage(
      title: entry.strategy,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter, AppSpace.lg, AppSpace.gutter, AppSpace.xxl),
        children: [
          Row(
            children: [
              WkTag(entry.verdictLabel, tone: tone, filled: true),
              const SizedBox(width: AppSpace.sm),
              if (entry.family.isNotEmpty) WkTag(entry.family),
              if (entry.needsRerun) ...[
                const SizedBox(width: AppSpace.sm),
                const WkTag('待重判', tone: AppColors.amber),
              ],
              const Spacer(),
              Text(
                  [
                    if (entry.name.isNotEmpty) entry.name,
                    entry.symbol,
                    freqLabel(entry.freq),
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: AppType.micro.copyWith(
                      color: AppColors.textTertiary,
                      fontFamilyFallback: AppType.numericFallback)),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          Text(entry.headline,
              style: AppType.display.copyWith(
                  fontSize: 22, height: 1.5, color: AppColors.textPrimary)),
          if (failed.isNotEmpty && entry.verdict == 'reject') ...[
            const SizedBox(height: AppSpace.sm),
            Text('死在：$failed',
                style: AppType.body
                    .copyWith(color: tone, fontWeight: FontWeight.w600)),
          ],
          if (entry.verdict == 'insufficient' &&
              entry.insufficientReason.startsWith('data:')) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
                '样本不足：${ArchiveEntry.gateNameOf(entry.insufficientReason.substring(5))}所需数据缺失，暂时判不了',
                style: AppType.caption.copyWith(color: AppColors.warning)),
          ],
          if (entry.source.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Text('策略出处：${entry.source}',
                style: AppType.caption.copyWith(color: AppColors.textTertiary)),
          ],
          if (entry.origin.isNotEmpty) ...[
            const SizedBox(height: AppSpace.xs),
            Text(entry.origin,
                style: AppType.caption.copyWith(color: AppColors.textTertiary)),
          ],
          if (entry.needsRerun && entry.rerunNote.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            WkNote(title: '待重判', text: entry.rerunNote),
          ],
          const SizedBox(height: AppSpace.lg),
          _MetricsGrid(metrics: entry.metrics),
          if (entry.gateResults.isNotEmpty) ...[
            const SizedBox(height: AppSpace.lg),
            _GateResults(entry: entry, gates: gates),
          ],
          if (entry.hasPaidContent) ...[
            const SizedBox(height: AppSpace.lg),
            if (showPaid) ...[
              if (entry.yearly.isNotEmpty) ...[
                _YearlyCard(title: '分年盈亏', points: entry.yearly),
                const SizedBox(height: AppSpace.lg),
              ],
              if (entry.mechanism.trim().isNotEmpty) ...[
                WkGroup(
                  header: '为什么是这个结论',
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSpace.lg),
                      child: Text(entry.mechanism,
                          style: AppType.read
                              .copyWith(color: AppColors.textSecondary)),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.lg),
              ],
              if (entry.command.isNotEmpty)
                _CommandCard(command: entry.command),
            ] else
              _LockCard(
                price: _price,
                busy: _busy || _checking,
                onUnlock: _unlock,
              ),
          ],
          const SizedBox(height: AppSpace.lg),
          WkGroup(
            children: [
              WkRow(
                icon: Icons.replay_rounded,
                title: '换品种 / 周期再跑一次',
                subtitle: '同一套策略，换个品种或周期重新过五道闸门',
                onTap: _rerun,
              ),
            ],
          ),
          const WkNote(
            title: '口径',
            text: '含成本回测：期货每边 1 跳滑点 + 双边手续费；A 股佣金 + 卖出'
                '印花税 + 最低 5 元，并强制 T+1。分年结果是必报项 —— 只报总收益'
                '的策略在这里一律不算数。',
          ),
        ],
      ),
    );
  }
}

/// 付费层的锁：说清楚里面有什么、多少钱，一个按钮。
class _LockCard extends StatelessWidget {
  const _LockCard({
    required this.price,
    required this.busy,
    required this.onUnlock,
  });

  final int price;
  final bool busy;
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return WkGroup(
      header: '研究细节',
      footer: '解锁一次永久可看；重复解锁不会重复扣费。',
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final t in const [
                ('分年盈亏', '每一年赚还是亏 —— 看「有效」是不是只来自某一年'),
                ('为什么是这个结论', '手写的机制分析：它为什么不行'),
                ('怎么复现', '一条命令跑回同样的结论'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lock_outline_rounded,
                          size: 16, color: AppColors.textTertiary),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(
                        child: Text.rich(TextSpan(children: [
                          TextSpan(
                              text: '${t.$1}  ',
                              style: AppType.body.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600)),
                          TextSpan(
                              text: t.$2,
                              style: AppType.caption
                                  .copyWith(color: AppColors.textTertiary)),
                        ])),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpace.xs),
              WkPrimaryButton(
                label: '$price 喜点解锁',
                icon: Icons.lock_open_rounded,
                busy: busy,
                onPressed: busy ? null : onUnlock,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 五道闸门的结果：每道一行，第一道没过的就是「死在哪一关」。
class _GateResults extends StatelessWidget {
  const _GateResults({required this.entry, required this.gates});

  final ArchiveEntry entry;
  final List<FalsificationGate> gates;

  static const _order = ['sample', 'scale', 'yearly', 'drawdown', 'robust'];

  @override
  Widget build(BuildContext context) {
    final ids = [
      for (final id in _order)
        if (entry.gateResults.containsKey(id)) id,
      for (final id in entry.gateResults.keys)
        if (!_order.contains(id)) id,
    ];
    return WkGroup(
      header: '五道闸门',
      footer: entry.thresholdVersion.isEmpty
          ? null
          : '阈值版本：${entry.thresholdVersion}',
      children: [
        for (final id in ids) _gateRow(id, entry.gateResults[id]!),
      ],
    );
  }

  Widget _gateRow(String id, GateResult r) {
    var name = ArchiveEntry.gateNameOf(id);
    for (final g in gates) {
      if (g.id == id) name = g.name;
    }
    final (label, color) = switch (r.status) {
      'pass' => ('通过', AppColors.info),
      'marginal' => ('勉强', AppColors.warning),
      'fail' => ('未过', AppColors.textSecondary),
      'review' => ('待人工复核', AppColors.amber),
      'unknown' => ('数据缺失', AppColors.textTertiary),
      'insufficient' => ('样本不足', AppColors.warning),
      'skip' => ('未检验', AppColors.textTertiary),
      _ => ('待验', AppColors.amber),
    };
    final detail = [
      if (r.value.isNotEmpty) r.value,
      if (r.threshold.isNotEmpty) '门槛 ${r.threshold}',
      if (r.note.isNotEmpty) r.note,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg, vertical: AppSpace.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: AppType.body.copyWith(
                        color: id == entry.failedGate
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        fontWeight: id == entry.failedGate
                            ? FontWeight.w600
                            : FontWeight.w400)),
                if (detail.isNotEmpty)
                  Text(detail,
                      style: AppType.caption.copyWith(
                          color: AppColors.textTertiary,
                          fontFamilyFallback: AppType.numericFallback)),
              ],
            ),
          ),
          WkTag(label, tone: color, filled: r.status == 'fail'),
        ],
      ),
    );
  }
}

/// 关键数字。四格排一行，窄屏自动换成两行。
class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.metrics});

  final ArchiveMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final cells = <Widget>[
      WkStat(
        value: metrics.trades == 0 ? '—' : '${metrics.trades}',
        label: '笔数',
      ),
      WkStat(
        value: metrics.pf == 0 ? '—' : metrics.pf.toStringAsFixed(3),
        label: 'PF 盈利因子',
        color: metrics.pf > 1 ? AppColors.positive : AppColors.negative,
      ),
      WkStat(
        value: metrics.avgPoints == 0
            ? '—'
            : '${metrics.avgPoints > 0 ? '+' : ''}'
                '${metrics.avgPoints.toStringAsFixed(2)}',
        label: '每手均点（含成本）',
        color: metrics.avgPoints >= 0 ? AppColors.positive : AppColors.negative,
      ),
      WkStat(
        value: metrics.years == 0
            ? '—'
            : '${metrics.positiveYears}/${metrics.years}',
        label: '正年数',
        color: metrics.years > 0 && metrics.positiveYears * 2 >= metrics.years
            ? AppColors.positive
            : AppColors.negative,
      ),
    ];
    return WkGroup(
      header: '关键数字',
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: LayoutBuilder(
            builder: (context, box) {
              // 固定两列：四个数挤在一行时，「1.050」这类五位数字会顶到格宽
              // 边界并折行，读起来像坏了。手机上两列本来就是更舒服的读法。
              const cols = 2;
              return Wrap(
                spacing: AppSpace.lg,
                runSpacing: AppSpace.lg,
                children: [
                  for (final c in cells)
                    SizedBox(
                        width: (box.maxWidth - AppSpace.lg * (cols - 1)) / cols,
                        child: c),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 分年柱：正红负绿（A 股惯例），长度按绝对值归一。
class _YearlyCard extends StatelessWidget {
  const _YearlyCard({required this.title, required this.points});

  final String title;
  final List<YearPnl> points;

  @override
  Widget build(BuildContext context) {
    final maxAbs =
        points.fold<double>(0, (m, p) => p.pnl.abs() > m ? p.pnl.abs() : m);
    final denom = maxAbs <= 0 ? 1.0 : maxAbs;

    return WkGroup(
      header: title,
      footer: '只看总收益没有意义：本工程的「有效」几乎全部来自单一年份。',
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            children: [
              for (final p in points)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.sm),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 42,
                        child: Text(p.year,
                            style: AppType.caption.copyWith(
                                color: AppColors.textSecondary,
                                fontFamilyFallback: AppType.numericFallback)),
                      ),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                          child: Container(
                            height: 12,
                            color: AppColors.bgRaised,
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor:
                                  (p.pnl.abs() / denom).clamp(0.02, 1.0),
                              child: Container(
                                color: p.pnl >= 0
                                    ? AppColors.positive
                                    : AppColors.negative,
                              ),
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 84,
                        child: Text(
                          '${p.pnl >= 0 ? '+' : '−'}'
                          '${p.pnl.abs().toStringAsFixed(0)}',
                          textAlign: TextAlign.right,
                          style: AppType.caption.copyWith(
                            color: p.pnl >= 0
                                ? AppColors.positive
                                : AppColors.negative,
                            fontFamilyFallback: AppType.numericFallback,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 可复现命令。能一条命令跑回来的结论，才值得相信。
class _CommandCard extends StatelessWidget {
  const _CommandCard({required this.command});

  final String command;

  @override
  Widget build(BuildContext context) {
    return WkGroup(
      header: '怎么复现',
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(
                  color: AppColors.bgRaised,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: SelectableText(
                  command,
                  style: AppType.caption.copyWith(
                    color: AppColors.textPrimary,
                    height: 1.6,
                    fontFamilyFallback: AppType.numericFallback,
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: command));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('命令已复制')),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('复制命令'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
