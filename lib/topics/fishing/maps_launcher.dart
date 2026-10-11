import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'fishing_models.dart';

/// 用系统地图打开钓点（不接地图 SDK）。
///
/// iOS → Apple 地图；Android → geo: 意图（由用户已装的地图 App 接管）；
/// 其他平台 → 高德网页。没有坐标时按名称搜索。
Uri mapsUriFor(FishingSpot s, {TargetPlatform? platform}) {
  final p = platform ?? defaultTargetPlatform;
  final name = s.name;
  if (s.hasCoord) {
    final ll = '${s.lat},${s.lon}';
    switch (p) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return Uri.https('maps.apple.com', '/', {'ll': ll, 'q': name});
      case TargetPlatform.android:
        return Uri.parse('geo:$ll?q=${Uri.encodeComponent('$ll($name)')}');
      default:
        return Uri.https('uri.amap.com', '/marker',
            {'position': '${s.lon},${s.lat}', 'name': name});
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
