import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fishing_api.dart';
import 'fishing_models.dart';

/// 喜爱钓鱼的主题私有状态：进入钓鱼主题时创建，切走即销毁（见 TopicPack.providers）。
class FishingState extends ChangeNotifier {
  FishingState({FishingApi? api}) : api = api ?? FishingApi();

  final FishingApi api;

  static const _kPlace = 'fishing.last_place';
  static const _kLat = 'fishing.last_lat';
  static const _kLon = 'fishing.last_lon';

  /// 没有历史地点时给的快捷选择。
  static const quickPlaces = ['北京', '上海', '武汉', '杭州', '成都', '千岛湖'];

  bool _disposed = false;

  // ── 出钓指数 ──
  FishingForecast? forecast;
  bool forecastLoading = false;
  String? forecastError;
  int selectedDay = 0;
  String lastPlace = '';
  double? _lastLat;
  double? _lastLon;

  // ── 禁渔提示 ──
  FishingRegulations? regulations;

  // ── 渔获 / 钓点（需登录）──
  List<FishCatch> catches = const [];
  CatchStats stats = const CatchStats();
  List<FishingSpot> spots = const [];
  bool journalLoading = false;
  bool journalLoaded = false;
  String? journalError;

  final Map<String, Future<Uint8List>> _photos = {};

  ForecastDay? get day {
    final f = forecast;
    if (f == null || f.days.isEmpty) return null;
    return f.days[selectedDay.clamp(0, f.days.length - 1)];
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// 进入「出钓」页：恢复上次地点并拉一次；禁渔提示也顺带拉。
  Future<void> bootstrap() async {
    if (regulations == null) {
      // ignore: unawaited_futures
      loadRegulations();
    }
    if (forecast != null || forecastLoading) return;
    try {
      final p = await SharedPreferences.getInstance();
      lastPlace = p.getString(_kPlace) ?? '';
      _lastLat = p.getDouble(_kLat);
      _lastLon = p.getDouble(_kLon);
    } catch (_) {}
    if (lastPlace.isEmpty) {
      _notify();
      return;
    }
    await loadForecast(place: lastPlace, lat: _lastLat, lon: _lastLon);
  }

  Future<void> loadForecast({String? place, double? lat, double? lon}) async {
    final name = (place ?? '').trim();
    if (name.isEmpty && (lat == null || lon == null)) return;
    forecastLoading = true;
    forecastError = null;
    _notify();
    try {
      final f = (lat != null && lon != null)
          ? await api.forecast(lat: lat, lon: lon, name: name)
          : await api.forecast(place: name);
      forecast = f;
      selectedDay = 0;
      lastPlace = name.isEmpty ? f.place : name;
      _lastLat = lat;
      _lastLon = lon;
      try {
        final p = await SharedPreferences.getInstance();
        await p.setString(_kPlace, lastPlace);
        if (lat != null && lon != null) {
          await p.setDouble(_kLat, lat);
          await p.setDouble(_kLon, lon);
        } else {
          await p.remove(_kLat);
          await p.remove(_kLon);
        }
      } catch (_) {}
    } catch (e) {
      forecastError = _msg(e, '天气数据暂时拿不到，稍后再试');
    } finally {
      forecastLoading = false;
      _notify();
    }
  }

  Future<void> reloadForecast() =>
      loadForecast(place: lastPlace, lat: _lastLat, lon: _lastLon);

  void selectDay(int i) {
    selectedDay = i;
    _notify();
  }

  Future<void> loadRegulations() async {
    try {
      regulations = await api.regulations();
      _notify();
    } catch (_) {
      // 禁渔提示拉不到不影响主流程；页面上展示本地兜底文案。
    }
  }

  // ── 渔获日记 ──

  void clearJournal() {
    catches = const [];
    spots = const [];
    stats = const CatchStats();
    journalLoaded = false;
    journalError = null;
    _photos.clear();
    _notify();
  }

  Future<void> refreshJournal() async {
    journalLoading = true;
    journalError = null;
    _notify();
    try {
      final (items, st) = await api.catches();
      catches = items;
      if (st != null) stats = st;
      spots = await api.spots();
      journalLoaded = true;
    } catch (e) {
      journalError = _msg(e, '渔获加载失败，下拉重试');
    } finally {
      journalLoading = false;
      _notify();
    }
  }

  Future<FishCatch> addCatch(Map<String, dynamic> body) async {
    final c = await api.createCatch(body);
    catches = [c, ...catches]..sort((a, b) => b.caughtAt.compareTo(a.caughtAt));
    // 汇总以服务端为准，后台刷新。
    // ignore: unawaited_futures
    _refreshStats();
    _notify();
    return c;
  }

  Future<void> _refreshStats() async {
    try {
      final (_, st) = await api.catches();
      if (st != null) {
        stats = st;
        _notify();
      }
    } catch (_) {}
  }

  Future<void> deleteCatch(String uuid) async {
    await api.deleteCatch(uuid);
    catches = catches.where((c) => c.uuid != uuid).toList();
    _photos.remove(uuid);
    // ignore: unawaited_futures
    _refreshStats();
    _notify();
  }

  Future<Uint8List> photo(String uuid) =>
      _photos.putIfAbsent(uuid, () => api.catchPhoto(uuid));

  Future<FishingSpot> saveSpot(Map<String, dynamic> body,
      {String? uuid}) async {
    final s = await api.saveSpot(body, uuid: uuid);
    spots = [s, ...spots.where((x) => x.uuid != s.uuid)];
    _notify();
    return s;
  }

  Future<void> deleteSpot(String uuid) async {
    await api.deleteSpot(uuid);
    spots = spots.where((s) => s.uuid != uuid).toList();
    _notify();
  }

  static String _msg(Object e, String fallback) {
    final s = e.toString();
    final i = s.indexOf(': ');
    if (s.startsWith('[') && i > 0) {
      final m = s.substring(i + 2).trim();
      if (m.isNotEmpty && m != 'unknown error' && m != 'internal error') {
        return m;
      }
    }
    return fallback;
  }
}
