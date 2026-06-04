import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../services/portfolio_import_service.dart';
import '../../../state/portfolio_state.dart';
import '../../../theme/app_theme.dart';

/// 「券商截图导入」对话框：选图 → 调用 vision 解析 → 用户编辑 → 批量导入。
///
/// 使用方式：
///   await showDialog(context: context, builder: (_) =>
///       const ImportScreenshotDialog());
///
/// 设计要点：
///  - 单一对话框承载完整流程，不强制用户跳页；
///  - 解析失败 / 列表为空时仍可重新选图，不退出；
///  - 解析成功后给一个可编辑的列表（代码/数量/成本可改），用户确认前
///    可以剔除模型识别错误的行。
class ImportScreenshotDialog extends StatefulWidget {
  const ImportScreenshotDialog({super.key});

  @override
  State<ImportScreenshotDialog> createState() =>
      _ImportScreenshotDialogState();
}

class _ImportScreenshotDialogState extends State<ImportScreenshotDialog> {
  final _picker = ImagePicker();
  final _svc = PortfolioImportService();

  bool _busy = false;
  String? _error;
  List<_EditableRow> _rows = const [];
  String _brokerHint = '';

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.bgSurface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.borderDim),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: MediaQuery.of(context).size.height * 0.86,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            Divider(height: 1, color: AppColors.borderDim),
            Expanded(child: _body()),
            Divider(height: 1, color: AppColors.borderDim),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
      child: Row(
        children: [
          const Icon(Icons.add_photo_alternate_outlined,
              color: AppColors.amber, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '券商截图导入',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: _busy ? null : () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_busy) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.amber),
              const SizedBox(height: 12),
              Text('正在识别截图…',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
    }
    if (_rows.isEmpty) {
      return _empty();
    }
    return _editor();
  }

  Widget _empty() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '把券商 App 的"持仓"页截图发上来，AI 会把代码/数量/成本读出来供你确认导入。',
            style: TextStyle(
                color: AppColors.textPrimary, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 8),
          Text(
            '提示：请截图包含完整列名行（市值/持仓/现价/成本/盈亏…）效果更好。',
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 11, height: 1.5),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.danger.withValues(alpha: 0.10),
                border: Border.all(
                    color: AppColors.danger.withValues(alpha: 0.40)),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _error!,
                style: const TextStyle(
                    color: AppColors.danger, fontSize: 11),
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _pick(ImageSource.gallery),
              icon: const Icon(Icons.image_outlined, size: 16),
              label: const Text('从相册选择'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _editor() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline,
                  color: AppColors.amber, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _brokerHint.isEmpty
                      ? '识别出 ${_rows.length} 条持仓，请核对后导入'
                      : '识别出 ${_rows.length} 条持仓（来源：$_brokerHint）',
                  style: TextStyle(
                      color: AppColors.textPrimary, fontSize: 12),
                ),
              ),
              TextButton.icon(
                onPressed: () => _pick(ImageSource.gallery),
                icon: const Icon(Icons.refresh, size: 14),
                label: const Text('换一张', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            itemCount: _rows.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: AppColors.borderDim),
            itemBuilder: (_, i) => _rowEditor(i),
          ),
        ),
      ],
    );
  }

  Widget _rowEditor(int i) {
    final row = _rows[i];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 24,
                child: Checkbox(
                  value: row.enabled,
                  onChanged: (v) => setState(() => row.enabled = v ?? true),
                  activeColor: AppColors.amber,
                ),
              ),
              Expanded(
                child: TextFormField(
                  initialValue: row.name,
                  onChanged: (v) => row.name = v,
                  decoration: const InputDecoration(
                    labelText: '名称',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: TextFormField(
                  initialValue: row.code,
                  onChanged: (v) => row.code = v,
                  decoration: const InputDecoration(
                    labelText: '代码',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: _fmt(row.quantity),
                  onChanged: (v) =>
                      row.quantity = double.tryParse(v) ?? 0,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: '数量',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: _fmt(row.avgCost),
                  onChanged: (v) =>
                      row.avgCost = double.tryParse(v) ?? 0,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: '成本价',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: _fmt(row.currentPrice),
                  enabled: false,
                  decoration: const InputDecoration(
                    labelText: '现价（仅参考）',
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    final canImport = _rows.any((r) =>
        r.enabled &&
        r.code.trim().isNotEmpty &&
        r.quantity > 0 &&
        r.avgCost > 0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed:
                (_rows.isEmpty || !canImport || _busy) ? null : _import,
            icon: const Icon(Icons.cloud_download_outlined, size: 16),
            label: const Text('导入到当前组合'),
          ),
        ],
      ),
    );
  }

  Future<void> _pick(ImageSource src) async {
    setState(() => _error = null);
    XFile? file;
    try {
      file = await _picker.pickImage(
        source: src,
        imageQuality: 90,
        maxWidth: 2400,
      );
    } catch (e) {
      setState(() => _error = '调起相册失败：$e');
      return;
    }
    if (file == null) return;

    setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      final result = await _svc.parseScreenshot(
        imageBytes: bytes,
        mimeType: file.mimeType ?? 'image/png',
      );
      setState(() {
        _brokerHint = result.brokerHint;
        _rows = result.holdings.map(_EditableRow.fromParsed).toList();
        _busy = false;
        if (_rows.isEmpty) {
          _error = '没识别到任何持仓行，请换一张更清晰的截图';
        }
      });
    } catch (e) {
      setState(() {
        _error = '识别失败：$e';
        _busy = false;
      });
    }
  }

  Future<void> _import() async {
    final ps = context.read<PortfolioState>();
    final rows = _rows
        .where((r) =>
            r.enabled &&
            r.code.trim().isNotEmpty &&
            r.quantity > 0 &&
            r.avgCost > 0)
        .map((r) => (
              code: r.code.trim(),
              name: r.name.trim(),
              market: r.market,
              quantity: r.quantity,
              avgCost: r.avgCost,
            ))
        .toList();
    if (rows.isEmpty) return;
    setState(() => _busy = true);
    int n;
    try {
      n = await ps.importParsedHoldings(rows);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '导入失败：$e';
        _busy = false;
      });
      return;
    }
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已导入 $n 条持仓到当前组合')),
    );
  }

  String _fmt(double v) {
    if (v == 0) return '';
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }
}

class _EditableRow {
  _EditableRow({
    required this.name,
    required this.code,
    required this.market,
    required this.quantity,
    required this.avgCost,
    required this.currentPrice,
  });

  factory _EditableRow.fromParsed(ParsedHolding p) => _EditableRow(
        name: p.name,
        code: p.code,
        market: p.market,
        quantity: p.quantity,
        avgCost: p.avgCost,
        currentPrice: p.currentPrice,
      );

  bool enabled = true;
  String name;
  String code;
  String market;
  double quantity;
  double avgCost;
  double currentPrice;
}
