import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/require_login.dart';
import '../../core/topic/topic_pack.dart';
import '../../core/topic/topic_registry.dart';
import '../../services/analytics.dart';
import '../../services/network_permission_service.dart';
import '../../state/auth_state.dart';
import '../../state/billing_state.dart';
import '../../theme/app_theme.dart';

/// 主界面：底部页签由当前主题包提供（[TopicPack.tabs]）。
///
/// 喜爱钱：对话 / 策略 / 发现 / 我的；喜爱钓鱼：对话 / 出钓 / 渔获 / 我的。
/// 底栏样式、登录门槛、角标、埋点对所有主题一致。
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver {
  // 页签下标，对应 `pack.tabs`。
  //
  // 底部四个页签：两个"主功能" + 一个二梯队/记录页 + 个人中心（照微信）。
  //
  // 仅用于设计走查：`--dart-define=INITIAL_TAB=1` 可以让 App 直接落在指定页签，
  // 免得每次截图都要手点。不影响正常构建（默认 0 = 对话）。
  int _index = const int.fromEnvironment('INITIAL_TAB', defaultValue: 0);

  // 网络由「受限」恢复「可用」时自增，用于重建页面子树触发各 tab 重新拉数据。
  int _reloadTick = 0;
  StreamSubscription<void>? _networkSub;

  late final TopicPack _pack = topicOf(context);
  late final List<TopicTab> _tabs = _pack.tabs;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _networkSub =
        NetworkPermissionService.instance.onNetworkAvailable.listen((_) {
      _onNetworkRestored();
    });
    // 进入主题（冷启动 / 切换主题后的首帧）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _pack.onEnter(context);
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
      if (mounted) _pack.onResume(context);
    }
  }

  /// iOS 首启用户授权「无线数据」后回调：预热网络 + 刷新登录态/账单，并
  /// bump reload tick 重建页面子树，让当前页面各 tab 重新执行初始加载。
  void _onNetworkRestored() {
    if (!mounted) return;
    _pack.onNetworkRestored(context);
    final auth = context.read<AuthState>();
    if (auth.isAuthenticated) {
      // ignore: unawaited_futures
      auth.refreshProfile();
      // ignore: unawaited_futures
      context.read<BillingState>().refreshAll();
    }
    setState(() => _reloadTick++);
  }

  bool _gated(int i) => i >= 0 && i < _tabs.length && _tabs[i].requiresLogin;

  /// 切换 tab；命中需鉴权的 tab 时先弹登录，放弃登录则停留原 tab。
  Future<void> _selectTab(int i) async {
    if (_gated(i) && !context.read<AuthState>().isAuthenticated) {
      final ok = await requireLogin(context);
      if (!ok || !mounted) return;
    }
    Analytics.instance.track(Analytics.evTabView, {'tab': _tabs[i].key});
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final index = _index.clamp(0, _tabs.length - 1);
    final pages = [for (final t in _tabs) t.builder(context)];

    // 登出 / 强制下线后若仍停在需登录的 tab，退回对话首页，避免展示空白个人页。
    final authed = context.watch<AuthState>().isAuthenticated;
    if (!authed && _gated(index)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !context.read<AuthState>().isAuthenticated) {
          setState(() => _index = 0);
        }
      });
    }

    return Scaffold(
      body: KeyedSubtree(
        key: ValueKey(_reloadTick),
        child: IndexedStack(index: index, children: pages),
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
                for (var i = 0; i < _tabs.length; i++)
                  _NavItem(
                    icon: _tabs[i].icon,
                    activeIcon: _tabs[i].activeIcon,
                    label: _tabs[i].label,
                    active: index == i,
                    badge: _tabs[i].badge?.call(context) ?? 0,
                    onTap: () => _selectTab(i),
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
