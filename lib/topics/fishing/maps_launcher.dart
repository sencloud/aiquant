import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'fishing_models.dart';
import 'map/geo_coord.dart';

/// 用系统地图导航到钓点。
///
/// 钓点坐标是 WGS-84。iOS → Apple 地图（大陆境内底图是 GCJ-02，先换算，
/// 否则会偏几百米）；Android → geo: 意图（标准规定 WGS-84，由用户已装的地图 App
/// 接管）；其他平台 → 高德网页（带 coordinate=wgs84 让高德自己换算）。
/// 没有坐标时按名称搜索。
Uri mapsUriFor(FishingSpot s, {TargetPlatform? platform}) {
  final p = platform ?? defaultTargetPlatform;
  final name = s.name;
  if (s.hasCoord) {
    final ll = '${s.lat},${s.lon}';
    switch (p) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        final g = wgsToGcj(s.lat!, s.lon!);
        return Uri.https('maps.apple.com', '/', {
          'll': '${g.lat.toStringAsFixed(6)},${g.lon.toStringAsFixed(6)}',
          'q': name
        });
      case TargetPlatform.android:
        return Uri.parse('geo:$ll?q=${Uri.encodeComponent('$ll($name)')}');
      default:
        return Uri.https('uri.amap.com', '/marker', {
          'position': '${s.lon},${s.lat}',
          'name': name,
          'coordinate': 'wgs84'
        });
    }
  }
  switch (p) {
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return Uri.https('maps.apple.com', '/', {'q': name});
    case TargetPlatform.android:
      return Uri.parse('geo:0,0?q=${Uri.encodeComponent(name)}');
    default:
      return Uri.https('uri.amap.com', '/search', {'keyword': name});
  }
}

Future<bool> openSpotInMaps(FishingSpot s) async {
  try {
    return await launchUrl(mapsUriFor(s), mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
