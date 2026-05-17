import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/auth/auth_gate.dart';
import 'state/settings_state.dart';
import 'theme/app_theme.dart';

class FinceptApp extends StatelessWidget {
  const FinceptApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsState>(
      builder: (context, settings, _) {
        final mode = settings.themeMode;
        // Build a single ThemeData for the active mode — also pushes the
        // matching palette into `AppColors` so widgets that reference it
        // pick up the new colours on this rebuild.
        final theme = AppTheme.build(mode);
        return MaterialApp(
          title: 'AIQuant',
          debugShowCheckedModeBanner: false,
          theme: theme,
          home: const AuthGate(),
        );
      },
    );
  }
}
