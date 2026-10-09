import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/require_login.dart';
import '../../services/network_permission_service.dart';
import '../../services/tushare_service.dart';
import '../../state/auth_state.dart';
import '../../state/billing_state.dart';
import '../../state/ding_state.dart';
import '../../theme/app_theme.dart';
import '../assistant/assistant_screen.dart';
import '../settings/settings_screen.dart';
import '../strategy/strategy_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver {
  // 0 = 对话, 1 = 策略, 2 = 我的
  //
  // 底部只留两个"主功能"（对话 / 策略）+ 个人中心：看盘、自选、DING、组合
  // 都收进「我的」。股票行情改成按需触达——聊天里提到某只股票时点链接进详情，
  // 而不是让人先切 tab 再去搜。
  int _index = 0;

  // 网络由「受限」恢复「可用」时自增，用于重建页面子树触发各 tab 重新拉数据。
  int _reloadTick = 0;
  StreamSubscription<void>? _networkSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _networkSub =
        NetworkPermissionService.instance.onNetworkAvailable.listen((_) {
      _onNetworkRestored();
    });
  }

  @override
  void dispose() {
    _networkSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 回到前台时让 DING 调度器追赶一次（移动端无真后台 cron）
      if (mounted) context.read<DingState>().resumeFromBackground();
    }
  }

  /// iOS 首启用户授权「无线数据」后回调：预热网络 + 刷新登录态/账单，并
  /// bump reload tick 重建页面子树，让当前页面各 tab 重新执行初始加载。
  void _onNetworkRestored() {
    if (!mounted) return;
    // ignore: unawaited_futures
    TushareService().warmup();
    final auth = context.read<AuthState>();
    if (auth.isAuthenticated) {
      // ignore: unawaited_futures
      auth.refreshProfile();
      // ignore: unawaited_futures
      context.read<BillingState>().refreshAll();
    }
    setState(() => _reloadTick++);
  }

  /// 需要登录才能进入的 tab：策略(1) / 我的(2)。
  /// 策略数据本身来自账号相关的实盘配置，未登录不展示。
  static const _gatedTabs = {1, 2};

  /// 切换 tab；命中需鉴权的 tab 时先弹登录，放弃登录则停留原 tab。
  Future<void> _selectTab(int i) async {
    if (_gatedTabs.contains(i) && !context.read<AuthState>().isAuthenticated) {
      final ok = await requireLogin(context);
      if (!ok || !mounted) return;
    }
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    const pages = [
      AssistantScreen(),
      StrategyScreen(),
      SettingsScreen(),
    ];
    final unread = context.watch<DingState>().unreadCount;

    // 登出 / 强制下线后若仍停在需登录的 tab，退回助理首页，避免展示空白个人页。
    final authed = context.watch<AuthState>().isAuthenticated;
    if (!authed && _gatedTabs.contains(_index)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !context.read<AuthState>().isAuthenticated) {
          setState(() => _index = 0);
        }
      });
    }

    return Scaffold(
      body: KeyedSubtree(
        key: ValueKey(_reloadTick),
        child: IndexedStack(index: _index, children: pages),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          border: Border(top: BorderSide(color: AppColors.borderDim)),
        ),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.only(bottom: 4),
          child: SizedBox(
            height: 56,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _NavItem(
                  icon: Icons.chat_bubble_outline,
                  activeIcon: Icons.chat_bubble,
                  label: '对话',
                  active: _index == 0,
                  onTap: () => _selectTab(0),
                ),
                _NavItem(
                  icon: Icons.insights_outlined,
                  activeIcon: Icons.insights,
                  label: '策略',
                  active: _index == 1,
                  onTap: () => _selectTab(1),
                ),
                _NavItem(
                  icon: Icons.person_outline,
                  activeIcon: Icons.person,
                  label: '我的',
                  active: _index == 2,
                  badge: unread,
                  onTap: () => _selectTab(2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.amber : AppColors.textSecondary;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(active ? activeIcon : icon, size: 18, color: color),
                if (badge > 0)
                  Positioned(
                    right: -8,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      constraints:
                          const BoxConstraints(minWidth: 14, minHeight: 14),
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: BorderRadius.circular(7),
                        border:
                            Border.all(color: AppColors.bgSurface, width: 1),
                      ),
                      child: Text(
                        badge > 99 ? '99+' : '$badge',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 1),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: active ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
