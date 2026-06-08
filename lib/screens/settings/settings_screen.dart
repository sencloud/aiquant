import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api/billing_models.dart';
import '../../core/format/credit_fmt.dart';
import '../../state/auth_state.dart';
import '../../state/billing_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/legal_links.dart';

/// "我的"页面 — 喜点余额、充值套餐、流水、账号管理。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _bootstrapped = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_bootstrapped) {
      _bootstrapped = true;
      final billing = context.read<BillingState>();
      // 进页面拉余额 + SKU + 重投未到账订单。
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
  }

  Future<void> _onCheckin(BillingState b) async {
    final r = await b.checkIn();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r.message),
      duration: const Duration(seconds: 2),
    ));
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
    if (err == null || err.isEmpty) {
      // 用户主动取消（lastError 已被清空）。
      return;
    }
    // verify 失败：明确告诉用户已记录待重试，避免「钱扣了喜点没到账」的恐慌。
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
    final balance = billing.balance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的'),
        actions: [
          IconButton(
            tooltip: '流水',
            icon: const Icon(Icons.receipt_long, size: 20),
            onPressed: () => _showLedger(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => billing.refreshAll(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (user != null)
              _AccountTile(nickname: user.nickname, uuid: user.uuid),
            if (user != null) const SizedBox(height: 16),
            _BalanceCard(balance: balance, loading: billing.loadingBalance),
            const SizedBox(height: 12),
            _CheckinCard(
              checkedIn: billing.checkedInToday,
              loading: billing.checkingIn,
              onTap: () => _onCheckin(billing),
            ),
            const SizedBox(height: 24),
            _section('充值喜点'),
            const SizedBox(height: 8),
            if (billing.loadingSkus && billing.skus.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else if (billing.skus.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    billing.lastError ?? '暂无可用套餐',
                    style: TextStyle(
                        color: AppColors.textTertiary, fontSize: 12),
                  ),
                ),
              )
            else
              for (final sku in billing.skus) ...[
                _PackageTile(
                  sku: sku,
                  loading: billing.isPurchasingSku(sku.code),
                  // 当前正在买另一档 → 本档不可点，但不显示 loading
                  disabled: billing.purchasing &&
                      !billing.isPurchasingSku(sku.code),
                  onTap: () => _onPackageTap(billing, sku),
                ),
                const SizedBox(height: 8),
              ],
            const SizedBox(height: 12),
            _section('喜点说明'),
            const SizedBox(height: 6),
            _bulletText('• 喜点是 App 内的虚拟道具，用于解锁 AI 助理与行情分析。'),
            _bulletText('• 每次回答消耗 6 喜点，调用行情、新闻等数据工具不再额外计费。'),
            _bulletText('• 喜点属于虚拟商品，购买后不支持退款或转让。'),
            if (user != null) ...[
              const SizedBox(height: 24),
              _section('账号管理'),
              const SizedBox(height: 6),
              _LogoutTile(),
              const SizedBox(height: 8),
              _DeleteAccountTile(),
            ],
            const SizedBox(height: 24),
            _section('法律条款'),
            const SizedBox(height: 6),
            const LegalLinksRow(),
            const SizedBox(height: 24),
            _section('关于'),
            ListTile(
              dense: true,
              leading: const Icon(Icons.info_outline, color: AppColors.amber),
              title: Text('喜宽',
                  style: TextStyle(color: AppColors.textPrimary)),
              subtitle: Text('AI 投资助手 · 让看盘和决策更轻松',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }

  void _showLedger(BuildContext ctx) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: AppColors.bgRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (_) => const _LedgerSheet(),
    );
  }

  static Widget _section(String t) => Text(
        t,
        style: const TextStyle(
          color: AppColors.amber,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.0,
        ),
      );

  static Widget _bulletText(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text(
          t,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 11,
            height: 1.6,
          ),
        ),
      );
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance, required this.loading});
  final int balance;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.amber, AppColors.amberDim],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.stars_rounded, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text(
                '我的喜点',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              if (loading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                CreditFmt.balance(balance),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '喜点',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.85),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 每日签到卡片 —— 签到领 10 喜点。今天已签到则显示禁用态 + 勾选。
class _CheckinCard extends StatelessWidget {
  const _CheckinCard({
    required this.checkedIn,
    required this.loading,
    required this.onTap,
  });
  final bool checkedIn;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final done = checkedIn;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.bgRaised,
        border: Border.all(color: AppColors.borderDim),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: (done ? AppColors.positive : AppColors.amber)
                  .withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              done ? Icons.event_available : Icons.card_giftcard,
              color: done ? AppColors.positive : AppColors.amber,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '每日签到',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  done ? '今天已签到,明天再来领' : '每天签到免费领 10 喜点',
                  style: TextStyle(
                      color: AppColors.textTertiary, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _CheckinButton(done: done, loading: loading, onTap: onTap),
        ],
      ),
    );
  }
}

class _CheckinButton extends StatelessWidget {
  const _CheckinButton({
    required this.done,
    required this.loading,
    required this.onTap,
  });
  final bool done;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (done) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.borderDim),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check, color: AppColors.positive, size: 14),
            const SizedBox(width: 4),
            Text(
              '已签到',
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }
    return Material(
      color: AppColors.amber,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Text(
            '签到',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _PackageTile extends StatelessWidget {
  const _PackageTile({
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
    final hasBonus = sku.bonusCredits > 0;
    final tappable = !loading && !disabled;
    return Material(
      color: AppColors.bgRaised,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppColors.borderDim),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: tappable ? onTap : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.amber.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.amber),
                ),
                child: const Icon(Icons.stars_rounded,
                    color: AppColors.amber, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          sku.baseLabel,
                          style: const TextStyle(
                            color: AppColors.amber,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (hasBonus) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.positive
                                  .withValues(alpha: 0.18),
                              border: Border.all(color: AppColors.positive),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              sku.bonusLabel,
                              style: const TextStyle(
                                color: AppColors.positive,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasBonus
                          ? '到账 ${sku.titleLabel} · 折合 ${sku.unitPriceLabel}'
                          : '折合 ${sku.unitPriceLabel}',
                      style: TextStyle(
                          color: AppColors.textTertiary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.amber,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        sku.priceLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.nickname, required this.uuid});
  final String nickname;
  final String uuid;

  @override
  Widget build(BuildContext context) {
    final shortId = uuid.length > 8 ? uuid.substring(0, 8) : uuid;
    final display = nickname.isEmpty ? '宽友' : nickname;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.bgRaised,
            AppColors.amber.withValues(alpha: 0.06),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        border: Border.all(color: AppColors.borderDim),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [AppColors.amber, AppColors.amberDim],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.amber.withValues(alpha: 0.35),
                  blurRadius: 10,
                ),
              ],
            ),
            child: const Icon(Icons.apple, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(display,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => _editNickname(context),
                      child: Icon(Icons.edit_outlined,
                          color: AppColors.textTertiary, size: 16),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.bgSurface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.borderDim),
                  ),
                  child: Text('ID · $shortId',
                      style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editNickname(BuildContext context) async {
    final ctrl = TextEditingController(text: nickname);
    final newNick = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bgRaised,
        title: const Text('修改昵称'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 20,
          style: TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(
            hintText: '输入新昵称',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.amber,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (newNick == null || newNick.isEmpty || newNick == nickname) return;
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AuthState>().updateNickname(newNick);
      messenger.showSnackBar(const SnackBar(content: Text('昵称已更新')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('修改失败:$e',
            maxLines: 2, overflow: TextOverflow.ellipsis),
      ));
    }
  }
}

class _LogoutTile extends StatelessWidget {
  Future<void> _confirmAndLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确定退出登录吗？'),
        content:
            const Text('退出后本机的对话记录会被清除，下次打开需要再次用 Apple 账号登录。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('退出登录'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await context.read<AuthState>().logout();
    if (context.mounted) {
      context.read<BillingState>().reset();
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgRaised,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppColors.borderDim),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: () => _confirmAndLogout(context),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.logout, color: AppColors.danger, size: 18),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('退出登录',
                    style: TextStyle(
                        color: AppColors.danger,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
              ),
              Icon(Icons.chevron_right,
                  color: AppColors.textTertiary, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeleteAccountTile extends StatelessWidget {
  Future<void> _confirm(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await context.read<AuthState>().deleteAccount();
      if (context.mounted) {
        context.read<BillingState>().reset();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('账户已注销'),
          duration: Duration(seconds: 2),
        ));
        Navigator.of(context).maybePop();
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('注销失败，请稍后再试'),
          duration: Duration(seconds: 3),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgRaised,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppColors.borderDim),
        borderRadius: BorderRadius.circular(8),
      ),
      child: InkWell(
        onTap: () => _confirm(context),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.no_accounts_outlined,
                  color: AppColors.danger, size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('注销账户',
                        style: TextStyle(
                            color: AppColors.danger,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('永久清除账号信息，且无法恢复',
                        style: TextStyle(
                            color: AppColors.textTertiary, fontSize: 11)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: AppColors.textTertiary, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

/// 注销二次确认：必须输入"确认注销"四字 + 5 秒倒计时按钮防误点。
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  static const _expected = '确认注销';
  final _controller = TextEditingController();
  int _countdown = 5;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _countdown--;
        if (_countdown <= 0) {
          _countdown = 0;
          t.cancel();
        }
      });
    });
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _countdown == 0 && _controller.text.trim() == _expected;
    return AlertDialog(
      title: const Text('注销账户'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
              '注销后会立刻清除你的身份资料（昵称、Apple 账号绑定、设备信息、定时任务）。\n\n'
              '依据监管要求，订单与喜点流水会保留，但不再与你关联。\n\n'
              '此操作无法撤销。请在下方输入「$_expected」确认。',
              style: TextStyle(fontSize: 13, height: 1.5)),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              isDense: true,
              hintText: '在此输入：$_expected',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: canSubmit ? AppColors.danger : Colors.grey,
          ),
          onPressed: canSubmit ? () => Navigator.pop(context, true) : null,
          child: Text(_countdown > 0 ? '请稍候 ${_countdown}s' : '确认注销'),
        ),
      ],
    );
  }
}

class _LedgerSheet extends StatefulWidget {
  const _LedgerSheet();
  @override
  State<_LedgerSheet> createState() => _LedgerSheetState();
}

class _LedgerSheetState extends State<_LedgerSheet> {
  @override
  void initState() {
    super.initState();
    final billing = context.read<BillingState>();
    Future.microtask(() => billing.refreshLedger(reset: true));
  }

  @override
  Widget build(BuildContext context) {
    final billing = context.watch<BillingState>();
    final items = billing.ledger;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (ctx, controller) {
        return Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderDim,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('喜点流水',
                    style: TextStyle(
                        color: AppColors.amber,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0)),
              ),
            ),
            Expanded(
              child: items.isEmpty && billing.loadingLedger
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : items.isEmpty
                      ? Center(
                          child: Text('还没有流水记录',
                              style: TextStyle(
                                  color: AppColors.textTertiary, fontSize: 12)))
                      : NotificationListener<ScrollNotification>(
                          onNotification: (n) {
                            if (n.metrics.pixels >=
                                    n.metrics.maxScrollExtent - 100 &&
                                billing.ledgerHasMore &&
                                !billing.loadingLedger) {
                              billing.refreshLedger();
                            }
                            return false;
                          },
                          child: ListView.separated(
                            controller: controller,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount:
                                items.length + (billing.ledgerHasMore ? 1 : 0),
                            separatorBuilder: (_, __) => Divider(
                              color: AppColors.borderDim,
                              height: 1,
                            ),
                            itemBuilder: (_, i) {
                              if (i >= items.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Center(
                                      child: SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))),
                                );
                              }
                              return _LedgerRow(item: items[i]);
                            },
                          ),
                        ),
            ),
          ],
        );
      },
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.item});
  final CreditLedgerItem item;

  @override
  Widget build(BuildContext context) {
    final positive = item.delta >= 0;
    final dt = DateTime.fromMillisecondsSinceEpoch(item.createdAt);
    final ts =
        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.reasonLabel,
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(ts,
                    style: TextStyle(
                        color: AppColors.textTertiary, fontSize: 11)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                item.deltaLabel,
                style: TextStyle(
                  color: positive ? AppColors.positive : AppColors.danger,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text('余 ${item.balanceLabel}',
                  style: TextStyle(
                      color: AppColors.textTertiary, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}
