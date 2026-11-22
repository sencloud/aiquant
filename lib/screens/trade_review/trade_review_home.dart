import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/auth_models.dart';
import '../../core/auth/require_login.dart';
import '../../models/trade_review.dart';
import '../../services/trade_review_repository.dart';
import '../../services/trade_screenshot_parser.dart';
import '../../state/auth_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import 'trade_confirm_screen.dart';
import 'trade_report_screen.dart';
import 'trade_review_history.dart';
import 'trade_review_widgets.dart';

/// 复盘结果优先的首页。
///
/// 有历史时先回答“上次看到了什么”，上传入口退居为一个明确动作；没有历史时
/// 才把上传工作台放到首屏。原图只在本次识别中使用，结构化成交与报告进入账号。
class TradeReviewHomeScreen extends StatefulWidget {
  const TradeReviewHomeScreen({
    super.key,
    this.picker,
    this.parser,
  });

  final TradeScreenshotPicker? picker;
  final TradeScreenshotParser? parser;

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
    if (!await requireLogin(context) || !mounted) return;
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

  void _openReport(TradeReviewReport report) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TradeReportScreen(report: report),
      ),
    );
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const TradeReviewHistoryScreen(),
      ),
    );
  }

  Future<void> _retrySync() async {
    try {
      await TradeReviewStore.instance.syncNow();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('复盘已同步到账号。')),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    return ColoredBox(
      color: AppColors.bgSurface,
      child: SafeArea(
        bottom: false,
        child: ColoredBox(
          color: AppColors.bgBase,
          child: AnimatedBuilder(
            animation: TradeReviewStore.instance,
            builder: (context, _) {
              final store = TradeReviewStore.instance;
              final reports = store.reports;
              final latest = reports.isEmpty ? null : reports.first;
              return CustomScrollView(
                key: const ValueKey('trade-review-home'),
                slivers: [
                  SliverToBoxAdapter(
                    child: _PageHeader(
                      hasReport: latest != null,
                      signedIn: auth.isAuthenticated,
                      onLogin: () => requireLogin(context),
                    ),
                  ),
                  if (_busy)
                    const SliverToBoxAdapter(
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  if (_error != null)
                    SliverToBoxAdapter(child: _errorBanner(_error!)),
                  if (store.loading)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (latest == null)
                    SliverToBoxAdapter(child: _firstReview(latest))
                  else ...[
                    SliverToBoxAdapter(
                      child: _LatestReportHero(
                        report: latest,
                        onOpen: () => _openReport(latest),
                        onUpload: _busy
                            ? null
                            : () => _pickAndParse(camera: false),
                        onCamera: _busy
                            ? null
                            : () => _pickAndParse(camera: true),
                      ),
                    ),
                    if (store.syncError != null)
                      SliverToBoxAdapter(
                        child: _syncBanner(
                          store.syncError!,
                          store.syncing ? null : _retrySync,
                        ),
                      ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpace.md,
                          AppSpace.lg,
                          AppSpace.md,
                          0,
                        ),
                        child: WkGroup(
                          children: [
                            WkRow(
                              key: const ValueKey('trade-all-reviews'),
                              icon: Icons.receipt_long_outlined,
                              iconColor: const Color(0xFF576B95),
                              title: '全部交易复盘',
                              subtitle: '手机和电脑登录同一账号后都能查看',
                              value: '${reports.length} 份',
                              onTap: _openHistory,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SliverToBoxAdapter(
                    child: SizedBox(height: AppSpace.xxl),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _firstReview(TradeReviewReport? _) {
    final signedIn = context.read<AuthState>().isAuthenticated;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.md,
        AppSpace.md,
        AppSpace.md,
        0,
      ),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.xl,
                AppSpace.xl,
                AppSpace.xl,
                AppSpace.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _ReviewMark(),
                  const SizedBox(height: AppSpace.lg),
                  Text(
                    '先看清，再改进',
                    style: AppType.display.copyWith(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    signedIn
                        ? '上传一张「历史成交」截图。核对成交后，'
                            '嘻，AI 会说明你的交易逻辑、主要问题和下一步改进。'
                        : '登录后上传一张「历史成交」截图。复盘结果会保存到账号，'
                            '在手机和电脑都能查看。',
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
              padding: const EdgeInsets.all(AppSpace.lg),
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
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      key: const ValueKey('trade-upload-camera'),
                      onPressed:
                          _busy ? null : () => _pickAndParse(camera: true),
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      label: const Text('拍一张交易记录'),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: AppColors.bgSurface,
                        side: BorderSide(color: AppColors.borderMed),
                        foregroundColor: AppColors.textPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 15,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(
                        child: Text(
                          '原图只用于本次识别，不会保存；成交字段和复盘报告'
                          '按登录账号同步。',
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

  Widget _syncBanner(String message, VoidCallback? onRetry) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpace.md,
        AppSpace.md,
        AppSpace.md,
        0,
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpace.md,
        AppSpace.sm,
        AppSpace.xs,
        AppSpace.sm,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E9),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 19,
            color: AppColors.warning,
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              message,
              style: AppType.micro.copyWith(
                color: AppColors.textSecondary,
                height: 1.55,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('重试同步'),
          ),
        ],
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.hasReport,
    required this.signedIn,
    required this.onLogin,
  });

  final bool hasReport;
  final bool signedIn;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.bgSurface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.lg,
          AppSpace.xl,
          AppSpace.lg,
          AppSpace.lg,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
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
                    hasReport
                        ? '你的最近一次复盘，已经可以回看。'
                        : '从成交记录里，看见你的交易逻辑。',
                    style: AppType.caption.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Material(
              color: Colors.transparent,
              child: InkWell(
                key: signedIn
                    ? null
                    : const ValueKey('trade-review-login'),
                onTap: signedIn ? null : onLogin,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.sm,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.bgRaised,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        signedIn
                            ? Icons.cloud_done_outlined
                            : Icons.person_outline_rounded,
                        size: 14,
                        color: signedIn
                            ? AppColors.amber
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        signedIn ? '账号同步' : '登录',
                        style: AppType.micro.copyWith(
                          color: signedIn
                              ? AppColors.amberDim
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LatestReportHero extends StatelessWidget {
  const _LatestReportHero({
    required this.report,
    required this.onOpen,
    required this.onUpload,
    required this.onCamera,
  });

  final TradeReviewReport report;
  final VoidCallback onOpen;
  final VoidCallback? onUpload;
  final VoidCallback? onCamera;

  @override
  Widget build(BuildContext context) {
    final metrics = report.metrics;
    final pnl = metrics.realizedPnl;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.md,
        AppSpace.md,
        AppSpace.md,
        0,
      ),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.lg,
                AppSpace.lg,
                AppSpace.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '最近复盘 · ${formatTradeDate(report.createdAt)}',
                        style: AppType.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      if (report.brokerHint.isNotEmpty)
                        WkTag(report.brokerHint),
                    ],
                  ),
                  const SizedBox(height: AppSpace.md),
                  Text(
                    report.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.title.copyWith(
                      fontSize: 22,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),
                  Text(
                    formatTradeMoney(pnl, currency: report.currency),
                    style: AppType.display.copyWith(
                      color: tradeResultColor(pnl),
                      fontSize: 34,
                      height: 1.1,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '已实现盈亏',
                    style: AppType.micro.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              color: AppColors.bgRaised,
              padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
              child: Row(
                children: [
                  _MetricCell(
                    value: '${metrics.matchedSellCount}',
                    label: '已平仓',
                  ),
                  _MetricCell(
                    value: formatTradePercent(metrics.winRate),
                    label: '胜率',
                  ),
                  _MetricCell(
                    value: _profitLossCaption(metrics.profitLossRatio),
                    label: '盈亏比',
                  ),
                ],
              ),
            ),
            _InsightPreview(
              title: '交易逻辑',
              text: _insightText(
                report.logic,
                fallback: '成交样本还不足以还原稳定逻辑。',
              ),
            ),
            Divider(
              height: 0.5,
              thickness: 0.5,
              indent: AppSpace.lg,
              color: AppColors.borderDim,
            ),
            _InsightPreview(
              title: '主要问题',
              text: _insightText(
                report.problems,
                fallback: '这份样本里没有识别到明确问题。',
              ),
              tone: AppColors.danger,
            ),
            Divider(
              height: 0.5,
              thickness: 0.5,
              indent: AppSpace.lg,
              color: AppColors.borderDim,
            ),
            _InsightPreview(
              title: '下一步',
              text: _insightText(
                report.improvements,
                fallback: '继续记录完整成交，再观察可验证的改进。',
              ),
              tone: AppColors.amber,
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Column(
                children: [
                  WkPrimaryButton(
                    key: const ValueKey('trade-review-again'),
                    label: '复盘另一张截图',
                    icon: Icons.add_rounded,
                    onPressed: onUpload,
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onOpen,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                            foregroundColor: AppColors.textPrimary,
                            side: BorderSide(color: AppColors.borderMed),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                          ),
                          child: const Text('查看完整报告'),
                        ),
                      ),
                      const SizedBox(width: AppSpace.sm),
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: OutlinedButton(
                          key: const ValueKey('trade-review-again-camera'),
                          onPressed: onCamera,
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            foregroundColor: AppColors.textSecondary,
                            side: BorderSide(color: AppColors.borderMed),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                          ),
                          child: const Icon(
                            Icons.photo_camera_outlined,
                            size: 19,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.md),
                  Text(
                    '原图只用于本次识别；成交字段和报告保存在你的账号。',
                    textAlign: TextAlign.center,
                    style: AppType.micro.copyWith(
                      color: AppColors.textTertiary,
                      height: 1.5,
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

  static String _insightText(
    List<TradeInsight> items, {
    required String fallback,
  }) {
    if (items.isEmpty) return fallback;
    final item = items.first;
    if (item.body.trim().isNotEmpty) return item.body.trim();
    if (item.title.trim().isNotEmpty) return item.title.trim();
    return fallback;
  }

  static String _profitLossCaption(double value) =>
      value.isFinite ? value.toStringAsFixed(2) : '∞';
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: AppType.title.copyWith(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppType.micro.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _InsightPreview extends StatelessWidget {
  const _InsightPreview({
    required this.title,
    required this.text,
    this.tone,
  });

  final String title;
  final String text;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.md,
        AppSpace.lg,
        AppSpace.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 58,
            child: Text(
              title,
              style: AppType.caption.copyWith(
                color: tone ?? AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                height: 1.55,
              ),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppType.caption.copyWith(
                color: AppColors.textSecondary,
                height: 1.62,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewMark extends StatelessWidget {
  const _ReviewMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        Icons.auto_graph_rounded,
        color: AppColors.amber,
        size: 24,
      ),
    );
  }
}
