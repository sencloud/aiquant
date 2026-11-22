import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../models/trade_review.dart';
import '../../services/trade_review_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/legal_links.dart';
import '../../widgets/wk_kit.dart';
import '../trade_review/trade_desktop_connect_screen.dart';
import '../trade_review/trade_report_screen.dart';
import '../trade_review/trade_review_history.dart';
import '../trade_review/trade_review_widgets.dart';
import '../watch/widgets/market_brand.dart';

/// 微信式个人页：不包卡片、不投影，用整宽白面和发丝线组织入口。
class MyScreen extends StatefulWidget {
  const MyScreen({
    super.key,
    required this.watchPageBuilder,
    this.desktopPageBuilder,
    this.historyPageBuilder,
  });

  final WidgetBuilder watchPageBuilder;
  final WidgetBuilder? desktopPageBuilder;
  final WidgetBuilder? historyPageBuilder;

  @override
  State<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends State<MyScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = 'v${info.version}');
    } catch (_) {
      // Package metadata is unavailable in some widget-test hosts.
    }
  }

  void _push(WidgetBuilder builder) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));
  }

  void _openHistory() {
    _push(widget.historyPageBuilder ?? (_) => const TradeReviewHistoryScreen());
  }

  void _openDesktop() {
    _push(
      widget.desktopPageBuilder ?? (_) => const TradeDesktopConnectScreen(),
    );
  }

  void _openReview(TradeReviewReport report) {
    _push((_) => TradeReportScreen(report: report));
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
            final latest = reports.isEmpty ? null : reports.first;
            return ListView(
              key: const ValueKey('my-page'),
              padding: const EdgeInsets.only(bottom: AppSpace.xxl),
              children: [
                _ProfileHeader(
                  reportCount: reports.length,
                  onTap: () => _showProfile(reports.length, latest),
                  onOpenDesktop: _openDesktop,
                ),
                const SizedBox(height: AppSpace.md),
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
                      title: '我的交易记录',
                      value: reports.isEmpty ? null : '${reports.length} 份',
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
                    _MyRow(
                      key: const ValueKey('my-desktop-connect'),
                      icon: Icons.devices_rounded,
                      iconColor: const Color(0xFFFA9D3B),
                      title: '电脑连接',
                      value: '局域网配对',
                      onTap: _openDesktop,
                    ),
                  ],
                ),
                _MyGroup(
                  children: [
                    _MyRow(
                      key: const ValueKey('my-data-privacy'),
                      icon: Icons.shield_outlined,
                      iconColor: const Color(0xFF4F86C6),
                      title: '数据与隐私',
                      value: '仅存本机',
                      onTap: () => _showPrivacy(reports.length, latest),
                    ),
                    const LegalLinksRow(),
                  ],
                ),
                _MyGroup(
                  children: [
                    _MyRow(
                      key: const ValueKey('my-about'),
                      icon: Icons.info_outline_rounded,
                      iconColor: AppColors.textSecondary,
                      title: '关于嘻，AI',
                      value: _version.isEmpty ? null : _version,
                      onTap: _showAbout,
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpace.lg,
                    AppSpace.lg,
                    AppSpace.lg,
                    AppSpace.md,
                  ),
                  child: Text(
                    '嘻，AI ${_version.isEmpty ? '' : _version}\n'
                    '从成交本身复盘，不用猜测代替事实',
                    textAlign: TextAlign.center,
                    style: AppType.micro.copyWith(
                      color: AppColors.textTertiary,
                      height: 1.7,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showProfile(int reportCount, TradeReviewReport? latest) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.xl,
            0,
            AppSpace.xl,
            AppSpace.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('本机档案', style: AppType.title),
              const SizedBox(height: AppSpace.sm),
              Text(
                '当前不要求登录。成交复盘只保存在这台设备，'
                '电脑连接也只在主动打开页面时接收数据。',
                style: AppType.caption.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.65,
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              _InfoLine(label: '复盘记录', value: '$reportCount 份'),
              _InfoLine(
                label: '最近复盘',
                value: latest?.title ?? '还没有记录',
              ),
              _InfoLine(
                label: '应用版本',
                value: _version.isEmpty ? '读取中' : _version,
              ),
              const SizedBox(height: AppSpace.lg),
              WkPrimaryButton(
                label: '连接电脑端',
                icon: Icons.devices_rounded,
                onPressed: () {
                  Navigator.of(context).pop();
                  _openDesktop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPrivacy(int reportCount, TradeReviewReport? latest) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.xl,
            0,
            AppSpace.xl,
            AppSpace.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('数据与隐私', style: AppType.title),
              const SizedBox(height: AppSpace.md),
              Text(
                '截图只用于当次识别，不保存原图。分析结果保存在本机，'
                '最多保留 20 份，可随时逐份删除。电脑连接只接收核对后的'
                '日期、方向、数量、价格和手续费，不接收账户密码或截图。',
                style: AppType.read.copyWith(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                  height: 1.75,
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              _InfoLine(label: '本机复盘', value: '$reportCount 份'),
              _InfoLine(
                label: '最近保存',
                value:
                    latest == null ? '暂无' : formatTradeDate(latest.createdAt),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('关于嘻，AI'),
        content: Text(
          '嘻，AI 读取你的成交记录，按先进先出还原已平仓交易，'
          '再用可以验证的数据说明交易逻辑、问题与改进措施。'
          '\n\n它不判断账户总资金，不推测截图中没有出现的仓位、'
          '止损金额、消息来源或临场情绪，也不提供交易指令或收益承诺。',
          style: AppType.body.copyWith(
            fontSize: 15,
            color: AppColors.textSecondary,
            height: 1.7,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.reportCount,
    required this.onTap,
    required this.onOpenDesktop,
  });

  final int reportCount;
  final VoidCallback onTap;
  final VoidCallback onOpenDesktop;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.bgSurface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpace.lg + AppSpace.xs,
          AppSpace.xxl + AppSpace.xl,
          AppSpace.sm,
          AppSpace.xxl + AppSpace.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const ValueKey('my-profile'),
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                    child: Row(
                      children: [
                        const MarketBrandMark(size: 64),
                        const SizedBox(width: AppSpace.lg),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '嘻，AI 用户',
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
                                '本机模式 · 记录仅存本机',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.caption.copyWith(
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: AppSpace.sm),
                              Row(
                                children: [
                                  _StatusTag(
                                    label: reportCount == 0
                                        ? '等待第一份复盘'
                                        : '已保存 $reportCount 份复盘',
                                  ),
                                  const SizedBox(width: AppSpace.sm),
                                  Text(
                                    '隐私可控',
                                    style: AppType.micro.copyWith(
                                      color: AppColors.textTertiary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpace.sm),
                        IconButton(
                          key: const ValueKey('my-qr-entry'),
                          tooltip: '连接电脑端',
                          onPressed: onOpenDesktop,
                          color: AppColors.textSecondary,
                          icon: const Icon(Icons.qr_code_2_rounded, size: 21),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.textTertiary,
                          size: 22,
                        ),
                        const SizedBox(width: AppSpace.xs),
                      ],
                    ),
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

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        style: AppType.micro.copyWith(
          color: AppColors.amberDim,
          fontSize: 10.5,
        ),
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
      margin: const EdgeInsets.only(bottom: AppSpace.md),
      color: AppColors.bgSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
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
                  Flexible(
                    child: Text(
                      value!,
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
