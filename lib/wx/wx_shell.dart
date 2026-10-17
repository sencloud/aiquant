import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_profile.dart';
import '../core/auth/require_login.dart';
import '../services/analytics.dart';
import '../services/network_permission_service.dart';
import '../state/auth_state.dart';
import '../state/billing_state.dart';
import '../theme/app_theme.dart';
import 'chat_list_tab.dart';
import 'discover_tab.dart';
import 'me_tab.dart';
import 'plaza_tab.dart';

/// App 外壳：底部四个页签，照微信。
///
///   消息 / 广场 / 发现 / 我
///
/// 消息是首屏：它是**会话列表**，点一行进聊天页（和微信一样，聊天是二级页，
/// 不是页签）。广场是今晚在这儿的人：六位 AI 居民，挑一个打招呼或者摇一摇。
/// 发现放第二梯队的东西。我是账号、喜点与设置。
///
/// 这一版把「主题 / 圈子」整个拿掉了：没有选主题页，没有切换主题，没有圈子
/// 首页，也不会再整屏换色 —— App 只有一个身份（见 `core/app_profile.dart`）。
class WxShell extends StatefulWidget {
  const WxShell({super.key});

  @override
  State<WxShell> createState() => _WxShellState();
}

class _WxShellState extends State<WxShell> with WidgetsBindingObserver {
  /// 仅用于设计走查：`--dart-define=INITIAL_TAB=1` 可以让 App 直接落在
  /// 指定页签，免得每次截图都要手点。默认 0 = 消息。
  int _index = const int.fromEnvironment('INITIAL_TAB', defaultValue: 0);

  /// 网络由「受限」恢复「可用」时自增，用于重建页面子树触发各页重新拉数据。
  int _reloadTick = 0;
  StreamSubscription<void>? _networkSub;

  static const _keys = ['chats', 'plaza', 'discover', 'me'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _networkSub =
        NetworkPermissionService.instance.onNetworkAvailable.listen((_) {
      _onNetworkRestored();
    });
    // 进入 App 后执行一次的副作用（预热 Tushare，触发首启联网授权弹窗）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) appProfile.onEnter(context);
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
    if (state == AppLifecycleState.resumed && mounted) {
      appProfile.onResume(context);
    }
  }

  /// iOS 首启用户授权「无线数据」后回调：预热网络 + 刷新登录态/账单，并
  /// bump reload tick 重建页面子树，让各页重新执行初始加载。
  void _onNetworkRestored() {
    if (!mounted) return;
    appProfile.onNetworkRestored(context);
    final auth = context.read<AuthState>();
    if (auth.isAuthenticated) {
      // ignore: unawaited_futures
      auth.refreshProfile();
      // ignore: unawaited_futures
      context.read<BillingState>().refreshAll();
    }
    setState(() => _reloadTick++);
  }

  Future<void> _select(int i) async {
    // 「我」要登录：与二级页里的需账号动作同一条规矩。
    if (i == 3 && !context.read<AuthState>().isAuthenticated) {
      final ok = await requireLogin(context);
      if (!ok || !mounted) return;
    }
    Analytics.instance.track(Analytics.evTabView, {'tab': _keys[i]});
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final index = _index.clamp(0, 3);
    final pages = <Widget>[
      const WxChatListTab(),
      const WxPlazaTab(),
      const WxDiscoverTab(),
      const WxMeTab(),
    ];

    // 登出 / 强制下线后若仍停在「我」，退回消息页，避免展示空白个人页。
    final authed = context.watch<AuthState>().isAuthenticated;
    if (!authed && index == 3) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !context.read<AuthState>().isAuthenticated) {
          setState(() => _index = 0);
        }
      });
    }

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: KeyedSubtree(
        key: ValueKey(_reloadTick),
        child: IndexedStack(index: index, children: pages),
      ),
      bottomNavigationBar: WxTabBar(
        index: index,
        onSelect: _select,
      ),
    );
  }
}

/// 微信式底栏：浅灰底 + 一条发丝线，图标 24、标签 11，选中是绿色。
class WxTabBar extends StatelessWidget {
  const WxTabBar({super.key, required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  static const _items = <(String, IconData, IconData)>[
    ('消息', Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded),
    ('广场', Icons.people_alt_outlined, Icons.people_alt_rounded),
    ('发现', Icons.explore_outlined, Icons.explore_rounded),
    ('我', Icons.person_outline_rounded, Icons.person_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgRaised,
        border: Border(top: BorderSide(color: AppColors.borderDim, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 50,
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                _WxNavItem(
                  icon: _items[i].$2,
                  activeIcon: _items[i].$3,
                  label: _items[i].$1,
                  active: index == i,
                  onTap: () => onSelect(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WxNavItem extends StatelessWidget {
  const _WxNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool active;
  final VoidCallback onTap;

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
            Icon(active ? activeIcon : icon, size: 24, color: color),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                height: 1.1,
                fontWeight: active ? FontWeight.w500 : FontWeight.w400,
                fontFamilyFallback: AppType.sansFallback,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
