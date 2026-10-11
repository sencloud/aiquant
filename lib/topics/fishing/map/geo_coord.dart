import 'dart:math' as math;

/// 坐标系换算：WGS-84（GPS 原始坐标）↔ GCJ-02（中国大陆地图用的加偏坐标）。
///
/// 约定：**库里、接口里、App 内部一律是 WGS-84**（系统定位给的就是它）。
/// 只有两处要换：
/// - 在 iOS 系统地图（MapKit）上显示：大陆境内的底图是 GCJ-02，图钉坐标要先
///   [wgsToGcj]，地图上取到的点（长按 / 中心点）要 [gcjToWgs] 再存；
/// - 交给高德等只认 GCJ-02 的地图（Apple 地图链接同理）。
/// 境外坐标两者相同，函数原样返回。
class LatLon {
  const LatLon(this.lat, this.lon);
  final double lat;
  final double lon;

  @override
  bool operator ==(Object other) =>
      other is LatLon && other.lat == lat && other.lon == lon;

  @override
  int get hashCode => Object.hash(lat, lon);

  @override
  String toString() => 'LatLon($lat, $lon)';
}

const double _a = 6378245.0;
const double _ee = 0.00669342162296594323;

/// 粗略判断是否在中国大陆加偏范围外（与业界通用实现一致的矩形判断）。
bool outOfChina(double lat, double lon) =>
    lon < 72.004 || lon > 137.8347 || lat < 0.8293 || lat > 55.8271;

double _tLat(double x, double y) {
  var r = -100.0 +
      2.0 * x +
      3.0 * y +
      0.2 * y * y +
      0.1 * x * y +
      0.2 * math.sqrt(x.abs());
  r += (20.0 * math.sin(6.0 * x * math.pi) +
          20.0 * math.sin(2.0 * x * math.pi)) *
      2.0 /
      3.0;
  r += (20.0 * math.sin(y * math.pi) + 40.0 * math.sin(y / 3.0 * math.pi)) *
      2.0 /
      3.0;
  r += (160.0 * math.sin(y / 12.0 * math.pi) +
          320 * math.sin(y * math.pi / 30.0)) *
      2.0 /
      3.0;
  return r;
}

double _tLon(double x, double y) {
  var r = 300.0 +
      x +
      2.0 * y +
      0.1 * x * x +
      0.1 * x * y +
      0.1 * math.sqrt(x.abs());
  r += (20.0 * math.sin(6.0 * x * math.pi) +
          20.0 * math.sin(2.0 * x * math.pi)) *
      2.0 /
      3.0;
  r += (20.0 * math.sin(x * math.pi) + 40.0 * math.sin(x / 3.0 * math.pi)) *
      2.0 /
      3.0;
  r += (150.0 * math.sin(x / 12.0 * math.pi) +
          300.0 * math.sin(x / 30.0 * math.pi)) *
      2.0 /
      3.0;
  return r;
}

LatLon _delta(double lat, double lon) {
  var dLat = _tLat(lon - 105.0, lat - 35.0);
  var dLon = _tLon(lon - 105.0, lat - 35.0);
  final radLat = lat / 180.0 * math.pi;
  var magic = math.sin(radLat);
  magic = 1 - _ee * magic * magic;
  final sqrtMagic = math.sqrt(magic);
  dLat = (dLat * 180.0) / ((_a * (1 - _ee)) / (magic * sqrtMagic) * math.pi);
  dLon = (dLon * 180.0) / (_a / sqrtMagic * math.cos(radLat) * math.pi);
  return LatLon(dLat, dLon);
}

/// WGS-84 → GCJ-02。
LatLon wgsToGcj(double lat, double lon) {
  if (outOfChina(lat, lon)) return LatLon(lat, lon);
  final d = _delta(lat, lon);
  return LatLon(lat + d.lat, lon + d.lon);
}

/// GCJ-02 → WGS-84（迭代求逆，误差 < 0.5 米）。
LatLon gcjToWgs(double lat, double lon) {
  if (outOfChina(lat, lon)) return LatLon(lat, lon);
  var wLat = lat, wLon = lon;
  for (var i = 0; i < 6; i++) {
    final g = wgsToGcj(wLat, wLon);
    wLat -= g.lat - lat;
    wLon -= g.lon - lon;
  }
  return LatLon(wLat, wLon);
}

/// 两点球面距离（米）。
double distanceMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final p1 = lat1 * math.pi / 180, p2 = lat2 * math.pi / 180;
  final dp = (lat2 - lat1) * math.pi / 180, dl = (lon2 - lon1) * math.pi / 180;
  final h = math.sin(dp / 2) * math.sin(dp / 2) +
      math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
  return 2 * r * math.asin(math.min(1, math.sqrt(h)));
}

/// 「1.2 km」「850 m」。
String formatDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  if (meters < 10000) return '${(meters / 1000).toStringAsFixed(1)} km';
  return '${(meters / 1000).round()} km';
}

/// 发给天气接口前把坐标降到约 1 km 精度：出钓指数用不着更精确的位置。
double coarse(double v) => (v * 100).roundToDouble() / 100;
