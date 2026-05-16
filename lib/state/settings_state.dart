import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../theme/app_theme.dart';

class SettingsState extends ChangeNotifier {
  bool _ready = false;
  bool get ready => _ready;

  Future<void> bootstrap() async {
    await AppConfig.instance.load();
    // Push the persisted palette into [AppColors] before the first build.
    AppColors.applyMode(AppConfig.instance.themeMode);
    _ready = true;
    notifyListeners();
  }

  ThemeMode get themeMode => AppConfig.instance.themeMode;

  Future<void> toggleThemeMode() async {
    final next =
        themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await AppConfig.instance.setThemeMode(next);
    AppColors.applyMode(next);
    notifyListeners();
  }

  String get tushareToken => AppConfig.instance.tushareToken;
  bool get hasTushareToken => AppConfig.instance.hasTushareToken;
  String get tushareEndpoint => AppConfig.instance.tushareEndpoint;

  String get deepseekKey => AppConfig.instance.deepseekApiKey;
  bool get hasDeepseekKey => AppConfig.instance.hasDeepseekKey;
  String get deepseekModel => AppConfig.instance.deepseekModel;
  bool get deepMode => AppConfig.instance.deepMode;

  Future<void> updateTushareToken(String token) async {
    await AppConfig.instance.setTushareToken(token);
    notifyListeners();
  }

  Future<void> updateTushareEndpoint(String url) async {
    await AppConfig.instance.setTushareEndpoint(url);
    notifyListeners();
  }

  Future<void> updateDeepseekKey(String key) async {
    await AppConfig.instance.setDeepseekApiKey(key);
    notifyListeners();
  }

  Future<void> updateDeepMode(bool on) async {
    await AppConfig.instance.setDeepMode(on);
    notifyListeners();
  }

  Future<void> updateDeepseekModel(String model) async {
    await AppConfig.instance.setDeepseekModel(model);
    notifyListeners();
  }
}
