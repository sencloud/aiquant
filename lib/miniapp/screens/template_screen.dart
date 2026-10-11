import 'package:flutter/material.dart';

import '../../core/auth/require_login.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import '../miniapp_models.dart';
import '../miniapp_store.dart';
import 'miniapp_body.dart';
import 'miniapp_common.dart';
import 'miniapp_screen.dart';

/// 官方模板预览：未登录也能看、能调参数；「用这个模板」需要登录（免费）。
class TemplateScreen extends StatefulWidget {
  const TemplateScreen({super.key, required this.topic, required this.template});

  final String topic;
  final MiniAppTemplate template;

  @override
  State<TemplateScreen> createState() => _TemplateScreenState();
}

class _TemplateScreenState extends State<TemplateScreen> {
  MiniAppStore get _store => MiniAppStore.of(widget.topic);
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.template.privateData &&
          _store.templateRuns[widget.template.id] == null) {
        _store.runTemplate(widget.template.id);
      }
    });
  }

  Future<void> _use() async {
    if (!await requireLogin(context)) return;
    if (!mounted) return;
    setState(() => _adding = true);
    try {
      final a = await _store.fromTemplate(widget.template.id);
      if (!mounted) return;
      showMiniAppSnack(context, a.mounted ? '已添加到发现页' : '已添加（发现页已满，先放在「管理」里）');
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) => MiniAppScreen(topic: widget.topic, appId: a.uuid)));
    } catch (e) {
      if (mounted) showMiniAppSnack(context, miniAppErrorText(e));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.template;
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) => WkPage(
        title: t.title,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              AppSpace.gutter, AppSpace.lg, AppSpace.gutter, AppSpace.xxl),
          children: [
            Text(t.summary,
                style: AppType.caption.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: AppSpace.md),
            if (_store.isRunning('tpl:${t.id}'))
              const LinearProgressIndicator(minHeight: 2),
            if (t.privateData)
              const WkNote(text: '这个模板用的是你自己的记录，添加后才能看到数据。'),
            MiniAppBody(
              spec: t.spec,
              run: _store.templateRuns[t.id],
              onRefetch: t.privateData
                  ? null
                  : (inputs) async {
                      await _store.runTemplate(t.id, inputs: inputs);
                    },
            ),
            const SizedBox(height: AppSpace.lg),
            WkPrimaryButton(
              key: const Key('miniapp-use-template'),
              label: '用这个模板（免费）',
              busy: _adding,
              onPressed: _adding ? null : _use,
            ),
          ],
        ),
      ),
    );
  }
}
