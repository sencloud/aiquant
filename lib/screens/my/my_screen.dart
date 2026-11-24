import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/auth_models.dart';
import '../../core/auth/require_login.dart';
import '../../core/format/credit_fmt.dart';
import '../../models/trade_review.dart';
import '../../services/trade_review_repository.dart';
import '../../state/auth_state.dart';
import '../../state/billing_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import '../settings/account_kit.dart';
import '../settings/settings_screen.dart';
import '../trade_review/trade_report_screen.dart';
import '../trade_review/trade_review_history.dart';
import '../trade_review/trade_review_widgets.dart';
import '../watch/widgets/market_brand.dart';

/// 微信式个人页。
///
/// 首屏保留最近复盘、交易记录、看盘、付费会员和设置；账号、隐私、协议与
/// 关于都进入二级页面。顶部档案区使用纯白背景，列表分组横向铺满。
class MyScreen extends StatefulWidget {
  const MyScreen({
    super.key,
    required this.watchPageBuilder,
    this.historyPageBuilder,
  });

  final WidgetBuilder watchPageBuilder;
  final WidgetBuilder? historyPageBuilder;

  @override
  State<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends State<MyScreen> {
  void _push(WidgetBuilder builder) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));
  }

  void _openHistory() {
    _push(widget.historyPageBuilder ?? (_) => const TradeReviewHistoryScreen());
  }

  void _openReview(TradeReviewReport report) {
    _push((_) => TradeReportScreen(report: report));
  }

  void _openSettings(int reportCount, DateTime? lastSavedAt) {
    _push(
      (_) => SettingsScreen(
        reportCount: reportCount,
        lastSavedAt: lastSavedAt,
      ),
    );
  }

  Future<void> _openProfile() async {
    final auth = context.read<AuthState>();
    if (!auth.isAuthenticated) {
      await requireLogin(context);
      return;
    }
    if (!mounted) return;
    final reports = TradeReviewStore.instance.reports;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.xl,
            0,
            AppSpace.xl,
            AppSpace.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('账号与同步', style: AppType.title),
              const SizedBox(height: AppSpace.md),
              const _InfoLine(label: '登录状态', value: '已登录'),
              _InfoLine(label: '账号标识', value: _shortAccount(auth)),
              _InfoLine(label: '复盘记录', value: '${reports.length} 份'),
              _InfoLine(
                label: '最近复盘',
                value: reports.isEmpty
                    ? '暂无'
                    : formatTradeDate(reports.first.createdAt),
              ),
              const SizedBox(height: AppSpace.md),
              Text(
                '登录同一账号后，手机和电脑看到的复盘报告保持一致。'
                '上传的截图只用于当次识别，不会保存。',
                style: AppType.caption.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.65,
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              WkPrimaryButton(
                label: '同步到云端',
                icon: Icons.cloud_sync_outlined,
                onPressed: () async {
                  Navigator.of(sheetContext).pop();
                  await _syncNow();
                },
              ),
              const SizedBox(height: AppSpace.sm),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  minimumSize: const Size.fromHeight(44),
                ),
                onPressed: () async {
                  Navigator.of(sheetContext).pop();
                  await auth.logout();
                },
                child: const Text('退出登录'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _syncNow() async {
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

  Future<void> _openMembership() async {
    if (!await requireLogin(context) || !mounted) return;
    final billing = context.read<BillingState>();
    await billing.refreshAll();
    if (!mounted) return;
    if (rechargeAvailable) {
      await showRechargeSheet(context);
    } else {
      showLedgerSheet(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final billing = context.watch<BillingState>();
    return ColoredBox(
      key: const ValueKey('my-top-white'),
      color: AppColors.bgSurface,
      child: SafeArea(
        bottom: false,
        child: ColoredBox(
          key: const ValueKey('my-page-surface'),
          // 页面底色用灰，白面只留给档案区与分组：最后一个分组（设置）下面
          // 自然露出灰色，作为分组之间的分割，而不是一直白到底。
          color: AppColors.bgBase,
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
                child: ListView(
                  key: const ValueKey('my-page'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: AppSpace.xxl),
                  children: [
                    _ProfileHeader(
                      signedIn: auth.isAuthenticated,
                      displayName: _displayName(auth),
                      accountCaption: _accountCaption(auth),
                      reportCount: reports.length,
                      syncing: store.syncing,
                      syncError: store.syncError,
                      onTap: _openProfile,
                    ),
                    const _MyGroupGap(),
                    _MyGroup(
                      children: [
                        _MyRow(
                          key: const ValueKey('my-recent-review'),
                          icon: Icons.auto_graph_rounded,
                          iconColor: AppColors.amber,
                          title: '最近复盘',
                          value: latest?.title ?? '暂无',
                          onTap: latest == null
                              ? _openHistory
                              : () => _openReview(latest),
                        ),
                        _MyRow(
                          key: const ValueKey('my-trade-history'),
                          icon: Icons.receipt_long_outlined,
                          iconColor: const Color(0xFF576B95),
                          title: '交易记录',
                          value: reports.isEmpty ? '暂无' : '${reports.length} 份',
                          onTap: _openHistory,
                        ),
                        _MyRow(
                          key: const ValueKey('my-watch-app'),
                          icon: Icons.candlestick_chart_rounded,
                          iconColor: const Color(0xFF17864E),
                          title: '看盘',
                          value: '行情终端',
                          onTap: () => _push(widget.watchPageBuilder),
                        ),
                      ],
                    ),
                    const _MyGroupGap(),
                    _MyGroup(
                      children: [
                        _MyRow(
                          key: const ValueKey('my-membership'),
                          icon: Icons.workspace_premium_outlined,
                          iconColor: const Color(0xFFC58A2B),
                          title: '付费会员',
                          value: auth.isAuthenticated
                              ? '喜点 ${CreditFmt.balance(billing.balance)}'
                              : '充值喜点',
                          onTap: _openMembership,
                        ),
                      ],
                    ),
                    const _MyGroupGap(),
                    _MyGroup(
                      children: [
                        _MyRow(
                          key: const ValueKey('my-settings'),
                          icon: Icons.settings_outlined,
                          iconColor: AppColors.textSecondary,
                          title: '设置',
                          onTap: () =>
                              _openSettings(reports.length, latest?.createdAt),
                        ),
                      ],
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

  static String _displayName(AuthState auth) {
    final nickname = auth.currentUser?.nickname.trim() ?? '';
    return nickname.isEmpty ? '喜爱用户' : nickname;
  }

  static String _shortAccount(AuthState auth) {
    final uuid = auth.currentUser?.uuid ?? '';
    if (uuid.length <= 8) return uuid;
    return '…${uuid.substring(uuid.length - 6).toUpperCase()}';
  }

  static String _accountCaption(AuthState auth) {
    if (!auth.isAuthenticated) return '未登录 · 点击登录后同步';
    return '喜爱账号 ${_shortAccount(auth)} · 云端同步';
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.signedIn,
    required this.displayName,
    required this.accountCaption,
    required this.reportCount,
    required this.syncing,
    required this.syncError,
    required this.onTap,
  });

  final bool signedIn;
  final String displayName;
  final String accountCaption;
  final int reportCount;
  final bool syncing;
  final String? syncError;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = !signedIn
        ? '登录后跨端同步'
        : syncing
            ? '正在同步'
            : syncError != null
                ? '等待同步'
                : reportCount == 0
                    ? '等待第一份复盘'
                    : '已同步 · $reportCount 份复盘';
    return ColoredBox(
      color: AppColors.bgSurface,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const ValueKey('my-profile'),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg + AppSpace.xs,
              AppSpace.xxl + AppSpace.lg,
              AppSpace.md,
              AppSpace.xxl,
            ),
            child: Row(
              children: [
                const MarketBrandMark(size: 64),
                const SizedBox(width: AppSpace.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamilyFallback: AppType.sansFallback,
                          color: AppColors.textPrimary,
                          fontSize: 24,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.4,
                        ),
                      ),
                      const SizedBox(height: AppSpace.sm),
                      Text(
                        accountCaption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: AppSpace.sm),
                      _StatusTag(label: status, warning: syncError != null),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpace.sm),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textTertiary,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.label, required this.warning});

  final String label;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final color = warning ? AppColors.warning : AppColors.amberDim;
    final background = warning ? const Color(0xFFFFF1E1) : AppColors.accentSoft;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        style: AppType.micro.copyWith(color: color, fontSize: 10.5),
      ),
    );
  }
}

class _MyGroup extends StatelessWidget {
  const _MyGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(
          Divider(
            height: 0.5,
            thickness: 0.5,
            indent: AppSpace.lg + 28 + AppSpace.md,
            color: AppColors.borderDim,
          ),
        );
      }
    }
    return Container(
      color: AppColors.bgSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }
}

class _MyGroupGap extends StatelessWidget {
  const _MyGroupGap();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 12,
      child: ColoredBox(color: AppColors.bgBase),
    );
  }
}

class _MyRow extends StatelessWidget {
  const _MyRow({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.value,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.lg,
              vertical: AppSpace.md,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: Icon(icon, color: iconColor, size: 24),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Text(
                    title,
                    style: AppType.body.copyWith(color: AppColors.textPrimary),
                  ),
                ),
                if (value != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 170),
                    child: Text(
                      value!,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.caption.copyWith(
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                const SizedBox(width: AppSpace.xs),
                Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textTertiary,
                  size: 21,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Row(
        children: [
          Text(label, style: AppType.body),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppType.caption.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
