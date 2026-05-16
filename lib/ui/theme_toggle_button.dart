import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/settings_state.dart';

/// AppBar action button that toggles between light/dark mode.
/// Drop this into any `AppBar.actions` list — it reads the current mode
/// from [SettingsState] and triggers a global theme rebuild on tap.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsState>();
    final isDark = settings.themeMode == ThemeMode.dark;
    return IconButton(
      tooltip: isDark ? '切换到 浅色 主题' : '切换到 深色 主题',
      icon: Icon(
        isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
        size: 18,
      ),
      onPressed: () => context.read<SettingsState>().toggleThemeMode(),
    );
  }
}
