import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import 'fishing_state.dart';

/// 记一条渔获。照片可选（压到 ≤1280px JPEG 再上传）。
class CatchEditorScreen extends StatefulWidget {
  const CatchEditorScreen({
    super.key,
    this.initialSpecies,
    this.initialPhoto,
    this.initialReleased = false,
  });

  final String? initialSpecies;
  final Uint8List? initialPhoto;
  final bool initialReleased;

  @override
  State<CatchEditorScreen> createState() => _CatchEditorScreenState();
}

const kFishingMethods = ['台钓', '传统钓', '路亚', '海竿', '飞蝇', '冰钓'];

class _CatchEditorScreenState extends State<CatchEditorScreen> {
  late final _species = TextEditingController(text: widget.initialSpecies);
  final _count = TextEditingController(text: '1');
  final _weightJin = TextEditingController();
  final _length = TextEditingController();
  final _bait = TextEditingController();
  final _note = TextEditingController();
  DateTime _at = DateTime.now();
  String _method = '';
  String? _spotUuid;
  late bool _released = widget.initialReleased;
  late Uint8List? _photo = widget.initialPhoto;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_species, _count, _weightJin, _length, _bait, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource src) async {
    try {
      final x = await ImagePicker().pickImage(
          source: src, maxWidth: 1280, maxHeight: 1280, imageQuality: 78);
      if (x == null) return;
      final b = await x.readAsBytes();
      if (mounted) setState(() => _photo = b);
    } catch (_) {}
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (d != null && mounted) {
      setState(
          () => _at = DateTime(d.year, d.month, d.day, _at.hour, _at.minute));
    }
  }

  Future<void> _save() async {
    final species = _species.text.trim();
    if (species.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('填一下鱼种')));
      return;
    }
    final fs = context.read<FishingState>();
    final day = fs.day;
    final jin = double.tryParse(_weightJin.text.trim());
    final body = <String, dynamic>{
      'caught_at': _at.millisecondsSinceEpoch,
      'species': species,
      'count': int.tryParse(_count.text.trim()) ?? 1,
      if (jin != null) 'weight_g': (jin * 500).round(),
      if (double.tryParse(_length.text.trim()) != null)
        'length_cm': double.parse(_length.text.trim()),
      if (_spotUuid != null) 'spot_uuid': _spotUuid,
      'method': _method,
      'bait': _bait.text.trim(),
      'note': _note.text.trim(),
      'released': _released,
      if (day != null && _isToday(_at))
        'weather': '${fs.forecast!.place} 出钓指数 ${day.score}（${day.level}）',
      if (_photo != null)
        'photo': 'data:image/jpeg;base64,${base64Encode(_photo!)}',
    };
    setState(() => _saving = true);
    try {
      await fs.addCatch(body);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('保存失败：$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static bool _isToday(DateTime d) {
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  InputDecoration _dec(String label, {String? suffix}) => InputDecoration(
        labelText: label,
        suffixText: suffix,
        border: InputBorder.none,
        isDense: true,
      );

  Widget _field(Widget child) => Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.lg, vertical: AppSpace.sm),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final spots = context.watch<FishingState>().spots;
    final num = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    return WkPage(
      title: '记渔获',
      actions: [
        TextButton(
          key: const Key('catch-save'),
          onPressed: _saving ? null : _save,
          child: const Text('保存'),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(AppSpace.gutter),
        children: [
          WkGroup(children: [
            _field(TextField(
                key: const Key('catch-species'),
                controller: _species,
                decoration: _dec('鱼种（必填）'))),
            _field(Row(children: [
              Expanded(
                  child: TextField(
                      controller: _count,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: _dec('数量', suffix: '条'))),
              Expanded(
                  child: TextField(
                      controller: _weightJin,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: num,
                      decoration: _dec('总重', suffix: '斤'))),
              Expanded(
                  child: TextField(
                      controller: _length,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: num,
                      decoration: _dec('最长', suffix: 'cm'))),
            ])),
            WkRow(
              title: '时间',
              value: '${_at.year}-${_two(_at.month)}-${_two(_at.day)}',
              onTap: _pickDate,
            ),
          ]),
          WkGroup(header: '钓点与钓法', children: [
            _field(DropdownButtonFormField<String?>(
              initialValue: _spotUuid,
              decoration: _dec('钓点'),
              items: [
                const DropdownMenuItem(value: null, child: Text('不关联')),
                for (final s in spots)
                  DropdownMenuItem(value: s.uuid, child: Text(s.name)),
              ],
              onChanged: (v) => setState(() => _spotUuid = v),
            )),
            _field(Wrap(
              spacing: AppSpace.sm,
              children: [
                for (final m in kFishingMethods)
                  ChoiceChip(
                    label: Text(m),
                    selected: _method == m,
                    onSelected: (v) => setState(() => _method = v ? m : ''),
                  ),
              ],
            )),
            _field(TextField(controller: _bait, decoration: _dec('饵料'))),
          ]),
          WkGroup(header: '照片与备注', children: [
            Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Row(children: [
                if (_photo != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: Image.memory(_photo!,
                        width: 72, height: 72, fit: BoxFit.cover),
                  ),
                if (_photo != null) const SizedBox(width: AppSpace.md),
                OutlinedButton.icon(
                  onPressed: () => _pickPhoto(ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text('拍照'),
                ),
                const SizedBox(width: AppSpace.sm),
                OutlinedButton.icon(
                  onPressed: () => _pickPhoto(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('相册'),
                ),
              ]),
            ),
            _field(TextField(
                controller: _note,
                maxLines: 3,
                minLines: 1,
                decoration: _dec('备注（水情、鱼口、窝料…）'))),
            SwitchListTile(
              title: const Text('已放流', style: AppType.body),
              value: _released,
              onChanged: (v) => setState(() => _released = v),
            ),
          ]),
          const SizedBox(height: AppSpace.md),
          WkPrimaryButton(label: '保存', busy: _saving, onPressed: _save),
        ],
      ),
    );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
