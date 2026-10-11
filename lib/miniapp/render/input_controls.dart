/// 小应用的参数控件：数字 / 文本 / 枚举 / 日期 / 开关 / 列表。
library;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../expr/xel.dart' show fmtNum;
import 'spec_runtime.dart';

class MiniAppInputControl extends StatelessWidget {
  const MiniAppInputControl({
    super.key,
    required this.def,
    required this.value,
    this.style = 'auto',
    this.onChanged,
  });

  final InputDef def;
  final dynamic value;
  final String style;
  final ValueChanged<dynamic>? onChanged;

  @override
  Widget build(BuildContext context) {
    final label = Text(def.label,
        style: AppType.caption.copyWith(color: AppColors.textSecondary));
    switch (def.type) {
      case 'number':
        return _NumberInput(def: def, value: value, onChanged: onChanged);
      case 'enum':
        final segmented = style == 'segmented' ||
            (style == 'auto' && def.options.length <= 4);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            label,
            const SizedBox(height: 4),
            if (segmented)
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final o in def.options)
                  ChoiceChip(
                    label: Text(o),
                    selected: o == value,
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    onSelected:
                        onChanged == null ? null : (_) => onChanged!(o),
                  ),
              ])
            else
              DropdownButton<String>(
                value: def.options.contains(value) ? value as String : null,
                isExpanded: true,
                isDense: true,
                underline: Container(height: 0.5, color: AppColors.borderMed),
                items: [
                  for (final o in def.options)
                    DropdownMenuItem(value: o, child: Text(o)),
                ],
                onChanged:
                    onChanged == null ? null : (v) => v == null ? null : onChanged!(v),
              ),
          ],
        );
      case 'bool':
        return Row(children: [
          Expanded(child: label),
          Switch(
            value: value == true,
            onChanged: onChanged == null ? null : (v) => onChanged!(v),
          ),
        ]);
      case 'date':
        final s = value is String ? value as String : '';
        return Row(children: [
          Expanded(child: label),
          TextButton.icon(
            icon: const Icon(Icons.event_rounded, size: 16),
            label: Text(s.isEmpty ? '今天' : s),
            onPressed: onChanged == null
                ? null
                : () async {
                    final now = DateTime.now();
                    final init = DateTime.tryParse(s) ?? now;
                    final d = await showDatePicker(
                      context: context,
                      initialDate: init,
                      firstDate: DateTime(now.year - 5),
                      lastDate: DateTime(now.year + 2),
                    );
                    if (d != null) {
                      onChanged!('${d.year.toString().padLeft(4, '0')}-'
                          '${d.month.toString().padLeft(2, '0')}-'
                          '${d.day.toString().padLeft(2, '0')}');
                    }
                  },
          ),
        ]);
      case 'list':
        return _ListInput(def: def, value: value, onChanged: onChanged);
      default:
        return _TextInput(def: def, value: value, onChanged: onChanged);
    }
  }
}

class _NumberInput extends StatelessWidget {
  const _NumberInput({required this.def, required this.value, this.onChanged});
  final InputDef def;
  final dynamic value;
  final ValueChanged<dynamic>? onChanged;

  @override
  Widget build(BuildContext context) {
    final v = value is num ? (value as num).toDouble() : 0.0;
    final step = def.step ?? 1;
    final decimals = step < 1 ? (step < 0.1 ? 2 : 1) : 0;
    double clamp(double x) {
      if (def.min != null && x < def.min!) x = def.min!;
      if (def.max != null && x > def.max!) x = def.max!;
      return double.parse(x.toStringAsFixed(decimals));
    }

    final hasRange = def.min != null && def.max != null && def.max! > def.min!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          Expanded(
            child: Text(def.label,
                style: AppType.caption.copyWith(color: AppColors.textSecondary)),
          ),
          _StepButton(
              icon: Icons.remove_rounded,
              onTap: onChanged == null ? null : () => onChanged!(clamp(v - step))),
          GestureDetector(
            onTap: onChanged == null ? null : () => _edit(context, v, clamp),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
              child: Text(
                '${fmtNum(v, decimals, true)}${def.unit == null ? '' : ' ${def.unit}'}',
                style: AppType.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    fontFamilyFallback: AppType.numericFallback),
              ),
            ),
          ),
          _StepButton(
              icon: Icons.add_rounded,
              onTap: onChanged == null ? null : () => onChanged!(clamp(v + step))),
        ]),
        if (hasRange)
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                overlayShape: SliderComponentShape.noOverlay,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7)),
            child: Slider(
              value: v.clamp(def.min!, def.max!),
              min: def.min!,
              max: def.max!,
              divisions: ((def.max! - def.min!) / step).round().clamp(1, 1000),
              onChanged: onChanged == null ? null : (x) => onChanged!(clamp(x)),
            ),
          ),
      ],
    );
  }

  Future<void> _edit(
      BuildContext context, double v, double Function(double) clamp) async {
    final c = TextEditingController(text: fmtNum(v, 6, false).replaceAll(',', ''));
    final r = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(def.label),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
          decoration: InputDecoration(suffixText: def.unit),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, double.tryParse(c.text.trim())),
              child: const Text('确定')),
        ],
      ),
    );
    if (r != null) onChanged!(clamp(r));
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: AppColors.bgRaised,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Icon(icon, size: 16, color: AppColors.textSecondary),
      ),
    );
  }
}

class _TextInput extends StatefulWidget {
  const _TextInput({required this.def, required this.value, this.onChanged});
  final InputDef def;
  final dynamic value;
  final ValueChanged<dynamic>? onChanged;

  @override
  State<_TextInput> createState() => _TextInputState();
}

class _TextInputState extends State<_TextInput> {
  late final TextEditingController _c =
      TextEditingController(text: widget.value is String ? widget.value as String : '');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      maxLength: 40,
      enabled: widget.onChanged != null,
      decoration: InputDecoration(
        labelText: widget.def.label,
        hintText: widget.def.placeholder,
        counterText: '',
        isDense: true,
      ),
      onSubmitted: (s) => widget.onChanged?.call(s.trim()),
      onEditingComplete: () => widget.onChanged?.call(_c.text.trim()),
    );
  }
}

class _ListInput extends StatelessWidget {
  const _ListInput({required this.def, required this.value, this.onChanged});
  final InputDef def;
  final dynamic value;
  final ValueChanged<dynamic>? onChanged;

  List<Map<String, dynamic>> get _items => [
        if (value is List)
          for (final e in value as List)
            if (e is Map) e.cast<String, dynamic>()
      ];

  String _line(Map<String, dynamic> m) => def.fields.keys
      .map((k) => m[k] is double ? fmtNum(m[k] as double, 0, false) : '${m[k] ?? ''}')
      .where((s) => s.isNotEmpty)
      .join(' · ');

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(def.label,
            style: AppType.caption.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (var i = 0; i < items.length; i++)
            InputChip(
              label: Text(_line(items[i])),
              visualDensity: VisualDensity.compact,
              onDeleted: onChanged == null
                  ? null
                  : () => onChanged!([...items]..removeAt(i)),
            ),
          if (onChanged != null && items.length < def.maxItems)
            ActionChip(
              avatar: const Icon(Icons.add_rounded, size: 16),
              label: const Text('添加'),
              visualDensity: VisualDensity.compact,
              onPressed: () async {
                final m = await _editItem(context);
                if (m != null) onChanged!([...items, m]);
              },
            ),
        ]),
      ],
    );
  }

  Future<Map<String, dynamic>?> _editItem(BuildContext context) {
    final ctrls = {for (final k in def.fields.keys) k: TextEditingController()};
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('添加${def.label}'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final e in def.fields.entries)
            TextField(
              controller: ctrls[e.key],
              keyboardType: e.value == 'number'
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              decoration: InputDecoration(labelText: e.key),
            ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              final m = <String, dynamic>{};
              for (final e in def.fields.entries) {
                final s = ctrls[e.key]!.text.trim();
                if (s.isEmpty) continue;
                if (e.value == 'number') {
                  final d = double.tryParse(s);
                  if (d != null) m[e.key] = d;
                } else {
                  m[e.key] = s.length > 30 ? s.substring(0, 30) : s;
                }
              }
              Navigator.pop(ctx, m.isEmpty ? null : m);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
