import 'package:flutter/material.dart';

import '../../models/falsification.dart';
import '../../theme/app_theme.dart';
import '../../widgets/wk_kit.dart';
import 'archive_widgets.dart';

/// 顶部固定入口点进来的列表：可交易 / 仍在验证 / 本周新证伪。
class ArchiveListScreen extends StatelessWidget {
  const ArchiveListScreen({
    super.key,
    required this.title,
    required this.entries,
    required this.gates,
    required this.emptyTitle,
    required this.emptyHint,
    required this.onOpen,
  });

  final String title;
  final List<ArchiveEntry> entries;
  final List<FalsificationGate> gates;
  final String emptyTitle;
  final String emptyHint;
  final void Function(BuildContext context, ArchiveEntry entry) onOpen;

  @override
  Widget build(BuildContext context) {
    return WkPage(
      title: title,
      child: entries.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(AppSpace.xl),
              children: [
                const SizedBox(height: 48),
                WkEmpty(
                  icon: Icons.rule_folder_rounded,
                  title: emptyTitle,
                  hint: emptyHint,
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.gutter, AppSpace.lg, AppSpace.gutter, AppSpace.xxl),
              children: [
                WkGroup(
                  children: [
                    for (final e in entries)
                      ArchiveRow(
                        entry: e,
                        gates: gates,
                        onTap: () => onOpen(context, e),
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}
