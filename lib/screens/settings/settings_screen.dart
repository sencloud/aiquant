import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../core/api/billing_models.dart';
import '../../core/auth/require_login.dart';
import '../../core/format/credit_fmt.dart';
import '../../state/auth_state.dart';
import '../../state/billing_state.dart';
import '../../state/ding_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/legal_links.dart';
import '../ding/ding_screen.dart';
import '../watch/watch_screen.dart';

/// 「我的」——**深色档案卷宗**。
///
/// 这一页不再用"卡片堆"：整页由三样东西构成——
///
///   1. **细线**（1px）分区与分行，代替卡片边框与阴影；
///   2. **等宽数字**（tabular figures）承载一切金额与编号，让"账"看起来是账；
///   3. **一处金黄**（印章色），只用在当前状态与唯一的主动作上。
///
/// 结构取自用户每天真正打交道的那类纸面：对账单、卷宗封面、交割单——
/// 身份在最上，账在中，工具与条款按序排在下方，页脚是存档戳。
/// 状态（未读、危险动作）用**线的存在与粗细**表达，不靠换颜色。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _bootstrapped = false;
  String _version = '';

  /// 仅 iOS / macOS 支持应用内购充值（Apple IAP）。安卓为个人开发者，
  /// 无合规的应用内虚拟商品支付通道，故隐藏充值入口。
  bool get _iapAvailable => !kIsWeb && (Platform.isIOS || Platform.isMacOS);

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((pkg) {
      if (mounted) setState(() => _version = 'v${pkg.version}');
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bootstrapped) return;
    _bootstrapped = true;
    final billing = context.read<BillingState>();
    Future.microtask(() async {
      await billing.refreshAll();
      final recovered = await billing.restoreUnverifiedPurchases();
      if (recovered > 0 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('已补充到账 $recovered 笔历史充值'),
          duration: const Duration(seconds: 3),
        ));
      }
    });
  }

  Future<void> _onPackageTap(BillingState b, CreditSku sku) async {
    final ok = await b.purchase(sku);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('充值成功 +${CreditFmt.label(sku.totalCredits)}'),
        duration: const Duration(seconds: 2),
      ));
      return;
    }
    final err = b.lastError;
    if (err == null || err.isEmpty) return; // 用户主动取消
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('喜点尚未到账'),
        content: Text(
          '$err\n\n如果苹果已经扣款，喜点稍后会自动到账。'
          '你也可以下拉刷新这个页面，或重新打开 App 触发自动补单。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('好的'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final n = await b.restoreUnverifiedPurchases();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(n > 0 ? '已补到账 $n 笔' : '暂无未到账的订单'),
              ));
            },
            child: const Text('立即重试'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final user = auth.currentUser;
    final billing = context.watch<BillingState>();
    final unread = context.watch<DingState>().unreadCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        actions: [
          IconButton(
            tooltip: '喜点流水',
            icon: const Icon(Icons.receipt_long, size: 20),
            onPressed: user == null ? null : () => _showLedger(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.amber,
        onRefresh: () => billing.refreshAll(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 36),
          children: [
            ProfileFolderHead(nickname: user?.nickname ?? '未登录', uid: user?.uuid ?? ''),
            const SizedBox(height: 22),
            ProfileCreditBureau(
              balance: billing.balance,
              loading: billing.loadingBalance,
              onRecharge: _iapAvailable && user != null
                  ? () => _showRechargeSheet(billing)
                  : null,
              onLedger: user == null ? null : () => _showLedger(context),
            ),
            const SizedBox(height: 30),
            const ProfileRule('随身工具'),
            ProfileIndexRow(
              icon: Icons.star_outline,
              title: '我的自选',
              note: '股票 / ETF / 期货',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const WatchScreen()),
              ),
            ),
            ProfileIndexRow(
              icon: Icons.alarm,
              title: '定时提醒',
              note: '按点让 AI 执行任务',
              badge: unread,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DingScreen()),
              ),
            ),
            ProfileIndexRow(
              icon: Icons.receipt_long_outlined,
              title: '喜点流水',
              note: '每一笔消耗与充值',
              onTap: user == null ? null : () => _showLedger(context),
            ),
            const SizedBox(height: 30),
            const ProfileRule('账号与条款'),
            if (user == null)
              ProfileIndexRow(
                icon: Icons.login,
                title: '登录 / 注册',
                note: '同步喜点与定时提醒',
                onTap: () => requireLogin(context),
              )
            else
              ProfileIndexRow(
                icon: Icons.logout,
                title: '退出登录',
                note: '',
                danger: true,
                onTap: () => _confirmLogout(context, auth),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: LegalLinksRow(),
            ),
            const SizedBox(height: 26),
            ProfileColophon(version: _version),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, AuthState auth) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出后本地缓存的对话与自选会一并清空，重新登录可恢复喜点余额。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('再想想')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('退出')),
        ],
      ),
    );
    if (ok == true) await auth.logout();
  }

  /// 充值套餐收进弹层：首屏只留一个「充值」动作，不再让套餐列表占地。
  void _showRechargeSheet(BillingState billing) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => AnimatedBuilder(
        animation: billing,
        builder: (ctx, _) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('充值喜点',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 14),
                if (billing.loadingSkus && billing.skus.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  )
                else if (billing.skus.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Text(billing.lastError ?? '暂无可用套餐',
                          style: TextStyle(
                              color: AppColors.textTertiary, fontSize: 12)),
                    ),
                  )
                else
                  for (final sku in billing.skus) ...[
                    _SkuRow(
                      sku: sku,
                      loading: billing.isPurchasingSku(sku.code),
                      disabled: billing.purchasing &&
                          !billing.isPurchasingSku(sku.code),
                      onTap: () => _onPackageTap(billing, sku),
                    ),
                    const SizedBox(height: 8),
                  ],
                const SizedBox(height: 8),
                Text(
                  '喜点是虚拟商品，购买后不支持退款或转让；'
                  '调用行情、新闻等数据工具不再额外计费。',
                  style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 10.5,
                      height: 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showLedger(BuildContext ctx) {
    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const _LedgerSheet(),
    );
  }
}

// ── 卷宗部件 ────────────────────────────────────────────────────────────

/// 等宽数字样式：金额、编号、版本号统一用它，让"账"看起来是账。
TextStyle mono({
  double size = 13,
  FontWeight weight = FontWeight.w700,
  Color? color,
}) =>
    TextStyle(
      color: color ?? AppColors.textPrimary,
      fontSize: size,
      fontWeight: weight,
      fontFeatures: const [FontFeature.tabularFigures()],
      letterSpacing: 0.2,
    );

/// 分区标题：上方留白多、下方留白少，一条细线收口。
class ProfileRule extends StatelessWidget {
  const ProfileRule(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.textTertiary,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 8),
          Container(height: 1, color: AppColors.borderDim),
        ],
      ),
    );
  }
}

/// 卷宗封面：方形号牌 + 姓名 + 档案编号。不用卡片，直接落在背景上。
class ProfileFolderHead extends StatelessWidget {
  const ProfileFolderHead({super.key, required this.nickname, required this.uid});

  final String nickname;
  final String uid;

  @override
  Widget build(BuildContext context) {
    final initial = nickname.trim().isEmpty ? '喜' : nickname.trim().characters.first;
    final shortUid = uid.length > 8 ? uid.substring(0, 8) : uid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.bgRaised,
                border: Border.all(color: AppColors.amber, width: 1),
              ),
              child: Text(initial,
                  style: const TextStyle(
                      color: AppColors.amber,
                      fontSize: 20,
                      fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    shortUid.isEmpty ? '未登录 · 数据仅存本机' : '档案号 $shortUid',
                    style: mono(size: 10.5, weight: FontWeight.w600,
                        color: AppColors.textTertiary),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(height: 1, color: AppColors.borderDim),
      ],
    );
  }
}

/// 喜点总账：一行标签 + 等宽大数 + 唯一的主动作。
class ProfileCreditBureau extends StatelessWidget {
  const ProfileCreditBureau({
    super.key,
    required this.balance,
    required this.loading,
    this.onRecharge,
    this.onLedger,
  });

  final int balance;
  final bool loading;
  final VoidCallback? onRecharge;
  final VoidCallback? onLedger;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('喜点余额',
            style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6)),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (loading)
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.amber)),
              )
            else
              Text(CreditFmt.balance(balance), style: mono(size: 30)),
            const Spacer(),
            if (onRecharge != null)
              _StampButton(label: '充值', onTap: onRecharge!, filled: true),
            if (onRecharge != null && onLedger != null) const SizedBox(width: 8),
            if (onLedger != null)
              _StampButton(label: '流水', onTap: onLedger!, filled: false),
          ],
        ),
        const SizedBox(height: 8),
        Text('每次回答消耗 6 喜点 · 调用行情、新闻等数据工具不再额外计费',
            style: TextStyle(
                color: AppColors.textTertiary, fontSize: 10.5, height: 1.5)),
      ],
    );
  }
}

/// 印章式按钮：方角、细边，主次靠填充区分（不靠颜色数量）。
class _StampButton extends StatelessWidget {
  const _StampButton({
    required this.label,
    required this.onTap,
    required this.filled,
  });

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? AppColors.amber : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            border: Border.all(
                color: filled ? AppColors.amber : AppColors.borderDim),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: filled ? Colors.white : AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ),
    );
  }
}

/// 一行档案条目：细线下压，右侧等宽说明或角标。
/// 未读用一条 2px 金黄竖线表达——状态靠线，不靠换色。
class ProfileIndexRow extends StatelessWidget {
  const ProfileIndexRow({
    super.key,
    required this.icon,
    required this.title,
    required this.note,
    this.onTap,
    this.badge = 0,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String note;
  final VoidCallback? onTap;
  final int badge;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.borderDim)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            children: [
              Container(
                width: 2,
                height: 16,
                color: badge > 0 ? AppColors.amber : Colors.transparent,
              ),
              const SizedBox(width: 10),
              Icon(icon,
                  size: 17,
                  color: danger
                      ? AppColors.danger
                      : (onTap == null
                          ? AppColors.textTertiary
                          : AppColors.textSecondary)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: danger
                        ? AppColors.danger
                        : (onTap == null
                            ? AppColors.textTertiary
                            : AppColors.textPrimary),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (note.isNotEmpty)
                Text(note,
                    style: TextStyle(
                        color: AppColors.textTertiary, fontSize: 10.5)),
              if (badge > 0) ...[
                const SizedBox(width: 8),
                Text(badge > 99 ? '99+' : '$badge',
                    style: mono(size: 11, color: AppColors.amber)),
              ],
              const SizedBox(width: 6),
              Icon(Icons.chevron_right,
                  size: 16,
                  color: onTap == null
                      ? AppColors.borderDim
                      : AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// 页脚存档戳：版本与来源，等宽小字。
class ProfileColophon extends StatelessWidget {
  const ProfileColophon({super.key, required this.version});
  final String version;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(height: 1, color: AppColors.borderDim),
        const SizedBox(height: 10),
        Row(
          children: [
            Text('喜宽 · AI 投资助手',
                style: TextStyle(
                    color: AppColors.textTertiary, fontSize: 10.5)),
            const Spacer(),
            Text(version.isEmpty ? '—' : version,
                style: mono(
                    size: 10.5,
                    weight: FontWeight.w600,
                    color: AppColors.textTertiary)),
          ],
        ),
      ],
    );
  }
}

/// 充值套餐行：等宽数字对齐，档位一眼可比。
class _SkuRow extends StatelessWidget {
  const _SkuRow({
    required this.sku,
    required this.loading,
    required this.disabled,
    required this.onTap,
  });

  final CreditSku sku;
  final bool loading;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = !disabled && !loading;
    return Material(
      color: AppColors.bgRaised,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            border: Border.all(
                color: enabled ? AppColors.borderDim : AppColors.bgRaised),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(CreditFmt.label(sku.totalCredits),
                        style: mono(size: 15)),
                    if (sku.bonusCredits > 0) ...[
                      const SizedBox(height: 3),
                      Text('含赠送 ${CreditFmt.amount(sku.bonusCredits)}',
                          style: TextStyle(
                              color: AppColors.textTertiary, fontSize: 10.5)),
                    ],
                  ],
                ),
              ),
              if (loading)
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else
                Text('¥${sku.priceYuan.toStringAsFixed(2)}',
                    style: mono(size: 14, color: enabled
                        ? AppColors.amber
                        : AppColors.textTertiary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// 喜点流水弹层：一条条对账单式的记录。
class _LedgerSheet extends StatefulWidget {
  const _LedgerSheet();

  @override
  State<_LedgerSheet> createState() => _LedgerSheetState();
}

class _LedgerSheetState extends State<_LedgerSheet> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) context.read<BillingState>().refreshLedger(reset: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final billing = context.watch<BillingState>();
    final items = billing.ledger;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      builder: (ctx, controller) => Column(
        children: [
          const SizedBox(height: 14),
          Text('喜点流水',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Expanded(
            child: billing.loadingLedger && items.isEmpty
                ? const Center(
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)))
                : items.isEmpty
                    ? Center(
                        child: Text('还没有流水记录',
                            style: TextStyle(
                                color: AppColors.textTertiary, fontSize: 12)),
                      )
                    : ListView.builder(
                        controller: controller,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        itemCount: items.length,
                        itemBuilder: (_, i) => _LedgerRow(item: items[i]),
                      ),
          ),
        ],
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.item});
  final CreditLedgerItem item;

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.fromMillisecondsSinceEpoch(item.createdAt);
    final stamp = '${dt.year}-${dt.month.toString().padLeft(2, '0')}'
        '-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
    final label = (item.remark == null || item.remark!.isEmpty)
        ? _reasonLabel(item.reason)
        : item.remark!;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderDim)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: AppColors.textPrimary, fontSize: 12.5)),
                const SizedBox(height: 3),
                Text(stamp,
                    style: mono(
                        size: 10.5,
                        weight: FontWeight.w600,
                        color: AppColors.textTertiary)),
              ],
            ),
          ),
          Text(CreditFmt.delta(item.delta),
              style: mono(
                  size: 13,
                  color: item.delta >= 0
                      ? AppColors.positive
                      : AppColors.textSecondary)),
          const SizedBox(width: 12),
          SizedBox(
            width: 54,
            child: Text(CreditFmt.balance(item.balanceAfter),
                textAlign: TextAlign.right,
                style: mono(size: 11, color: AppColors.textTertiary)),
          ),
        ],
      ),
    );
  }

  static String _reasonLabel(String reason) {
    switch (reason) {
      case 'consume_ai':
        return 'AI 对话消耗';
      case 'consume_ding':
        return '定时任务消耗';
      case 'purchase':
        return '充值';
      case 'checkin':
        return '每日签到';
      case 'invite_reward':
        return '邀请奖励';
      default:
        return reason.isEmpty ? '变动' : reason;
    }
  }
}
