import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/trade_review.dart';
import '../../services/trade_file_parser.dart';
import '../../services/trade_screenshot_parser.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import 'trade_confirm_screen.dart';

class TradeImportScreen extends StatefulWidget {
  const TradeImportScreen({
    super.key,
    this.screenshotPicker,
    this.screenshotParser,
    this.filePicker,
    this.fileParser,
  });

  final TradeScreenshotPicker? screenshotPicker;
  final TradeScreenshotParser? screenshotParser;
  final TradeFilePicker? filePicker;
  final TradeFileParser? fileParser;

  @override
  State<TradeImportScreen> createState() => _TradeImportScreenState();
}

class _TradeImportScreenState extends State<TradeImportScreen> {
  late final TradeScreenshotPicker _screenshotPicker =
      widget.screenshotPicker ?? TradeScreenshotPicker();
  late final TradeScreenshotParser _screenshotParser =
      widget.screenshotParser ?? TradeScreenshotParser();
  late final TradeFilePicker _filePicker =
      widget.filePicker ?? TradeFilePicker();
  late final TradeFileParser _fileParser;

  late DateTime _start;
  late DateTime _end;
  bool _busy = false;
  String? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fileParser = widget.fileParser ?? const TradeFileParser();
    final now = DateTime.now();
    _end = DateTime(now.year, now.month, now.day);
    _start = _end.subtract(const Duration(days: 89));
  }

  Future<void> _choosePeriod() async {
    if (_busy) return;
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: DateTimeRange(start: _start, end: _end),
      helpText: '选择成交日期范围',
      cancelText: '取消',
      confirmText: '确定',
      saveText: '确定',
    );
    if (range == null || !mounted) return;
    setState(() {
      _start = DateTime(range.start.year, range.start.month, range.start.day);
      _end = DateTime(range.end.year, range.end.month, range.end.day);
      _error = null;
    });
  }

  Future<void> _importScreenshots({required bool camera}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = camera ? '正在读取照片…' : '正在读取截图…';
    });
    try {
      final screenshots = camera
          ? [
              if (await _screenshotPicker.fromCamera() case final item?) item,
            ]
          : await _screenshotPicker.fromGallery();
      if (screenshots.isEmpty || !mounted) return;
      setState(() {
        _progress = screenshots.length == 1
            ? '正在识别成交记录…'
            : '正在识别 0/${screenshots.length} 张截图…';
      });
      final parsed = await _screenshotParser.parseBatch(
        screenshots,
        onProgress: (completed, total) {
          if (!mounted || total <= 1) return;
          setState(() => _progress = '正在识别 $completed/$total 张截图…');
        },
      );
      if (!mounted) return;
      final filtered =
          parsed.filterByPeriod(periodStart: _start, periodEnd: _end);
      if (filtered.trades.isEmpty) {
        setState(() {
          _error = '所选时间段内没有成交记录。识别到 '
              '${parsed.trades.length} 笔成交，但都不在 '
              '${_dateText(_start)} 至 ${_dateText(_end)}。'
              '请调整时间段后重新导入。';
        });
        return;
      }
      _openConfirm(
        filtered.withImportMetadata(
          trades: filtered.trades,
          periodStart: _start,
          periodEnd: DateTime(
            _end.year,
            _end.month,
            _end.day,
            23,
            59,
            59,
          ),
          importSource: '图片',
          rawTradeCount: filtered.rawTradeCount,
          validTradeCount: filtered.validTradeCount,
          invalidRowCount: filtered.invalidRowCount,
          dateFilteredOutTradeCount: filtered.dateFilteredOutTradeCount,
          duplicateTradeCount: filtered.duplicateTradeCount,
        ),
        screenshots.first.bytes,
      );
    } on TradeParseException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '导入时遇到问题，请重新选择。');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _importFile() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _progress = '正在读取表格…';
    });
    try {
      final file = await _filePicker.pick();
      if (file == null || !mounted) return;
      final parsed = _fileParser.parse(
        file,
        periodStart: _start,
        periodEnd: _end,
      );
      if (!mounted) return;
      _openConfirm(parsed, null);
    } on TradeParseException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '表格导入失败，请确认文件格式后重试。');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  void _openConfirm(ParsedTradesResult parsed, Uint8List? imageBytes) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TradeConfirmScreen(
          parsed: parsed,
          imageBytes: imageBytes,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgSurface,
      appBar: AppBar(
        title: const Text('导入交易记录'),
        backgroundColor: AppColors.bgSurface,
      ),
      body: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.sm,
          AppSpace.lg,
          AppSpace.xxl,
        ),
        children: [
          const _StepLabel(index: 1, title: '选择成交时间段'),
          const SizedBox(height: AppSpace.sm),
          Material(
            color: AppColors.bgRaised,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: InkWell(
              key: const ValueKey('trade-import-period'),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              onTap: _choosePeriod,
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.lg),
                child: Row(
                  children: [
                    Icon(
                      Icons.date_range_outlined,
                      color: AppColors.amber,
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_dateText(_start)} 至 ${_dateText(_end)}',
                            style: AppType.body.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '按成交日期筛选，起止日期都包含',
                            style: AppType.micro.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textTertiary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpace.xl),
          const _StepLabel(index: 2, title: '选择导入方式'),
          const SizedBox(height: AppSpace.sm),
          _ImportOption(
            key: const ValueKey('trade-import-gallery'),
            icon: Icons.photo_library_outlined,
            title: '成交截图',
            subtitle: '可多选，相邻截图重叠成交自动去重',
            enabled: !_busy,
            onTap: () => _importScreenshots(camera: false),
          ),
          const SizedBox(height: AppSpace.sm),
          _ImportOption(
            key: const ValueKey('trade-import-camera'),
            icon: Icons.photo_camera_outlined,
            title: '现场拍照',
            subtitle: '拍摄券商成交记录页面',
            enabled: !_busy,
            onTap: () => _importScreenshots(camera: true),
          ),
          const SizedBox(height: AppSpace.sm),
          _ImportOption(
            key: const ValueKey('trade-import-file'),
            icon: Icons.table_chart_outlined,
            title: 'CSV / Excel',
            subtitle: '从券商导出 .csv 或 .xlsx 成交明细',
            enabled: !_busy,
            onTap: _importFile,
          ),
          if (_busy) ...[
            const SizedBox(height: AppSpace.lg),
            const LinearProgressIndicator(minHeight: 2),
            if (_progress != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.sm),
                child: Text(
                  _progress!,
                  textAlign: TextAlign.center,
                  style: AppType.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpace.lg),
            Container(
              padding: const EdgeInsets.all(AppSpace.md),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4F2),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 19,
                    color: AppColors.danger,
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text(
                      _error!,
                      style: AppType.caption.copyWith(height: 1.55),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpace.xl),
          const WkNote(
            title: '数据安全',
            text: '截图原图只用于本次识别，不上传到账号存储。'
                '确认后的结构化成交和复盘报告会同步到登录账号。',
          ),
        ],
      ),
    );
  }

  static String _dateText(DateTime date) =>
      '${date.year}.${date.month.toString().padLeft(2, '0')}.'
      '${date.day.toString().padLeft(2, '0')}';
}

class _StepLabel extends StatelessWidget {
  const _StepLabel({required this.index, required this.title});

  final int index;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
              decoration: BoxDecoration(
            color: AppColors.textPrimary,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$index',
            style: AppType.micro.copyWith(
              color: AppColors.bgSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: AppSpace.sm),
        Text(title, style: AppType.title.copyWith(fontSize: 17)),
      ],
    );
  }
}

class _ImportOption extends StatelessWidget {
  const _ImportOption({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgSurface,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppColors.borderMed),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.bgRaised,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(icon, size: 21, color: AppColors.textPrimary),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppType.body),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: AppType.micro.copyWith(
                        color: AppColors.textSecondary,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

