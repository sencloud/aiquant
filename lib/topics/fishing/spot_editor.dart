import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import 'fishing_models.dart';
import 'fishing_state.dart';

/// 新建 / 编辑私人钓点。坐标可选：可以从地图 App 里复制「纬度,经度」粘贴进来。
Future<FishingSpot?> showSpotEditor(BuildContext context, {FishingSpot? spot}) {
  return showModalBottomSheet<FishingSpot>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.bgSurface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (_) => ChangeNotifierProvider.value(
      value: context.read<FishingState>(),
      child: _SpotEditor(spot: spot),
    ),
  );
}

/// 解析「30.12, 120.34」这类坐标文本；不合法返回 null。
(double, double)? parseLatLon(String text) {
  final m = RegExp(r'(-?\d+(?:\.\d+)?)\s*[,，\s]\s*(-?\d+(?:\.\d+)?)')
      .firstMatch(text.trim());
  if (m == null) return null;
  final a = double.parse(m.group(1)!);
  final b = double.parse(m.group(2)!);
  if (a.abs() > 90 || b.abs() > 180) return null;
  return (a, b);
}

class _SpotEditor extends StatefulWidget {
  const _SpotEditor({this.spot});
  final FishingSpot? spot;

  @override
  State<_SpotEditor> createState() => _SpotEditorState();
}

class _SpotEditorState extends State<_SpotEditor> {
  late final _name = TextEditingController(text: widget.spot?.name);
  late final _coord = TextEditingController(
      text: widget.spot?.hasCoord == true
          ? '${widget.spot!.lat}, ${widget.spot!.lon}'
          : '');
  late final _note = TextEditingController(text: widget.spot?.note);
  late String _water = widget.spot?.waterType ?? '';
  bool _saving = false;
  String? _err;

  static const _waters = ['水库', '野河', '湖泊', '黑坑', '溪流', '其他'];

  @override
  void dispose() {
    _name.dispose();
    _coord.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _err = '给钓点起个名字');
      return;
    }
    final c = _coord.text.trim();
    final ll = c.isEmpty ? null : parseLatLon(c);
    if (c.isNotEmpty && ll == null) {
      setState(() => _err = '坐标格式：纬度, 经度（例如 30.27, 120.15）');
      return;
    }
    setState(() {
      _saving = true;
      _err = null;
    });
    try {
      final s = await context.read<FishingState>().saveSpot({
        'name': name,
        if (ll != null) 'lat': ll.$1,
        if (ll != null) 'lon': ll.$2,
        'water_type': _water,
        'note': _note.text.trim(),
      }, uuid: widget.spot?.uuid);
      if (mounted) Navigator.of(context).pop(s);
    } catch (e) {
      if (mounted) setState(() => _err = '保存失败，稍后再试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpace.xl, AppSpace.lg, AppSpace.xl,
          MediaQuery.of(context).viewInsets.bottom + AppSpace.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.spot == null ? '新建私人钓点' : '编辑钓点',
              style: AppType.title.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: AppSpace.xs),
          Text('钓点只有你自己能看到。',
              style: AppType.caption.copyWith(color: AppColors.textTertiary)),
          TextField(
              key: const Key('spot-name'),
              controller: _name,
              decoration: const InputDecoration(labelText: '名称')),
          TextField(
            key: const Key('spot-coord'),
            controller: _coord,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,，\s-]'))
            ],
            decoration: const InputDecoration(
                labelText: '坐标（可选）', hintText: '纬度, 经度，可从地图 App 复制'),
          ),
          const SizedBox(height: AppSpace.md),
          Wrap(spacing: AppSpace.sm, children: [
            for (final w in _waters)
              ChoiceChip(
                label: Text(w),
                selected: _water == w,
                onSelected: (v) => setState(() => _water = v ? w : ''),
              ),
          ]),
          TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: '备注（停车、钓位、水深…）')),
          if (_err != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(_err!,
                style: AppType.caption.copyWith(color: AppColors.danger)),
          ],
          const SizedBox(height: AppSpace.lg),
          FilledButton(
            key: const Key('spot-save'),
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : '保存'),
          ),
        ],
      ),
    );
  }
}
