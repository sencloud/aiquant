/// 小应用的客户端状态：每个主题一份（发现页、小应用页、工坊共用）。
///
/// 不挂在 Provider 树上：发现页 push 出去的页面、工坊回来后的刷新都直接拿
/// [MiniAppStore.of]，主题切换不需要重建。登录身份变化（[syncUser]）时清空私有数据。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'miniapp_api.dart';
import 'miniapp_models.dart';

class MiniAppStore extends ChangeNotifier {
  MiniAppStore._(this.topic);

  static final Map<String, MiniAppStore> _stores = {};

  /// 测试可替换。
  static MiniAppApi api = MiniAppApi();

  static MiniAppStore of(String topic) =>
      _stores.putIfAbsent(topic, () => MiniAppStore._(topic));

  /// 测试用：清空全部实例。
  @visibleForTesting
  static void resetAll() {
    for (final s in _stores.values) {
      s.dispose();
    }
    _stores.clear();
  }

  final String topic;

  MiniAppCatalog catalog = MiniAppCatalog();
  List<MiniAppTemplate> templates = const [];
  List<MiniApp> apps = const [];
  final Map<String, MiniAppRun> runs = {};
  final Map<String, MiniAppRun> templateRuns = {};
  final Set<String> _running = {};

  bool loadingPublic = false;
  bool loadingApps = false;
  bool publicLoaded = false;
  bool appsLoaded = false;
  String? error;
  String? _user;
  DateTime? _lastRefresh;

  List<MiniApp> get mounted => apps.where((a) => a.mounted).toList()
    ..sort((a, b) => a.position.compareTo(b.position));
  List<MiniApp> get unmounted => apps.where((a) => !a.mounted).toList();
  bool isRunning(String id) => _running.contains(id);

  MiniApp? byId(String id) {
    for (final a in apps) {
      if (a.uuid == id) return a;
    }
    return null;
  }

  /// 登录身份变化：换人 / 登出时清空私有数据。返回是否发生了变化。
  bool syncUser(String? userUuid) {
    if (userUuid == _user) return false;
    _user = userUuid;
    apps = const [];
    runs.clear();
    appsLoaded = false;
    _lastRefresh = null;
    notifyListeners();
    return true;
  }

  /// 进入发现页时调用：公开数据只拉一次；私有列表与卡片数据 60 秒内不重复刷新。
  Future<void> ensureLoaded({bool force = false}) async {
    final jobs = <Future<void>>[];
    if (!publicLoaded || force) jobs.add(loadPublic());
    final fresh = _lastRefresh != null &&
        DateTime.now().difference(_lastRefresh!) < const Duration(seconds: 60);
    if (_user != null && (force || !fresh)) {
      jobs.add(loadApps().then((_) => refreshMounted()));
    }
    await Future.wait(jobs);
  }

  Future<void> loadPublic() async {
    loadingPublic = true;
    notifyListeners();
    try {
      final r = await Future.wait([api.catalog(topic), api.templates(topic)]);
      catalog = r[0] as MiniAppCatalog;
      templates = r[1] as List<MiniAppTemplate>;
      publicLoaded = true;
      error = null;
    } catch (e) {
      error = '$e';
    } finally {
      loadingPublic = false;
      notifyListeners();
    }
  }

  /// 拉私有列表（调用方保证已登录；发现页经 [ensureLoaded] 只在登录后调用）。
  Future<void> loadApps() async {
    loadingApps = true;
    notifyListeners();
    try {
      apps = await api.list(topic);
      appsLoaded = true;
      _lastRefresh = DateTime.now();
      error = null;
    } catch (e) {
      error = '$e';
    } finally {
      loadingApps = false;
      notifyListeners();
    }
  }

  /// 刷新发现页上全部卡片的数据（并发，单个失败不影响其他）。
  Future<void> refreshMounted() async {
    await Future.wait([for (final a in mounted) run(a.uuid)]);
  }

  Future<MiniAppRun?> run(String id, {Map<String, dynamic>? inputs}) async {
    _running.add(id);
    notifyListeners();
    try {
      final r = await api.run(id, inputs: inputs);
      runs[id] = r;
      return r;
    } catch (_) {
      return runs[id];
    } finally {
      _running.remove(id);
      notifyListeners();
    }
  }

  Future<MiniAppRun?> runTemplate(String id, {Map<String, dynamic>? inputs}) async {
    _running.add('tpl:$id');
    notifyListeners();
    try {
      final r = await api.runTemplate(id, inputs: inputs);
      templateRuns[id] = r;
      return r;
    } catch (_) {
      return templateRuns[id];
    } finally {
      _running.remove('tpl:$id');
      notifyListeners();
    }
  }

  void _put(MiniApp a) {
    final i = apps.indexWhere((x) => x.uuid == a.uuid);
    apps = i < 0 ? [...apps, a] : ([...apps]..[i] = a);
    notifyListeners();
  }

  /// 拉一个小应用的最新版本（工坊生成 / 修改之后）。
  Future<MiniApp> refreshApp(String id) async {
    final a = await api.get(id);
    _put(a);
    return a;
  }

  Future<MiniApp> mount(String id, {String? cardSize}) async {
    final a = await api.mount(id, cardSize: cardSize);
    _put(a);
    await loadApps();
    unawaited(run(id));
    return a;
  }

  Future<void> unmount(String id) async {
    await api.unmount(id);
    await loadApps();
  }

  Future<void> delete(String id) async {
    await api.delete(id);
    runs.remove(id);
    await loadApps();
  }

  Future<void> reorder(List<String> ids) async {
    apps = await api.reorder(topic, ids);
    notifyListeners();
  }

  Future<MiniApp> fromTemplate(String templateId) async {
    final a = await api.fromTemplate(templateId);
    await loadApps();
    unawaited(run(a.uuid));
    return a;
  }

  Future<MiniApp> rename(String id, String title) async {
    final a = await api.rename(id, title: title);
    _put(a);
    return a;
  }

  Future<MiniApp> restore(String id, int version) async {
    final a = await api.restore(id, version);
    _put(a);
    unawaited(run(id));
    return a;
  }

  Timer? _saveTimer;

  /// 参数改动后防抖保存（不阻塞界面）。
  void saveInputs(String id, Map<String, dynamic> inputs) {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), () {
      api.saveState(id, inputs: inputs).catchError((_) {});
    });
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
