import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/portfolio.dart';
import '../../../state/portfolio_state.dart';
import '../../../theme/app_theme.dart';

class PortfolioCommandBar extends StatelessWidget {
  const PortfolioCommandBar({
    super.key,
    required this.onCreate,
    this.onAddAsset,
    this.onDelete,
  });

  final VoidCallback onCreate;
  final VoidCallback? onAddAsset;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final ps = context.watch<PortfolioState>();
    final active = ps.activeId == null
        ? null
        : ps.portfoliosForId(ps.activeId!);

    return Container(
      height: 48,
      color: AppColors.bgSurface,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: _selector(context, ps, active),
          ),
          IconButton(
            tooltip: '新建组合',
            icon: const Icon(Icons.create_new_folder_outlined,
                color: AppColors.amber, size: 18),
            onPressed: onCreate,
          ),
          IconButton(
            tooltip: '加入品种',
            icon: const Icon(Icons.playlist_add,
                color: AppColors.amber, size: 18),
            onPressed: onAddAsset,
          ),
          IconButton(
            tooltip: '删除组合',
            icon: const Icon(Icons.delete_outline,
                color: AppColors.negative, size: 18),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }

  Widget _selector(
    BuildContext context,
    PortfolioState ps,
    Portfolio? active,
  ) {
    if (ps.portfolios.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Text('暂无组合',
            style:
                TextStyle(color: AppColors.textTertiary, fontSize: 12)),
      );
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showSelector(context, ps),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              const Icon(Icons.folder_open,
                  color: AppColors.amber, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  active == null
                      ? '选择组合'
                      : '${active.name} · ${active.currency}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                ),
              ),
              Icon(Icons.keyboard_arrow_down,
                  color: AppColors.textTertiary, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showSelector(BuildContext context, PortfolioState ps) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgSurface,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text('选择组合',
                  style: TextStyle(
                      color: AppColors.amber,
                      fontSize: 13,
                      fontWeight: FontWeight.w800)),
            ),
            Divider(height: 1, color: AppColors.borderDim),
            for (final p in ps.portfolios)
              ListTile(
                dense: true,
                title: Text(p.name,
                    style: TextStyle(
                        color: AppColors.textPrimary, fontSize: 13)),
                subtitle: Text(p.currency,
                    style: TextStyle(
                        color: AppColors.textTertiary, fontSize: 11)),
                trailing: p.id == ps.activeId
                    ? const Icon(Icons.check, color: AppColors.amber)
                    : null,
                onTap: () {
                  ps.selectPortfolio(p.id);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }
}
