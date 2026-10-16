import 'package:flutter/material.dart';

import '../core/config/app_config.dart';

class SettingsState extends ChangeNotifier {
  bool _ready = false;
  bool get ready => _ready;

  Future<void> bootstrap() async {
    await AppConfig.instance.load();
    _ready = true;
    notifyListeners();
  }

  ThemeMode get themeMode => AppConfig.instance.themeMode;

  // App 只有浅色一套（微信式外观就是浅色那一套）。深色没有入口，
  // 所以这里不再往 AppColors 推任何模式。
}
