import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/api/auth_models.dart';
import '../../core/auth/require_login.dart';
import '../../screens/strategy/paywall.dart' show showInsufficientBalance;
import '../../state/billing_state.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import 'catch_editor_screen.dart';
import 'fishing_models.dart';
import 'fishing_state.dart';

/// 识鱼单价（与后端 fishing.IdentifyCredits 一致）。
const kIdentifyCredits = 3;

/// 识别结果必须展示的提示（后端也会下发同义文案）。
const kIdentifyDisclaimer = 'AI 识别仅供参考';

/// 拍照识鱼：选图 → 3 喜点识别（失败自动退回）→ 候选鱼种 → 一键记入渔获。
class IdentifyScreen extends StatefulWidget {
  const IdentifyScreen({super.key, this.initialImage});

  /// 测试 / 外部入口直接带图。
  final Uint8List? initialImage;

  @override
  State<IdentifyScreen> createState() => _IdentifyScreenState();
}

class _IdentifyScreenState extends State<IdentifyScreen> {
  Uint8List? _image;
  String _requestId = '';
  bool _busy = false;
  FishIdentification? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialImage != null) _setImage(widget.initialImage!);
  }

  void _setImage(Uint8List b) {
    _image = b;
    // 每张图一个 request_id：同一张图重试不会重复扣费。
    _requestId = 'fi-${const Uuid().v4()}';
    _result = null;
    _error = null;
  }

  Future<void> _pick(ImageSource src) async {
    try {
      final x = await ImagePicker().pickImage(
          source: src, maxWidth: 1024, maxHeight: 1024, imageQuality: 80);
      if (x == null) return;
      final b = await x.readAsBytes();
      if (!mounted) return;
      setState(() => _setImage(b));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('没拿到照片，请检查相机 / 相册权限')));
    }
  }

  Future<void> _identify() async {
    final img = _image;
    if (img == null || _busy) return;
    if (!await requireLogin(context)) return;
    if (!mounted) return;
    final fs = context.read<FishingState>();
    final billing = context.read<BillingState>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final (r, _) = await fs.api.identify(requestId: _requestId, jpeg: img);
      if (!mounted) return;
      setState(() => _result = r);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 402) {
        await showInsufficientBalance(context,
            need: kIdentifyCredits, what: '拍照识鱼');
      } else {
        setState(() => _error = e.statusCode == 409
            ? '正在识别中，请稍候再看'
            : e.statusCode == 503
                ? '识鱼服务暂未开放'
                : '识别失败：${e.message}');
      }
    } catch (_) {
      if (mounted) setState(() => _error = '网络不太好，稍后重试（不会重复扣费）');
    } finally {
      // ignore: unawaited_futures
      billing.refreshBalance();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return WkPage(
      title: '拍照识鱼',
      child: ListView(
        padding: const EdgeInsets.all(AppSpace.gutter),
        children: [
          _photoBox(),
          const SizedBox(height: AppSpace.md),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _pick(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('拍照'),
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('相册'),
              ),
            ),
          ]),
          const SizedBox(height: AppSpace.md),
          if (r == null) ...[
            WkPrimaryButton(
              key: const Key('identify-go'),
              label: '开始识别 · $kIdentifyCredits 喜点',
              icon: Icons.search_rounded,
              busy: _busy,
              onPressed: _image == null ? null : _identify,
            ),
            const SizedBox(height: AppSpace.sm),
            Text('识别失败或没认出鱼会自动退回喜点；让鱼体完整、侧面入镜更准。',
                textAlign: TextAlign.center,
                style: AppType.caption.copyWith(color: AppColors.textTertiary)),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpace.md),
            WkNote(text: _error!),
          ],
          if (r != null) ..._resultView(r),
        ],
      ),
    );
  }

  Widget _photoBox() {
    final img = _image;
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.bgSurface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        clipBehavior: Clip.antiAlias,
        child: img == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.set_meal_outlined,
                      size: 40, color: AppColors.textTertiary),
                  const SizedBox(height: AppSpace.sm),
                  Text('拍一张鱼的侧面照',
                      style:
                          AppType.body.copyWith(color: AppColors.textTertiary)),
                ],
              )
            : Image.memory(img, fit: BoxFit.cover),
      ),
    );
  }

  List<Widget> _resultView(FishIdentification r) {
    if (!r.ok) {
      return [
        WkNote(
          title: r.refunded ? '没认出来，喜点已退回' : '没认出来',
          text: r.error.isNotEmpty ? r.error : '换个角度、让鱼体完整入镜再试试。',
        ),
        const SizedBox(height: AppSpace.md),
        OutlinedButton(
            onPressed: () => setState(() => _result = null),
            child: const Text('换张照片')),
      ];
    }
    final protected = r.candidates.any((c) => c.protected);
    return [
      Container(
        key: const Key('identify-disclaimer'),
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: AppColors.accentSoft,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(children: [
          Icon(Icons.info_outline_rounded, size: 18, color: AppColors.amber),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              r.disclaimer.isNotEmpty ? r.disclaimer : kIdentifyDisclaimer,
              style: AppType.caption
                  .copyWith(color: AppColors.textPrimary, height: 1.5),
            ),
          ),
        ]),
      ),
      const SizedBox(height: AppSpace.md),
      if (protected) ...[
        Container(
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            color: AppColors.danger.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Text('疑似国家重点保护水生野生动物：请立即放流，不得捕捞、出售。',
              style: AppType.body.copyWith(color: AppColors.danger)),
        ),
        const SizedBox(height: AppSpace.md),
      ],
      WkGroup(
        header: '可能是',
        children: [
          for (final c in r.candidates)
            Padding(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(c.name,
                        style: AppType.title
                            .copyWith(color: AppColors.textPrimary)),
                    const SizedBox(width: AppSpace.sm),
                    if (c.latin.isNotEmpty)
                      Flexible(
                        child: Text(c.latin,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.caption.copyWith(
                                color: AppColors.textTertiary,
                                fontStyle: FontStyle.italic)),
                      ),
                    const Spacer(),
                    if (c.protected)
                      const WkTag('保护', tone: AppColors.danger, filled: true),
                    const SizedBox(width: AppSpace.xs),
                    Text('${(c.confidence * 100).round()}%',
                        style: AppType.body.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.amber)),
                  ]),
                  if (c.features.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.xs),
                    Text(c.features,
                        style: AppType.caption.copyWith(
                            color: AppColors.textSecondary, height: 1.5)),
                  ],
                  if (c.note.isNotEmpty) ...[
                    const SizedBox(height: AppSpace.xs),
                    Text(c.note,
                        style: AppType.caption.copyWith(
                            color: c.protected
                                ? AppColors.danger
                                : AppColors.textTertiary)),
                  ],
                ],
              ),
            ),
        ],
      ),
      if (r.tips.isNotEmpty) ...[
        WkNote(text: r.tips),
        const SizedBox(height: AppSpace.md),
      ],
      WkPrimaryButton(
        label: protected ? '记入渔获（标记放流）' : '记入渔获',
        icon: Icons.edit_note_rounded,
        onPressed: () => Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => CatchEditorScreen(
              initialSpecies: r.candidates.first.name,
              initialPhoto: _image,
              initialReleased: protected,
            ),
          ),
        ),
      ),
    ];
  }
}
