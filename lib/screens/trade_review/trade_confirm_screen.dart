import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/auth_models.dart';
import '../../models/trade_review.dart';
import '../../services/trade_review_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import 'trade_report_screen.dart';
import 'trade_review_widgets.dart';

class TradeConfirmScreen extends StatefulWidget {
  const TradeConfirmScreen({
    super.key,
    required this.parsed,
    required this.imageBytes,
  });

  final ParsedTradesResult parsed;
  final Uint8List? imageBytes;

  @override
  State<TradeConfirmScreen> createState() => _TradeConfirmScreenState();
}

class _TradeConfirmScreenState extends State<TradeConfirmScreen> {
  late final List<ParsedTrade> _trades = [...widget.parsed.trades];
  bool _saving = false;

  Future<void> _edit(int index) async {
    final updated = await showModalBottomSheet<ParsedTrade>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.bgSurface,
      builder: (_) => _TradeEditorSheet(trade: _trades[index]),
    );
    if (updated == null || !mounted) return;
    setState(() => _trades[index] = updated);
  }

  void _remove(int index) {
    final removed = _trades[index];
    setState(() => _trades.removeAt(index));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('已移除 ${removed.instrumentLabel}'),
          action: SnackBarAction(
            label: '撤销',
            textColor: Colors.white,
            onPressed: () {
              if (!mounted) return;
              setState(() => _trades.insert(index, removed));
            },
          ),
        ),
      );
  }

  Future<void> _generate() async {
    if (_saving || _trades.isEmpty) return;
    setState(() => _saving = true);
    try {
      final report = await TradeReviewStore.instance.analyze(
        trades: _trades,
        brokerHint: widget.parsed.brokerHint,
        currency: widget.parsed.currency,
        warnings: widget.parsed.warnings,
      );
      var pendingSync = false;
      try {
        await TradeReviewStore.instance.save(report);
      } on ApiException catch (error) {
        if (error.code != 'TRADE_REVIEW.SYNC_FAILED') rethrow;
        pendingSync = true;
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => TradeReportScreen(report: report),
        ),
      );
      if (pendingSync) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('报告已保存在本机；账号云端同步暂时失败，可稍后重试。'),
          ),
        );
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(title: const Text('核对成交记录')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: AppSpace.xl),
              children: [
                _summary(),
                if (widget.parsed.warnings.isNotEmpty)
                  _parserWarnings(widget.parsed.warnings),
                const TradeSectionTitle(
                  title: '逐笔核对',
                  caption: '识别可能受截图清晰度影响。点一行即可修改，错误行可直接删除。',
                ),
                if (_trades.isEmpty)
                  const SizedBox(
                    height: 220,
                    child: WkEmpty(
                      icon: Icons.playlist_remove_rounded,
                      title: '成交行已全部移除',
                      hint: '返回上一页重新选择成交记录截图。',
                    ),
                  )
                else
                  WkGroup(
                    children: [
                      for (var i = 0; i < _trades.length; i++)
                        _TradeRow(
                          trade: _trades[i],
                          index: i,
                          onTap: () => _edit(i),
                          onRemove: () => _remove(i),
                        ),
                    ],
                  ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: AppSpace.lg),
                  child: WkNote(
                    title: '复盘口径',
                    text: '卖出按先进先出与买入配对，买卖手续费都计入成本。'
                        '截图不含账户总资金与单笔风险预算，因此不会推断仓位比例或止损金额。',
                  ),
                ),
              ],
            ),
          ),
          _bottomBar(),
        ],
      ),
    );
  }

  Widget _summary() {
    return Container(
      color: AppColors.bgSurface,
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.lg,
        AppSpace.lg,
        AppSpace.lg,
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: widget.imageBytes == null
                ? Container(
                    width: 62,
                    height: 78,
                    color: AppColors.bgRaised,
                    child: Icon(
                      widget.parsed.importSource == 'Excel'
                          ? Icons.table_chart_outlined
                          : Icons.description_outlined,
                      color: AppColors.textTertiary,
                    ),
                  )
                : Image.memory(
                    widget.imageBytes!,
                    width: 62,
                    height: 78,
                    fit: BoxFit.cover,
                    cacheWidth: 186,
                    errorBuilder: (_, __, ___) => Container(
                      width: 62,
                      height: 78,
                      color: AppColors.bgRaised,
                      child: Icon(
                        Icons.receipt_long_outlined,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.parsed.brokerHint.isEmpty
                      ? '已导入成交记录'
                      : widget.parsed.brokerHint,
                  style: AppType.title,
                ),
                const SizedBox(height: 5),
                Text(
                  '${widget.parsed.importSource} · '
                  '${_periodLabel(widget.parsed)} · '
                  '确认 ${_trades.length} 笔 · '
                  '${_trades.where((trade) => trade.side == TradeSide.buy).length} 买 '
                  '${_trades.where((trade) => trade.side == TradeSide.sell).length} 卖',
                  style: AppType.caption.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (widget.parsed.screenshotCount > 0 &&
                        widget.parsed.successfulScreenshotCount <
                        widget.parsed.screenshotCount)
                      WkTag(
                        '成功 ${widget.parsed.successfulScreenshotCount}/'
                        '${widget.parsed.screenshotCount} 张',
                      ),
                    if (widget.parsed.invalidRowCount > 0)
                      WkTag('跳过 ${widget.parsed.invalidRowCount} 行无效数据'),
                    if (widget.parsed.dateFilteredOutTradeCount > 0)
                      WkTag('过滤 ${widget.parsed.dateFilteredOutTradeCount} 笔'),
                    if (widget.parsed.duplicateTradeCount > 0)
                      WkTag('已合并 ${widget.parsed.duplicateTradeCount} 笔重叠'),
                    WkTag(
                      widget.imageBytes == null ? '结构化数据导入' : '图片仅用于本次识别',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _parserWarnings(List<String> warnings) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.md,
        AppSpace.md,
        AppSpace.md,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7E9),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.info_outline_rounded,
              size: 19,
              color: AppColors.warning,
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '识别时有 ${warnings.length} 处不确定',
                    style: AppType.caption.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpace.xs),
                  Text(
                    warnings.join('\n'),
                    style: AppType.micro.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _periodLabel(ParsedTradesResult parsed) {
    final start = parsed.periodStart;
    final end = parsed.periodEnd;
    if (start == null || end == null) {
      return parsed.rawTradeCount > 0
          ? '原始 ${parsed.rawTradeCount} 行'
          : '未筛选日期';
    }
    String date(DateTime value) =>
        '${value.year}.${value.month.toString().padLeft(2, '0')}.'
        '${value.day.toString().padLeft(2, '0')}';
    return '${date(start)}–${date(end)}';
  }

  Widget _bottomBar() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        border: Border(
          top: BorderSide(color: AppColors.borderDim, width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.md,
          AppSpace.lg,
          AppSpace.md,
        ),
        child: WkPrimaryButton(
          key: const ValueKey('trade-review-generate'),
          label: '确认并生成复盘',
          icon: Icons.auto_awesome_outlined,
          busy: _saving,
          onPressed: _trades.isEmpty ? null : _generate,
        ),
      ),
    );
  }
}

class _TradeRow extends StatelessWidget {
  const _TradeRow({
    required this.trade,
    required this.index,
    required this.onTap,
    required this.onRemove,
  });

  final ParsedTrade trade;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final isBuy = trade.side == TradeSide.buy;
    final tone = isBuy ? AppColors.positive : AppColors.negative;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('trade-row-$index'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            AppSpace.md,
            AppSpace.xs,
            AppSpace.md,
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Text(
                  trade.side.label,
                  style: AppType.micro.copyWith(
                    color: tone,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trade.instrumentLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.body.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${formatTradeMinute(trade.occurredAt)} · '
                      '${_quantity(trade.quantity)} @ ${trade.price.toStringAsFixed(2)}'
                      '${trade.fee > 0 ? ' · 费 ${trade.fee.toStringAsFixed(2)}' : ''}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.micro.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.5,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '删除这一行',
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                color: AppColors.textTertiary,
                constraints: const BoxConstraints.tightFor(
                  width: 44,
                  height: 44,
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textTertiary,
                size: 21,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _quantity(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }
}

class _TradeEditorSheet extends StatefulWidget {
  const _TradeEditorSheet({required this.trade});

  final ParsedTrade trade;

  @override
  State<_TradeEditorSheet> createState() => _TradeEditorSheetState();
}

class _TradeEditorSheetState extends State<_TradeEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _symbol;
  late final TextEditingController _quantity;
  late final TextEditingController _price;
  late final TextEditingController _fee;
  late TradeSide _side;
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    final trade = widget.trade;
    _name = TextEditingController(text: trade.name);
    _symbol = TextEditingController(text: trade.symbol);
    _quantity = TextEditingController(text: _plainNumber(trade.quantity));
    _price = TextEditingController(text: _plainNumber(trade.price));
    _fee = TextEditingController(text: _plainNumber(trade.fee));
    _side = trade.side;
    _date = trade.occurredAt;
  }

  @override
  void dispose() {
    _name.dispose();
    _symbol.dispose();
    _quantity.dispose();
    _price.dispose();
    _fee.dispose();
    super.dispose();
  }

  Future<void> _chooseDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 366)),
      helpText: '选择成交日期',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (selected == null) return;
    setState(() {
      _date = DateTime(
        selected.year,
        selected.month,
        selected.day,
        _date.hour,
        _date.minute,
        _date.second,
      );
    });
  }

  Future<void> _chooseTime() async {
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_date),
      helpText: '选择成交时间',
      cancelText: '取消',
      confirmText: '确定',
    );
    if (selected == null) return;
    setState(() {
      _date = DateTime(
        _date.year,
        _date.month,
        _date.day,
        selected.hour,
        selected.minute,
      );
    });
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final name = _name.text.trim();
    final symbol = _symbol.text.trim();
    if (name.isEmpty && symbol.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请至少填写证券名称或代码。')),
      );
      return;
    }
    Navigator.of(context).pop(
      widget.trade.copyWith(
        occurredAt: _date,
        name: name,
        symbol: symbol,
        side: _side,
        quantity: double.parse(_quantity.text.trim()),
        price: double.parse(_price.text.trim()),
        fee: _fee.text.trim().isEmpty ? 0 : double.parse(_fee.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.xs,
          AppSpace.lg,
          AppSpace.xl,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('修改成交',
                        style: AppType.title.copyWith(fontSize: 20)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: AppSpace.xs),
                  FilledButton(
                    onPressed: _submit,
                    child: const Text('保存'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.lg),
              Text(
                '买卖方向',
                style: AppType.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              SegmentedButton<TradeSide>(
                segments: const [
                  ButtonSegment(
                    value: TradeSide.buy,
                    label: Text('买入'),
                    icon: Icon(Icons.add_rounded, size: 18),
                  ),
                  ButtonSegment(
                    value: TradeSide.sell,
                    label: Text('卖出'),
                    icon: Icon(Icons.remove_rounded, size: 18),
                  ),
                ],
                selected: {_side},
                showSelectedIcon: false,
                onSelectionChanged: (value) {
                  setState(() => _side = value.first);
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.standard,
                  foregroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? AppColors.onAccent
                        : AppColors.textPrimary,
                  ),
                  backgroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? (_side == TradeSide.buy
                            ? AppColors.positive
                            : AppColors.negative)
                        : AppColors.bgRaised,
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              Row(
                children: [
                  Expanded(
                    child: _DateTimeField(
                      label: '成交日期',
                      value:
                          '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}',
                      onTap: _chooseDate,
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: _DateTimeField(
                      label: '成交时间',
                      value:
                          '${_date.hour.toString().padLeft(2, '0')}:${_date.minute.toString().padLeft(2, '0')}',
                      onTap: _chooseTime,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.lg),
              TextFormField(
                controller: _name,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: '证券名称'),
              ),
              const SizedBox(height: AppSpace.md),
              TextFormField(
                controller: _symbol,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '证券代码',
                  hintText: '例如 600519',
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Row(
                children: [
                  Expanded(
                    child: _NumberField(
                      controller: _quantity,
                      label: '成交数量',
                      mustBePositive: true,
                    ),
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    child: _NumberField(
                      controller: _price,
                      label: '成交单价',
                      mustBePositive: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.md),
              _NumberField(
                controller: _fee,
                label: '手续费合计',
                hint: '看不到可填 0',
                mustBePositive: false,
              ),
              const SizedBox(height: AppSpace.xl),
              WkPrimaryButton(label: '保存这一笔', onPressed: _submit),
            ],
          ),
        ),
      ),
    );
  }

  static String _plainNumber(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '');
  }
}

class _DateTimeField extends StatelessWidget {
  const _DateTimeField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: AppType.body.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Icon(
              Icons.calendar_today_outlined,
              size: 17,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.mustBePositive,
    this.hint,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool mustBePositive;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      decoration: InputDecoration(labelText: label, hintText: hint),
      validator: (value) {
        final number = double.tryParse(value?.trim() ?? '');
        if (number == null) return '请输入数字';
        if (mustBePositive && number <= 0) return '必须大于 0';
        if (!mustBePositive && number < 0) return '不能小于 0';
        return null;
      },
    );
  }
}
