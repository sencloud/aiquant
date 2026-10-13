import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/topic/topic_picker_screen.dart';
import '../../core/topic/topic_state.dart';
import '../../core/auth/require_login.dart';
import '../../screens/settings/settings_screen.dart';
import '../../services/analytics.dart';
import '../../state/auth_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import 'hub_screen.dart';

/// 兴趣圈外壳：App 的首屏。三个页签 —— 首页（今日指数台）/ 圈子 / 我的。
///
/// 进圈是**整屏**（[HubState.insideCircle] 为 true 时换成那个圈的页签外壳），
/// 所以这里不需要二级路由：首页与圈是一层状态切换。
class HubShell extends StatefulWidget {
  const HubShell({super.key});

  @override
  State<HubShell> createState() => _HubShellState();
}

class _HubShellState extends State<HubShell> {
  int _index = 0;

  static const _keys = ['hub', 'circles', 'me'];

  Future<void> _select(int i) async {
    // 「我的」要登录：与圈内「我的」同一条规矩。
    if (i == 2 && !context.read<AuthState>().isAuthenticated) {
      final ok = await requireLogin(context);
      if (!ok || !mounted) return;
    }
    Analytics.instance.track(Analytics.evTabView, {'tab': _keys[i]});
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const HubHomeTab(),
      const HubCirclesTab(),
      const SettingsScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          border:
              Border(top: BorderSide(color: AppColors.borderDim, width: 0.5)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 54,
            child: Row(
              children: [
                _HubNavItem(
                  icon: Icons.wb_twilight_outlined,
                  activeIcon: Icons.wb_twilight_rounded,
                  label: '首页',
                  active: _index == 0,
                  onTap: () => _select(0),
                ),
                _HubNavItem(
                  icon: Icons.grid_view_outlined,
                  activeIcon: Icons.grid_view_rounded,
                  label: '圈子',
                  active: _index == 1,
                  onTap: () => _select(1),
                ),
                _HubNavItem(
                  icon: Icons.person_outline_rounded,
                  activeIcon: Icons.person_rounded,
                  label: '我的',
                  active: _index == 2,
                  onTap: () => _select(2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 「圈子」页签：全部兴趣圈 + 换一个。
class HubCirclesTab extends StatelessWidget {
  const HubCirclesTab({super.key});

  @override
  Widget build(BuildContext context) {
    final topics = context.watch<TopicState>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.gutter, AppSpace.xl, AppSpace.gutter, AppSpace.xxl),
      children: [
        const Text('圈子', style: AppType.display),
        const SizedBox(height: AppSpace.sm),
        Text(
          '每个圈有自己的 AI、自己的记录、自己的配色。进一个圈，整屏就换成它的颜色。',
          style: AppType.read.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: AppSpace.xl),
        WkGroup(
          children: [
            for (final pack in topics.available)
              WkRow(
                key: ValueKey('circles-${pack.id}'),
                icon: pack.icon,
                title: pack.name,
                subtitle: pack.blurb,
                trailing: pack.id == topics.currentId
                    ? const WkTag('当前', filled: true)
                    : null,
                onTap: () => enterCircle(context, pack),
              ),
            WkRow(
              key: const ValueKey('circles-switch'),
              icon: Icons.swap_horiz_rounded,
              title: '换一个圈',
              subtitle: '账号与喜点通用，记录各自保留',
              onTap: () => showTopicSwitcher(context),
            ),
          ],
        ),
        const WkNote(
          text: '新增圈子时会先问三个问题（你在琢磨什么、最想要哪种帮忙、每周能花多少时间），'
              '再推荐你从哪两个圈开始。',
        ),
      ],
    );
  }
}

class _HubNavItem extends StatelessWidget {
  const _HubNavItem({
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
            Icon(active ? activeIcon : icon, size: 22, color: color),
            const SizedBox(height: 1),
            Text(label,
                style: TextStyle(
                  color: color,
                  fontSize: 10.5,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                )),
          ],
        ),
      ),
    );
  }
}
