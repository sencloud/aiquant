import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme.dart';

/// 短线动量策略的回测参数配置（UI → 引擎的传参结构）。
class EtfShortTermEngineConfig {
  const EtfShortTermEngineConfig({
    required this.symbols,
    required this.initialCapital,
    required this.startDate,
    required this.endDate,
    required this.momentumWindow,
    required this.buyThreshold,
    required this.firstBuyRatio,
    required this.addThreshold,
    required this.addMaxRatio,
    required this.stopLoss,
    required this.maxHoldingDays,
    required this.maxPositions,
  });

  final List<String> symbols;
  final double initialCapital;
  final DateTime? startDate;
  final DateTime? endDate;
  final int momentumWindow;
  final double buyThreshold;
  final double firstBuyRatio;
  final double addThreshold;
  final double addMaxRatio;
  final double stopLoss;
  final int maxHoldingDays;
  final int maxPositions;
}

/// 短线动量策略参数表单：候选池（仅深市 159）+ 资金与风控 + 运行按钮。
///
/// 默认值即用户约束：本金 5 万、最多 2 只、最长持仓 10 天、
/// 万 3 手续费（引擎内固定，不在表单暴露）。
class ShortTermForm extends StatefulWidget {
  const ShortTermForm({
    super.key,
    required this.running,
    required this.onRun,
    this.progress = '',
  });

  final bool running;
  final Future<void> Function(EtfShortTermEngineConfig) onRun;
  final String progress;

  @override
  State<ShortTermForm> createState() => _ShortTermFormState();
}

class _ShortTermFormState extends State<ShortTermForm> {
  /// 候选池（159 开头深市 ETF）。默认给一组常用池，可增删。
  final List<String> _symbols = [
    '159915', // 创业板
    '159949', // 创业板 50
    '159905', // 中小 100
    '159920', // 恒生
    '159980', // 有色
    '159995', // 芯片
  ];

  late final TextEditingController _capitalCtrl =
      TextEditingController(text: '50000');
  late final TextEditingController _startCtrl = TextEditingController(
      text: _ymd(
          DateTime.now().subtract(const Duration(days: 365))));
  late final TextEditingController _endCtrl =
      TextEditingController(text: _ymd(DateTime.now()));
  late final TextEditingController _momWindowCtrl =
      TextEditingController(text: '5');
  late final TextEditingController _buyThreshCtrl =
      TextEditingController(text: '1'); // %，提交时 ÷100
  late final TextEditingController _firstRatioCtrl =
      TextEditingController(text: '50'); // %
  late final TextEditingController _addThreshCtrl =
      TextEditingController(text: '4'); // %
  late final TextEditingController _addMaxCtrl =
      TextEditingController(text: '70'); // %
  late final TextEditingController _stopCtrl =
      TextEditingController(text: '8'); // %
  late final TextEditingController _maxDaysCtrl =
      TextEditingController(text: '10');
  late final TextEditingController _maxPosCtrl =
      TextEditingController(text: '2');

  @override
  void dispose() {
    for (final c in [
      _capitalCtrl,
      _startCtrl,
      _endCtrl,
      _momWindowCtrl,
      _buyThreshCtrl,
      _firstRatioCtrl,
      _addThreshCtrl,
      _addMaxCtrl,
      _stopCtrl,
      _maxDaysCtrl,
      _maxPosCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  EtfShortTermEngineConfig _buildConfig() {
    return EtfShortTermEngineConfig(
      symbols: List.of(_symbols),
      initialCapital:
          double.tryParse(_capitalCtrl.text.trim()) ?? 50000,
      startDate: _parseYmd(_startCtrl.text),
      endDate: _parseYmd(_endCtrl.text),
      momentumWindow: int.tryParse(_momWindowCtrl.text.trim()) ?? 5,
      buyThreshold:
          (double.tryParse(_buyThreshCtrl.text.trim()) ?? 1) / 100,
      firstBuyRatio:
          (double.tryParse(_firstRatioCtrl.text.trim()) ?? 50) / 100,
      addThreshold:
          -(double.tryParse(_addThreshCtrl.text.trim()) ?? 4) / 100,
      addMaxRatio:
          (double.tryParse(_addMaxCtrl.text.trim()) ?? 70) / 100,
      stopLoss: -(double.tryParse(_stopCtrl.text.trim()) ?? 8) / 100,
      maxHoldingDays:
          int.tryParse(_maxDaysCtrl.text.trim()) ?? 10,
      maxPositions: int.tryParse(_maxPosCtrl.text.trim()) ?? 2,
    );
  }

  void _addSymbol(String code) {
    final c = code.trim();
    // 只允许深市 ETF（159 开头）
    if (c.length != 6 || !c.startsWith('159')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('仅支持深市 ETF（159 开头）')),
      );
      return;
    }
    if (_symbols.contains(c)) return;
    if (_symbols.length >= 16) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('候选池最多 16 只')),
      );
      return;
    }
    setState(() => _symbols.add(c));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgSurface,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _groupCard(
                    icon: Icons.grid_view_outlined,
                    title: '候选池（仅深市 159）',
                    subtitle: '${_symbols.length} 只',
                    child: Column(
                      children: [
                        _symbolChips(),
                        _addSymbolRow(),
                      ],
                    ),
                  ),
                  _groupCard(
                    icon: Icons.date_range_outlined,
                    title: '时间范围',
                    subtitle: '建议 1 年以上',
                    child: Row(children: [
                      Expanded(
                          child: _labeledField('起始', _startCtrl,
                              date: true)),
                      const SizedBox(width: 8),
                      Expanded(
                          child:
                              _labeledField('结束', _endCtrl, date: true)),
                    ]),
                  ),
                  _groupCard(
                    icon: Icons.bolt,
                    title: '入场',
                    subtitle: '动量最强者入选',
                    child: Column(
                      children: [
                        Row(children: [
                          Expanded(child: _labeledField(
                              '动量窗口(日)', _momWindowCtrl,
                              digits: true)),
                          const SizedBox(width: 8),
                          Expanded(child: _labeledField(
                              '买入阈值(%)', _buyThreshCtrl,
                              decimal: true)),
                        ]),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(child: _labeledField(
                              '首次仓位(%)', _firstRatioCtrl,
                              decimal: true)),
                          const SizedBox(width: 8),
                          Expanded(child: _labeledField(
                              '最多同时持有', _maxPosCtrl,
                              digits: true)),
                        ]),
                      ],
                    ),
                  ),
                  _groupCard(
                    icon: Icons.shield_outlined,
                    title: '风控',
                    subtitle: '补仓 / 止损 / 持仓时限',
                    child: Column(
                      children: [
                        Row(children: [
                          Expanded(child: _labeledField(
                              '补仓线(%)', _addThreshCtrl,
                              decimal: true)),
                          const SizedBox(width: 8),
                          Expanded(child: _labeledField(
                              '补仓后上限(%)', _addMaxCtrl,
                              decimal: true)),
                        ]),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(child: _labeledField(
                              '止损线(%)', _stopCtrl,
                              decimal: true)),
                          const SizedBox(width: 8),
                          Expanded(child: _labeledField(
                              '最长持仓(日)', _maxDaysCtrl,
                              digits: true)),
                        ]),
                      ],
                    ),
                  ),
                  _groupCard(
                    icon: Icons.payments_outlined,
                    title: '资金',
                    subtitle: 'T+1 / 万3 / 100 份整数倍',
                    child: _labeledField(
                        '初始本金(元)', _capitalCtrl, decimal: true),
                  ),
                ],
              ),
            ),
          ),
          _runBar(),
        ],
      ),
    );
  }

  Widget _groupCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderDim),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 14, color: AppColors.amber),
            const SizedBox(width: 6),
            Text(title,
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700)),
            const Spacer(),
            Text(subtitle,
                style: TextStyle(
                    color: AppColors.textTertiary, fontSize: 10.5)),
          ]),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _symbolChips() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final s in _symbols)
          InputChip(
            label: Text(s, style: const TextStyle(fontSize: 12)),
            backgroundColor: AppColors.bgBase,
            side: BorderSide(color: AppColors.borderDim),
            deleteIcon: Icon(Icons.close,
                size: 13, color: AppColors.textTertiary),
            onDeleted: widget.running
                ? null
                : () => setState(() => _symbols.remove(s)),
          ),
      ],
    );
  }

  Widget _addSymbolRow() {
    final ctrl = TextEditingController();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              enabled: !widget.running,
              style: const TextStyle(fontSize: 12),
              decoration: _inputDeco('159 开头的深市 ETF 代码'),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (v) {
                _addSymbol(v);
                ctrl.clear();
              },
            ),
          ),
          const SizedBox(width: 8),
          _iconButton(
            icon: Icons.add,
            tooltip: '添加到候选池',
            onTap: widget.running
                ? null
                : () {
                    _addSymbol(ctrl.text);
                    ctrl.clear();
                  },
          ),
        ],
      ),
    );
  }

  Widget _labeledField(
    String label,
    TextEditingController ctrl, {
    bool digits = false,
    bool decimal = false,
    bool date = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style:
                TextStyle(color: AppColors.textTertiary, fontSize: 10.5)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          enabled: !widget.running,
          style: const TextStyle(fontSize: 12.5),
          decoration: _inputDeco(''),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(
                date ? r'[\d-]' : decimal ? r'[\d.]' : r'\d')),
          ],
        ),
      ],
    );
  }

  Widget _iconButton({
    required IconData icon,
    required String tooltip,
    VoidCallback? onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor: onTap != null
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.bgBase,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.borderDim),
            ),
            child:
                Icon(icon, size: 16, color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }

  Widget _runBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        border:
            Border(top: BorderSide(color: AppColors.borderDim)),
      ),
      child: SizedBox(
        height: 44,
        child: FilledButton.icon(
          onPressed: widget.running
              ? null
              : () => widget.onRun(_buildConfig()),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.amber,
            foregroundColor: Colors.black,
            disabledBackgroundColor:
                AppColors.amber.withValues(alpha: 0.4),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          icon: widget.running
              ? const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow, size: 19),
          label: Text(
            widget.running
                ? (widget.progress.isEmpty ? '运行中…' : widget.progress)
                : '运行回测',
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        hintStyle: TextStyle(color: AppColors.textTertiary, fontSize: 11),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AppColors.borderDim)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
                color: AppColors.amber.withValues(alpha: 0.7))),
        disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AppColors.borderDim)),
      );
}

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? _parseYmd(String s) {
  final m = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s.trim());
  if (m == null) return null;
  return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!),
      int.parse(m.group(3)!));
}
