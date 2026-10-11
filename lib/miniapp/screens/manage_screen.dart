import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import '../miniapp_icons.dart';
import '../miniapp_models.dart';
import '../miniapp_store.dart';
import 'miniapp_common.dart';
import 'miniapp_screen.dart';

/// 管理小应用：发现页上的排序（拖动）、放上 / 取下、未放上的列表。
class ManageScreen extends StatefulWidget {
  const ManageScreen({super.key, required this.topic});

  final String topic;

  @override
  State<ManageScreen> createState() => _ManageScreenState();
}

class _ManageScreenState extends State<ManageScreen> {
  MiniAppStore get _store => MiniAppStore.of(widget.topic);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _store.loadApps());
  }

  Future<void> _guard(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (mounted) showMiniAppSnack(context, miniAppErrorText(e));
    }
  }

  void _open(MiniApp a) => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MiniAppScreen(topic: widget.topic, appId: a.uuid)));

  Widget _tile(MiniApp a, {Widget? trailing, Widget? leading}) => Material(
        key: ValueKey(a.uuid),
        color: AppColors.bgSurface,
        child: ListTile(
          leading: leading ?? Icon(miniAppIcon(a.icon), color: AppColors.amber),
          title: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: a.summary.isEmpty
              ? null
              : Text(a.summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.micro.copyWith(color: AppColors.textTertiary)),
          trailing: trailing,
          onTap: () => _open(a),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final on = _store.mounted;
        final off = _store.unmounted;
        final c = _store.catalog;
        return WkPage(
          title: '管理小应用',
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.gutter, AppSpace.lg, AppSpace.gutter, AppSpace.xxl),
            children: [
              Padding(
                padding: const EdgeInsets.only(left: AppSpace.xs, bottom: AppSpace.sm),
                child: Text('发现页上（${on.length}/${c.maxMounted}）· 按住拖动排序',
                    style: AppType.caption.copyWith(color: AppColors.textTertiary)),
              ),
              if (on.isEmpty)
                const WkNote(text: '还没有放到发现页的小应用。')
              else
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    onReorderItem: (from, to) {
                      final ids = [for (final a in on) a.uuid];
                      ids.insert(to, ids.removeAt(from));
                      _guard(() => _store.reorder(ids));
                    },
                    children: [
                      for (var i = 0; i < on.length; i++)
                        _tile(
                          on[i],
                          leading: ReorderableDragStartListener(
                            index: i,
                            child: Icon(Icons.drag_indicator_rounded,
                                color: AppColors.textTertiary),
                          ),
                          trailing: IconButton(
                            tooltip: '从发现页取下',
                            icon: Icon(Icons.remove_circle_outline_rounded,
                                color: AppColors.textTertiary),
                            onPressed: () => _guard(() => _store.unmount(on[i].uuid)),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpace.lg),
              if (off.isNotEmpty)
                WkGroup(
                  header: '未放到发现页',
                  children: [
                    for (final a in off)
                      _tile(a,
                          trailing: TextButton(
                            onPressed: () => _guard(() => _store.mount(a.uuid)),
                            child: const Text('放上'),
                          )),
                  ],
                ),
              WkNote(
                text: '每个主题最多 ${c.maxApps} 个小应用（现在 ${_store.apps.length} 个），'
                    '发现页最多放 ${c.maxMounted} 个。',
              ),
            ],
          ),
        );
      },
    );
  }
}
