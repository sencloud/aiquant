import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/require_login.dart';
import '../../services/analytics.dart';
import '../../services/network_permission_service.dart';
import '../../services/tushare_service.dart';
import '../../state/auth_state.dart';
import '../../state/billing_state.dart';
import '../../state/ding_state.dart';
import '../../theme/app_theme.dart';
import '../assistant/assistant_screen.dart';
import '../discover/discover_screen.dart';
import '../settings/settings_screen.dart';
import '../strategy/strategy_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver {
  // 0 = 对话, 1 = 策略, 2 = 发现, 3 = 我的
  //
  // 底部四个页签：两个"主功能"（对话 / 策略）+ 发现 + 个人中心。
  // 「发现」是第二梯队功能的归档页（照微信），想找什么翻它，而不是全堆首屏。
  // 股票行情改成按需触达——聊天里提到某只股票时点链接进详情，而不是让人先切
  // tab 再去搜。
  //
  // 仅用于设计走查：`--dart-define=INITIAL_TAB=1` 可以让 App 直接落在指定页签，
  // 免得每次截图都要手点。不影响正常构建（默认 0 = 对话）。
  int _index = const int.fromEnvironment('INITIAL_TAB', defaultValue: 0);

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

  /// 需要登录才能进入的 tab：只有「我的」(3)。
  ///
  /// 「策略」页签现在是证伪台，内容不依赖账号，而且它是获客内容 ——
  /// 没有理由让新用户在登录墙后面才能看到它第一次回答「什么不行」。
  /// 「发现」同理：内容可浏览，需要账号的动作自己会弹登录。
  /// 「策略」里真正与账号相关的「实盘策略」入口也自己弹登录。
  static const _gatedTabs = {3};

  /// 切换 tab；命中需鉴权的 tab 时先弹登录，放弃登录则停留原 tab。
  Future<void> _selectTab(int i) async {
    if (_gatedTabs.contains(i) && !context.read<AuthState>().isAuthenticated) {
      final ok = await requireLogin(context);
      if (!ok || !mounted) return;
    }
    Analytics.instance.track(Analytics.evTabView, {'tab': _tabNames[i]});
    setState(() => _index = i);
  }

  static const _tabNames = ['chat', 'strategy', 'discover', 'me'];

  @override
  Widget build(BuildContext context) {
    const pages = [
      AssistantScreen(),
      StrategyScreen(),
      DiscoverScreen(),
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
          border: Border(top: BorderSide(color: AppColors.borderDim, width: 0.5)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 54,
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
                  icon: Icons.explore_outlined,
                  activeIcon: Icons.explore,
                  label: '发现',
                  active: _index == 2,
                  badge: unread,
                  onTap: () => _selectTab(2),
                ),
                _NavItem(
                  icon: Icons.person_outline,
                  activeIcon: Icons.person,
                  label: '我的',
                  active: _index == 3,
                  onTap: () => _selectTab(3),
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
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(active ? activeIcon : icon, size: 22, color: color),
                if (badge > 0)
                  Positioned(
                    right: -10,
                    top: -5,
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
                fontSize: 10.5,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
