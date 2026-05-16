import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// 推理过程展示块（默认折叠，可点击展开）。
/// 流式中默认展开，结束后默认折叠。
class ReasoningBlock extends StatefulWidget {
  const ReasoningBlock({
    super.key,
    required this.text,
    required this.streaming,
  });

  final String text;
  final bool streaming;

  @override
  State<ReasoningBlock> createState() => _ReasoningBlockState();
}

class _ReasoningBlockState extends State<ReasoningBlock> {
  bool? _userOverrideExpanded;

  @override
  Widget build(BuildContext context) {
    final expanded = _userOverrideExpanded ?? widget.streaming;
    return Container(
      margin: const EdgeInsets.only(bottom: 6, top: 2),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        border: Border.all(color: AppColors.borderDim),
        borderRadius: const BorderRadius.all(Radius.circular(6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() {
              _userOverrideExpanded = !expanded;
            }),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.psychology_outlined,
                      size: 12, color: AppColors.amber),
                  const SizedBox(width: 4),
                  const Text(
                    '深度推理',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.amber,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (widget.streaming)
                    Text(
                      '· 思考中…',
                      style: TextStyle(
                          fontSize: 10, color: AppColors.textTertiary),
                    ),
                  const Spacer(),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: AppColors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Text(
                widget.text,
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 11,
                  height: 1.45,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
