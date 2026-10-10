import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/falsification.dart';
import '../../services/analytics.dart';
import '../../services/falsification_service.dart';
import '../../state/billing_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import 'archive_widgets.dart';
import 'falsification_detail_screen.dart';
import 'paywall.dart';

/// 跑一次证伪：选策略 × 品种 × 周期，扣喜点后交给 alpha-radar 计算。
///
/// 日线 10 喜点、分钟线 30 喜点（价格以服务端下发为准）。扣费和退款都在
/// 服务端：任务失败自动退回。计算队列没接通时，下单只登记需求、不扣费。
/// 调用方负责先登录（requireLogin）。
class FalsifyRunScreen extends StatefulWidget {
  const FalsifyRunScreen({super.key, this.service, this.strategy});

  final FalsificationService? service;

  /// 预选的策略（key 或名字），从详情页「再跑一次」带过来。
  final String? strategy;

  @override
  State<FalsifyRunScreen> createState() => _FalsifyRunScreenState();
}

class _FalsifyRunScreenState extends State<FalsifyRunScreen> {
  late final FalsificationService _svc =
      widget.service ?? FalsificationService.shared;

  RunOptions? _opts;
  String? _error;
  String? _strategy;
  String? _symbol;
  String? _freq;
  bool _submitting = false;
  FalsificationRun? _run;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    // ignore: unawaited_futures
    _loadOptions();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    setState(() => _error = null);
    try {
      final o = await _svc.runOptions();
      if (!mounted) return;
      final hint = widget.strategy;
      String? pre;
      if (hint != null) {
        for (final s in o.strategies) {
          if (s.key == hint || s.name == hint) pre = s.key;
        }
      }
      setState(() {
        _opts = o;
        _strategy =
            pre ?? (o.strategies.isNotEmpty ? o.strategies.first.key : null);
        _symbol = o.symbols.isNotEmpty ? o.symbols.first : null;
        _freq = o.freqs.contains('1d')
            ? '1d'
            : (o.freqs.isNotEmpty ? o.freqs.first : null);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = asApiException(e)?.message ?? '选项加载失败，请检查网络后重试');
    }
  }

  Future<void> _submit() async {
    final o = _opts;
    if (o == null || _strategy == null || _symbol == null || _freq == null) {
      return;
    }
    final price = o.prices.forFreq(_freq!);
    setState(() => _submitting = true);
    Analytics.instance.track(Analytics.evFalsifyRunSubmit, {
      'strategy': _strategy,
      'symbol': _symbol,
      'freq': _freq,
      'available': o.available,
    });
    try {
      final r = await _svc.createRun(
          strategy: _strategy!, symbol: _symbol!, freq: _freq!);
      if (!mounted) return;
      setState(() => _run = r.run);
      if (r.run.charged) {
        // ignore: unawaited_futures
        context.read<BillingState>().refreshBalance();
      }
      if (!r.run.finished) _startPolling(r.run.id);
    } catch (e) {
      if (!mounted) return;
      final api = asApiException(e);
      if (api?.code == 'FALSIFICATION.INSUFFICIENT_BALANCE') {
        await showInsufficientBalance(context, need: price, what: '跑一次证伪');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(api?.message ?? '提交失败，请稍后再试'),
        ));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _startPolling(String id) {
    _poll?.cancel();
    var ticks = 0;
    _poll = Timer.periodic(const Duration(seconds: 4), (t) async {
      ticks++;
      if (ticks > 150) {
        t.cancel(); // 10 分钟还没出结果就停；任务仍在服务端继续。
        return;
      }
      try {
        final run = await _svc.getRun(id);
        if (!mounted) return;
        setState(() => _run = run);
        if (run.finished) {
          t.cancel();
          if (run.refunded) {
            // ignore: unawaited_futures
            context.read<BillingState>().refreshBalance();
          }
        }
      } catch (_) {
        // 网络抖动：下一轮再查。
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return WkPage(title: '跑一次证伪', child: _body());
  }

  Widget _body() {
    final o = _opts;
    if (o == null) {
      if (_error == null) {
        return const Center(
          child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2)),
        );
      }
      return ListView(
        padding: const EdgeInsets.all(AppSpace.xl),
        children: [
          const SizedBox(height: 48),
          WkEmpty(
            icon: Icons.cloud_off_rounded,
            title: '暂时打不开',
            hint: _error,
            action: OutlinedButton(
                onPressed: _loadOptions, child: const Text('重试')),
          ),
        ],
      );
    }

    final price = _freq == null ? 0 : o.prices.forFreq(_freq!);
    final run = _run;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter, AppSpace.lg, AppSpace.gutter, AppSpace.xxl),
      children: [
        if (!o.available)
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpace.md),
            child: WkNote(
              title: '计算队列接入中',
              text: '现在提交只登记需求、不扣喜点；开放后按登记顺序优先处理。',
            ),
          ),
        _ChoiceGroup(
          header: '策略',
          options: [for (final s in o.strategies) (s.key, s.name)],
          selected: _strategy,
          onSelect: (v) => setState(() => _strategy = v),
        ),
        _ChoiceGroup(
          header: '品种',
          options: [for (final s in o.symbols) (s, s)],
          selected: _symbol,
          onSelect: (v) => setState(() => _symbol = v),
        ),
        _ChoiceGroup(
          header: '周期',
          footer: '日线 ${o.prices.falsifyDaily} 喜点 · 分钟线 '
              '${o.prices.falsifyMinute} 喜点（分钟线数据量大、算得久）。'
              '任务失败自动退回喜点。',
          options: [for (final f in o.freqs) (f, freqLabel(f))],
          selected: _freq,
          onSelect: (v) => setState(() => _freq = v),
        ),
        const SizedBox(height: AppSpace.sm),
        WkPrimaryButton(
          label: o.available ? '开始证伪（$price 喜点）' : '登记需求（不扣费）',
          icon: Icons.play_arrow_rounded,
          busy: _submitting,
          onPressed: _submitting ||
                  (run != null && !run.finished) ||
                  _strategy == null ||
                  _symbol == null ||
                  _freq == null
              ? null
              : _submit,
        ),
        if (run != null) ...[
          const SizedBox(height: AppSpace.lg),
          _RunCard(run: run, service: _svc),
        ],
        const SizedBox(height: AppSpace.lg),
        const WkNote(
          text: '结论按同一套五道闸门判定：含成本、必报分年。'
              '「可交易」只能在人工稳健性复核后给出，自动任务不会产出。',
        ),
      ],
    );
  }
}

class _ChoiceGroup extends StatelessWidget {
  const _ChoiceGroup({
    required this.header,
    required this.options,
    required this.selected,
    required this.onSelect,
    this.footer,
  });

  final String header;
  final String? footer;
  final List<(String, String)> options;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return WkGroup(
      header: header,
      footer: footer,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: options.isEmpty
              ? Text('暂无可选项',
                  style:
                      AppType.caption.copyWith(color: AppColors.textTertiary))
              : Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.sm,
                  children: [
                    for (final (value, label) in options)
                      ChoiceChip(
                        label: Text(label),
                        selected: value == selected,
                        onSelected: (_) => onSelect(value),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _RunCard extends StatelessWidget {
  const _RunCard({required this.run, required this.service});

  final FalsificationRun run;
  final FalsificationService service;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (run.status) {
      'queued' => ('排队中', AppColors.amber),
      'running' => ('计算中', AppColors.amber),
      'done' => ('已出结论', AppColors.info),
      'failed' => ('失败', AppColors.danger),
      'unsupported' => ('已登记', AppColors.textSecondary),
      _ => (run.status, AppColors.textSecondary),
    };
    final note = switch (run.status) {
      'failed' => run.refunded
          ? '计算失败，${run.credits} 喜点已退回。${run.error}'
          : '计算失败。${run.error}',
      'unsupported' => run.message,
      'queued' || 'running' => '可以离开本页，结果会保存在服务端。',
      _ => run.message,
    };
    final result = run.result;
    return WkGroup(
      header: '本次任务',
      children: [
        WkRow(
          title: '${run.strategy} · ${run.symbol} · ${freqLabel(run.freq)}',
          subtitle: note.isEmpty ? null : note,
          trailing: WkTag(label, tone: color, filled: true),
        ),
        if (result != null)
          ArchiveRow(
            entry: result,
            gates: service.cached?.gates ?? const [],
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  FalsificationDetailScreen(entry: result, service: service),
            )),
          ),
      ],
    );
  }
}
