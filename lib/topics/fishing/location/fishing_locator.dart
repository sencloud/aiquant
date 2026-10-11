import 'package:geolocator/geolocator.dart';

import '../map/geo_coord.dart';

/// 定位授权状态（只申请「使用 App 期间」）。
enum LocAccess {
  /// 还没问过用户：可以先讲清用途，再弹系统授权框。
  notDetermined,

  /// 已允许（含 iOS「大致位置」）。
  granted,

  /// 用户拒绝过 / 家长控制等受限：系统不会再弹框，只能引导去设置。
  denied,

  /// 系统定位服务整体关闭。
  serviceOff,
}

/// 喜爱钓鱼的定位入口。测试里实现一个假的即可。
///
/// 隐私约定：
/// - 只在用户正在用相关功能（出钓指数、钓点地图、新建钓点）时取一次位置，不持续追踪、
///   不在后台定位；
/// - 位置只放在内存里，不写日志、不存历史；查出钓指数时发给服务端的坐标先降到约 1 km
///   精度（见 [coarse]），只有用户主动保存为钓点时才会存精确坐标。
abstract class FishingLocator {
  Future<LocAccess> access();

  /// 弹系统授权框（调用前应已向用户说明用途）。返回授权后的状态。
  Future<LocAccess> request();

  /// 取当前位置（WGS-84）。没授权 / 超时 / 失败返回 null。
  Future<LatLon?> current();

  /// 打开本 App 的系统设置页（用户拒绝过之后唯一能改授权的地方）。
  Future<bool> openSettings();
}

/// 基于 geolocator 的实现。
class GeoFishingLocator implements FishingLocator {
  const GeoFishingLocator();

  static LocAccess _map(LocationPermission p) => switch (p) {
        LocationPermission.always ||
        LocationPermission.whileInUse =>
          LocAccess.granted,
        LocationPermission.deniedForever => LocAccess.denied,
        // iOS 上「还没问过」也报 denied；真正拒绝过的是 deniedForever。
        LocationPermission.denied => LocAccess.notDetermined,
        LocationPermission.unableToDetermine => LocAccess.notDetermined,
      };

  @override
  Future<LocAccess> access() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return LocAccess.serviceOff;
      }
      return _map(await Geolocator.checkPermission());
    } catch (_) {
      return LocAccess.denied;
    }
  }

  @override
  Future<LocAccess> request() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return LocAccess.serviceOff;
      }
      final p = await Geolocator.requestPermission();
      // Android 上第一次拒绝仍是 denied（可以再问），统一按「拒绝」处理，别连续弹。
      if (p == LocationPermission.denied) return LocAccess.denied;
      return _map(p);
    } catch (_) {
      return LocAccess.denied;
    }
  }

  @override
  Future<LatLon?> current() async {
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return LatLon(p.latitude, p.longitude);
    } catch (_) {
      try {
        final p = await Geolocator.getLastKnownPosition();
        return p == null ? null : LatLon(p.latitude, p.longitude);
      } catch (_) {
        return null;
      }
    }
  }

  @override
  Future<bool> openSettings() async {
    try {
      return await Geolocator.openAppSettings();
    } catch (_) {
      return false;
    }
  }
}
