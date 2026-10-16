import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/billing_models.dart';
import '../../core/format/credit_fmt.dart';
import '../../services/analytics.dart';
import '../../state/billing_state.dart';
import '../../theme/app_theme.dart';

/// 账号与喜点这一摊的公共部件：充值面板、喜点明细、分组行、注销确认。
///
/// 「我」页（`lib/wx/me_tab.dart`）和需要拉起充值的页面（证伪档案的解锁、
/// 对话里的余额不足）都从这里取。

/// 当前平台能不能充值喜点（仅 iOS / macOS 走 Apple IAP；Android 暂不发布、
/// Web 不开放付费）。
bool get rechargeAvailable => !kIsWeb && (Platform.isIOS || Platform.isMacOS);

/// 等宽数字样式：金额、编号、版本号统一用它，让「账」看起来是账。
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

/// 充值套餐收进弹层：页面上只留一个「充值」动作，不让套餐列表占地。
///
/// 只在 iOS / macOS 可用（Apple IAP）；其他平台调用方应先用
/// [rechargeAvailable] 判断。
Future<void> showRechargeSheet(BuildContext context) {
  final billing = context.read<BillingState>();
  if (billing.skus.isEmpty && !billing.loadingSkus) {
    // ignore: unawaited_futures
    billing.refreshSkus();
  }
  Analytics.instance.track(Analytics.evRechargeSheet);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.bgSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
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
              const Text('充值喜点', style: AppType.title),
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
                        style: AppType.caption
                            .copyWith(color: AppColors.textTertiary)),
                  ),
                )
              else
                for (final sku in billing.skus) ...[
                  _SkuRow(
                    sku: sku,
                    loading: billing.isPurchasingSku(sku.code),
                    disabled: billing.purchasing &&
                        !billing.isPurchasingSku(sku.code),
                    onTap: () => _onPackageTap(context, billing, sku),
                  ),
                  const SizedBox(height: 8),
                ],
              const SizedBox(height: 8),
              Text(
                '喜点是虚拟商品，购买后不支持退款或转让；'
                '调用行情、新闻等数据工具不再额外计费。',
                style: AppType.micro.copyWith(
                    color: AppColors.textTertiary, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<void> _onPackageTap(
    BuildContext context, BillingState b, CreditSku sku) async {
  Analytics.instance.track(Analytics.evRechargeStart, {'sku': sku.code});
  final ok = await b.purchase(sku);
  if (!context.mounted) return;
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
            if (!context.mounted) return;
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

/// 喜点明细弹层。
void showLedgerSheet(BuildContext ctx) {
  showModalBottomSheet<void>(
    context: ctx,
    isScrollControlled: true,
    backgroundColor: AppColors.bgSurface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (_) => const _LedgerSheet(),
  );
}

/// 分组卡里的一行：左图标 + 标题 + 右侧说明 / 未读角标 + 箭头。
///
/// 比 [WkRow] 更轻（没有副标题、图标不带底色），「我」页用它。
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
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.lg, vertical: 12),
            child: Row(
              children: [
                Icon(icon,
                    size: 22,
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
                              fontWeight: FontWeight.w500)),
                    ),
                  ),
                if (enabled) ...[
                  const SizedBox(width: AppSpace.xs),
                  Icon(Icons.chevron_right_rounded,
                      size: 22, color: AppColors.textTertiary),
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
        Text('喜爱 · 喜爱，并不是一定要得到',
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
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
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
                          style: AppType.micro
                              .copyWith(color: AppColors.textTertiary)),
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
                    style: mono(
                        size: 14,
                        color: enabled
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
          const Text('喜点明细', style: AppType.title),
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
                            style: AppType.body
                                .copyWith(color: AppColors.textTertiary)),
                      )
                    : ListView.builder(
                        controller: controller,
                        padding:
                            const EdgeInsets.symmetric(horizontal: AppSpace.lg),
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
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.body),
                const SizedBox(height: 4),
                Text(stamp,
                    style:
                        AppType.micro.copyWith(color: AppColors.textTertiary)),
              ],
            ),
          ),
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
                  style: AppType.micro.copyWith(color: AppColors.textTertiary)),
            ],
          ),
        ],
      ),
    );
  }
}

/// 注销账号二次确认：讲清楚会删什么、留什么，3 秒后才能点确认。
class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({super.key});

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  int _countdown = 3;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _countdown--);
      if (_countdown <= 0) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _countdown <= 0;
    return AlertDialog(
      key: const Key('delete-account-dialog'),
      title: const Text('注销账号'),
      content: const Text(
        '注销后立即生效、无法恢复：\n'
        '· 清除登录信息（邮箱 / Apple 账号绑定）、昵称和设备信息；\n'
        '· 删除 AI 对话记录、自建小应用和本机记下的事；\n'
        '· 剩余喜点作废。\n\n'
        '依据法规，充值订单与喜点流水会匿名保留，不再与你关联。',
        style: TextStyle(fontSize: 15, height: 1.6),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        TextButton(
          key: const Key('delete-account-confirm'),
          style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          onPressed: ready ? () => Navigator.pop(context, true) : null,
          child: Text(ready ? '确认注销' : '确认注销（$_countdown）'),
        ),
      ],
    );
  }
}
