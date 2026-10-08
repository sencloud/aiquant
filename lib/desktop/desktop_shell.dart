import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'backtest/backtest_screen.dart';
import 'desktop_chat_screen.dart';

/// DesktopShell 是桌面端（Windows/macOS/Linux）的主框架。
///
/// 自定义侧边栏（非 Material NavigationRail）：
/// - 顶部品牌区：金黄闪电 + 产品名 + 定位语
/// - 中部导航：助理 / 回测，琥珀色激活态（左侧指示条 + 柔和底色）
/// - 底部：版本信息
///
/// 移动端不受影响：app.dart 仅在桌面平台才挂载本 Shell。
class DesktopShell extends StatefulWidget {
  const DesktopShell({super.key});

  @override
  State<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends State<DesktopShell> {
  int _selectedIndex = 0;

  // 用 IndexedStack 保活两个页面：切换页签不丢聊天滚动位置 / 回测参数。
  static const _pages = <Widget>[
    DesktopChatScreen(),
    BacktestScreen(),
  ];

  static const _navItems = [
    (Icons.chat_bubble_outline, Icons.chat_bubble, '助理', 'AI 对话'),
    (Icons.query_stats_outlined, Icons.query_stats, '回测', 'ETF 策略调试'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Row(
        children: [
          _sidebar(context),
          Expanded(child: _pages[_selectedIndex]),
        ],
      ),
    );
  }

  Widget _sidebar(BuildContext context) {
    return Container(
      width: 208,
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        border: Border(
          right: BorderSide(color: AppColors.borderDim),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 品牌区 ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.amber,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.bolt,
                      color: Colors.black, size: 20),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '喜宽',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                      ),
                    ),
                    Text(
                      'AI 投研终端',
                      style: TextStyle(
                          color: AppColors.textTertiary, fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── 导航区 ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              children: [
                for (var i = 0; i < _navItems.length; i++)
                  _NavItem(
                    icon: _navItems[i].$1,
                    activeIcon: _navItems[i].$2,
                    label: _navItems[i].$3,
                    subtitle: _navItems[i].$4,
                    active: _selectedIndex == i,
                    onTap: () => setState(() => _selectedIndex = i),
                  ),
              ],
            ),
          ),

          const Spacer(),

          // ── 底部版本 ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              '桌面版 · 本地回测引擎',
              style:
                  TextStyle(color: AppColors.textTertiary, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单个导航项：图标 + 主标签 + 副标签。
/// 激活时左侧 3px 琥珀指示条 + 12% 琥珀底色；悬停有轻微提亮。
class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.subtitle,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String subtitle;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final bg = widget.active
        ? AppColors.amber.withValues(alpha: 0.12)
        : _hovering
            ? AppColors.bgHover
            : Colors.transparent;
    final fg = widget.active
        ? AppColors.amber
        : AppColors.textSecondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 56,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(10),
              border: widget.active
                  ? Border.all(color: AppColors.amber.withValues(alpha: 0.35))
                  : null,
            ),
            child: Row(
              children: [
                // 激活指示条
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 3,
                  height: widget.active ? 22 : 0,
                  margin: const EdgeInsets.only(left: 6),
                  decoration: BoxDecoration(
                    color: AppColors.amber,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  widget.active ? widget.activeIcon : widget.icon,
                  size: 20,
                  color: fg,
                ),
                const SizedBox(width: 12),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: TextStyle(
                        color: widget.active
                            ? AppColors.textPrimary
                            : AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: widget.active
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                    Text(
                      widget.subtitle,
                      style: TextStyle(
                          color: AppColors.textTertiary, fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
