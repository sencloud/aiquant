import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../../models/portfolio.dart';
import '../../../state/portfolio_state.dart';
import '../../../theme/app_theme.dart';

/// "报告" — 一键导出组合的 Markdown / JSON / PDF 报告。
class ReportsTab extends StatefulWidget {
  const ReportsTab({super.key});

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  bool _exporting = false;

  @override
  Widget build(BuildContext context) {
    final ps = context.watch<PortfolioState>();
    final s = ps.currentSummary;
    if (s == null || s.holdings.isEmpty) {
      return const _Empty('加入品种后这里会生成可分享的组合报告。');
    }

    final markdown = _buildMarkdown(s);
    final json = const JsonEncoder.withIndent('  ').convert({
      'name': s.portfolio.name,
      'currency': s.portfolio.currency,
      'total_market_value': s.totalMarketValue,
      'total_pnl': s.totalUnrealizedPnl,
      'positions': [
        for (final h in s.holdings)
          {
            'symbol': h.symbol,
            'name': h.name,
            'sector': h.sector,
            'asset_class': h.assetClass,
            'quantity': h.quantity,
            'avg_buy_price': h.avgBuyPrice,
            'current_price': h.currentPrice,
            'market_value': h.marketValue,
            'unrealized_pnl': h.unrealizedPnl,
            'unrealized_pnl_pct': h.unrealizedPnlPercent,
          },
      ],
    });

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Expanded(child: _Title('一键导出')),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.picture_as_pdf, size: 16),
                      label: Text(_exporting ? '生成中…' : '导出 PDF / 分享'),
                      onPressed: _exporting
                          ? null
                          : () => _exportPdf(context, s),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.content_copy, size: 16),
                      label: const Text('复制 Markdown'),
                      onPressed: () => _copy(context, markdown),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.code, size: 16),
                      label: const Text('复制 JSON'),
                      onPressed: () => _copy(context, json),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                    '说明：PDF 使用思源黑体（首次生成需要联网下载并缓存中文字体）。',
                    style: TextStyle(
                        color: AppColors.textTertiary, fontSize: 10)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(child: _Title('Markdown 报告')),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.copy, size: 14),
                      label: const Text('复制'),
                      onPressed: () => _copy(context, markdown),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _CodeBlock(text: markdown),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(child: _Title('JSON 导出')),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.copy, size: 14),
                      label: const Text('复制'),
                      onPressed: () => _copy(context, json),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _CodeBlock(text: json),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制到剪贴板')),
      );
    }
  }

  Future<void> _exportPdf(BuildContext context, PortfolioSummary s) async {
    setState(() => _exporting = true);
    try {
      final bytes = await _buildPdf(s);
      await Printing.sharePdf(
          bytes: bytes,
          filename:
              '${s.portfolio.name}_组合报告_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF 导出失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// 生成 PDF 字节流。pdf 包默认 Latin 字体，中文必须额外加载字体；
  /// 这里用 printing 包的 PdfGoogleFonts 拉取「思源黑体」(Noto Sans SC)。
  Future<Uint8List> _buildPdf(PortfolioSummary s) async {
    final font = await PdfGoogleFonts.notoSansSCRegular();
    final fontBold = await PdfGoogleFonts.notoSansSCBold();
    final theme = pw.ThemeData.withFont(base: font, bold: fontBold);

    final fmt = NumberFormat('#,##0.00');
    final df = DateFormat('yyyy-MM-dd HH:mm');

    final doc = pw.Document(theme: theme);

    final sectorRows = (s.sectorWeights.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .toList();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        header: (ctx) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 8),
          decoration: const pw.BoxDecoration(
            border: pw.Border(
                bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.5)),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('${s.portfolio.name} 组合报告',
                  style: pw.TextStyle(
                      fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.Text(df.format(s.lastUpdated),
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey600)),
            ],
          ),
        ),
        footer: (ctx) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 8),
          child: pw.Text('Page ${ctx.pageNumber} / ${ctx.pagesCount}',
              style:
                  const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
        ),
        build: (ctx) => [
          pw.SizedBox(height: 8),
          pw.Text('概览',
              style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.amber800)),
          pw.SizedBox(height: 4),
          pw.Wrap(
            spacing: 20,
            runSpacing: 6,
            children: [
              _kvPdf('货币', s.portfolio.currency),
              _kvPdf('持仓数',
                  '${s.positions} (涨 ${s.gainers} · 跌 ${s.losers})'),
              _kvPdf('组合市值', fmt.format(s.totalMarketValue)),
              _kvPdf(
                  '未实现盈亏',
                  '${s.totalUnrealizedPnl >= 0 ? '+' : '-'}${fmt.format(s.totalUnrealizedPnl.abs())} '
                      '(${s.totalUnrealizedPnlPercent.toStringAsFixed(2)}%)'),
              _kvPdf('生成时间', df.format(s.lastUpdated)),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Text('持仓明细',
              style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.amber800)),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            cellStyle: const pw.TextStyle(fontSize: 9),
            headerStyle: pw.TextStyle(
                fontSize: 9.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.amber800),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerLeft,
              2: pw.Alignment.centerLeft,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
              6: pw.Alignment.centerRight,
              7: pw.Alignment.centerRight,
            },
            headers: ['代码', '名称', '行业', '数量', '均价', '最新', '市值', '盈亏%'],
            data: [
              for (final h in s.holdings)
                [
                  h.symbol,
                  h.name,
                  h.sector,
                  fmt.format(h.quantity),
                  fmt.format(h.avgBuyPrice),
                  h.currentPrice == null ? '--' : fmt.format(h.currentPrice),
                  fmt.format(h.marketValue),
                  '${h.unrealizedPnlPercent.toStringAsFixed(2)}%',
                ]
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Text('行业分布',
              style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.amber800)),
          pw.SizedBox(height: 4),
          pw.TableHelper.fromTextArray(
            cellStyle: const pw.TextStyle(fontSize: 9.5),
            headerStyle: pw.TextStyle(
                fontSize: 9.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white),
            headerDecoration:
                const pw.BoxDecoration(color: PdfColors.amber800),
            cellAlignments: {
              0: pw.Alignment.centerLeft,
              1: pw.Alignment.centerRight,
            },
            headers: ['行业', '占比'],
            data: [
              for (final e in sectorRows)
                [e.key, '${e.value.toStringAsFixed(1)}%']
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Text('免责声明',
              style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey700)),
          pw.SizedBox(height: 2),
          pw.Text(
              '本报告基于 Tushare 数据与本地交易记录生成，仅供参考；不构成任何投资建议。',
              style:
                  const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ],
      ),
    );

    return doc.save();
  }

  pw.Widget _kvPdf(String k, String v) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text('$k：',
            style: const pw.TextStyle(
                fontSize: 9.5, color: PdfColors.grey700)),
        pw.Text(v,
            style: pw.TextStyle(
                fontSize: 10, fontWeight: pw.FontWeight.bold)),
      ],
    );
  }

  String _buildMarkdown(PortfolioSummary s) {
    final fmt = NumberFormat('#,##0.00');
    final df = DateFormat('yyyy-MM-dd HH:mm');
    final sb = StringBuffer();
    sb.writeln('# ${s.portfolio.name} 组合报告');
    sb.writeln();
    sb.writeln('* 货币：${s.portfolio.currency}');
    sb.writeln('* 持仓数：${s.positions} (涨 ${s.gainers} · 跌 ${s.losers})');
    sb.writeln('* 组合市值：${fmt.format(s.totalMarketValue)}');
    sb.writeln(
        '* 未实现盈亏：${s.totalUnrealizedPnl >= 0 ? '+' : '-'}${fmt.format(s.totalUnrealizedPnl.abs())} '
        '(${s.totalUnrealizedPnlPercent.toStringAsFixed(2)}%)');
    sb.writeln('* 生成时间：${df.format(s.lastUpdated)}');
    sb.writeln();
    sb.writeln('## 持仓明细');
    sb.writeln();
    sb.writeln('| 代码 | 名称 | 行业 | 数量 | 均价 | 最新 | 市值 | 盈亏% |');
    sb.writeln('| --- | --- | --- | ---: | ---: | ---: | ---: | ---: |');
    for (final h in s.holdings) {
      sb.writeln(
          '| ${h.symbol} | ${h.name} | ${h.sector} | ${fmt.format(h.quantity)} '
          '| ${fmt.format(h.avgBuyPrice)} | ${h.currentPrice == null ? "--" : fmt.format(h.currentPrice)} '
          '| ${fmt.format(h.marketValue)} | ${h.unrealizedPnlPercent.toStringAsFixed(2)}% |');
    }
    sb.writeln();
    sb.writeln('## 行业分布');
    sb.writeln();
    final w = s.sectorWeights.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in w) {
      sb.writeln('* ${e.key}：${e.value.toStringAsFixed(1)}%');
    }
    return sb.toString();
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(
          color: AppColors.amber,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6));
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
        ),
      );
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.bgBase,
        border: Border.all(color: AppColors.borderDim),
        borderRadius: BorderRadius.circular(2),
      ),
      child: SelectableText(
        text,
        style: TextStyle(
          color: AppColors.textPrimary,
          fontFamily: 'monospace',
          fontSize: 11,
          height: 1.4,
        ),
      ),
    );
  }
}
