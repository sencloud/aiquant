import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../theme/app_theme.dart';

class SettingsState extends ChangeNotifier {
  bool _ready = false;
  bool get ready => _ready;

  Future<void> bootstrap() async {
    await AppConfig.instance.load();
    AppColors.applyMode(AppConfig.instance.themeMode);
    _ready = true;
    notifyListeners();
  }

  ThemeMode get themeMode => AppConfig.instance.themeMode;

  // 兼容 app.dart 里的 ThemeMode 监听调用，但 UI 已不再暴露切换入口。
  // 主题恒为 Light Mode。
}
