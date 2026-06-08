import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/require_login.dart';
import '../../state/auth_state.dart';
import '../../state/ding_state.dart';
import '../../theme/app_theme.dart';
import '../assistant/assistant_screen.dart';
import '../ding/ding_screen.dart';
import '../live/live_screen.dart';
import '../portfolio/portfolio_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver {
  // 0 = 助理, 1 = 组合, 2 = AI 直播(中间凸起), 3 = DING, 4 = 我的
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
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

  /// 需要登录才能进入的 tab：DING(3) / 我的(4)。
  static const _gatedTabs = {3, 4};

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
      PortfolioScreen(),
      LiveScreen(),
      DingScreen(),
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
      body: IndexedStack(index: _index, children: pages),
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
                  icon: Icons.psychology_outlined,
                  activeIcon: Icons.psychology,
                  label: '助理',
                  active: _index == 0,
                  onTap: () => _selectTab(0),
                ),
                _NavItem(
                  icon: Icons.pie_chart_outline,
                  activeIcon: Icons.pie_chart,
                  label: '组合',
                  active: _index == 1,
                  onTap: () => _selectTab(1),
                ),
                _LiveCenterButton(
                  active: _index == 2,
                  onTap: () => _selectTab(2),
                ),
                _NavItem(
                  icon: Icons.notifications_none,
                  activeIcon: Icons.notifications_active,
                  label: 'DING',
                  active: _index == 3,
                  badge: unread,
                  onTap: () => _selectTab(3),
                ),
                _NavItem(
                  icon: Icons.person_outline,
                  activeIcon: Icons.person,
                  label: '我的',
                  active: _index == 4,
                  onTap: () => _selectTab(4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 底部中间「AI 直播」凸起按钮 —— 圆形金黄渐变 + 直播红点,
/// 比普通 tab 更突出,强调"实时直播"的核心入口地位。
class _LiveCenterButton extends StatelessWidget {
  const _LiveCenterButton({required this.active, required this.onTap});
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.amber, AppColors.amberDim],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.amber.withValues(alpha: active ? 0.55 : 0.3),
                    blurRadius: active ? 12 : 6,
                    spreadRadius: active ? 1 : 0,
                  ),
                ],
                border: Border.all(color: AppColors.bgSurface, width: 2),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.live_tv, color: Colors.white, size: 20),
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFFef4444),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 1),
            Text(
              '直播',
              style: TextStyle(
                color: active ? AppColors.amber : AppColors.textSecondary,
                fontSize: 10,
                fontWeight: active ? FontWeight.w800 : FontWeight.w700,
              ),
            ),
          ],
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
