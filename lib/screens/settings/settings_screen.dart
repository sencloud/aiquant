import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../core/api/billing_models.dart';
import '../../core/auth/require_login.dart';
import '../../core/format/credit_fmt.dart';
import '../../services/analytics.dart';
import '../../state/auth_state.dart';
import '../../state/billing_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/legal_links.dart';
import '../../widgets/wk_kit.dart';
import '../watch/watch_screen.dart';

/// 「我的」——微信式分组列表。
///
/// 顺序沿用微信的习惯：身份在最上，账在其后，然后是工具、账号与条款，
/// 页脚收尾。每一组是一张白面卡，卡内行与行之间只有一条发丝线；
/// 未读角标用红色圆点标签，危险动作（退出登录）才用红色文字。
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
    Analytics.instance.track(Analytics.evRechargeStart, {'sku': sku.code});
    final ok = await b.purchase(sku);
    if (!mounted) return;
    if (ok) {
      Analytics.instance.track(Analytics.evRechargeSuccess, {
        'sku': sku.code,
        'amount_yuan': sku.priceYuan,
      });
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        actions: [
          IconButton(
            tooltip: '喜点明细',
            icon: const Icon(Icons.receipt_long_rounded, size: 20),
            onPressed: user == null ? null : () => _showLedger(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.amber,
        onRefresh: () => billing.refreshAll(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.gutter, AppSpace.sm, AppSpace.gutter, AppSpace.xxl),
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
            // 微信式分组：一组一个白面卡，卡内行与行之间一条发丝线。
            WkGroup(
              header: '随身工具',
              children: [
                ProfileIndexRow(
                  icon: Icons.star_outline_rounded,
                  title: '我的自选',
                  note: '股票 / ETF / 期货',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const WatchScreen()),
                  ),
                ),
                ProfileIndexRow(
                  icon: Icons.receipt_long_rounded,
                  title: '喜点明细',
                  note: '充值、消耗都在这里',
                  onTap: user == null ? null : () => _showLedger(context),
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            WkGroup(
              header: '账号与条款',
              children: [
                if (user == null)
                  ProfileIndexRow(
                    icon: Icons.login_rounded,
                    title: '登录 / 注册',
                    note: '同步喜点与定时提醒',
                    onTap: () => requireLogin(context),
                  )
                else
                  ProfileIndexRow(
                    icon: Icons.logout_rounded,
                    title: '退出登录',
                    note: '',
                    danger: true,
                    onTap: () => _confirmLogout(context, auth),
                  ),
                const LegalLinksRow(),
              ],
            ),
            const SizedBox(height: AppSpace.xl),
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
    Analytics.instance.track(Analytics.evRechargeSheet);
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

/// 分区标题：微信分组头，只在卡片上方出现一次。
class ProfileRule extends StatelessWidget {
  const ProfileRule(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpace.xs, bottom: AppSpace.sm),
      child: Text(label,
          style: AppType.section.copyWith(color: AppColors.textSecondary)),
    );
  }
}

/// 用户抬头：方头像 + 昵称 + 档案号。
class ProfileFolderHead extends StatelessWidget {
  const ProfileFolderHead({super.key, required this.nickname, required this.uid});

  final String nickname;
  final String uid;

  @override
  Widget build(BuildContext context) {
    // 未登录时昵称就是「未登录」三个字，取首字会变成「未」—— 用品牌字兜底。
    final name = nickname.trim();
    final initial =
        (name.isEmpty || name == '未登录') ? '喜' : name.characters.first;
    final shortUid = uid.length > 8 ? uid.substring(0, 8) : uid;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.xs, vertical: AppSpace.sm),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Text(initial,
                style: AppType.display
                    .copyWith(fontSize: 24, color: AppColors.amberDim)),
          ),
          const SizedBox(width: AppSpace.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.title.copyWith(fontSize: 19)),
                const SizedBox(height: 4),
                Text(
                  shortUid.isEmpty ? '未登录 · 数据仅存本机' : '档案号 $shortUid',
                  style: AppType.micro.copyWith(
                      color: AppColors.textTertiary,
                      fontFamilyFallback: AppType.numericFallback),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 喜点总账：白面卡 + 大数 + 主动作。
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
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('喜点余额',
              style: AppType.caption.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: AppSpace.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (loading)
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                Text(CreditFmt.balance(balance),
                    style: AppType.display.copyWith(fontSize: 30)),
              const Spacer(),
              if (onRecharge != null)
                _StampButton(label: '充值', onTap: onRecharge!, filled: true),
              if (onRecharge != null && onLedger != null)
                const SizedBox(width: AppSpace.sm),
              if (onLedger != null)
                _StampButton(label: '流水', onTap: onLedger!, filled: false),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Text('每次回答消耗 6 喜点 · 调用行情、新闻等数据工具不再额外计费',
              style: AppType.micro
                  .copyWith(color: AppColors.textTertiary, height: 1.6)),
        ],
      ),
    );
  }
}

/// 卡内小按钮：主次靠填充区分，形状跟卡片语言一致。
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
    final radius = BorderRadius.circular(AppRadius.sm);
    return Material(
      color: filled ? AppColors.amber : Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.lg, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
                color: filled ? AppColors.amber : AppColors.borderMed),
          ),
          child: Text(
            label,
            style: AppType.caption.copyWith(
              color: filled ? AppColors.onAccent : AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// 分组卡里的一行：左图标 + 标题 + 右侧说明 / 未读角标 + 箭头。
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
    final enabled = onTap != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.lg, vertical: 12),
            child: Row(
              children: [
                Icon(icon,
                    size: 20,
                    color: danger
                        ? AppColors.danger
                        : (enabled ? AppColors.amber : AppColors.textTertiary)),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Text(
                    title,
                    style: AppType.body.copyWith(
                      color: danger
                          ? AppColors.danger
                          : (enabled
                              ? AppColors.textPrimary
                              : AppColors.textTertiary),
                    ),
                  ),
                ),
                if (note.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpace.sm),
                    child: Text(note,
                        style: AppType.caption
                            .copyWith(color: AppColors.textTertiary)),
                  ),
                if (badge > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: AppSpace.sm),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      constraints:
                          const BoxConstraints(minWidth: 18, minHeight: 18),
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(badge > 99 ? '99+' : '$badge',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              height: 1.3,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                if (enabled) ...[
                  const SizedBox(width: AppSpace.xs),
                  Icon(Icons.chevron_right,
                      size: 20, color: AppColors.textTertiary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 页脚：版本与来源，安静地收尾。
class ProfileColophon extends StatelessWidget {
  const ProfileColophon({super.key, required this.version});
  final String version;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('喜爱 · 喜 AI 策略证伪台',
            style: AppType.micro.copyWith(color: AppColors.textTertiary)),
        const SizedBox(width: AppSpace.sm),
        Text(version.isEmpty ? '—' : version,
            style: AppType.micro.copyWith(
                color: AppColors.textTertiary,
                fontFamilyFallback: AppType.numericFallback)),
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

/// 喜点明细弹层：一条条记录，进账为正、消耗为负，右边给出变动后的余额。
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
          Text('喜点明细',
              style: AppType.title.copyWith(fontSize: 16)),
          const SizedBox(height: 6),
          Text('充值和赠送是正的，AI 回答和定时任务是负的',
              style: AppType.micro.copyWith(color: AppColors.textTertiary)),
          const SizedBox(height: AppSpace.md),
          Expanded(
            child: billing.loadingLedger && items.isEmpty
                ? const Center(
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2)))
                : items.isEmpty
                    ? Center(
                        child: Text('还没有喜点记录',
                            style: AppType.body.copyWith(
                                color: AppColors.textTertiary)),
                      )
                    : ListView.builder(
                        controller: controller,
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpace.lg),
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
    final stamp = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
    // 后端给的 remark 是运营写的备注，优先用它；没有就用 reason 翻出来的人话。
    final label = (item.remark == null || item.remark!.isEmpty)
        ? item.reasonLabel
        : item.remark!;
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.borderDim)),
      ),
      padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.body.copyWith(color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text(stamp,
                    style: AppType.micro
                        .copyWith(color: AppColors.textTertiary)),
              ],
            ),
          ),
          // 右边两行：变动多少 + 变完还剩多少。两个数字都带单位，
          // 不再是一串看不懂的裸数字。
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${CreditFmt.delta(item.delta)} 喜点',
                style: AppType.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: item.delta >= 0
                      ? AppColors.positive
                      : AppColors.textPrimary,
                  fontFamilyFallback: AppType.numericFallback,
                ),
              ),
              const SizedBox(height: 4),
              Text('余额 ${CreditFmt.balance(item.balanceAfter)}',
                  style: AppType.micro
                      .copyWith(color: AppColors.textTertiary)),
            ],
          ),
        ],
      ),
    );
  }
}
