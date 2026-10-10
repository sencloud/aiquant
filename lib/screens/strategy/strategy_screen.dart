import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/require_login.dart';
import '../../models/falsification.dart';
import '../../models/falsification_index.dart';
import '../../services/analytics.dart';
import '../../services/falsification_service.dart';
import '../../state/auth_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import 'archive_list_screen.dart';
import 'archive_widgets.dart';
import 'falsification_detail_screen.dart';
import 'falsify_run_screen.dart';
import 'live_strategy_screen.dart';
import 'method_screen.dart';

/// 证伪档案 —— 「策略」页签的主内容，版式照微信「通讯录」。
///
/// 定位来自 alpha-radar（策略证伪器）：**它不是策略生成器，是策略证伪器。**
/// 首屏只做一件事：让人看到每条策略和它的证伪情况。
///
/// - 顶部：搜索（能搜到样本不足的条目）；
/// - 固定入口：可交易 / 仍在验证 / 本周新证伪 / 跑一次证伪（像「新的朋友」）；
/// - 精选档案（像「星标朋友」）；
/// - 按策略家族分组，右侧索引条可点跳转（像 A–Z）。
///
/// 方法论（结论总览、成本尺、五道闸门、口径）收进右上角「方法」。
/// 本页不要求登录：证伪结论本身就是内容；解锁细节和跑一次证伪才要登录。
class StrategyScreen extends StatefulWidget {
  const StrategyScreen({
    super.key,
    this.service,
    this.initialData,
    this.now,
  });

  /// 测试注入。
  final FalsificationService? service;
  final FalsificationData? initialData;
  final DateTime? now;

  @override
  State<StrategyScreen> createState() => _StrategyScreenState();
}

class _StrategyScreenState extends State<StrategyScreen> {
  late final FalsificationService _svc =
      widget.service ?? FalsificationService.shared;
  final _query = TextEditingController();
  final _scroll = ScrollController();
  final Map<String, GlobalKey> _anchors = {};

  FalsificationData? _data;
  ArchiveIndex? _index;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final seed = widget.initialData;
    if (seed != null) {
      _apply(seed);
      _loading = false;
    } else {
      // ignore: unawaited_futures
      _load();
    }
  }

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _apply(FalsificationData data) {
    _data = data;
    _index = ArchiveIndex.build(data.archive, now: widget.now);
  }

  Future<void> _load({bool force = false}) async {
    if (mounted) setState(() => _loading = true);
    try {
      final data = await _svc.load(force: force);
      if (!mounted) return;
      setState(() {
        _apply(data);
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
      title: '证伪档案',
      actions: [
        TextButton(
          onPressed: data == null ? null : () => _openMethod(data),
          child: const Text('方法'),
        ),
      ],
      child: _body(data),
    );
  }

  Widget _body(FalsificationData? data) {
    final index = _index;
    if (_loading && data == null) {
      return const Center(
        child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (data == null || index == null) {
      return RefreshIndicator(
        color: AppColors.amber,
        onRefresh: () => _load(force: true),
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.xl),
          children: [
            const SizedBox(height: 64),
            WkEmpty(
              icon: Icons.rule_folder_rounded,
              title: '证伪档案读取失败',
              hint: _error,
              action: OutlinedButton(
                  onPressed: () => _load(force: true), child: const Text('重试')),
            ),
          ],
        ),
      );
    }

    final searching = _query.text.trim().isNotEmpty;
    // (显示的字, 锚点)：锚点用完整家族名，避免两个家族首字相同时撞车。
    final labels = <(String, String)>[
      if (index.curated.isNotEmpty) ('★', '★'),
      for (final s in index.sections) (s.label, s.key),
    ];

    return Stack(
      children: [
        RefreshIndicator(
          color: AppColors.amber,
          onRefresh: () => _load(force: true),
          child: SingleChildScrollView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.md,
                AppSpace.gutter + 14, AppSpace.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SearchBar(
                  controller: _query,
                  onChanged: (q) {
                    setState(() {});
                    if (q.trim().length == 1) {
                      Analytics.instance.track(Analytics.evArchiveSearch);
                    }
                  },
                ),
                const SizedBox(height: AppSpace.md),
                if (searching)
                  ..._searchResults(data, index)
                else
                  ..._directory(data, index),
              ],
            ),
          ),
        ),
        if (!searching && labels.length > 1)
          Positioned(
            right: 2,
            top: 0,
            bottom: 0,
            child: Center(
              child: _IndexBar(labels: labels, onTap: _jumpTo),
            ),
          ),
      ],
    );
  }

  List<Widget> _searchResults(FalsificationData data, ArchiveIndex index) {
    final hits = index.search(_query.text);
    if (hits.isEmpty) {
      return [
        const SizedBox(height: 48),
        const WkEmpty(
          icon: Icons.search_off_rounded,
          title: '没有找到',
          hint: '可以搜策略名、家族、品种或周期，比如「突破」「P.DCE」「5min」。',
        ),
      ];
    }
    return [
      WkGroup(
        header: '搜索结果 · ${hits.length} 条',
        footer: '搜索结果包含「样本不足」的条目：它们不算淘汰，只是还不能下结论。',
        children: [for (final e in hits) _row(e, data)],
      ),
    ];
  }

  List<Widget> _directory(FalsificationData data, ArchiveIndex index) {
    final prices = data.prices;
    return [
      WkGroup(
        children: [
          EntryRow(
            icon: Icons.verified_rounded,
            color: AppColors.info,
            title: '可交易',
            value: '${index.tradable.length}',
            onTap: () => _openList(
              '可交易',
              index.tradable,
              data,
              emptyTitle: '暂无可交易策略',
              emptyHint: '目前没有策略通过全部闸门和人工稳健性复核，这正是证伪的意义。',
            ),
          ),
          EntryRow(
            icon: Icons.hourglass_top_rounded,
            color: AppColors.amber,
            title: '仍在验证',
            value: '${index.pending.length}',
            onTap: () => _openList(
              '仍在验证',
              index.pending,
              data,
              emptyTitle: '暂无仍在验证的策略',
              emptyHint: '过了前几道闸门、还在等更多样本或稳健性复核的策略会出现在这里。',
            ),
          ),
          EntryRow(
            icon: Icons.new_releases_rounded,
            color: AppColors.textSecondary,
            title: '本周新证伪',
            value: '${index.recentRejects.length}',
            onTap: () => _openList(
              '本周新证伪',
              index.recentRejects,
              data,
              emptyTitle: '本周没有新的证伪结论',
              emptyHint: '最近 7 天内新判「淘汰」的策略会出现在这里。',
            ),
          ),
          EntryRow(
            icon: Icons.play_arrow_rounded,
            color: AppColors.sectorPalette[3],
            title: '跑一次证伪',
            value: '${prices.falsifyDaily} 喜点起',
            onTap: () => _openRun(),
          ),
        ],
      ),
      if (index.curated.isNotEmpty)
        KeyedSubtree(
          key: _anchor('★'),
          child: WkGroup(
            header: '精选档案',
            children: [for (final e in index.curated) _row(e, data)],
          ),
        ),
      for (final s in index.sections)
        KeyedSubtree(
          key: _anchor(s.key),
          child: WkGroup(
            header: '${s.family} · ${s.entries.length}',
            children: [for (final e in s.entries) _row(e, data)],
          ),
        ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
        child: Text(
          '${index.mainCount} 条档案'
          '${index.insufficientCount > 0 ? ' · 另有 ${index.insufficientCount} 条样本不足，可搜索查看' : ''}',
          textAlign: TextAlign.center,
          style: AppType.caption.copyWith(color: AppColors.textTertiary),
        ),
      ),
      _LiveEntry(onTap: _openLive),
      const WkNote(
        text: '本页是研究结论，不是投资建议。回测不含冲击成本、涨跌停无法成交、'
            '盘中流动性枯竭等实盘约束；历史表现不代表未来收益。',
      ),
    ];
  }

  Widget _row(ArchiveEntry e, FalsificationData data) =>
      ArchiveRow(entry: e, gates: data.gates, onTap: () => _openEntry(e));

  GlobalKey _anchor(String label) =>
      _anchors.putIfAbsent(label, () => GlobalKey(debugLabel: 'idx-$label'));

  void _jumpTo(String label) {
    final ctx = _anchors[label]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx,
        duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
  }

  // ── 跳转 ─────────────────────────────────────────────────────────────

  Future<void> _openEntry(ArchiveEntry e) async {
    Analytics.instance
        .track(Analytics.evArchiveOpen, {'id': e.id, 'verdict': e.verdict});
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FalsificationDetailScreen(entry: e, service: _svc),
    ));
  }

  Future<void> _openList(
    String title,
    List<ArchiveEntry> entries,
    FalsificationData data, {
    required String emptyTitle,
    required String emptyHint,
  }) async {
    Analytics.instance.track(Analytics.evArchiveList, {'list': title});
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ArchiveListScreen(
        title: title,
        entries: entries,
        gates: data.gates,
        emptyTitle: emptyTitle,
        emptyHint: emptyHint,
        onOpen: (ctx, e) => Navigator.of(ctx).push(MaterialPageRoute(
          builder: (_) => FalsificationDetailScreen(entry: e, service: _svc),
        )),
      ),
    ));
  }

  Future<void> _openMethod(FalsificationData data) async {
    Analytics.instance.track(Analytics.evMethodOpen);
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => MethodScreen(data: data),
    ));
  }

  Future<void> _openRun({String? strategy}) async {
    Analytics.instance.track(Analytics.evFalsifyRunOpen);
    if (!context.read<AuthState>().isAuthenticated) {
      final ok = await requireLogin(context);
      if (!ok || !mounted) return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FalsifyRunScreen(service: _svc, strategy: strategy),
    ));
  }

  Future<void> _openLive() async {
    Analytics.instance.track(Analytics.evLiveEntry);
    if (!context.read<AuthState>().isAuthenticated) {
      final ok = await requireLogin(context);
      if (!ok || !mounted) return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const LiveStrategyScreen(),
    ));
  }
}

/// 顶部搜索框（微信通讯录的灰底圆角搜索条）。
class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: AppType.body.copyWith(color: AppColors.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 9),
          prefixIcon: Icon(Icons.search_rounded,
              size: 18, color: AppColors.textTertiary),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 36, minHeight: 20),
          hintText: '搜索策略、家族、品种、周期',
          hintStyle: AppType.body.copyWith(color: AppColors.textTertiary),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: Icon(Icons.cancel_rounded,
                      size: 16, color: AppColors.textTertiary),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
        ),
      ),
    );
  }
}

/// 右侧索引条：★ 是精选，其余是家族首字。点一下跳到对应分组。
class _IndexBar extends StatelessWidget {
  const _IndexBar({required this.labels, required this.onTap});

  final List<(String, String)> labels;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (l, anchor) in labels)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onTap(anchor),
            child: SizedBox(
              width: 18,
              height: 20,
              child: Center(
                child: Text(l,
                    style: AppType.micro.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ),
      ],
    );
  }
}

/// 实盘策略入口：需要登录，所以放在档案之后而不是之前。
class _LiveEntry extends StatelessWidget {
  const _LiveEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final authed = context.watch<AuthState>().isAuthenticated;
    return WkGroup(
      header: '实盘',
      children: [
        WkRow(
          icon: Icons.account_balance_wallet_rounded,
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
