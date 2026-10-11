import 'package:flutter/foundation.dart';

import '../../theme/app_theme.dart';
import '../storage/hive_setup.dart';
import 'topic_pack.dart';

/// 全局主题状态：当前主题、首启选择、持久化。
///
/// 持久化两处：
/// - 本地 Hive `app_prefs` 的 `topic_id`：冷启动时在 `runApp` 之前读出并立即
///   换色，不闪色；
/// - 登录用户同步到服务端 `users.preferred_topic`（`PATCH /v1/me`），换机后恢复。
///   冲突时以最近一次写入为准：本机切换立刻推到服务端；换号 / 新设备登录时
///   采用服务端记录（见 [reconcileWithServer]）。
class TopicState extends ChangeNotifier {
  TopicState({required List<TopicPack> packs, this.onSwitched})
      : assert(packs.isNotEmpty),
        _packs = packs,
        _current = packs.first;

  static const kPrefTopicId = 'topic_id';
  static const kPrefBannerSeen = 'topic_new_banner_seen';

  final List<TopicPack> _packs;
  TopicPack _current;
  bool _needsPick = false;
  bool _existingUser = false;
  bool _bannerSeen = true;

  /// 本机切换主题后回调（main.dart 用它在已登录时同步到服务端）。
  final void Function(String topicId)? onSwitched;

  /// 可选主题（喜爱钓鱼开关关闭时只有喜爱钱）。
  List<TopicPack> get available => List.unmodifiable(_packs);
  TopicPack get current => _current;
  String get currentId => _current.id;

  /// 是否有多个主题可切换（决定「切换主题」入口是否出现）。
  bool get canSwitch => _packs.length > 1;

  /// 全新安装且有多个主题：开屏之后先选主题。
  bool get needsPick => _needsPick;

  /// 老用户（升级上来）在「我的」顶部看一次「新：喜爱钓鱼」提示条。
  bool get showNewTopicBanner => canSwitch && _existingUser && !_bannerSeen;

  TopicPack? byId(String? id) {
    for (final p in _packs) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 冷启动时（`runApp` 之前）调用。
  ///
  /// [hasLocalAccount] 由 main.dart 提供（是否存有登录 token），用来区分老用户
  /// 与全新安装：老用户（有本地会话 / 组合 / 偏好 / 登录态）默认喜爱钱、
  /// 不强制弹选择页；全新安装才要求先选主题。
  Future<void> bootstrap({Future<bool> Function()? hasLocalAccount}) async {
    final saved = prefsBox.get(kPrefTopicId);
    final pack = saved is String ? byId(saved) : null;
    _bannerSeen = prefsBox.get(kPrefBannerSeen) == true;
    if (pack != null) {
      _current = pack;
      _existingUser = prefsBox.get('${kPrefTopicId}_legacy') == true;
    } else {
      final existing = chatSessionsBox.isNotEmpty ||
          portfoliosBox.isNotEmpty ||
          prefsBox.isNotEmpty ||
          (hasLocalAccount != null && await _safe(hasLocalAccount));
      _existingUser = existing;
      _current = _packs.first; // 喜爱钱
      if (existing || !canSwitch) {
        // 老用户 / 只有一个主题：直接喜爱钱，不弹选择页。
        await prefsBox.put(kPrefTopicId, _current.id);
        if (existing) await prefsBox.put('${kPrefTopicId}_legacy', true);
      } else {
        _needsPick = true;
      }
    }
    AppColors.applyTopic(_current.palette);
  }

  static Future<bool> _safe(Future<bool> Function() f) async {
    try {
      return await f();
    } catch (_) {
      return false;
    }
  }

  /// 首启选择页选定主题。
  Future<void> completePick(String id) async {
    _needsPick = false;
    await switchTo(id);
  }

  /// 切换主题：持久化、换色、通知重建（app.dart 会以新主题包重建整棵树）。
  Future<void> switchTo(String id, {bool fromServer = false}) async {
    final pack = byId(id);
    if (pack == null) return;
    final changed = pack.id != _current.id;
    _current = pack;
    await prefsBox.put(kPrefTopicId, pack.id);
    AppColors.applyTopic(pack.palette);
    if (!fromServer) onSwitched?.call(pack.id);
    if (changed || !fromServer) notifyListeners();
  }

  /// 登录后与服务端偏好对齐。
  ///
  /// - [freshLogin]（本次是从未登录 / 另一个账号登录进来）且服务端有记录：
  ///   采用服务端（换机恢复）；
  /// - 否则以本机为准，服务端不同就推上去。
  Future<void> reconcileWithServer({
    required String? serverTopic,
    required bool freshLogin,
  }) async {
    final server = byId(serverTopic);
    if (freshLogin && server != null && !_needsPick) {
      if (server.id != _current.id) await switchTo(server.id, fromServer: true);
      return;
    }
    if (serverTopic != _current.id) onSwitched?.call(_current.id);
  }

  void dismissBanner() {
    if (_bannerSeen) return;
    _bannerSeen = true;
    prefsBox.put(kPrefBannerSeen, true);
    notifyListeners();
  }

  /// 仅供测试：不经过 Hive 直接设定当前主题。
  @visibleForTesting
  void debugSet(String id, {bool needsPick = false}) {
    _current = byId(id) ?? _current;
    _needsPick = needsPick;
    AppColors.applyTopic(_current.palette);
    notifyListeners();
  }
}
