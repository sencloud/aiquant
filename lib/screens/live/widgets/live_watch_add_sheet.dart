import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/live_state.dart';
import '../../../theme/app_theme.dart';

/// 关注添加 bottom sheet：手动输入 ts_code（如 600519.SH）+ 可选中文名。
///
/// MVP 不接 search_instrument 接口；后续可以在这里加 typeahead 搜索。
class LiveWatchAddSheet {
  static Future<void> show(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _AddSheet(),
    );
  }
}

class _AddSheet extends StatefulWidget {
  const _AddSheet();
  @override
  State<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends State<_AddSheet> {
  final _symbolCtl = TextEditingController();
  final _nameCtl = TextEditingController();
  bool _submitting = false;
  String? _err;

  @override
  void dispose() {
    _symbolCtl.dispose();
    _nameCtl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final sym = _symbolCtl.text.trim().toUpperCase();
    if (sym.isEmpty) {
      setState(() => _err = '请输入股票代码（如 600519.SH）');
      return;
    }
    if (!RegExp(r'^[0-9A-Z]{4,8}\.(SH|SZ|BJ)$').hasMatch(sym)) {
      setState(() => _err = '格式不对：需要带后缀，如 600519.SH / 000001.SZ');
      return;
    }
    setState(() {
      _submitting = true;
      _err = null;
    });
    try {
      await context
          .read<LiveState>()
          .addWatch(sym, name: _nameCtl.text.trim());
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _err = '添加失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderDim,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '加关注（直播将优先纳入选股）',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '示例：贵州茅台 600519.SH；招商银行 600036.SH；宁德时代 300750.SZ',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _symbolCtl,
            textCapitalization: TextCapitalization.characters,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '股票代码（必填）',
              hintText: '600519.SH',
              filled: true,
              fillColor: AppColors.bgRaised,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.borderDim),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _nameCtl,
            decoration: InputDecoration(
              labelText: '中文名（可选）',
              hintText: '贵州茅台',
              filled: true,
              fillColor: AppColors.bgRaised,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.borderDim),
              ),
            ),
          ),
          if (_err != null) ...[
            const SizedBox(height: 8),
            Text(_err!,
                style: const TextStyle(
                    color: Color(0xFFef4444), fontSize: 12)),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.amber,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _submitting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('加入关注', style: TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}
