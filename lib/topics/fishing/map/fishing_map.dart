import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../theme/app_theme.dart';
import '../fishing_models.dart';
import 'geo_coord.dart';

/// 私人钓点地图。
///
/// - **iOS**：系统 MapKit（AppDelegate.swift 里注册的平台视图 `xiai/fishing_map`）。
///   免费、无需 key，中国大陆用的是有审图号的合规底图。大陆境内 MapKit 底图是 GCJ-02，
///   所以图钉坐标在这里先 WGS→GCJ，地图上取到的点（长按 / 中心点）再 GCJ→WGS；
///   原生侧不管坐标系。
/// - **其他平台**（Android 本次不发布、桌面、测试）：flutter_map + OpenStreetMap
///   瓦片（WGS-84，不需要换算），右下角带 OSM 署名。
///
/// 对外的坐标一律是 WGS-84。
class FishingMap extends StatefulWidget {
  const FishingMap({
    super.key,
    required this.spots,
    this.initial,
    this.here,
    this.controller,
    this.onSpotTap,
    this.onLongPress,
  });

  final List<FishingSpot> spots;

  /// 初始中心（WGS-84）。为空时用 [here]，再没有就看全部钓点 / 默认武汉。
  final LatLon? initial;

  /// 我的位置（WGS-84，已授权才有）。iOS 上由 MapKit 自己画蓝点。
  final LatLon? here;

  final FishingMapController? controller;
  final ValueChanged<FishingSpot>? onSpotTap;
  final ValueChanged<LatLon>? onLongPress;

  /// 测试 / 截图用：替换瓦片来源（不联网）。
  @visibleForTesting
  static TileProvider? debugTileProvider;
  @visibleForTesting
  static String? debugUrlTemplate;

  /// 测试用：强制走 / 不走原生 MapKit。
  @visibleForTesting
  static bool? debugUseNative;

  static bool get _useNative =>
      debugUseNative ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS);

  /// 没有任何位置时的默认中心（武汉，大致在全国中部）。
  static const fallbackCenter = LatLon(30.5928, 114.3055);

  @override
  State<FishingMap> createState() => _FishingMapState();
}

/// 地图控制：取中心点、移动视角。坐标都是 WGS-84。
class FishingMapController {
  _FishingMapState? _s;

  Future<LatLon?> center() async => _s?._center();

  Future<void> moveTo(LatLon p, {double zoom = 14}) async =>
      _s?._moveTo(p, zoom);
}

class _FishingMapState extends State<FishingMap> {
  final _fm = MapController();
  MethodChannel? _channel;

  LatLon get _start {
    final w = widget;
    if (w.initial != null) return w.initial!;
    if (w.here != null) return w.here!;
    final s = w.spots.where((e) => e.hasCoord).toList();
    if (s.isNotEmpty) return LatLon(s.first.lat!, s.first.lon!);
    return FishingMap.fallbackCenter;
  }

  @override
  void initState() {
    super.initState();
    widget.controller?._s = this;
  }

  @override
  void didUpdateWidget(FishingMap old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?._s = null;
      widget.controller?._s = this;
    }
    if (!identical(old.spots, widget.spots)) {
      _channel?.invokeMethod('setSpots', _nativeSpots());
    }
    if ((old.here == null) != (widget.here == null)) {
      _channel?.invokeMethod('setShowsUser', widget.here != null);
    }
  }

  @override
  void dispose() {
    if (widget.controller?._s == this) widget.controller?._s = null;
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  // ── 坐标换算（只在原生 MapKit 路径用）──
  static LatLon _toMap(LatLon w) => wgsToGcj(w.lat, w.lon);
  static LatLon _fromMap(double lat, double lon) => gcjToWgs(lat, lon);

  List<Map<String, Object?>> _nativeSpots() => [
        for (final s in widget.spots)
          if (s.hasCoord)
            () {
              final m = _toMap(LatLon(s.lat!, s.lon!));
              return {
                'id': s.uuid,
                'name': s.name,
                'subtitle': [
                  if (s.waterType.isNotEmpty) s.waterType,
                  if (s.species.isNotEmpty) s.species,
                ].join(' · '),
                'lat': m.lat,
                'lon': m.lon,
              };
            }(),
      ];

  Future<LatLon?> _center() async {
    if (FishingMap._useNative) {
      final r = await _channel?.invokeListMethod<double>('center');
      if (r == null || r.length < 2) return null;
      return _fromMap(r[0], r[1]);
    }
    final c = _fm.camera.center;
    return LatLon(c.latitude, c.longitude);
  }

  Future<void> _moveTo(LatLon p, double zoom) async {
    if (FishingMap._useNative) {
      final m = _toMap(p);
      // MapKit 用跨度（米）表达缩放：zoom 14 ≈ 4 km。
      final span = 4000.0 * (1 << (14 - zoom.round()).clamp(0, 10));
      await _channel
          ?.invokeMethod('moveTo', {'lat': m.lat, 'lon': m.lon, 'span': span});
      return;
    }
    _fm.move(LatLng(p.lat, p.lon), zoom);
  }

  Future<dynamic> _onNative(MethodCall call) async {
    final args = (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
    switch (call.method) {
      case 'spotTap':
        final id = args['id'] as String?;
        final s = widget.spots.where((e) => e.uuid == id).firstOrNull;
        if (s != null) widget.onSpotTap?.call(s);
      case 'longPress':
        final lat = (args['lat'] as num?)?.toDouble();
        final lon = (args['lon'] as num?)?.toDouble();
        if (lat != null && lon != null) {
          widget.onLongPress?.call(_fromMap(lat, lon));
        }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return FishingMap._useNative ? _native() : _flutterMap();
  }

  Widget _native() {
    final m = _toMap(_start);
    return UiKitView(
      viewType: 'xiai/fishing_map',
      creationParamsCodec: const StandardMessageCodec(),
      creationParams: {
        'lat': m.lat,
        'lon': m.lon,
        'span':
            widget.initial != null || widget.here != null ? 6000.0 : 60000.0,
        'showsUser': widget.here != null,
        'spots': _nativeSpots(),
        'tint': AppColors.amber.toARGB32(),
      },
      gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
        Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
      },
      onPlatformViewCreated: (id) {
        _channel = MethodChannel('xiai/fishing_map/$id')
          ..setMethodCallHandler(_onNative);
      },
    );
  }

  Widget _flutterMap() {
    final start = _start;
    final here = widget.here;
    return FlutterMap(
      mapController: _fm,
      options: MapOptions(
        initialCenter: LatLng(start.lat, start.lon),
        initialZoom: widget.initial != null || here != null ? 13.5 : 10,
        minZoom: 3,
        maxZoom: 18,
        interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
        onLongPress: (_, p) =>
            widget.onLongPress?.call(LatLon(p.latitude, p.longitude)),
      ),
      children: [
        TileLayer(
          urlTemplate: FishingMap.debugUrlTemplate ??
              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'cn.singzquant.aiquant',
          tileProvider: FishingMap.debugTileProvider,
          maxNativeZoom: 18,
        ),
        MarkerLayer(markers: [
          if (here != null)
            Marker(
              key: const Key('map-here'),
              point: LatLng(here.lat, here.lon),
              width: 22,
              height: 22,
              child: const _HereDot(),
            ),
          for (final s in widget.spots)
            if (s.hasCoord)
              Marker(
                key: Key('map-pin-${s.uuid}'),
                point: LatLng(s.lat!, s.lon!),
                width: 120,
                height: 58,
                alignment: Alignment.topCenter,
                child: _Pin(spot: s, onTap: () => widget.onSpotTap?.call(s)),
              ),
        ]),
        // OSM 瓦片要求署名；自己画一个不会溢出的小角标。
        Align(
          alignment: Alignment.bottomRight,
          child: Container(
            margin: const EdgeInsets.all(2),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            color: Colors.white.withValues(alpha: 0.75),
            child: const Text('© OpenStreetMap',
                maxLines: 1,
                style: TextStyle(fontSize: 9, color: Colors.black87)),
          ),
        ),
      ],
    );
  }
}

class _HereDot extends StatelessWidget {
  const _HereDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF2F7CF6),
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(color: Color(0x552F7CF6), blurRadius: 10, spreadRadius: 4),
        ],
      ),
    );
  }
}

/// 图钉：圆形主题色头 + 名字标签，尖端落在坐标点上。
class _Pin extends StatelessWidget {
  const _Pin({required this.spot, required this.onTap});
  final FishingSpot spot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              boxShadow: const [
                BoxShadow(
                    color: AppColors.shadow,
                    blurRadius: 6,
                    offset: Offset(0, 1)),
              ],
            ),
            child: Text(
              spot.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.micro.copyWith(
                  color: AppColors.textPrimary, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 2),
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: AppColors.amber,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: const Icon(Icons.phishing_rounded,
                size: 14, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
