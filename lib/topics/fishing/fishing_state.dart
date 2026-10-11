import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fishing_api.dart';
import 'fishing_models.dart';
import 'location/fishing_locator.dart';
import 'map/geo_coord.dart';

/// 喜爱钓鱼的主题私有状态：进入钓鱼主题时创建，切走即销毁（见 TopicPack.providers）。
class FishingState extends ChangeNotifier {
  FishingState({FishingApi? api, FishingLocator? locator})
      : api = api ?? FishingApi(),
        locator = locator ?? const GeoFishingLocator();

  final FishingApi api;
  final FishingLocator locator;

  /// 出钓指数用「当前位置」时显示的地名。
  static const herePlace = '当前位置';
  static const _kHere = 'fishing.last_is_here';

  // ── 定位（只在内存里，不落盘、不留历史）──
  LatLon? here;
  bool locating = false;
  LocAccess? locAccess;

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
    var lastWasHere = false;
    try {
      final p = await SharedPreferences.getInstance();
      lastPlace = p.getString(_kPlace) ?? '';
      _lastLat = p.getDouble(_kLat);
      _lastLon = p.getDouble(_kLon);
      lastWasHere = p.getBool(_kHere) ?? false;
    } catch (_) {}
    // 已经授权过定位、且上次用的就是当前位置（或者还没选过地点）：直接按现在的位置算，
    // 不弹任何授权框（没授权就什么都不做，页面上给「用我的位置」入口）。
    if (lastWasHere || lastPlace.isEmpty) {
      locAccess = await locator.access();
      if (locAccess == LocAccess.granted && await forecastHere()) return;
    }
    if (lastPlace.isEmpty) {
      _notify();
      return;
    }
    await loadForecast(place: lastPlace, lat: _lastLat, lon: _lastLon);
  }

  Future<LocAccess> refreshAccess() async {
    locAccess = await locator.access();
    _notify();
    return locAccess!;
  }

  /// 取一次当前位置（调用方负责先走授权流程）。失败返回 null。
  Future<LatLon?> locate() async {
    locating = true;
    _notify();
    try {
      final p = await locator.current();
      if (p != null) here = p;
      return p;
    } finally {
      locating = false;
      _notify();
    }
  }

  /// 按当前位置查出钓指数。坐标先降到约 1 km 精度再发给服务端。
  Future<bool> forecastHere() async {
    final p = await locate();
    if (p == null) return false;
    await loadForecast(
        place: herePlace, lat: coarse(p.lat), lon: coarse(p.lon), isHere: true);
    return forecastError == null;
  }

  /// 有坐标的钓点按离「我」（没定位就按当前出钓指数的位置）由近到远。
  List<(FishingSpot, double)> nearbySpots({int limit = 5, double maxKm = 80}) {
    final o = here ??
        ((_lastLat != null && _lastLon != null)
            ? LatLon(_lastLat!, _lastLon!)
            : null);
    if (o == null) return const [];
    final out = <(FishingSpot, double)>[
      for (final s in spots)
        if (s.hasCoord) (s, distanceMeters(o.lat, o.lon, s.lat!, s.lon!)),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return out.where((e) => e.$2 <= maxKm * 1000).take(limit).toList();
  }

  Future<void> loadForecast(
      {String? place, double? lat, double? lon, bool isHere = false}) async {
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
        // 只记「上次用的是当前位置」这一个开关和约 1 km 精度的最后一次坐标，不留轨迹。
        await p.setBool(_kHere, isHere);
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

  Future<void> reloadForecast() => loadForecast(
      place: lastPlace,
      lat: _lastLat,
      lon: _lastLon,
      isHere: lastPlace == herePlace);

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

  /// 退出登录 / 换号：内存里的位置也一起清掉。
  void forgetLocation() {
    here = null;
    _notify();
  }

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
