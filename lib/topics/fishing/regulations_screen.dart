import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import 'fishing_models.dart';

/// 全国性流域禁渔 / 休渔制度一览。不含省市细则，固定提示以当地公告为准。
class RegulationsScreen extends StatelessWidget {
  const RegulationsScreen({super.key, required this.regs});
  final FishingRegulations? regs;

  @override
  Widget build(BuildContext context) {
    final items = regs?.items ?? const <FishingRegulation>[];
    return WkPage(
      title: '禁渔期',
      child: ListView(
        padding: const EdgeInsets.all(AppSpace.gutter),
        children: [
          WkNote(
            title: '以当地公告为准',
            text: regs?.disclaimer.isNotEmpty == true
                ? regs!.disclaimer
                : '以下为全国性流域禁渔制度摘要，各地另有规定，以当地渔政部门公告为准。电鱼、炸鱼、毒鱼任何时候都违法。',
          ),
          const SizedBox(height: AppSpace.md),
          if (items.isEmpty)
            const WkEmpty(
                icon: Icons.cloud_off_rounded, title: '暂时没拉到禁渔信息，稍后再试')
          else
            for (final r in items)
              WkGroup(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(AppSpace.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text(r.name,
                                  style: AppType.body
                                      .copyWith(fontWeight: FontWeight.w600))),
                          if (r.active)
                            const WkTag('今日生效',
                                tone: AppColors.danger, filled: true),
                        ]),
                        const SizedBox(height: AppSpace.sm),
                        _kv('水域', r.waters),
                        _kv('时间', r.period),
                        _kv('禁止', r.scope),
                        _kv('垂钓', r.angling),
                        _kv('依据', r.source),
                      ],
                    ),
                  ),
                ],
              ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 40,
                child: Text(k,
                    style: AppType.caption
                        .copyWith(color: AppColors.textTertiary))),
            Expanded(
                child: Text(v,
                    style: AppType.caption.copyWith(
                        color: AppColors.textSecondary, height: 1.5))),
          ],
        ),
      );
}
