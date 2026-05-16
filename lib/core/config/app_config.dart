import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Built-in default credentials. The two tokens below ship with the app so a
/// fresh install works immediately — no settings detour required. The user
/// can still override either one via the Settings screen; the override takes
/// precedence (see [AppConfig] getters below).
class BuiltInSecrets {
  /// Tushare Pro API token (built-in).
  static const String tushareToken =
      'fb95c93a8669026e18f48134d12bf8df936a58e4a02b2fba6a173d65';

  /// DeepSeek API key (built-in).
  static const String deepseekApiKey =
      'sk-b3f9ace2217b4a999569c236850fc6ba';

  /// Default endpoint for Tushare. Don't change unless mirroring.
  static const String tushareEndpoint = 'http://api.tushare.pro';

  /// DeepSeek base URL. Compatible with the OpenAI Chat Completions schema.
  static const String deepseekBaseUrl = 'https://api.deepseek.com';

  /// First-launch model — the lightweight v4-flash gives instant replies and
  /// is what the user wants the app to default to.
  static const String defaultDeepseekModel = 'deepseek-v4-flash';

  /// Reasoning ("深度模式") model — opt-in via the settings switch.
  static const String reasoningDeepseekModel = 'deepseek-reasoner';

  /// Standard chat model — kept as a manual override option.
  static const String chatDeepseekModel = 'deepseek-chat';
}

class AppConfig {
  AppConfig._();
  static final AppConfig instance = AppConfig._();

  static const _kTushareToken = 'tushare_token';
  static const _kTushareEndpoint = 'tushare_endpoint';
  static const _kDeepseekKey = 'deepseek_api_key';
  static const _kDeepseekModel = 'deepseek_model';
  static const _kDeepseekDeepMode = 'deepseek_deep_mode';
  static const _kThemeMode = 'theme_mode';

  late SharedPreferences _prefs;
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _prefs = await SharedPreferences.getInstance();
    _loaded = true;
  }

  // ── Tushare ────────────────────────────────────────────────────────────
  String get tushareToken {
    final v = _prefs.getString(_kTushareToken);
    if (v != null && v.trim().isNotEmpty) return v.trim();
    return BuiltInSecrets.tushareToken;
  }

  Future<void> setTushareToken(String token) async {
    await _prefs.setString(_kTushareToken, token.trim());
  }

  bool get hasTushareToken =>
      tushareToken.isNotEmpty && !tushareToken.startsWith('PUT_YOUR_');

  /// Tushare HTTP endpoint. Mobile/desktop builds talk straight to
  /// `http://api.tushare.pro`; Web builds hit a CORS wall, so users can plug
  /// in their own HTTPS proxy (e.g. self-hosted Cloudflare Worker) here.
  String get tushareEndpoint {
    final v = _prefs.getString(_kTushareEndpoint);
    if (v != null && v.trim().isNotEmpty) return v.trim();
    return BuiltInSecrets.tushareEndpoint;
  }

  Future<void> setTushareEndpoint(String url) async {
    await _prefs.setString(_kTushareEndpoint, url.trim());
  }

  // ── DeepSeek ───────────────────────────────────────────────────────────
  String get deepseekApiKey {
    final v = _prefs.getString(_kDeepseekKey);
    if (v != null && v.trim().isNotEmpty) return v.trim();
    return BuiltInSecrets.deepseekApiKey;
  }

  Future<void> setDeepseekApiKey(String key) async {
    await _prefs.setString(_kDeepseekKey, key.trim());
  }

  bool get hasDeepseekKey =>
      deepseekApiKey.isNotEmpty && !deepseekApiKey.startsWith('PUT_YOUR_');

  String get deepseekModel =>
      _prefs.getString(_kDeepseekModel) ?? BuiltInSecrets.defaultDeepseekModel;

  Future<void> setDeepseekModel(String model) =>
      _prefs.setString(_kDeepseekModel, model);

  /// Deep-reasoning toggle. Off by default because the built-in model is the
  /// fast `deepseek-v4-flash`; flipping it on switches to `deepseek-reasoner`.
  bool get deepMode => _prefs.getBool(_kDeepseekDeepMode) ?? false;
  Future<void> setDeepMode(bool on) async {
    await _prefs.setBool(_kDeepseekDeepMode, on);
    await setDeepseekModel(on
        ? BuiltInSecrets.reasoningDeepseekModel
        : BuiltInSecrets.defaultDeepseekModel);
  }

  // ── Theme ──────────────────────────────────────────────────────────────
  /// App theme. Defaults to [ThemeMode.light] per user request.
  ThemeMode get themeMode {
    final v = _prefs.getString(_kThemeMode);
    return v == 'dark' ? ThemeMode.dark : ThemeMode.light;
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setString(
        _kThemeMode, mode == ThemeMode.dark ? 'dark' : 'light');
  }
}
