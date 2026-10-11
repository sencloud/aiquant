import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../miniapp_models.dart';
import '../render/components.dart';
import '../render/spec_runtime.dart';

/// 小应用的完整界面（layout）：本地参数 + 最近一次取数。
///
/// 改动只影响 computed 的参数 → 立即本地重算；改动被数据绑定引用的参数 →
/// 防抖后回调 [onRefetch] 重新取数。参数变化通过 [onInputsChanged] 交给外层保存。
class MiniAppBody extends StatefulWidget {
  const MiniAppBody({
    super.key,
    required this.spec,
    required this.run,
    this.savedInputs = const {},
    this.onRefetch,
    this.onInputsChanged,
    this.now,
    this.footer,
  });

  final Map<String, dynamic> spec;
  final MiniAppRun? run;
  final Map<String, dynamic> savedInputs;
  final Future<void> Function(Map<String, dynamic> inputs)? onRefetch;
  final ValueChanged<Map<String, dynamic>>? onInputsChanged;
  final DateTime Function()? now;
  final Widget? footer;

  @override
  State<MiniAppBody> createState() => _MiniAppBodyState();
}

class _MiniAppBodyState extends State<MiniAppBody> {
  late SpecRuntime _rt = SpecRuntime(widget.spec);
  Map<String, dynamic>? _local;
  Timer? _debounce;

  DateTime Function() get _clock => widget.now ?? DateTime.now;

  @override
  void didUpdateWidget(covariant MiniAppBody old) {
    super.didUpdateWidget(old);
    if (!identical(old.spec, widget.spec)) {
      _rt = SpecRuntime(widget.spec);
      _local = null;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Map<String, dynamic> get _inputs {
    final base = _local ??
        (widget.run?.inputs.isNotEmpty == true
            ? widget.run!.inputs
            : widget.savedInputs);
    return _rt.resolveInputs(base, _clock());
  }

  void _onInput(String key, dynamic v) {
    final next = {..._inputs, key: v};
    setState(() => _local = next);
    widget.onInputsChanged?.call(next);
    if (_rt.dataInputs.contains(key) && widget.onRefetch != null) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 600), () {
        widget.onRefetch!(next);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final env = _rt.env(
        inputs: _inputs, data: widget.run?.data ?? const {}, now: _clock);
    final fetched = widget.run?.fetchedAt ?? 0;
    final note = <String>[
      if (fetched > 0) '数据更新于 ${_hm(fetched)}',
      if (_rt.disclaimer.isNotEmpty) _rt.disclaimer,
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_rt.hasData && widget.run == null)
          const Padding(
            padding: EdgeInsets.all(AppSpace.xl),
            child: Center(child: CircularProgressIndicator()),
          )
        else
          MiniAppRenderer(
            runtime: _rt,
            node: _rt.layout,
            env: env,
            onInput: _onInput,
            errors: widget.run?.errors ?? const {},
          ),
        if (note.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.lg),
            child: Text(note,
                textAlign: TextAlign.center,
                style: AppType.micro.copyWith(color: AppColors.textTertiary)),
          ),
        if (widget.footer != null) widget.footer!,
      ],
    );
  }

  String _hm(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true)
        .add(const Duration(hours: 8));
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}
