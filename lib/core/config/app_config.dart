import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 启动时由 main() 调用，必须在 [AppConfig.load] 之前完成。
Future<void> loadEnv() => dotenv.load(fileName: '.env');

/// 内置密钥统一从 .env 读取——开发时写在 .env（不入 git），CI 打包时由
/// GitHub Secrets 在 build 之前生成 .env 文件。直接缺失即抛错，不做兜底。
class BuiltInSecrets {
  static String _required(String key) {
    final v = dotenv.env[key];
    if (v == null || v.trim().isEmpty) {
      throw StateError('.env 缺少必填项 "$key" — 请检查项目根目录的 .env 是否存在并配置完整。');
    }
    return v.trim();
  }

  static String _optional(String key, String defaultValue) {
    final v = dotenv.env[key];
    if (v == null || v.trim().isEmpty) return defaultValue;
    return v.trim();
  }

  static String get tushareToken => _required('TUSHARE_TOKEN');
  static String get tushareEndpoint =>
      _optional('TUSHARE_ENDPOINT', 'http://api.tushare.pro');

  static String get deepseekApiKey => _required('DEEPSEEK_API_KEY');
  static String get deepseekBaseUrl =>
      _optional('DEEPSEEK_BASE_URL', 'https://api.deepseek.com');

  /// NASA FIRMS 卫星火点 API 的免费 MAP_KEY。空值表示未配置——
  /// 对应 AI 工具会返回提示让用户去申请。
  /// 申请地址：https://firms.modaps.eosdis.nasa.gov/api/area/
  static String get firmsMapKey => _optional('FIRMS_MAP_KEY', '');

  /// Finme Backend API base URL。
  ///
  /// 生产构建优先从 `--dart-define=API_BASE_URL=...` 读取，便于 CI 注入；
  /// 本地开发再读取 `.env`。这里不再提供 127.0.0.1 兜底，避免 TestFlight
  /// 缺配置时静默连到手机本机地址。
  static String get apiBaseUrl {
    const defined = String.fromEnvironment('API_BASE_URL');
    final value =
        defined.trim().isNotEmpty ? defined.trim() : _required('API_BASE_URL');
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      throw StateError('API_BASE_URL 格式错误：$value');
    }
    final host = uri.host.toLowerCase();
    if (kReleaseMode &&
        (host == 'localhost' || host == '127.0.0.1' || host == '::1')) {
      throw StateError('Release 包禁止使用本机 API_BASE_URL：$value');
    }
    return value.replaceFirst(RegExp(r'/+$'), '');
  }

  /// 默认走深度模式（携带 reasoning），用户实际上看不到模型切换
  /// 入口——AI 助理顶部不再显示模型 badge。
  static const String reasoningDeepseekModel = 'deepseek-reasoner';

  /// tool calling 时强制走 chat（reasoner 不支持 tool_calls）
  static const String chatDeepseekModel = 'deepseek-chat';
}

class AppConfig {
  AppConfig._();
  static final AppConfig instance = AppConfig._();

  static const _kThemeMode = 'theme_mode';

  late SharedPreferences _prefs;
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _prefs = await SharedPreferences.getInstance();
    _loaded = true;
  }

  // ── Tushare ────────────────────────────────────────────────────────────
  String get tushareToken => BuiltInSecrets.tushareToken;
  String get tushareEndpoint => BuiltInSecrets.tushareEndpoint;
  bool get hasTushareToken => true;

  // ── DeepSeek ───────────────────────────────────────────────────────────
  String get deepseekApiKey => BuiltInSecrets.deepseekApiKey;
  bool get hasDeepseekKey => true;

  /// 用户不再能通过 UI 切换模型；默认就是深度模式。
  String get deepseekModel => BuiltInSecrets.reasoningDeepseekModel;
  bool get deepMode => true;

  // ── 卫星 / 全球事件 ────────────────────────────────────────────────────
  /// NASA FIRMS MAP_KEY；未配置时事件流里的火点工具会返回空。
  String get firmsMapKey => BuiltInSecrets.firmsMapKey;

  // ── Finme Backend ─────────────────────────────────────────────────────
  /// Finme Backend API base URL。
  String get apiBaseUrl => BuiltInSecrets.apiBaseUrl;

  // ── Theme ──────────────────────────────────────────────────────────────
  /// 当前 App 仅支持 light 模式（Dark 模式入口已被隐藏）。
  ThemeMode get themeMode => ThemeMode.light;

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setString(
        _kThemeMode, mode == ThemeMode.dark ? 'dark' : 'light');
  }
}
