import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../state/portfolio_state.dart';
import '../../../theme/app_theme.dart';

/// "交易" tab — 完整账本 + CSV 批量导入 + 公司行动（分红/拆分）。
class TransactionsTab extends StatelessWidget {
  const TransactionsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final ps = context.watch<PortfolioState>();
    final txns = ps.currentTransactions();
    final df = DateFormat('yyyy-MM-dd');
    final fmt = NumberFormat('#,##0.00');

    return Column(
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.bgRaised,
            border: Border(
              bottom: BorderSide(color: AppColors.borderDim),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '共 ${txns.length} 条记录',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12),
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.upload_file, size: 14),
                label: const Text('导入 CSV'),
                onPressed: () => _importCsv(context),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.account_tree_outlined, size: 14),
                label: const Text('公司行动'),
                onPressed: () => _corporateActionDialog(context),
              ),
            ],
          ),
        ),
        Expanded(
          child: txns.isEmpty
              ? _empty()
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  itemCount: txns.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: AppColors.borderDim),
                  itemBuilder: (_, i) {
                    final t = txns[i];
                    final color = _typeColor(t.type);
                    return Dismissible(
                      key: ValueKey(t.id),
                      background: Container(
                        alignment: Alignment.centerRight,
                        color: AppColors.danger,
                        padding: const EdgeInsets.only(right: 16),
                        child: const Icon(Icons.delete_outline,
                            color: Colors.white),
                      ),
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (_) async {
                        return await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('删除交易记录'),
                                content: const Text('确定要删除这条交易吗？'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(ctx, false),
                                    child: const Text('取消'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () =>
                                        Navigator.pop(ctx, true),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            AppColors.danger),
                                    child: const Text('删除'),
                                  ),
                                ],
                              ),
                            ) ??
                            false;
                      },
                      onDismissed: (_) => ps.deleteTransaction(t.id),
                      child: ListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        leading: Container(
                          width: 38,
                          height: 22,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border.all(color: color),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(_typeLabel(t.type),
                              style: TextStyle(
                                  color: color,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800)),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${t.symbol}  ${t.name}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                            Text(df.format(t.date),
                                style: TextStyle(
                                    color: AppColors.textTertiary,
                                    fontSize: 11)),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Row(
                            children: [
                              Text(_subtitleText(t.type, t, fmt),
                                  style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontFamily: 'monospace',
                                      fontSize: 11)),
                              if (t.notes.isNotEmpty)
                                Expanded(
                                  child: Text('  · ${t.notes}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: AppColors.textTertiary,
                                          fontSize: 10)),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _subtitleText(
      String type, dynamic t, NumberFormat fmt) {
    switch (type) {
      case 'split':
        return '拆分比例 ${fmt.format(t.quantity)}（仓位 × ${fmt.format(t.quantity)}）';
      case 'dividend':
        return '${fmt.format(t.quantity)} 股 × ${fmt.format(t.price)}/股 = ${fmt.format(t.totalValue)} 现金';
      default:
        return '${fmt.format(t.quantity)} × ${fmt.format(t.price)} = ${fmt.format(t.totalValue)}';
    }
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('当前组合还没有交易记录。',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      ),
    );
  }

  // ── CSV 导入 ────────────────────────────────────────────────────────────

  Future<void> _importCsv(BuildContext context) async {
    final ps = context.read<PortfolioState>();
    final pick = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'txt'],
      withData: true,
    );
    if (pick == null || pick.files.isEmpty) return;
    final f = pick.files.first;
    if (f.bytes == null) {
      if (context.mounted) _toast(context, '无法读取文件内容');
      return;
    }
    final content = utf8.decode(f.bytes!, allowMalformed: true);

    final res = await ps.importTransactionsCsv(content);
    if (!context.mounted) return;
    final msg = StringBuffer('已导入 ${res.imported} 条记录');
    if (res.errors.isNotEmpty) {
      msg.write('；${res.errors.length} 条错误');
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('CSV 导入完成'),
        content: SingleChildScrollView(
          child: Text(
            res.errors.isEmpty
                ? msg.toString()
                : '${msg.toString()}\n\n${res.errors.take(10).join('\n')}'
                    '${res.errors.length > 10 ? '\n…（更多错误已省略）' : ''}',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('确定')),
        ],
      ),
    );
  }

  // ── 公司行动对话框 ──────────────────────────────────────────────────────

  Future<void> _corporateActionDialog(BuildContext context) async {
    final ps = context.read<PortfolioState>();
    final summary = ps.currentSummary;
    if (summary == null || summary.holdings.isEmpty) {
      _toast(context, '请先添加持仓');
      return;
    }

    String? symbol = summary.holdings.first.symbol;
    String type = 'dividend';
    final qtyCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final ratioCtrl = TextEditingController(text: '2');
    DateTime date = DateTime.now();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
        return AlertDialog(
          title: const Text('记录公司行动'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: symbol,
                  decoration: const InputDecoration(labelText: '持仓'),
                  items: [
                    for (final h in summary.holdings)
                      DropdownMenuItem(
                        value: h.symbol,
                        child: Text(
                            '${h.symbol}  ${h.name.isEmpty ? '' : h.name}'),
                      ),
                  ],
                  onChanged: (v) => setState(() => symbol = v),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: '类型'),
                  items: const [
                    DropdownMenuItem(
                        value: 'dividend', child: Text('现金分红')),
                    DropdownMenuItem(
                        value: 'split', child: Text('拆分 / 送股')),
                  ],
                  onChanged: (v) => setState(() => type = v ?? 'dividend'),
                ),
                const SizedBox(height: 8),
                if (type == 'dividend') ...[
                  TextField(
                    controller: qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: '当时持仓股数', hintText: '例如 1000'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: '每股分红 (元)', hintText: '例如 0.5'),
                  ),
                ] else ...[
                  TextField(
                    controller: ratioCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: '拆分比例',
                        hintText: '1 拆 2 → 输入 2；2 合 1 → 0.5'),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text('日期：${DateFormat('yyyy-MM-dd').format(date)}'),
                    ),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: date,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) setState(() => date = picked);
                      },
                      child: const Text('选择'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消')),
            ElevatedButton(
              onPressed: () async {
                if (symbol == null) return;
                final h = summary.holdings.firstWhere(
                  (e) => e.symbol == symbol,
                  orElse: () => summary.holdings.first,
                );
                if (type == 'dividend') {
                  final q = double.tryParse(qtyCtrl.text);
                  final p = double.tryParse(priceCtrl.text);
                  if (q == null || p == null || q <= 0 || p <= 0) {
                    _toast(ctx, '请输入合法的数量与每股分红');
                    return;
                  }
                  await ps.recordDividend(
                    symbol: symbol!,
                    quantity: q,
                    dividendPerShare: p,
                    date: date,
                    name: h.name,
                    sector: h.sector,
                    assetClass: h.assetClass,
                  );
                } else {
                  final r = double.tryParse(ratioCtrl.text);
                  if (r == null || r <= 0) {
                    _toast(ctx, '请输入合法的拆分比例');
                    return;
                  }
                  await ps.recordSplit(
                    symbol: symbol!,
                    ratio: r,
                    date: date,
                    name: h.name,
                    sector: h.sector,
                    assetClass: h.assetClass,
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        );
      }),
    );
  }

  void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  static String _typeLabel(String t) {
    switch (t) {
      case 'buy':
        return '买入';
      case 'sell':
        return '卖出';
      case 'dividend':
        return '分红';
      case 'split':
        return '拆分';
      default:
        return t.toUpperCase();
    }
  }

  static Color _typeColor(String t) {
    switch (t) {
      case 'buy':
        return AppColors.positive;
      case 'sell':
        return AppColors.negative;
      case 'dividend':
        return AppColors.amber;
      case 'split':
        return AppColors.info;
      default:
        return AppColors.textSecondary;
    }
  }
}
