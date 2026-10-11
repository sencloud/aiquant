import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/require_login.dart';
import '../../state/auth_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import 'catch_editor_screen.dart';
import 'fishing_models.dart';
import 'fishing_state.dart';
import 'identify_screen.dart';
import 'maps_launcher.dart';
import 'spot_editor.dart';

/// 「渔获」页签：渔获日记 + 私人钓点 + 拍照识鱼入口。需登录（数据存在服务端）。
class CatchesScreen extends StatefulWidget {
  const CatchesScreen({super.key});

  @override
  State<CatchesScreen> createState() => _CatchesScreenState();
}

class _CatchesScreenState extends State<CatchesScreen> {
  int _seg = 0; // 0 渔获 / 1 钓点

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = context.read<FishingState>();
      if (context.read<AuthState>().isAuthenticated &&
          !s.journalLoaded &&
          !s.journalLoading) {
        s.refreshJournal();
      }
    });
  }

  Future<void> _addCatch() async {
    if (!await requireLogin(context)) return;
    if (!mounted) return;
    await Navigator.of(context).push(
        MaterialPageRoute<bool>(builder: (_) => const CatchEditorScreen()));
  }

  Future<void> _identify() async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const IdentifyScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final authed = context.watch<AuthState>().isAuthenticated;
    final s = context.watch<FishingState>();
    return WkPage(
      title: '渔获',
      actions: [
        IconButton(
          key: const Key('catches-identify'),
          tooltip: '拍照识鱼',
          icon: const Icon(Icons.center_focus_strong_outlined),
          onPressed: _identify,
        ),
      ],
      child: !authed
          ? WkEmpty(
              icon: Icons.menu_book_outlined,
              title: '登录后记录你的渔获',
              hint: '渔获日记和私人钓点保存在云端，换手机也不丢；钓点只有你自己能看到。',
              action: FilledButton(
                key: const Key('catches-login'),
                onPressed: () async {
                  if (await requireLogin(context) && context.mounted) {
                    context.read<FishingState>().refreshJournal();
                  }
                },
                child: const Text('登录'),
              ),
            )
          : RefreshIndicator(
              onRefresh: s.refreshJournal,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.sm,
                    AppSpace.gutter, AppSpace.xxl),
                children: [
                  _statsCard(s.stats),
                  Row(children: [
                    Expanded(
                      child: WkPrimaryButton(
                        key: const Key('catches-add'),
                        label: '记一条',
                        icon: Icons.add_rounded,
                        onPressed: _addCatch,
                      ),
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: _identify,
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: const Text('拍照识鱼'),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: AppSpace.lg),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('渔获')),
                      ButtonSegment(value: 1, label: Text('私人钓点')),
                    ],
                    selected: {_seg},
                    showSelectedIcon: false,
                    onSelectionChanged: (v) => setState(() => _seg = v.first),
                  ),
                  const SizedBox(height: AppSpace.md),
                  if (s.journalError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpace.md),
                      child: WkNote(text: s.journalError!),
                    ),
                  if (s.journalLoading && !s.journalLoaded)
                    const Padding(
                      padding: EdgeInsets.all(AppSpace.xxl),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_seg == 0)
                    ..._catchList(s)
                  else
                    ..._spotList(s),
                ],
              ),
            ),
    );
  }

  Widget _statsCard(CatchStats st) {
    return WkGroup(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.lg, vertical: AppSpace.lg),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            WkStat(value: '${st.trips}', label: '记录'),
            WkStat(value: '${st.fish}', unit: '条', label: '渔获'),
            WkStat(value: '${st.species}', unit: '种', label: '鱼种'),
            WkStat(value: '${st.released}', unit: '条', label: '放流'),
          ],
        ),
      ],
    );
  }

  List<Widget> _catchList(FishingState s) {
    if (s.catches.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpace.xxl),
          child: WkEmpty(
            icon: Icons.set_meal_outlined,
            title: '还没有渔获记录',
            hint: '每次出钓记一笔：鱼种、钓点、钓法、饵料，慢慢就有了自己的鱼情本。',
          ),
        ),
      ];
    }
    return [
      WkGroup(children: [
        for (final c in s.catches) _CatchRow(item: c),
      ]),
    ];
  }

  List<Widget> _spotList(FishingState s) {
    return [
      WkGroup(
        footer: '导航会打开手机自带的地图 App；坐标可在地图 App 里长按位置复制。',
        children: [
          for (final sp in s.spots)
            WkRow(
              icon: Icons.bookmark_outline_rounded,
              title: sp.name,
              subtitle: [
                if (sp.waterType.isNotEmpty) sp.waterType,
                if (sp.hasCoord)
                  '${sp.lat!.toStringAsFixed(4)}, ${sp.lon!.toStringAsFixed(4)}'
                else
                  '未填坐标',
                if (sp.note.isNotEmpty) sp.note,
              ].join(' · '),
              trailing: PopupMenuButton<String>(
                key: Key('spot-menu-${sp.uuid}'),
                onSelected: (v) => _spotAction(v, sp),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'nav', child: Text('导航（系统地图）')),
                  if (sp.hasCoord)
                    const PopupMenuItem(
                        value: 'forecast', child: Text('看出钓指数')),
                  const PopupMenuItem(value: 'edit', child: Text('编辑')),
                  const PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ),
          WkRow(
            key: const Key('spot-add'),
            icon: Icons.add_location_alt_outlined,
            title: '新建私人钓点',
            onTap: () => showSpotEditor(context),
          ),
        ],
      ),
    ];
  }

  Future<void> _spotAction(String v, FishingSpot sp) async {
    final s = context.read<FishingState>();
    switch (v) {
      case 'nav':
        final ok = await openSpotInMaps(sp);
        if (!ok && mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('没能打开地图 App')));
        }
      case 'forecast':
        await s.loadForecast(place: sp.name, lat: sp.lat, lon: sp.lon);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('已切到「${sp.name}」，到「出钓」页查看')));
        }
      case 'edit':
        await showSpotEditor(context, spot: sp);
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('删除「${sp.name}」？'),
            content: const Text('已有渔获里的钓点名称会保留。'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('删除')),
            ],
          ),
        );
        if (ok == true) await s.deleteSpot(sp.uuid);
    }
  }
}

class _CatchRow extends StatelessWidget {
  const _CatchRow({required this.item});
  final FishCatch item;

  @override
  Widget build(BuildContext context) {
    final c = item;
    final d = c.caughtAt;
    final meta = [
      '${d.month}月${d.day}日',
      if (c.spotName.isNotEmpty) c.spotName,
      if (c.method.isNotEmpty) c.method,
      if (c.weightG != null) '${(c.weightG! / 500).toStringAsFixed(1)}斤',
      if (c.lengthCm != null) '${c.lengthCm!.toStringAsFixed(0)}cm',
    ].join(' · ');
    return InkWell(
      onTap: () => _detail(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.lg, vertical: AppSpace.md),
        child: Row(
          children: [
            _Thumb(item: c),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text('${c.species} ×${c.count}',
                        style:
                            AppType.body.copyWith(fontWeight: FontWeight.w600)),
                    if (c.released) ...[
                      const SizedBox(width: AppSpace.sm),
                      WkTag('放流', tone: AppColors.amber, filled: true),
                    ],
                  ]),
                  const SizedBox(height: 3),
                  Text(meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.caption
                          .copyWith(color: AppColors.textTertiary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _detail(BuildContext context) async {
    final s = context.read<FishingState>();
    final c = item;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.bgSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (c.hasPhoto)
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: FutureBuilder<Uint8List>(
                    future: s.photo(c.uuid),
                    builder: (_, snap) => snap.hasData
                        ? Image.memory(snap.data!,
                            height: 220,
                            width: double.infinity,
                            fit: BoxFit.cover)
                        : const SizedBox(
                            height: 220,
                            child: Center(child: CircularProgressIndicator())),
                  ),
                ),
              const SizedBox(height: AppSpace.md),
              Text('${c.species} ×${c.count}', style: AppType.title),
              const SizedBox(height: AppSpace.sm),
              for (final line in [
                '时间：${c.caughtAt.year}-${c.caughtAt.month}-${c.caughtAt.day}',
                if (c.spotName.isNotEmpty) '钓点：${c.spotName}',
                if (c.method.isNotEmpty) '钓法：${c.method}',
                if (c.bait.isNotEmpty) '饵料：${c.bait}',
                if (c.weather.isNotEmpty) '天气：${c.weather}',
                if (c.note.isNotEmpty) '备注：${c.note}',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(line,
                      style: AppType.body
                          .copyWith(color: AppColors.textSecondary)),
                ),
              const SizedBox(height: AppSpace.md),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await s.deleteCatch(c.uuid);
                  },
                  icon:
                      const Icon(Icons.delete_outline, color: AppColors.danger),
                  label: const Text('删除',
                      style: TextStyle(color: AppColors.danger)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.item});
  final FishCatch item;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(Icons.set_meal_rounded, color: AppColors.amber, size: 24),
    );
    if (!item.hasPhoto) return box;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: FutureBuilder<Uint8List>(
        future: context.read<FishingState>().photo(item.uuid),
        builder: (_, snap) => snap.hasData
            ? Image.memory(snap.data!, width: 48, height: 48, fit: BoxFit.cover)
            : box,
      ),
    );
  }
}
