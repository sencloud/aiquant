import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../state/billing_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import '../miniapp_models.dart';
import '../miniapp_store.dart';
import 'miniapp_card.dart';
import 'miniapp_common.dart';
import 'miniapp_screen.dart';

/// 工坊：用对话新建 / 修改一个小应用。
///
/// 每一轮先扣喜点（新建 / 修改价不同），服务端异步生成，这里轮询结果。
/// AI 追问、拒绝、没做出来都全额退回。
class WorkshopScreen extends StatefulWidget {
  const WorkshopScreen({
    super.key,
    required this.topic,
    this.app,
    this.pollInterval = const Duration(milliseconds: 1500),
  });

  final String topic;

  /// 修改已有的小应用；null 表示新建。
  final MiniApp? app;

  final Duration pollInterval;

  @override
  State<WorkshopScreen> createState() => _WorkshopScreenState();
}

class _WorkshopScreenState extends State<WorkshopScreen> {
  MiniAppStore get _store => MiniAppStore.of(widget.topic);
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<MiniAppGen> _rounds = [];
  final Map<int, String> _picks = {};
  String? _sessionId;
  String? _appId;
  bool _sending = false;
  Timer? _poll;
  DateTime? _pollStarted;

  bool get _pending => _rounds.isNotEmpty && _rounds.last.pending;

  @override
  void initState() {
    super.initState();
    _appId = widget.app?.uuid;
    final sid = widget.app?.sessionId ?? '';
    if (sid.isNotEmpty) {
      _sessionId = sid;
      _loadHistory(sid);
    }
    if (!_store.publicLoaded) _store.loadPublic();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadHistory(String sid) async {
    try {
      final items = await MiniAppStore.api.session(sid);
      if (!mounted) return;
      setState(() {
        _rounds
          ..clear()
          ..addAll(items);
      });
      if (_pending) _startPoll();
      _toBottom();
    } catch (_) {}
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  void _setBalance(int? b) {
    if (b == null) return;
    try {
      context.read<BillingState>().refreshBalance();
    } catch (_) {}
  }

  Future<void> _send([String? text]) async {
    final msg = (text ?? _input.text).trim();
    if (msg.isEmpty || _sending || _pending) return;
    setState(() => _sending = true);
    try {
      final (g, bal) = await MiniAppStore.api.generate(
        requestId: const Uuid().v4(),
        topic: widget.topic,
        message: msg,
        appUuid: _appId,
        sessionId: _sessionId,
      );
      _input.clear();
      _picks.clear();
      _sessionId = g.sessionId.isEmpty ? _sessionId : g.sessionId;
      _setBalance(bal);
      setState(() => _rounds.add(g));
      _toBottom();
      if (g.pending) {
        _startPoll();
      } else {
        await _onDone(g);
      }
    } catch (e) {
      if (mounted) showMiniAppSnack(context, miniAppErrorText(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _startPoll() {
    _poll?.cancel();
    _pollStarted = DateTime.now();
    _poll = Timer.periodic(widget.pollInterval, (_) => _tick());
  }

  Future<void> _tick() async {
    if (!mounted || _rounds.isEmpty) return;
    final rid = _rounds.last.requestId;
    try {
      final (g, bal) = await MiniAppStore.api.gen(rid);
      if (!mounted) return;
      final i = _rounds.indexWhere((r) => r.requestId == rid);
      if (i >= 0) setState(() => _rounds[i] = g);
      if (!g.pending) {
        _poll?.cancel();
        _setBalance(bal);
        await _onDone(g);
      }
    } catch (_) {
      // 网络抖动：下一拍再试；超过 6 分钟放弃（服务端会自行退款）。
      if (_pollStarted != null &&
          DateTime.now().difference(_pollStarted!) > const Duration(minutes: 6)) {
        _poll?.cancel();
        if (mounted) showMiniAppSnack(context, '网络不太好，结果稍后会出现在「管理」里');
      }
    }
  }

  Future<void> _onDone(MiniAppGen g) async {
    if (g.outcome == 'spec' && g.appUuid != null) {
      _appId = g.appUuid;
      try {
        await _store.refreshApp(g.appUuid!);
        await _store.loadApps();
        unawaited(_store.run(g.appUuid!));
      } catch (_) {}
    }
    if (mounted) setState(() {});
    _toBottom();
  }

  Future<void> _mount(String id) async {
    try {
      await _store.mount(id);
      if (mounted) showMiniAppSnack(context, '已放到发现页');
    } catch (e) {
      if (mounted) showMiniAppSnack(context, miniAppErrorText(e));
    }
  }

  void _open(String id) {
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => MiniAppScreen(topic: widget.topic, appId: id)));
  }

  void _answer(MiniAppGen g) {
    final parts = <String>[
      for (var i = 0; i < g.questions.length; i++)
        if (_picks[i] != null) '${g.questions[i].q}：${_picks[i]}'
    ];
    final extra = _input.text.trim();
    if (extra.isNotEmpty) parts.add(extra);
    if (parts.isEmpty) return;
    _send(parts.join('；'));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final c = _store.catalog;
        final iterate = _appId != null;
        return WkPage(
          title: widget.app != null ? '改一改 · ${widget.app!.title}' : '新建小应用',
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(
                      AppSpace.gutter, AppSpace.lg, AppSpace.gutter, AppSpace.lg),
                  children: [
                    if (_rounds.isEmpty) _intro(c, iterate),
                    for (var i = 0; i < _rounds.length; i++)
                      ..._round(_rounds[i], i == _rounds.length - 1),
                  ],
                ),
              ),
              _composer(c, iterate),
            ],
          ),
        );
      },
    );
  }

  Widget _intro(MiniAppCatalog c, bool iterate) {
    final examples = miniAppExamples(widget.topic);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(iterate ? '想怎么改？' : '想要一个什么样的小工具？',
            style: AppType.title.copyWith(color: AppColors.textPrimary)),
        const SizedBox(height: AppSpace.sm),
        Text(
          iterate
              ? '比如「加一个 60 日均线」「数字换成大字」「默认看主力合约」。'
              : 'AI 会帮你把它做成发现页上的一张卡片：看行情、算一算、盯数据都行。'
                  '它只能读数据和计算，不会帮你下单。',
          style: AppType.caption.copyWith(color: AppColors.textSecondary),
        ),
        if (!iterate) ...[
          const SizedBox(height: AppSpace.lg),
          Text('试试这样说',
              style: AppType.micro.copyWith(color: AppColors.textTertiary)),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: [
              for (final e in examples)
                ActionChip(
                  label: Text(e, style: AppType.caption),
                  backgroundColor: AppColors.bgSurface,
                  side: BorderSide(color: AppColors.borderDim),
                  onPressed: () {
                    _input.text = e;
                    _input.selection =
                        TextSelection.collapsed(offset: e.length);
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }

  List<Widget> _round(MiniAppGen g, bool last) {
    return [
      Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpace.sm, left: 48),
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpace.md, vertical: AppSpace.sm),
          decoration: BoxDecoration(
            color: AppColors.amber,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Text(g.message,
              style: AppType.body.copyWith(color: AppColors.onAccent)),
        ),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpace.lg, right: 24),
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: _reply(g, last),
        ),
      ),
    ];
  }

  Widget _reply(MiniAppGen g, bool last) {
    final note = AppType.micro.copyWith(color: AppColors.textTertiary);
    if (g.pending) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 1.6, color: AppColors.amber)),
        const SizedBox(width: AppSpace.sm),
        Flexible(
          child: Text(miniAppStageLabel(g.stage),
              key: const Key('workshop-stage'),
              style: AppType.body.copyWith(color: AppColors.textSecondary)),
        ),
      ]);
    }
    final refundNote = g.refunded && g.credits > 0
        ? Text('已退回 ${g.credits} 喜点', style: note)
        : null;
    switch (g.outcome) {
      case 'ask':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((g.resultMessage ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.sm),
                child: Text(g.resultMessage!, style: AppType.body),
              ),
            for (var i = 0; i < g.questions.length; i++) ...[
              Text(g.questions[i].q,
                  style: AppType.body.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: AppSpace.xs),
              Wrap(
                spacing: AppSpace.xs,
                runSpacing: AppSpace.xs,
                children: [
                  for (final o in g.questions[i].options)
                    ChoiceChip(
                      label: Text(o, style: AppType.caption),
                      selected: last && _picks[i] == o,
                      onSelected: last
                          ? (v) => setState(() => v ? _picks[i] = o : _picks.remove(i))
                          : null,
                    ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
            ],
            if (last)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  key: const Key('workshop-answer'),
                  onPressed: _sending ? null : () => _answer(g),
                  child: const Text('就这样'),
                ),
              ),
            if (refundNote != null) refundNote,
          ],
        );
      case 'spec':
        final a = g.appUuid == null ? null : _store.byId(g.appUuid!);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              g.kind == 'iterate'
                  ? '改好了（第 ${g.version ?? '-'} 版）${(g.summary ?? '').isEmpty ? '' : '：${g.summary}'}'
                  : '做好了：${(g.summary ?? '').isEmpty ? '看看效果' : g.summary}',
              style: AppType.body,
            ),
            const SizedBox(height: AppSpace.sm),
            if (a != null && last)
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: AppColors.borderDim),
                ),
                child: MiniAppCard(
                  key: const Key('workshop-preview'),
                  spec: a.spec,
                  title: a.title,
                  icon: a.icon,
                  run: _store.runs[a.uuid],
                  inputs: a.inputs,
                  loading: _store.isRunning(a.uuid),
                  onTap: () => _open(a.uuid),
                ),
              ),
            if (a != null && last) ...[
              const SizedBox(height: AppSpace.sm),
              Row(children: [
                if (!a.mounted)
                  Expanded(
                    child: FilledButton(
                      key: const Key('workshop-mount'),
                      onPressed: () => _mount(a.uuid),
                      child: const Text('放到发现页'),
                    ),
                  ),
                if (!a.mounted) const SizedBox(width: AppSpace.sm),
                Expanded(
                  child: OutlinedButton(
                    key: const Key('workshop-open'),
                    onPressed: () => _open(a.uuid),
                    child: const Text('打开'),
                  ),
                ),
              ]),
              const SizedBox(height: AppSpace.xs),
              Text('不满意就接着说，${_store.catalog.iterateCredits} 喜点改一次', style: note),
            ],
            if (g.warnings.isNotEmpty)
              Text('提示：${g.warnings.first}', style: note),
          ],
        );
      case 'refuse':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(g.resultMessage ?? '这个做不了。', style: AppType.body),
            if (refundNote != null) refundNote,
          ],
        );
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(g.resultMessage ?? '这次没做出来，换个说法试试？', style: AppType.body),
            if (refundNote != null) refundNote,
          ],
        );
    }
  }

  Widget _composer(MiniAppCatalog c, bool iterate) {
    final busy = _sending || _pending;
    final price = iterate
        ? '修改 ${c.iterateCredits} 喜点 · 没改成全额退回'
        : '新建 ${c.createCredits} 喜点 · 未做出来全额退回';
    return Container(
      color: AppColors.bgSurface,
      padding: EdgeInsets.fromLTRB(AppSpace.gutter, AppSpace.sm, AppSpace.sm,
          AppSpace.sm + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(c.generation ? price : '生成暂时不可用，稍后再试',
              key: const Key('workshop-price'),
              style: AppType.micro.copyWith(color: AppColors.textTertiary)),
          const SizedBox(height: AppSpace.xs),
          Row(children: [
            Expanded(
              child: TextField(
                key: const Key('workshop-input'),
                controller: _input,
                enabled: c.generation,
                minLines: 1,
                maxLines: 4,
                maxLength: c.maxMessage,
                buildCounter: (_, {required currentLength, required isFocused, maxLength}) =>
                    null,
                decoration: InputDecoration(
                  hintText: iterate ? '说说哪里要改' : '说说你想要的小工具',
                  isDense: true,
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            IconButton(
              key: const Key('workshop-send'),
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.arrow_upward_rounded, color: AppColors.amber),
              onPressed: busy || !c.generation ? null : () => _send(),
            ),
          ]),
        ],
      ),
    );
  }
}

