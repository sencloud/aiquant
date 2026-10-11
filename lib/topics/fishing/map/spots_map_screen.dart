import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../theme/app_theme.dart';
import '../fishing_models.dart';
import '../fishing_state.dart';
import '../location/fishing_locator.dart';
import '../location/location_flow.dart';
import '../maps_launcher.dart';
import '../spot_editor.dart';
import 'fishing_map.dart';
import 'geo_coord.dart';

/// 钓点地图：我的位置 + 私人钓点图钉；长按地图或「在中心添加」新建钓点。
///
/// 钓点只有自己能看到（服务端按用户隔离）。需登录，由入口负责。
class SpotsMapScreen extends StatefulWidget {
  const SpotsMapScreen({super.key, this.focus});

  /// 打开时居中到这个钓点（可空）。
  final FishingSpot? focus;

  @override
  State<SpotsMapScreen> createState() => _SpotsMapScreenState();
}

class _SpotsMapScreenState extends State<SpotsMapScreen> {
  final _map = FishingMapController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final s = context.read<FishingState>();
      if (!s.journalLoaded && !s.journalLoading) {
        // ignore: unawaited_futures
        s.refreshJournal();
      }
      // 已授权才静默取一次位置；没授权不弹框，等用户点「定位」按钮。
      if (s.here == null && await s.locator.access() == LocAccess.granted) {
        final p = await s.locate();
        if (p != null && mounted && widget.focus == null) {
          await _map.moveTo(p);
        }
      }
    });
  }

  Future<void> _locateMe() async {
    final s = context.read<FishingState>();
    final ok = await ensureLocationAccess(context, s.locator,
        purpose: '在地图上显示你在哪，方便就地标记钓点。');
    if (!ok || !mounted) return;
    final p = await s.locate();
    if (!mounted) return;
    if (p == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('暂时没拿到位置，到开阔处再试试')));
      return;
    }
    await _map.moveTo(p, zoom: 15);
  }

  Future<void> _addAt(LatLon? p) async {
    final at = p ?? await _map.center();
    if (!mounted) return;
    final saved = await showSpotEditor(context, at: at);
    if (saved != null && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已保存「${saved.name}」，只有你能看到')));
    }
  }

  Future<void> _open(FishingSpot sp) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<FishingState>(),
        child: SpotCard(spot: sp),
      ),
    );
    if (action == 'edit' && mounted) {
      final cur =
          context.read<FishingState>().spots.where((e) => e.uuid == sp.uuid);
      await showSpotEditor(context, spot: cur.isEmpty ? sp : cur.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<FishingState>();
    final focus = widget.focus;
    final noCoord = s.spots.where((e) => !e.hasCoord).length;
    return Scaffold(
      appBar: AppBar(title: const Text('钓点地图')),
      body: Stack(
        children: [
          Positioned.fill(
            child: FishingMap(
              key: const Key('fishing-map'),
              controller: _map,
              spots: s.spots,
              here: s.here,
              initial: focus != null && focus.hasCoord
                  ? LatLon(focus.lat!, focus.lon!)
                  : null,
              onSpotTap: _open,
              onLongPress: _addAt,
            ),
          ),
          // 地图中心准星：「在中心添加」就落在这里。
          IgnorePointer(
            child: Center(
              child: Icon(Icons.add_rounded,
                  size: 28,
                  color: AppColors.textPrimary.withValues(alpha: 0.7)),
            ),
          ),
          Positioned(
            left: AppSpace.md,
            top: AppSpace.md,
            right: 72,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.md, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.bgSurface.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  boxShadow: const [
                    BoxShadow(color: AppColors.shadow, blurRadius: 8),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline_rounded,
                        size: 14, color: AppColors.amber),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${s.spots.where((e) => e.hasCoord).length} 个钓点 · 只有你能看到'
                        '${noCoord > 0 ? ' · $noCoord 个未定位' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.caption
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: AppSpace.md,
            top: AppSpace.md,
            child: _RoundButton(
              key: const Key('map-locate'),
              icon: s.locating
                  ? Icons.more_horiz_rounded
                  : Icons.my_location_rounded,
              tooltip: '定位到我',
              onPressed: s.locating ? null : _locateMe,
            ),
          ),
          Positioned(
            left: AppSpace.xl,
            right: AppSpace.xl,
            bottom: MediaQuery.paddingOf(context).bottom + AppSpace.xl,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpace.md, vertical: 4),
                    margin: const EdgeInsets.only(bottom: AppSpace.sm),
                    decoration: BoxDecoration(
                      color: AppColors.textPrimary.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text('长按地图也能添加',
                        style: AppType.micro.copyWith(color: Colors.white)),
                  ),
                ),
                FilledButton.icon(
                  key: const Key('map-add-center'),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(48)),
                  onPressed: () => _addAt(null),
                  icon: const Icon(Icons.add_location_alt_outlined),
                  label: const Text('在地图中心添加钓点'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton(
      {super.key, required this.icon, required this.tooltip, this.onPressed});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgSurface,
      shape: const CircleBorder(),
      elevation: 2,
      shadowColor: AppColors.shadow,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: AppColors.amber),
      ),
    );
  }
}

/// 点图钉弹出的钓点卡片：导航 / 出钓指数 / 编辑 / 删除。
class SpotCard extends StatelessWidget {
  const SpotCard({super.key, required this.spot});
  final FishingSpot spot;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<FishingState>();
    final sp = s.spots.where((e) => e.uuid == spot.uuid).firstOrNull ?? spot;
    final here = s.here;
    final dist = here != null && sp.hasCoord
        ? formatDistance(distanceMeters(here.lat, here.lon, sp.lat!, sp.lon!))
        : null;
    final meta = [
      if (sp.waterType.isNotEmpty) sp.waterType,
      if (sp.species.isNotEmpty) sp.species,
      if (dist != null) '距你 $dist',
    ].join(' · ');
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpace.xl, AppSpace.lg, AppSpace.xl, AppSpace.md),
        child: Column(
          key: const Key('spot-card'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(sp.name,
                style: AppType.title.copyWith(color: AppColors.textPrimary)),
            if (meta.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(meta,
                  style:
                      AppType.caption.copyWith(color: AppColors.textSecondary)),
            ],
            if (sp.note.isNotEmpty) ...[
              const SizedBox(height: AppSpace.sm),
              Text(sp.note,
                  style: AppType.body.copyWith(color: AppColors.textPrimary)),
            ],
            const SizedBox(height: AppSpace.lg),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    final m = ScaffoldMessenger.of(context);
                    final ok = await openSpotInMaps(sp);
                    if (!ok) {
                      m.showSnackBar(
                          const SnackBar(content: Text('没能打开地图 App')));
                    }
                  },
                  icon: const Icon(Icons.navigation_outlined, size: 18),
                  label: const Text('导航'),
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: sp.hasCoord
                      ? () {
                          final m = ScaffoldMessenger.of(context);
                          s.loadForecast(
                              place: sp.name, lat: sp.lat, lon: sp.lon);
                          Navigator.of(context).pop();
                          m.showSnackBar(SnackBar(
                              content: Text('已切到「${sp.name}」，到「出钓」页查看')));
                        }
                      : null,
                  icon: const Icon(Icons.wb_twilight_outlined, size: 18),
                  label: const Text('出钓指数'),
                ),
              ),
            ]),
            const SizedBox(height: AppSpace.xs),
            Row(children: [
              Expanded(
                child: TextButton(
                  key: const Key('spot-card-edit'),
                  onPressed: () => Navigator.of(context).pop('edit'),
                  child: const Text('编辑'),
                ),
              ),
              Expanded(
                child: TextButton(
                  key: const Key('spot-card-delete'),
                  style:
                      TextButton.styleFrom(foregroundColor: AppColors.danger),
                  onPressed: () async {
                    final ok = await confirmDeleteSpot(context, sp);
                    if (ok != true || !context.mounted) return;
                    final m = ScaffoldMessenger.of(context);
                    try {
                      await s.deleteSpot(sp.uuid);
                      if (context.mounted) Navigator.of(context).pop();
                    } catch (_) {
                      m.showSnackBar(
                          const SnackBar(content: Text('删除失败，稍后再试')));
                    }
                  },
                  child: const Text('删除'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

Future<bool?> confirmDeleteSpot(BuildContext context, FishingSpot sp) =>
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除「${sp.name}」？'),
        content: const Text('已有渔获里的钓点名称会保留。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
              key: const Key('spot-delete-confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
