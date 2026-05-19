import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../../core/storage/hive_setup.dart';
import '../../../core/utils/china_market.dart';
import '../../../models/portfolio.dart';
import '../../../services/ai_chat_service.dart';
import '../../../state/portfolio_state.dart';
import '../../../theme/app_theme.dart';

/// 报告 Tab — 直接以排版好的卡片形式展示组合报告，
/// 顶部仅提供「导出 PDF」与「复制纯文本」两个动作。
class ReportsTab extends StatefulWidget {
  const ReportsTab({super.key});

  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  bool _exporting = false;

  // AI 诊断报告状态
  final _aiSvc = AiChatService();
  StreamSubscription<AiChatEvent>? _aiSub;
  String _aiText = '';
  String _aiReasoning = '';
  bool _aiLoading = false;
  String? _aiError;
  DateTime? _aiGeneratedAt;
  String? _aiCacheKeyLoaded;

  static const _kAiCachePrefix = 'portfolio_ai_report:';

  @override
  void dispose() {
    _aiSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ps = context.watch<PortfolioState>();
    final s = ps.currentSummary;
    if (s == null || s.holdings.isEmpty) {
      return const _Empty('加入品种后这里会生成可分享的组合报告。');
    }

    // 进入页面 / 切换组合时尝试加载缓存的 AI 报告（不自动发请求）
    final key = _aiCacheKey(s);
    if (_aiCacheKeyLoaded != key) {
      _aiCacheKeyLoaded = key;
      _loadCachedAi(key);
    }

    final fmt = NumberFormat('#,##0.00');
    final df = DateFormat('yyyy-MM-dd HH:mm');
    final sectorRows = (s.sectorWeights.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .toList();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _aiReportCard(s),
        const SizedBox(height: 12),
        _actionsCard(s),
        const SizedBox(height: 12),
        _summaryCard(s, fmt, df),
        const SizedBox(height: 12),
        _holdingsCard(s, fmt),
        const SizedBox(height: 12),
        _sectorCard(sectorRows),
        const SizedBox(height: 12),
        _disclaimerCard(),
      ],
    );
  }

  // ── AI 诊断报告卡 ───────────────────────────────────────────────────

  /// AI 诊断报告卡：未生成时显示「生成」按钮；生成中显示流式 markdown +
  /// reasoning（可选）；生成完显示 markdown + 时间戳 + 重新生成 + 复制。
  Widget _aiReportCard(PortfolioSummary s) {
    final df = DateFormat('yyyy-MM-dd HH:mm');
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome,
                    color: AppColors.amber, size: 14),
                const SizedBox(width: 6),
                const Expanded(child: _Title('AI 持仓诊断')),
                if (_aiGeneratedAt != null && !_aiLoading)
                  Text(
                    df.format(_aiGeneratedAt!),
                    style: TextStyle(
                        color: AppColors.textTertiary, fontSize: 10),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            if (_aiText.isEmpty && !_aiLoading) _aiEmpty(s),
            if (_aiLoading) ...[
              if (_aiReasoning.isNotEmpty) _aiReasoningBlock(),
              if (_aiText.isNotEmpty)
                _aiMarkdownBlock(_aiText, streaming: true),
              if (_aiText.isEmpty && _aiReasoning.isEmpty)
                const _AiThinkingDots(),
            ] else if (_aiText.isNotEmpty) ...[
              _aiMarkdownBlock(_aiText, streaming: false),
            ],
            if (_aiError != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.40)),
                ),
                child: Text(_aiError!,
                    style: const TextStyle(
                        color: AppColors.danger, fontSize: 11)),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (_aiText.isEmpty)
                  ElevatedButton.icon(
                    onPressed: _aiLoading ? null : () => _runAiReport(s),
                    icon: const Icon(Icons.bolt_rounded, size: 16),
                    label: const Text('生成 AI 诊断'),
                  )
                else ...[
                  OutlinedButton.icon(
                    onPressed: _aiLoading ? null : () => _runAiReport(s),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('重新生成'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _copy(context, _aiText),
                    icon: const Icon(Icons.content_copy, size: 16),
                    label: const Text('复制全文'),
                  ),
                ],
                if (_aiLoading)
                  TextButton.icon(
                    onPressed: _abortAi,
                    icon: const Icon(Icons.stop_circle_outlined, size: 16),
                    label: const Text('停止生成'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _aiEmpty(PortfolioSummary s) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        '基于当前 ${s.holdings.length} 只持仓 + 实时行情 + 关键新闻，'
        'AI 会出一份可执行的诊断报告（行业集中度、个股逻辑、风险点、下周重点）。'
        '默认深度推理，预计耗几枚喜点。',
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
          height: 1.55,
        ),
      ),
    );
  }

  Widget _aiReasoningBlock() {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.bgRaised,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderDim),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_outlined,
                  color: AppColors.amber, size: 12),
              const SizedBox(width: 4),
              Text('推理中…',
                  style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _aiReasoning,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 10, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _aiMarkdownBlock(String md, {required bool streaming}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.bgBase,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderDim),
      ),
      child: MarkdownBody(
        data: md.isEmpty ? '…' : md,
        selectable: true,
        styleSheet: MarkdownStyleSheet(
          p: TextStyle(
              color: AppColors.textPrimary, fontSize: 12, height: 1.55),
          h1: const TextStyle(
              color: AppColors.amber,
              fontWeight: FontWeight.w800,
              fontSize: 16),
          h2: const TextStyle(
              color: AppColors.amber,
              fontWeight: FontWeight.w800,
              fontSize: 14),
          h3: const TextStyle(
              color: AppColors.amber,
              fontWeight: FontWeight.w800,
              fontSize: 13),
          listBullet:
              TextStyle(color: AppColors.textPrimary, fontSize: 12),
          strong: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w800),
          tableHead: const TextStyle(
              color: AppColors.amber,
              fontSize: 11,
              fontWeight: FontWeight.w800),
          tableBody: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 11,
              fontFamily: 'monospace'),
          code: TextStyle(
              color: AppColors.amber,
              backgroundColor: AppColors.bgRaised,
              fontFamily: 'monospace',
              fontSize: 11),
          codeblockDecoration: BoxDecoration(
            color: AppColors.bgRaised,
            border: Border.all(color: AppColors.borderDim),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }

  String _aiCacheKey(PortfolioSummary s) =>
      '$_kAiCachePrefix${s.portfolio.id}';

  Future<void> _loadCachedAi(String key) async {
    final raw = prefsBox.get(key);
    if (raw is! Map) {
      _resetAi();
      return;
    }
    final text = raw['text'] as String? ?? '';
    final atMs = raw['at_ms'] as int?;
    if (text.isEmpty) {
      _resetAi();
      return;
    }
    setState(() {
      _aiText = text;
      _aiGeneratedAt =
          atMs == null ? null : DateTime.fromMillisecondsSinceEpoch(atMs);
      _aiError = null;
    });
  }

  void _resetAi() {
    if (!mounted) return;
    setState(() {
      _aiText = '';
      _aiReasoning = '';
      _aiGeneratedAt = null;
      _aiError = null;
    });
  }

  Future<void> _runAiReport(PortfolioSummary s) async {
    await _aiSub?.cancel();
    setState(() {
      _aiLoading = true;
      _aiError = null;
      _aiText = '';
      _aiReasoning = '';
    });
    final completer = Completer<void>();
    _aiSub = _aiSvc
        .stream(
      message: _kReportPrompt,
      systemHint: _kReportSystemHint,
      deepMode: true,
      portfolioContext: s.toAiContext(),
    )
        .listen((ev) {
      switch (ev.kind) {
        case AiChatEventKind.textDelta:
          if (!mounted) return;
          setState(() => _aiText += ev.delta ?? '');
          break;
        case AiChatEventKind.toolCall:
          // 报告页不展示具体 tool 调用细节，只在 reasoning 区透露"在查 xxx"
          if (!mounted) return;
          setState(() {
            _aiReasoning =
                '正在调用工具：${ev.toolName ?? '...'}（${ev.toolArguments ?? ''}）';
          });
          break;
        case AiChatEventKind.toolResult:
          break;
        case AiChatEventKind.session:
          break;
        case AiChatEventKind.done:
          break;
        case AiChatEventKind.error:
          if (!mounted) return;
          setState(() {
            _aiError = '${ev.errorCode}：${ev.errorMessage}';
          });
          break;
      }
    }, onError: (Object e, StackTrace _) {
      if (!completer.isCompleted) completer.complete();
    }, onDone: () {
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future;
    if (!mounted) return;
    setState(() {
      _aiLoading = false;
      _aiReasoning = '';
      if (_aiText.isNotEmpty) {
        _aiGeneratedAt = DateTime.now();
        prefsBox.put(_aiCacheKey(s), {
          'text': _aiText,
          'at_ms': _aiGeneratedAt!.millisecondsSinceEpoch,
        });
      }
    });
  }

  Future<void> _abortAi() async {
    await _aiSub?.cancel();
    _aiSub = null;
    if (!mounted) return;
    setState(() {
      _aiLoading = false;
      _aiReasoning = '';
    });
  }

  Widget _actionsCard(PortfolioSummary s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Title('一键导出'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf, size: 16),
                  label: Text(_exporting ? '生成中…' : '导出 PDF / 分享'),
                  onPressed: _exporting ? null : () => _exportPdf(context, s),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.content_copy, size: 16),
                  label: const Text('复制报告'),
                  onPressed: () => _copy(context, _buildPlainText(s)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
                _aiText.isEmpty
                    ? '说明：PDF 使用思源黑体（首次生成需联网下载并缓存中文字体）。'
                    : '说明：PDF 会一并包含上方 AI 诊断报告 + 持仓明细 / 行业分布。',
                style: TextStyle(
                    color: AppColors.textTertiary, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(
      PortfolioSummary s, NumberFormat fmt, DateFormat df) {
    final pnlColor = s.totalUnrealizedPnl > 0
        ? AppColors.positive
        : (s.totalUnrealizedPnl < 0
            ? AppColors.negative
            : AppColors.textPrimary);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _Title('${s.portfolio.name} · 组合概览')),
                Text(df.format(s.lastUpdated),
                    style: TextStyle(
                        color: AppColors.textTertiary, fontSize: 10)),
              ],
            ),
            const SizedBox(height: 8),
            _kvRow('货币', s.portfolio.currency),
            _kvRow('持仓数', '${s.positions} 只 · 涨 ${s.gainers} · 跌 ${s.losers}'),
            _kvRow('组合市值', fmt.format(s.totalMarketValue)),
            _kvRow(
              '未实现盈亏',
              '${s.totalUnrealizedPnl >= 0 ? '+' : '-'}${fmt.format(s.totalUnrealizedPnl.abs())} '
                  '(${s.totalUnrealizedPnlPercent.toStringAsFixed(2)}%)',
              valueColor: pnlColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _holdingsCard(PortfolioSummary s, NumberFormat fmt) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Title('持仓明细'),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 28,
                dataRowMinHeight: 26,
                dataRowMaxHeight: 30,
                columnSpacing: 18,
                horizontalMargin: 4,
                headingTextStyle: const TextStyle(
                  color: AppColors.amber,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
                dataTextStyle: TextStyle(
                  color: AppColors.textPrimary,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
                columns: const [
                  DataColumn(label: Text('品种')),
                  DataColumn(label: Text('行业')),
                  DataColumn(label: Text('数量'), numeric: true),
                  DataColumn(label: Text('均价'), numeric: true),
                  DataColumn(label: Text('最新'), numeric: true),
                  DataColumn(label: Text('市值'), numeric: true),
                  DataColumn(label: Text('盈亏%'), numeric: true),
                ],
                rows: [
                  for (final h in s.holdings)
                    DataRow(cells: [
                      DataCell(Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(h.name.isEmpty
                              ? ChinaMarket.displaySymbol(h.symbol)
                              : h.name),
                          Text(
                            ChinaMarket.displaySymbol(h.symbol),
                            style: TextStyle(
                                color: AppColors.textTertiary,
                                fontFamily: 'monospace',
                                fontSize: 9),
                          ),
                        ],
                      )),
                      DataCell(Text(h.sector)),
                      DataCell(Text(
                          '${fmt.format(h.quantity)} ${ChinaMarket.quantityUnit(h.assetClass)}')),
                      DataCell(Text(fmt.format(h.avgBuyPrice))),
                      DataCell(Text(h.currentPrice == null
                          ? '--'
                          : fmt.format(h.currentPrice))),
                      DataCell(Text(fmt.format(h.marketValue))),
                      DataCell(Text(
                        '${h.unrealizedPnlPercent >= 0 ? '+' : ''}${h.unrealizedPnlPercent.toStringAsFixed(2)}%',
                        style: TextStyle(
                          color: h.unrealizedPnlPercent > 0
                              ? AppColors.positive
                              : (h.unrealizedPnlPercent < 0
                                  ? AppColors.negative
                                  : AppColors.textPrimary),
                          fontFamily: 'monospace',
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      )),
                    ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectorCard(List<MapEntry<String, double>> rows) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Title('行业分布'),
            const SizedBox(height: 8),
            for (final e in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(e.key,
                          style: TextStyle(
                              color: AppColors.textPrimary, fontSize: 12)),
                    ),
                    SizedBox(
                      width: 80,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: (e.value / 100).clamp(0.0, 1.0),
                          minHeight: 6,
                          backgroundColor: AppColors.bgBase,
                          valueColor: const AlwaysStoppedAnimation(
                              AppColors.amber),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 56,
                      child: Text(
                        '${e.value.toStringAsFixed(1)}%',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontFamily: 'monospace',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
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

  Widget _disclaimerCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Title('免责声明'),
            const SizedBox(height: 6),
            Text(
              '本报告基于 Tushare 行情与本地交易记录生成，仅供参考，不构成任何投资建议。',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kvRow(String k, String v, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(k,
                style: TextStyle(
                    color: AppColors.textTertiary, fontSize: 11)),
          ),
          Expanded(
            child: Text(
              v,
              style: TextStyle(
                color: valueColor ?? AppColors.textPrimary,
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
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
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF 导出失败，请稍后再试')),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// 复制按钮使用的纯文本（便于粘贴到聊天 / 邮件 / 微信）。
  String _buildPlainText(PortfolioSummary s) {
    final fmt = NumberFormat('#,##0.00');
    final df = DateFormat('yyyy-MM-dd HH:mm');
    final sb = StringBuffer();
    sb.writeln('${s.portfolio.name} · 组合报告');
    sb.writeln('生成时间：${df.format(s.lastUpdated)}');
    sb.writeln('--------------------');
    sb.writeln('货币：${s.portfolio.currency}');
    sb.writeln('持仓数：${s.positions} 只（涨 ${s.gainers} · 跌 ${s.losers}）');
    sb.writeln('组合市值：${fmt.format(s.totalMarketValue)}');
    sb.writeln(
        '未实现盈亏：${s.totalUnrealizedPnl >= 0 ? '+' : '-'}${fmt.format(s.totalUnrealizedPnl.abs())} '
        '(${s.totalUnrealizedPnlPercent.toStringAsFixed(2)}%)');
    sb.writeln('--------------------');
    sb.writeln('持仓明细');
    for (final h in s.holdings) {
      sb.writeln(
          '· ${h.symbol} ${h.name} | ${h.sector} | 数量 ${fmt.format(h.quantity)} | '
          '均价 ${fmt.format(h.avgBuyPrice)} | 最新 ${h.currentPrice == null ? "--" : fmt.format(h.currentPrice)} | '
          '市值 ${fmt.format(h.marketValue)} | 盈亏 ${h.unrealizedPnlPercent.toStringAsFixed(2)}%');
    }
    sb.writeln('--------------------');
    sb.writeln('行业分布');
    final w = s.sectorWeights.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in w) {
      sb.writeln('· ${e.key}：${e.value.toStringAsFixed(1)}%');
    }
    sb.writeln('--------------------');
    sb.writeln('免责声明：本报告基于 Tushare 行情与本地交易记录生成，仅供参考，不构成投资建议。');
    return sb.toString();
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

    final aiSnippets = _splitAiMarkdown(_aiText);

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
          if (aiSnippets.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text('AI 持仓诊断',
                style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.amber800)),
            if (_aiGeneratedAt != null)
              pw.Text('生成时间：${df.format(_aiGeneratedAt!)}',
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey600)),
            pw.SizedBox(height: 4),
            for (final block in aiSnippets) block,
            pw.SizedBox(height: 12),
          ],
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

  /// 把 AI 生成的 markdown 拆成一组 pdf widgets。pdf 包没有原生 markdown
  /// 渲染，这里手工识别 #/##/### 标题、`-`/`*` bullet、表格用纯文本表示。
  /// 表格在 markdown 里复杂多变，简单起见整行作为段落输出（用户已能在 UI
  /// 看到漂亮版本，PDF 当作分享附件即可）。
  List<pw.Widget> _splitAiMarkdown(String md) {
    if (md.trim().isEmpty) return const [];
    final out = <pw.Widget>[];
    for (final raw in md.split('\n')) {
      final line = raw.trimRight();
      if (line.isEmpty) {
        out.add(pw.SizedBox(height: 4));
        continue;
      }
      if (line.startsWith('### ')) {
        out.add(pw.Padding(
          padding: const pw.EdgeInsets.only(top: 4, bottom: 2),
          child: pw.Text(line.substring(4),
              style: pw.TextStyle(
                  fontSize: 11, fontWeight: pw.FontWeight.bold)),
        ));
        continue;
      }
      if (line.startsWith('## ')) {
        out.add(pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6, bottom: 2),
          child: pw.Text(line.substring(3),
              style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.amber800)),
        ));
        continue;
      }
      if (line.startsWith('# ')) {
        out.add(pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8, bottom: 3),
          child: pw.Text(line.substring(2),
              style: pw.TextStyle(
                  fontSize: 13, fontWeight: pw.FontWeight.bold)),
        ));
        continue;
      }
      if (line.startsWith('- ') || line.startsWith('* ')) {
        out.add(pw.Padding(
          padding: const pw.EdgeInsets.only(left: 8, top: 1, bottom: 1),
          child: pw.Text('• ${line.substring(2)}',
              style: const pw.TextStyle(fontSize: 9.5)),
        ));
        continue;
      }
      if (RegExp(r'^\d+\.\s').hasMatch(line)) {
        out.add(pw.Padding(
          padding: const pw.EdgeInsets.only(left: 4, top: 1, bottom: 1),
          child: pw.Text(line, style: const pw.TextStyle(fontSize: 9.5)),
        ));
        continue;
      }
      out.add(pw.Padding(
        padding: const pw.EdgeInsets.only(top: 1, bottom: 1),
        child: pw.Text(line, style: const pw.TextStyle(fontSize: 9.5)),
      ));
    }
    return out;
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

class _AiThinkingDots extends StatefulWidget {
  const _AiThinkingDots();

  @override
  State<_AiThinkingDots> createState() => _AiThinkingDotsState();
}

class _AiThinkingDotsState extends State<_AiThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final n = ((_c.value * 4).floor() % 4);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.amber,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'AI 正在分析持仓${'·' * n}',
                style: TextStyle(
                    fontSize: 11, color: AppColors.textSecondary),
              ),
            ],
          ),
        );
      },
    );
  }
}

const _kReportSystemHint = '''
你是专业的中国 A 股投研分析师。任务：基于附带的"用户当前组合快照"，输出一份
可执行的"持仓诊断报告"。允许且鼓励调用提供的 tool 拉行情/财报/新闻/技术指标等
辅助数据；不要凭空猜测。不要对任何标的下"必涨/必跌"结论；不要给免责声明。''';

const _kReportPrompt = '''
请基于已附带的当前组合，生成一份"持仓诊断报告"。结构如下（用 markdown，二级
标题用 ##）：

## 一、整体诊断
- 仓位/集中度/行业偏向（一句话总览 + 关键数字）
- 当前最大风险点（不超过 3 条）
- 当前最重要机会（不超过 3 条）

## 二、个股逐一诊断
对每只持仓输出一段（按市值降序）：
- 标的（代码 + 名称）
- 一句话定位（行业 + 商业模式）
- 现状：现价/成本/盈亏/权重；与同行业对比的相对位置（必要时调用 quote/财务工具）
- 近期催化剂（新闻或公告，必要时调用 search_chinese_news）
- 操作建议：继续持有 / 加仓（具体价位）/ 减仓（具体价位）/ 换仓到谁

## 三、行业集中度风险
- 当前权重排名前 3 的行业
- 是否存在单一行业过度暴露（>30%）的风险
- 给出"再平衡的具体方向"（哪个行业减、哪个加）

## 四、下周关键事件
- 列 3-5 条与当前持仓相关的关键事件 / 数据 / 财报披露日 / 重要会议
- 每条注明影响哪只标的、可能方向

## 五、可执行清单
- 给一份"未来 5 个交易日"逐日操作清单（每日不超过 3 条）
- 每条具体到代码 / 价位 / 数量 / 触发条件
''';
