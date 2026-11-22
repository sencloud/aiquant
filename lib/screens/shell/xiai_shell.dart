import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../assistant/assistant_screen.dart';
import '../my/my_screen.dart';
import '../trade_review/trade_review_home.dart';
import '../watch/watch_screen.dart';

/// Three-tab application shell: 嘻，AI / 对话 / 我的.
///
/// Screenshot review is the primary job. The restored AI conversation and the
/// account tools remain one tap away. IndexedStack keeps every page warm while
/// switching tabs.
class XiaiShell extends StatefulWidget {
  const XiaiShell({
    super.key,
    this.chatPageBuilder,
    this.watchPageBuilder,
    this.historyPageBuilder,
  });

  final WidgetBuilder? chatPageBuilder;
  final WidgetBuilder? watchPageBuilder;
  final WidgetBuilder? historyPageBuilder;

  @override
  State<XiaiShell> createState() => _XiaiShellState();
}

class _XiaiShellState extends State<XiaiShell> {
  int _index = 0;

  void _select(int index) {
    if (_index == index) return;
    HapticFeedback.selectionClick();
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final watchPageBuilder =
        widget.watchPageBuilder ?? (_) => const WatchScreen();
    final pages = <Widget>[
      const TradeReviewHomeScreen(),
      (widget.chatPageBuilder ?? (_) => const AssistantScreen())(context),
      MyScreen(
        watchPageBuilder: watchPageBuilder,
        historyPageBuilder: widget.historyPageBuilder,
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.bgSurface,
      body: IndexedStack(
        index: _index,
        children: [
          for (var i = 0; i < pages.length; i++)
            TickerMode(enabled: i == _index, child: pages[i]),
        ],
      ),
      bottomNavigationBar: _XiaiTabBar(
        index: _index,
        onSelect: _select,
      ),
    );
  }
}

class _XiaiTabBar extends StatelessWidget {
  const _XiaiTabBar({
    required this.index,
    required this.onSelect,
  });

  final int index;
  final ValueChanged<int> onSelect;

  static const _items = <(String, IconData, IconData)>[
    ('嘻，AI', Icons.auto_awesome_outlined, Icons.auto_awesome_rounded),
    ('对话', Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded),
    ('我的', Icons.person_outline_rounded, Icons.person_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F8F8),
        border: Border(
          top: BorderSide(color: AppColors.borderDim, width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: _TabButton(
                    label: _items[i].$1,
                    icon: _items[i].$2,
                    activeIcon: _items[i].$3,
                    active: index == i,
                    onTap: () => onSelect(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.active,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.amber : AppColors.textSecondary;
    return Semantics(
      selected: active,
      button: true,
      label: label,
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
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                fontFamilyFallback: AppType.sansFallback,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
