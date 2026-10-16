import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../core/app_profile.dart';
import '../core/auth/require_login.dart';
import '../core/format/credit_fmt.dart';
import '../screens/settings/account_kit.dart';
import '../screens/settings/invite_credits_screen.dart';
import '../state/auth_state.dart';
import '../state/billing_state.dart';
import '../theme/app_theme.dart';
import '../widgets/legal_links.dart';
import '../widgets/wk_kit.dart';
import 'wx_kit.dart';

/// 「我」页签：微信式个人页。
///
/// 顺序照微信：身份在最上（头像在右、名字在左），下面是几组行 —— 喜点、
/// 随身工具、账号与条款，页脚收尾。没有导航栏，也没有「设置」二级页：
/// 这一页本身就是设置。
class WxMeTab extends StatefulWidget {
  const WxMeTab({super.key});

  @override
  State<WxMeTab> createState() => _WxMeTabState();
}

class _WxMeTabState extends State<WxMeTab> {
  bool _bootstrapped = false;
  String _version = '';

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

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final user = auth.currentUser;
    final billing = context.watch<BillingState>();
    final note = appProfile.settingsNote(context);

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: AppColors.amber,
        onRefresh: () => billing.refreshAll(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.md, AppSpace.md, AppSpace.md, AppSpace.xxl),
          children: [
            _ProfileHead(
              nickname: user?.nickname ?? '未登录',
              uid: user?.uuid ?? '',
              onTap: () async {
                if (user == null) {
                  await requireLogin(context);
                  return;
                }
                // 已登录：这一格暂时没有资料页，给一句实话，不做假页面。
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('昵称和头像用的是账号里的资料，暂不支持在这里改'),
                  duration: Duration(seconds: 2),
                ));
              },
            ),
            WkGroup(
              children: [
                _ValueRow(
                  key: const ValueKey('me-credits'),
                  icon: Icons.savings_outlined,
                  title: '喜点',
                  value: billing.loadingBalance
                      ? '…'
                      : CreditFmt.balance(billing.balance),
                  onTap: user == null
                      ? null
                      : () {
                          if (rechargeAvailable) {
                            // ignore: unawaited_futures
                            showRechargeSheet(context);
                          } else {
                            showLedgerSheet(context);
                          }
                        },
                ),
                ProfileIndexRow(
                  key: const ValueKey('me-ledger'),
                  icon: Icons.receipt_long_rounded,
                  title: '喜点明细',
                  note: '每轮对话 1 喜点',
                  onTap: user == null ? null : () => showLedgerSheet(context),
                ),
              ],
            ),
            WkGroup(
              children: [
                ...appProfile.settingsTools(context),
                ProfileIndexRow(
                  key: const ValueKey('me-invite'),
                  icon: Icons.card_giftcard_rounded,
                  title: '邀请好友',
                  note: '双方各得 100 喜点',
                  onTap: () async {
                    if (!await requireLogin(context)) return;
                    if (!context.mounted) return;
                    await Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => const InviteCreditsScreen()));
                  },
                ),
              ],
            ),
            if (note != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpace.xs, 0, AppSpace.xs, AppSpace.sm),
                child: Text(
                  note,
                  style: AppType.caption
                      .copyWith(color: AppColors.textTertiary, height: 1.5),
                ),
              ),
            WkGroup(
              children: [
                if (user == null)
                  ProfileIndexRow(
                    key: const ValueKey('me-login'),
                    icon: Icons.login_rounded,
                    title: '登录 / 注册',
                    note: '同步喜点与定时提醒',
                    onTap: () => requireLogin(context),
                  )
                else
                  ProfileIndexRow(
                    key: const ValueKey('me-logout'),
                    icon: Icons.logout_rounded,
                    title: '退出登录',
                    note: '',
                    danger: true,
                    onTap: () => _confirmLogout(context, auth),
                  ),
                if (user != null)
                  ProfileIndexRow(
                    key: const Key('settings-delete-account'),
                    icon: Icons.person_remove_outlined,
                    title: '注销账号',
                    note: '',
                    onTap: () => _confirmDelete(context, auth),
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
        content: const Text('退出后本地缓存的对话会一并清空，重新登录可恢复喜点余额。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('再想想')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('退出')),
        ],
      ),
    );
    if (ok == true) await auth.logout();
  }

  /// 注销账号（App Store 5.1.1(v)）：说明后果 + 3 秒倒计时防误点。
  Future<void> _confirmDelete(BuildContext context, AuthState auth) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const DeleteAccountDialog(),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await auth.deleteAccount();
      messenger.showSnackBar(const SnackBar(content: Text('账号已注销')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('注销失败，请检查网络后再试')));
    }
  }
}

/// 微信式抬头：名字与号在左，头像在右。
class _ProfileHead extends StatelessWidget {
  const _ProfileHead({
    required this.nickname,
    required this.uid,
    required this.onTap,
  });

  final String nickname;
  final String uid;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = nickname.trim().isEmpty ? '未登录' : nickname.trim();
    final shortUid = uid.length > 8 ? uid.substring(0, 8) : uid;
    return Material(
      color: AppColors.bgSurface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        key: const ValueKey('me-profile'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.lg, AppSpace.lg, AppSpace.md, AppSpace.lg),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.title.copyWith(
                            fontSize: 22, fontWeight: FontWeight.w600)),
                    const SizedBox(height: AppSpace.sm),
                    Text(
                      shortUid.isEmpty ? '未登录 · 数据只在本机' : '喜爱号 $shortUid',
                      style: AppType.caption.copyWith(
                        color: AppColors.textSecondary,
                        fontFamilyFallback: AppType.numericFallback,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpace.md),
              const WxAvatar(text: kBrandMark, size: 60),
              Icon(Icons.chevron_right_rounded,
                  size: 22, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

/// 带右侧数值的行（喜点余额用它）。
class _ValueRow extends StatelessWidget {
  const _ValueRow({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
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
                horizontal: AppSpace.lg, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 22, color: AppColors.amber),
                const SizedBox(width: AppSpace.md),
                Expanded(child: Text(title, style: AppType.body)),
                Text(value,
                    style: AppType.body.copyWith(
                      color: AppColors.textSecondary,
                      fontFamilyFallback: AppType.numericFallback,
                    )),
                if (onTap != null) ...[
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
