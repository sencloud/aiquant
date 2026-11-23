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
import 'trade_import_screen.dart';
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

  final bool _busy = false;
  String? _error;
  String? _parseProgress;

  Future<void> _pickAndParse({required bool camera}) async {
    if (_busy) return;
    if (!await requireLogin(context) || !mounted) return;
    setState(() => _error = null);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TradeImportScreen(
          screenshotPicker: _picker,
          screenshotParser: _parser,
        ),
      ),
    );
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

  Future<void> _refresh() async {
    if (!context.read<AuthState>().isAuthenticated) return;
    await TradeReviewStore.instance.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    return ColoredBox(
      key: const ValueKey('trade-review-top-white'),
      color: AppColors.bgSurface,
      child: SafeArea(
        bottom: false,
        child: ColoredBox(
          key: const ValueKey('trade-review-page-surface'),
          color: AppColors.bgSurface,
          child: AnimatedBuilder(
            animation: TradeReviewStore.instance,
            builder: (context, _) {
              final store = TradeReviewStore.instance;
              final reports = store.reports;
              final latest = reports.isEmpty ? null : reports.first;
              return RefreshIndicator(
                color: AppColors.amber,
                backgroundColor: AppColors.bgSurface,
                onRefresh: _refresh,
                child: CustomScrollView(
                  key: const ValueKey('trade-review-home'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: _PageHeader(
                        hasReport: latest != null,
                        signedIn: auth.isAuthenticated,
                        onLogin: () => requireLogin(context),
                      ),
                    ),
                    if (_busy)
                      SliverToBoxAdapter(
                        child: _parseStatus(),
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
                          onUpload:
                              _busy ? null : () => _pickAndParse(camera: false),
                          onCamera:
                              _busy ? null : () => _pickAndParse(camera: true),
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
                ),
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
        AppSpace.sm,
        AppSpace.md,
        0,
      ),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFFFCFAF6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE9DFCF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.xl,
                AppSpace.lg,
                AppSpace.xl,
                AppSpace.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '最近复盘',
                        style: AppType.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '等待第一组成交',
                        style: AppType.micro.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.xl),
                  Text(
                    '把成交记录交给嘻，AI',
                    style: AppType.display.copyWith(
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    signedIn
                        ? '一次选择多张「历史成交」截图。核对成交后，'
                            '嘻，AI 会说明你的交易逻辑、主要问题和下一步改进。'
                        : '登录后选择一组「历史成交」截图。复盘结果会保存到账号，'
                            '在手机和电脑都能查看。',
                    style: AppType.read.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 15,
                      height: 1.7,
                    ),
                  ),
                  const SizedBox(height: AppSpace.lg),
                  const _EmptyStatement(),
                ],
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF7F1E7),
                border: Border(
                  top: BorderSide(color: Color(0xFFE9DFCF), width: 0.5),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.lg,
                AppSpace.lg,
                AppSpace.md,
              ),
              child: Column(
                children: [
                  WkPrimaryButton(
                    key: const ValueKey('trade-upload-gallery'),
                    label:
                        _busy ? (_parseProgress ?? '正在准备截图…') : '选择成交截图（可多选）',
                    icon: Icons.add_photo_alternate_outlined,
                    busy: _busy,
                    onPressed: () => _pickAndParse(camera: false),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: OutlinedButton.icon(
                            key: const ValueKey('trade-upload-camera'),
                            onPressed: _busy
                                ? null
                                : () => _pickAndParse(camera: true),
                            icon: const Icon(
                              Icons.photo_camera_outlined,
                              size: 18,
                            ),
                            label: const Text('现场拍一张'),
                            style: OutlinedButton.styleFrom(
                              backgroundColor: AppColors.bgSurface,
                              side: BorderSide(color: AppColors.borderMed),
                              foregroundColor: AppColors.textPrimary,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(AppRadius.md),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
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
                          '一次最多 ${TradeScreenshotPicker.maxGalleryImages} 张；'
                          '相邻截图重叠的成交会自动合并。原图只用于本次识别，'
                          '不会保存。',
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

  Widget _parseStatus() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.md,
        AppSpace.sm,
        AppSpace.md,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LinearProgressIndicator(minHeight: 2),
          if (_parseProgress != null) ...[
            const SizedBox(height: AppSpace.xs),
            Text(
              _parseProgress!,
              style: AppType.micro.copyWith(color: AppColors.textSecondary),
            ),
          ],
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
                    hasReport ? '你的最近一次复盘，已经可以回看。' : '从成交记录里，看见你的交易逻辑。',
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
                key: signedIn ? null : const ValueKey('trade-review-login'),
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
    final tradeDate = report.trades.isEmpty
        ? report.createdAt
        : report.trades.last.occurredAt;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.md,
        AppSpace.sm,
        AppSpace.md,
        0,
      ),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: const Color(0xFFFCFAF6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE9DFCF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpace.xl,
                AppSpace.lg,
                AppSpace.xl,
                AppSpace.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '最近复盘 · ${_reviewDate(tradeDate)}',
                        style: AppType.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const Spacer(),
                      if (report.brokerHint.isNotEmpty)
                        WkTag(report.brokerHint),
                    ],
                  ),
                  const SizedBox(height: AppSpace.lg),
                  Text(
                    report.title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.title.copyWith(
                      fontSize: 21,
                      height: 1.42,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: AppSpace.xl),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '已实现盈亏',
                              style: AppType.micro.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              formatTradeMoney(
                                pnl,
                                currency: report.currency,
                              ),
                              style: AppType.display.copyWith(
                                color: tradeResultColor(pnl),
                                fontSize: 30,
                                height: 1.15,
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${report.trades.length} 笔成交',
                        style: AppType.micro.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpace.lg),
                  Row(
                    children: [
                      _MetricCell(
                        value: '${metrics.matchedSellCount}',
                        label: '已平仓',
                        alignStart: true,
                      ),
                      _MetricCell(
                        value: formatTradePercent(metrics.winRate),
                        label: '胜率',
                      ),
                      _MetricCell(
                        value: _profitLossCaption(metrics.profitLossRatio),
                        label: '盈亏比',
                        alignEnd: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (report.trades.isNotEmpty)
              _TradeTrace(
                trades: report.trades,
                currency: report.currency,
              ),
            const Divider(
              height: 0.5,
              thickness: 0.5,
              color: Color(0xFFE9DFCF),
            ),
            _InsightPreview(
              title: '交易逻辑',
              text: _insightText(
                report.logic,
                fallback: '成交样本还不足以还原稳定逻辑。',
              ),
              evidence: _evidenceText(report.logic),
            ),
            const Divider(
              height: 0.5,
              thickness: 0.5,
              indent: AppSpace.xl,
              endIndent: AppSpace.xl,
              color: Color(0xFFE9DFCF),
            ),
            _InsightPreview(
              title: '主要问题',
              text: _insightText(
                report.problems,
                fallback: '这份样本里没有识别到明确问题。',
              ),
              evidence: _evidenceText(report.problems),
              tone: AppColors.danger,
            ),
            const Divider(
              height: 0.5,
              thickness: 0.5,
              indent: AppSpace.xl,
              endIndent: AppSpace.xl,
              color: Color(0xFFE9DFCF),
            ),
            _InsightPreview(
              title: '下一步',
              text: _insightText(
                report.improvements,
                fallback: '继续记录完整成交，再观察可验证的改进。',
              ),
              evidence: _evidenceText(report.improvements),
              tone: AppColors.amber,
            ),
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF7F1E7),
                border: Border(
                  top: BorderSide(color: Color(0xFFE9DFCF), width: 0.5),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(
                AppSpace.lg,
                AppSpace.lg,
                AppSpace.lg,
                AppSpace.md,
              ),
              child: Column(
                children: [
                  WkPrimaryButton(
                    key: const ValueKey('trade-review-again'),
                    label: '复盘另一组截图',
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
                            backgroundColor: AppColors.bgSurface,
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
                            backgroundColor: AppColors.bgSurface,
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
                    '可一次选择多张截图，重叠成交会自动合并；'
                    '原图只用于本次识别。',
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

  static String _reviewDate(DateTime date) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return '${date.month}月${date.day}日 ${weekdays[date.weekday - 1]}';
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

  static String? _evidenceText(List<TradeInsight> items) {
    if (items.isEmpty) return null;
    final evidence = items.first.evidence;
    if (evidence.isEmpty) return null;
    final text = evidence.first.trim();
    return text.isEmpty ? null : text;
  }

  static String _profitLossCaption(double value) =>
      value.isFinite ? value.toStringAsFixed(2) : '∞';
}

class _TradeTrace extends StatelessWidget {
  const _TradeTrace({
    required this.trades,
    required this.currency,
  });

  final List<ParsedTrade> trades;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final start = trades.length > 3 ? trades.length - 3 : 0;
    final samples = trades.sublist(start);
    final remainder = trades.length - samples.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        0,
        AppSpace.xl,
        AppSpace.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(
            height: 0.5,
            thickness: 0.5,
            color: Color(0xFFE9DFCF),
          ),
          const SizedBox(height: AppSpace.lg),
          Row(
            children: [
              Text(
                '成交切片',
                style: AppType.caption.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '按成交时间',
                style: AppType.micro.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          for (var i = 0; i < samples.length; i++)
            _TradeTraceRow(
              trade: samples[i],
              currency: currency,
              first: i == 0,
              last: i == samples.length - 1 && remainder == 0,
            ),
          if (remainder > 0)
            Padding(
              padding: const EdgeInsets.only(left: 62, top: AppSpace.xs),
              child: Text(
                '另有 $remainder 笔成交，完整报告里按时间列出',
                style: AppType.micro.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TradeTraceRow extends StatelessWidget {
  const _TradeTraceRow({
    required this.trade,
    required this.currency,
    required this.first,
    required this.last,
  });

  final ParsedTrade trade;
  final String currency;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final sideColor =
        trade.side == TradeSide.buy ? AppColors.positive : AppColors.negative;
    final date = trade.occurredAt;
    final time = '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
    final day = '${date.month.toString().padLeft(2, '0')}/'
        '${date.day.toString().padLeft(2, '0')}';
    return SizedBox(
      height: 50,
      child: Row(
        children: [
          SizedBox(
            width: 54,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  day,
                  style: AppType.micro.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 10,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  time,
                  style: AppType.micro.copyWith(
                    color: AppColors.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 14,
            height: 50,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (!first)
                  Positioned(
                    top: 0,
                    bottom: 25,
                    child: Container(
                      width: 0.5,
                      color: const Color(0xFFD9CCBA),
                    ),
                  ),
                if (!last)
                  Positioned(
                    top: 25,
                    bottom: 0,
                    child: Container(
                      width: 0.5,
                      color: const Color(0xFFD9CCBA),
                    ),
                  ),
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: sideColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trade.instrumentLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${_formatQuantity(trade.quantity)} 股 @ '
                  '${formatTradeAmount(trade.price, currency: currency)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.micro.copyWith(
                    color: AppColors.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpace.sm),
          Text(
            trade.side.label,
            style: AppType.micro.copyWith(
              color: sideColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatQuantity(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }
}

class _EmptyStatement extends StatelessWidget {
  const _EmptyStatement();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: Color(0xFFE9DFCF), width: 0.5),
              bottom: BorderSide(color: Color(0xFFE9DFCF), width: 0.5),
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
          child: Row(
            children: [
              Text(
                '成交时间',
                style: AppType.micro.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
              const Spacer(),
              Text(
                '标的 · 方向 · 成交价',
                style: AppType.micro.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
        for (var i = 0; i < 3; i++)
          Container(
            constraints: const BoxConstraints(minHeight: 42),
            padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: i == 2 ? Colors.transparent : AppColors.borderDim,
                  width: 0.5,
                ),
              ),
            ),
            child: Row(
              children: [
                Text(
                  '--:--',
                  style: AppType.micro.copyWith(
                    color: AppColors.textTertiary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: AppSpace.lg),
                Expanded(
                  child: Container(
                    height: 1,
                    color: AppColors.borderDim,
                  ),
                ),
                const SizedBox(width: AppSpace.lg),
                Text(
                  '待识别',
                  style: AppType.micro.copyWith(
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpace.md),
        Text(
          '截图导入后，这里会按真实成交顺序还原买卖。',
          style: AppType.micro.copyWith(
            color: AppColors.textSecondary,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({
    required this.value,
    required this.label,
    this.alignStart = false,
    this.alignEnd = false,
  });

  final String value;
  final String label;
  final bool alignStart;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final alignment = alignStart
        ? CrossAxisAlignment.start
        : alignEnd
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.center;
    return Expanded(
      child: Column(
        crossAxisAlignment: alignment,
        children: [
          Text(
            value,
            style: AppType.title.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 1),
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
    this.evidence,
    this.tone,
  });

  final String title;
  final String text;
  final String? evidence;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.lg,
        AppSpace.xl,
        AppSpace.lg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: tone ?? AppColors.amber,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppType.micro.copyWith(
                    color: tone ?? AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  text,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.caption.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    height: 1.65,
                  ),
                ),
                if (evidence != null) ...[
                  const SizedBox(height: AppSpace.sm),
                  Text(
                    evidence!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.micro.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.55,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
