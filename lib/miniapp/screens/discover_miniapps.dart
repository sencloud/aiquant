import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/auth/require_login.dart';
import '../../state/auth_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import '../miniapp_icons.dart';
import '../miniapp_models.dart';
import '../miniapp_store.dart';
import 'manage_screen.dart';
import 'miniapp_card.dart';
import 'miniapp_screen.dart';
import 'template_screen.dart';
import 'workshop_screen.dart';

/// 发现页上的小应用区：「我的小应用」卡片墙 + ＋新建 + 官方模板。
///
/// 两个主题共用；数据走 [MiniAppStore.of]（按主题一份）。未登录只显示
/// 官方模板与「＋新建」（点了先登录）。
class DiscoverMiniApps extends StatefulWidget {
  const DiscoverMiniApps({
    super.key,
    required this.topic,
    this.builtins = const [],
    this.store,
  });

  final String topic;

  /// 主题内置入口（排在卡片墙之后、官方模板之前）。
  final List<Widget> builtins;

  /// 测试注入。
  final MiniAppStore? store;

  @override
  State<DiscoverMiniApps> createState() => _DiscoverMiniAppsState();
}

class _DiscoverMiniAppsState extends State<DiscoverMiniApps> {
  MiniAppStore get _store => widget.store ?? MiniAppStore.of(widget.topic);

  String? _seenUid = '\u0000';

  void _sync() {
    if (!mounted) return;
    final uid = context.read<AuthState>().currentUser?.uuid;
    _store.syncUser(uid);
    _store.ensureLoaded();
  }

  Future<void> _create() async {
    if (!await requireLogin(context)) return;
    if (!mounted) return;
    _sync();
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => WorkshopScreen(topic: widget.topic)));
    if (mounted) _store.ensureLoaded(force: true);
  }

  void _open(MiniApp a) {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => MiniAppScreen(topic: widget.topic, appId: a.uuid)));
  }

  void _manage() {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ManageScreen(topic: widget.topic)));
  }

  void _template(MiniAppTemplate t) {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => TemplateScreen(topic: widget.topic, template: t)));
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthState>().currentUser?.uuid;
    if (uid != _seenUid) {
      // 首帧 / 登录 / 登出 / 换号：帧后同步（build 里不能 notify）。
      _seenUid = uid;
      WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
    }
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final mounted = _store.mounted;
        final drafts = _store.unmounted;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(
              title: '我的小应用',
              action: uid != null && _store.apps.isNotEmpty ? '管理' : null,
              onAction: _manage,
            ),
            _CardWall(
              apps: mounted,
              store: _store,
              onOpen: _open,
              onCreate: _create,
            ),
            if (uid != null && drafts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.sm),
                child: WkGroup(children: [
                  WkRow(
                    key: const Key('miniapp-drafts'),
                    icon: Icons.inventory_2_outlined,
                    title: '未放到发现页的小应用',
                    value: '${drafts.length}',
                    onTap: _manage,
                  ),
                ]),
              ),
            const SizedBox(height: AppSpace.md),
            ...widget.builtins,
            if (_store.templates.isNotEmpty)
              WkGroup(
                header: '官方模板',
                footer: '模板免费使用；想要别的，点「＋新建」用一句话描述。',
                children: [
                  for (final t in _store.templates)
                    WkRow(
                      key: Key('miniapp-tpl-${t.id}'),
                      icon: miniAppIcon(t.icon),
                      title: t.title,
                      subtitle: t.summary,
                      onTap: () => _template(t),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.xs, 0, AppSpace.xs, AppSpace.sm),
      child: Row(children: [
        Expanded(
          child: Text(title,
              style: AppType.caption.copyWith(color: AppColors.textTertiary)),
        ),
        if (action != null)
          GestureDetector(
            key: const Key('miniapp-manage'),
            onTap: onAction,
            child: Text(action!,
                style: AppType.caption.copyWith(color: AppColors.amber)),
          ),
      ]),
    );
  }
}

/// 卡片墙：small 半宽、medium / large 整宽；最后一格是「＋新建」。
class _CardWall extends StatelessWidget {
  const _CardWall({
    required this.apps,
    required this.store,
    required this.onOpen,
    required this.onCreate,
  });

  final List<MiniApp> apps;
  final MiniAppStore store;
  final ValueChanged<MiniApp> onOpen;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      const gap = AppSpace.sm;
      final half = (c.maxWidth - gap) / 2;
      final tiles = <Widget>[
        for (final a in apps)
          SizedBox(
            width: a.cardSize == 'small' ? half : c.maxWidth,
            child: MiniAppCard(
              key: Key('miniapp-card-${a.uuid}'),
              spec: a.spec,
              title: a.title,
              icon: a.icon,
              run: store.runs[a.uuid],
              inputs: a.inputs,
              loading: store.isRunning(a.uuid),
              onTap: () => onOpen(a),
            ),
          ),
        SizedBox(
          width: apps.isEmpty ? c.maxWidth : half,
          child: _NewTile(onTap: onCreate, wide: apps.isEmpty),
        ),
      ];
      return Wrap(spacing: gap, runSpacing: gap, children: tiles);
    });
  }
}

class _NewTile extends StatelessWidget {
  const _NewTile({required this.onTap, required this.wide});
  final VoidCallback onTap;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.bgSurface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        key: const Key('miniapp-new'),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Container(
          height: wide ? 76 : 64,
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.borderMed, width: 1),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, color: AppColors.amber, size: 20),
              const SizedBox(width: AppSpace.xs),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('新建',
                        style: AppType.body.copyWith(
                            color: AppColors.amber, fontWeight: FontWeight.w600)),
                    if (wide)
                      Text('说一句话，做一个自己的小工具',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.micro
                              .copyWith(color: AppColors.textTertiary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
