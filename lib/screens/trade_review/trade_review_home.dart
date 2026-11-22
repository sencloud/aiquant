import 'package:flutter/material.dart';

import '../../models/trade_review.dart';
import '../../services/trade_review_repository.dart';
import '../../services/trade_screenshot_parser.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import 'trade_confirm_screen.dart';
import 'trade_desktop_connect_screen.dart';
import 'trade_report_screen.dart';
import 'trade_review_widgets.dart';

class TradeReviewHomeScreen extends StatefulWidget {
  const TradeReviewHomeScreen({
    super.key,
    this.picker,
    this.parser,
    this.desktopPageBuilder,
  });

  final TradeScreenshotPicker? picker;
  final TradeScreenshotParser? parser;
  final WidgetBuilder? desktopPageBuilder;

  @override
  State<TradeReviewHomeScreen> createState() => _TradeReviewHomeScreenState();
}

class _TradeReviewHomeScreenState extends State<TradeReviewHomeScreen> {
  late final TradeScreenshotPicker _picker =
      widget.picker ?? TradeScreenshotPicker();
  late final TradeScreenshotParser _parser =
      widget.parser ?? TradeScreenshotParser();

  bool _busy = false;
  String? _error;

  Future<void> _pickAndParse({required bool camera}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final screenshot =
          camera ? await _picker.fromCamera() : await _picker.fromGallery();
      if (screenshot == null) return;
      final parsed = await _parser.parse(
        imageBytes: screenshot.bytes,
        mimeType: screenshot.mimeType,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TradeConfirmScreen(
            parsed: parsed,
            imageBytes: screenshot.bytes,
          ),
        ),
      );
    } on TradeParseException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = '识别时遇到问题，请重新上传一次。');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openDesktop() {
    final builder =
        widget.desktopPageBuilder ?? (_) => const TradeDesktopConnectScreen();
    Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));
  }

  void _openReport(TradeReviewReport report) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TradeReportScreen(report: report),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.bgBase,
      child: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: TradeReviewStore.instance,
          builder: (context, _) {
            final reports = TradeReviewStore.instance.reports;
            return CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _pageHeader()),
                SliverToBoxAdapter(
                  child: _uploadSurface(),
                ),
                if (_busy)
                  const SliverToBoxAdapter(
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                if (_error != null)
                  SliverToBoxAdapter(child: _errorBanner(_error!)),
                SliverToBoxAdapter(
                  child: TradeSectionTitle(
                    title: '最近复盘',
                    caption: reports.isEmpty
                        ? '上传一张成交记录，第一份复盘会保存在这台设备。'
                        : '只保存分析结果，不保存你上传的截图。',
                  ),
                ),
                if (reports.isEmpty)
                  SliverToBoxAdapter(child: _emptyReviews())
                else
                  SliverToBoxAdapter(
                    child: WkGroup(
                      children: [
                        for (final report in reports.take(3))
                          _RecentReviewRow(
                            report: report,
                            onTap: () => _openReport(report),
                          ),
                      ],
                    ),
                  ),
                const SliverToBoxAdapter(
                  child: TradeSectionTitle(
                    title: '电脑端接入',
                    caption: '电脑上的交易记录可以直接交给手机分析。',
                  ),
                ),
                SliverToBoxAdapter(
                  child: WkGroup(
                    children: [
                      WkRow(
                        key: const ValueKey('trade-desktop-entry'),
                        leading: _LineIcon(
                          icon: Icons.qr_code_2_rounded,
                          color: AppColors.amber,
                        ),
                        title: '连接电脑端',
                        subtitle: '局域网配对 · 仅传输结构化成交行',
                        value: '配对',
                        onTap: _openDesktop,
                      ),
                    ],
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: AppSpace.xxl)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _pageHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.lg,
        AppSpace.lg,
        AppSpace.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '嘻，AI',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 30,
              height: 1.15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
              fontFamilyFallback: AppType.sansFallback,
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            '从成交记录里，看见你的交易逻辑。',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              height: 1.5,
              fontFamilyFallback: AppType.sansFallback,
            ),
          ),
        ],
      ),
    );
  }

  Widget _uploadSurface() {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpace.md,
        AppSpace.sm,
        AppSpace.md,
        AppSpace.xs,
      ),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.xl,
              AppSpace.lg,
              AppSpace.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const _ReviewMark(),
                    const Spacer(),
                    WkTag('成交记录', tone: AppColors.amber, filled: true),
                  ],
                ),
                const SizedBox(height: AppSpace.xl),
                Text(
                  '把截图交给嘻，AI',
                  style: AppType.display.copyWith(
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                Text(
                  '识别买卖、数量、价格与手续费，再按先进先出配对，'
                  '告诉你实际呈现出的交易逻辑、问题和下一步改法。',
                  style: AppType.read.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 15,
                    height: 1.7,
                  ),
                ),
              ],
            ),
          ),
          Container(
            color: const Color(0xFFF8F3EA),
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.lg,
              AppSpace.lg,
              AppSpace.lg,
            ),
            child: Column(
              children: [
                WkPrimaryButton(
                  key: const ValueKey('trade-upload-gallery'),
                  label: _busy ? '正在识别成交记录…' : '从相册选择成交截图',
                  icon: Icons.add_photo_alternate_outlined,
                  busy: _busy,
                  onPressed: () => _pickAndParse(camera: false),
                ),
                const SizedBox(height: AppSpace.sm),
                SizedBox(
                  height: 46,
                  child: OutlinedButton.icon(
                    key: const ValueKey('trade-upload-camera'),
                    onPressed: _busy ? null : () => _pickAndParse(camera: true),
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: const Text('拍一张交易记录'),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: AppColors.bgSurface,
                      side: BorderSide(color: AppColors.borderMed),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(
                        Icons.lock_outline_rounded,
                        size: 15,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text(
                        '图片只用于本次识别，处理完不保存原图；复盘结果仅存本机。',
                        style: AppType.micro.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.55,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner(String message) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpace.md,
        AppSpace.md,
        AppSpace.md,
        0,
      ),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4F2),
        borderRadius: BorderRadius.circular(AppRadius.lg),
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
              message,
              style: AppType.caption.copyWith(
                color: AppColors.textPrimary,
                height: 1.6,
              ),
            ),
          ),
          TextButton(
            onPressed: _busy ? null : () => _pickAndParse(camera: false),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _emptyReviews() {
    return WkGroup(
      children: [
        SizedBox(
          height: 220,
          child: WkEmpty(
            icon: Icons.receipt_long_outlined,
            title: '还没有复盘记录',
            hint: '选择「成交记录」或「历史成交」页面的完整截图，识别会更准确。',
            action: TextButton(
              onPressed: _busy ? null : () => _pickAndParse(camera: false),
              child: const Text('上传第一张'),
            ),
          ),
        ),
      ],
    );
  }
}

class _RecentReviewRow extends StatelessWidget {
  const _RecentReviewRow({
    required this.report,
    required this.onTap,
  });

  final TradeReviewReport report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pnl = report.metrics.realizedPnl;
    return WkRow(
      title: report.title,
      subtitle: '${report.brokerHint.isEmpty ? '成交记录' : report.brokerHint} · '
          '${report.trades.length} 笔成交 · ${formatTradeDate(report.createdAt)}',
      trailing: Container(
        constraints: const BoxConstraints(minWidth: 68),
        alignment: Alignment.centerRight,
        child: Text(
          formatTradeMoney(pnl, currency: report.currency),
          style: AppType.caption.copyWith(
            color: tradeResultColor(pnl),
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
      onTap: onTap,
    );
  }
}

class _ReviewMark extends StatelessWidget {
  const _ReviewMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(
        Icons.auto_graph_rounded,
        color: AppColors.amber,
        size: 23,
      ),
    );
  }
}

class _LineIcon extends StatelessWidget {
  const _LineIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: Icon(icon, color: color, size: 26),
    );
  }
}
