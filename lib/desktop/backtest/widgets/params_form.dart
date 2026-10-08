import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/backtest/etf_rotation.dart';
import '../../../theme/app_theme.dart';

/// 回测参数表单：分组卡片（候选池 / 时间范围 / 策略参数 / 防御基准）+
/// 底部常驻运行按钮。
///
/// 所有字段带默认值（与后端 backtest_etf_rotation 工具一致）；
/// 点「运行回测」组装 EtfRotationParams 回调给父级执行。
class ParamsForm extends StatefulWidget {
  const ParamsForm({
    super.key,
    required this.running,
    required this.onRun,
    this.progress = '',
  });

  final bool running;
  final Future<void> Function(EtfRotationParams) onRun;
  final String progress;

  @override
  State<ParamsForm> createState() => _ParamsFormState();
}

class _ParamsFormState extends State<ParamsForm> {
  // ── 候选池（chip 编辑） ─────────────────────────────────────────
  final List<String> _symbols = [
    '510300', '510500', '159915', '588000', '510880', '518880',
  ];

  // ── 时间范围 ───────────────────────────────────────────────────
  late final TextEditingController _startCtrl = TextEditingController(
      text: _ymd(
          DateTime.now().subtract(const Duration(days: 365 * 3))));
  late final TextEditingController _endCtrl =
      TextEditingController(text: _ymd(DateTime.now()));

  // ── 策略参数（空 = 走引擎默认值） ──────────────────────────────
  late final TextEditingController _rebalanceCtrl =
      TextEditingController(text: '20');
  late final TextEditingController _shortCtrl =
      TextEditingController(text: '20');
  late final TextEditingController _longCtrl =
      TextEditingController(text: '60');
  late final TextEditingController _wShortCtrl =
      TextEditingController(text: '0.6');
  late final TextEditingController _wLongCtrl =
      TextEditingController(text: '0.4');
  late final TextEditingController _topNCtrl =
      TextEditingController(text: '3');
  late final TextEditingController _defensiveCtrl =
      TextEditingController(text: '511260');
  late final TextEditingController _benchmarkCtrl =
      TextEditingController(text: '510300');

  @override
  void dispose() {
    for (final c in [
      _startCtrl,
      _endCtrl,
      _rebalanceCtrl,
      _shortCtrl,
      _longCtrl,
      _wShortCtrl,
      _wLongCtrl,
      _topNCtrl,
      _defensiveCtrl,
      _benchmarkCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  EtfRotationParams _buildParams() {
    return EtfRotationParams(
      symbols: List.of(_symbols),
      startDate: _parseYmd(_startCtrl.text),
      endDate: _parseYmd(_endCtrl.text),
      rebalanceDays: int.tryParse(_rebalanceCtrl.text.trim()),
      shortWindow: int.tryParse(_shortCtrl.text.trim()),
      longWindow: int.tryParse(_longCtrl.text.trim()),
      wShort: double.tryParse(_wShortCtrl.text.trim()),
      wLong: double.tryParse(_wLongCtrl.text.trim()),
      topN: int.tryParse(_topNCtrl.text.trim()),
      defensive: _defensiveCtrl.text.trim(),
      benchmark: _benchmarkCtrl.text.trim(),
    );
  }

  void _addSymbol(String code) {
    final c = code.trim();
    if (c.isEmpty || _symbols.contains(c)) return;
    if (_symbols.length >= 12) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('候选池最多 12 只')),
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
                    title: '候选 ETF 池',
                    subtitle: '最多 12 只，按动量排名轮换',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
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
                              digits: true)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: _labeledField(
                              '结束', _endCtrl, digits: true)),
                    ]),
                  ),
                  _groupCard(
                    icon: Icons.tune,
                    title: '策略参数',
                    subtitle: '留空走引擎默认值',
                    child: Column(
                      children: [
                        Row(children: [
                          Expanded(child: _labeledField(
                              '再平衡周期(日)', _rebalanceCtrl,
                              digits: true)),
                          const SizedBox(width: 8),
                          Expanded(child: _labeledField(
                              '持仓数 Top N', _topNCtrl,
                              digits: true)),
                        ]),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(child: _labeledField(
                              '短动量窗口', _shortCtrl, digits: true)),
                          const SizedBox(width: 8),
                          Expanded(child: _labeledField(
                              '长动量窗口', _longCtrl, digits: true)),
                        ]),
                        const SizedBox(height: 10),
                        Row(children: [
                          Expanded(child: _labeledField(
                              '短权重', _wShortCtrl, decimal: true)),
                          const SizedBox(width: 8),
                          Expanded(child: _labeledField(
                              '长权重', _wLongCtrl, decimal: true)),
                        ]),
                      ],
                    ),
                  ),
                  _groupCard(
                    icon: Icons.shield_outlined,
                    title: '防御 / 基准',
                    subtitle: '负动量时切防御；基准用于对比',
                    child: Column(
                      children: [
                        _labeledField('防御 ETF', _defensiveCtrl),
                        const SizedBox(height: 10),
                        _labeledField('基准 ETF', _benchmarkCtrl),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // 运行按钮固定在参数区底部，不随内容滚动
          _runBar(),
        ],
      ),
    );
  }

  /// 分组卡片：小图标 + 标题 + 副标题 + 内容。
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
              decoration: _inputDeco('输入 6 位 ETF 代码，如 512880'),
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

  /// 带标签的输入框：标签在输入框上方，桌面表单惯例。
  Widget _labeledField(
    String label,
    TextEditingController ctrl, {
    bool digits = false,
    bool decimal = false,
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
            FilteringTextInputFormatter.allow(
                RegExp(decimal ? r'[\d.]' : digits ? r'[\d-]' : r'.')),
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

  /// 底部运行按钮区：与参数区同背景色，上边框分隔。
  Widget _runBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        border: Border(
            top: BorderSide(color: AppColors.borderDim)),
      ),
      child: SizedBox(
        height: 44,
        child: FilledButton.icon(
          onPressed: widget.running
              ? null
              : () => widget.onRun(_buildParams()),
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
