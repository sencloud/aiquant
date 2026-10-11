import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import '../miniapp_models.dart';
import '../miniapp_store.dart';
import 'miniapp_body.dart';
import 'miniapp_common.dart';
import 'workshop_screen.dart';

/// 一个小应用的完整页：参数 + 视图 + 「改一改」。
class MiniAppScreen extends StatefulWidget {
  const MiniAppScreen({super.key, required this.topic, required this.appId});

  final String topic;
  final String appId;

  @override
  State<MiniAppScreen> createState() => _MiniAppScreenState();
}

class _MiniAppScreenState extends State<MiniAppScreen> {
  MiniAppStore get _store => MiniAppStore.of(widget.topic);
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_store.byId(widget.appId) == null) {
        await _store.refreshApp(widget.appId);
      }
      if (_store.runs[widget.appId] == null) await _store.run(widget.appId);
    } catch (e) {
      _error = miniAppErrorText(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit(MiniApp a) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => WorkshopScreen(topic: widget.topic, app: a)));
    if (!mounted) return;
    try {
      await _store.refreshApp(widget.appId);
      await _store.run(widget.appId);
    } catch (_) {}
  }

  Future<void> _menu(MiniApp a, String action) async {
    try {
      switch (action) {
        case 'mount':
          await _store.mount(a.uuid);
          if (mounted) showMiniAppSnack(context, '已放到发现页');
        case 'unmount':
          await _store.unmount(a.uuid);
          if (mounted) showMiniAppSnack(context, '已从发现页取下');
        case 'rename':
          final t = await _askTitle(a.title);
          if (t != null && t.trim().isNotEmpty) await _store.rename(a.uuid, t.trim());
        case 'versions':
          await _versions(a);
        case 'delete':
          final ok = await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: const Text('删除这个小应用？'),
              content: const Text('删除后发现页和历史版本都会一起清掉。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('取消')),
                TextButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('删除', style: TextStyle(color: AppColors.danger))),
              ],
            ),
          );
          if (ok == true) {
            await _store.delete(a.uuid);
            if (mounted) Navigator.of(context).pop();
          }
      }
    } catch (e) {
      if (mounted) showMiniAppSnack(context, miniAppErrorText(e));
    }
  }

  Future<String?> _askTitle(String current) {
    final c = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名'),
        content: TextField(controller: c, maxLength: 20, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, c.text), child: const Text('好')),
        ],
      ),
    );
  }

  Future<void> _versions(MiniApp a) async {
    final items = await MiniAppStore.api.versions(a.uuid);
    if (!mounted) return;
    final v = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(AppSpace.lg),
              child: Text('版本记录', style: AppType.section),
            ),
            for (final it in items)
              ListTile(
                title: Text('v${it['version']}'
                    '${it['current'] == true ? '（当前）' : ''}'),
                subtitle: Text(_versionNote(it)),
                trailing: it['current'] == true ? null : const Text('恢复'),
                onTap: it['current'] == true
                    ? null
                    : () => Navigator.pop(ctx, (it['version'] as num).toInt()),
              ),
          ],
        ),
      ),
    );
    if (v != null) {
      await _store.restore(a.uuid, v);
      if (mounted) showMiniAppSnack(context, '已恢复到 v$v（另存为新版本）');
    }
  }

  String _versionNote(Map<String, dynamic> it) {
    final ms = (it['created_at'] as num?)?.toInt() ?? 0;
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final who = switch (it['author']) {
      'template' => '来自模板',
      'restore' => '恢复',
      _ => 'AI 生成',
    };
    final s = (it['summary'] as String?) ?? '';
    return '${d.month}月${d.day}日 · $who${s.isEmpty ? '' : ' · $s'}';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final a = _store.byId(widget.appId);
        if (a == null) {
          return WkPage(
            title: '小应用',
            child: Center(
              child: _loading
                  ? const CircularProgressIndicator()
                  : WkEmpty(
                      icon: Icons.apps_rounded,
                      title: _error ?? '小应用不存在或已删除'),
            ),
          );
        }
        final catalog = _store.catalog;
        return WkPage(
          title: a.title,
          actions: [
            IconButton(
              key: const Key('miniapp-refresh'),
              tooltip: '刷新',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _store.isRunning(a.uuid) ? null : () => _store.run(a.uuid),
            ),
            PopupMenuButton<String>(
              key: const Key('miniapp-menu'),
              onSelected: (v) => _menu(a, v),
              itemBuilder: (_) => [
                PopupMenuItem(
                    value: a.mounted ? 'unmount' : 'mount',
                    child: Text(a.mounted ? '从发现页取下' : '放到发现页')),
                const PopupMenuItem(value: 'rename', child: Text('重命名')),
                const PopupMenuItem(value: 'versions', child: Text('版本记录')),
                const PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          ],
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                AppSpace.gutter, AppSpace.lg, AppSpace.gutter, AppSpace.xxl),
            children: [
              if (_store.isRunning(a.uuid))
                const LinearProgressIndicator(minHeight: 2),
              MiniAppBody(
                key: ValueKey('${a.uuid}-${a.version}'),
                spec: a.spec,
                run: _store.runs[a.uuid],
                savedInputs: a.inputs,
                onRefetch: (inputs) async {
                  await _store.run(a.uuid, inputs: inputs);
                },
                onInputsChanged: (inputs) => _store.saveInputs(a.uuid, inputs),
              ),
              const SizedBox(height: AppSpace.lg),
              WkPrimaryButton(
                key: const Key('miniapp-edit'),
                label: '改一改',
                icon: Icons.auto_fix_high_rounded,
                onPressed: () => _edit(a),
              ),
              const SizedBox(height: AppSpace.sm),
              Text(
                '用一句话告诉 AI 怎么改 · ${catalog.iterateCredits} 喜点 / 次，没改成全额退回',
                textAlign: TextAlign.center,
                style: AppType.micro.copyWith(color: AppColors.textTertiary),
              ),
            ],
          ),
        );
      },
    );
  }
}
