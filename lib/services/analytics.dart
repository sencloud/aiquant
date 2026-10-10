import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// 极简埋点。默认接 Umami（开源、有免费云额度、纯 HTTP），不需要任何原生
/// 依赖，因此不会给 iOS / Android 打包增加风险。
///
/// 设计要点：
/// - **未配置就静默**：`.env` 里没有 UMAMI_WEBSITE_ID 时整个服务是 no-op，
///   开发机、CI 打包都不会往外面发东西。
/// - **绝不阻塞 UI**：入队即返回，后台单线程发送；失败直接丢弃，不重试、
///   不弹错。埋点坏掉不该影响用户。
/// - **不带 PII**：distinct_id 是本地生成的随机 UUID，不带手机号 / 邮箱。
///
/// 要接自建 Umami：把 UMAMI_HOST 指向自己的实例即可（同一套 /api/send 协议）。
class Analytics {
  Analytics._();
  static final Analytics instance = Analytics._();

  static const _kDeviceId = 'analytics_device_id';

  final List<_Event> _queue = [];
  bool _sending = false;
  bool _enabled = false;
  String _deviceId = '';

  /// 关键路径上的事件名集中列在这里，避免各处写错字符串后数据对不上。
  static const evAppOpen = 'app_open';
  static const evSplashDone = 'splash_done';
  static const evTabView = 'tab_view';
  static const evFalsificationView = 'falsification_view';
  static const evDiscoverOpen = 'discover_open';
  static const evCostRuler = 'cost_ruler';
  static const evArchiveOpen = 'archive_open';
  static const evGateOpen = 'gate_open';
  static const evLiveEntry = 'live_strategy_entry';
  static const evLoginStart = 'login_start';
  static const evLoginSuccess = 'login_success';
  static const evChatSend = 'chat_send';
  static const evRechargeSheet = 'recharge_sheet_open';
  static const evRechargeStart = 'recharge_start';
  static const evRechargeSuccess = 'recharge_success';

  String get _host =>
      (dotenv.maybeGet('UMAMI_HOST') ?? '').trim().isEmpty
          ? 'https://cloud.umami.is'
          : dotenv.env['UMAMI_HOST']!.trim().replaceFirst(RegExp(r'/+$'), '');

  String get _websiteId => (dotenv.maybeGet('UMAMI_WEBSITE_ID') ?? '').trim();

  /// 在 main() 里 bootstrap 阶段调用一次。任何异常都吞掉。
  Future<void> init() async {
    try {
      if (_websiteId.isEmpty) {
        _enabled = false;
        if (kDebugMode) {
          debugPrint('[analytics] 未配置 UMAMI_WEBSITE_ID，埋点关闭');
        }
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString(_kDeviceId);
      if (id == null || id.isEmpty) {
        id = const Uuid().v4();
        await prefs.setString(_kDeviceId, id);
      }
      _deviceId = id;
      _enabled = true;
      if (kDebugMode) debugPrint('[analytics] 已启用 → $_host');
    } catch (_) {
      _enabled = false;
    }
  }

  /// 埋一个事件。[props] 的值只放数字 / 短字符串，别塞内容或个人信息。
  void track(String event, [Map<String, Object?>? props]) {
    if (!_enabled) {
      if (kDebugMode) debugPrint('[analytics] $event ${props ?? ''}');
      return;
    }
    if (_queue.length >= 64) _queue.removeAt(0); // 队列有界，别攒内存
    _queue.add(_Event(event, props ?? const {}));
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_sending) return;
    _sending = true;
    try {
      while (_queue.isNotEmpty) {
        final e = _queue.removeAt(0);
        await _post(e);
      }
    } finally {
      _sending = false;
    }
  }

  Future<void> _post(_Event e) async {
    try {
      final body = json.encode({
        'type': 'event',
        'payload': {
          'website': _websiteId,
          'hostname': 'app.xiai',
          'url': '/${e.name}',
          'name': e.name,
          // Distinct ID 要走 payload 顶层的 `id`（官方文档：Sending stats API
          // 直接推送时用 `id` 设置 Distinct ID）。放在 data 里会被当成一个普通
          // 自定义属性：既占额度，又会因为每条都不同而把属性列表刷花。
          if (_deviceId.isNotEmpty) 'id': _deviceId,
          'data': {'platform': _platformTag, ...e.props},
        },
      });
      final resp = await http
          .post(
            Uri.parse('$_host/api/send'),
            headers: const {
              'Content-Type': 'application/json',
              'User-Agent': 'xiai-app/1.0',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 5));
      if (kDebugMode && resp.statusCode >= 400) {
        debugPrint('[analytics] ${e.name} → ${resp.statusCode}');
      }
    } catch (_) {
      // 埋点失败不影响任何功能，直接丢。
    }
  }

  static String get _platformTag {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS) return 'macos';
    return 'other';
  }
}

class _Event {
  _Event(this.name, this.props);
  final String name;
  final Map<String, Object?> props;
}
