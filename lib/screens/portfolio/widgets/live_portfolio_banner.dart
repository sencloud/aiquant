import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/auth/require_login.dart';
import '../../../services/analytics.dart';
import '../../../state/auth_state.dart';
import '../../../state/portfolio_state.dart';
import '../../../theme/app_theme.dart';
import '../../strategy/live_strategy_screen.dart';

/// 组合页顶部的「策略模拟」条（策略模拟资金，非实盘）：
///   - 选中策略模拟组合时：模拟口径 + 截至日 + 总资产/现金/累计盈亏 + 进策略详情；
///   - 未登录时：提示登录后自动同步策略模拟组合（原「策略 → 实盘」入口搬到这里）。
class LivePortfolioBanner extends StatelessWidget {
  const LivePortfolioBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final ps = context.watch<PortfolioState>();
    final authed = context.watch<AuthState>().isAuthenticated;
    if (!authed) return const _LoginCta();
    if (!ps.activeIsManaged) return const SizedBox.shrink();
    return const _LiveInfo();
  }
}

class _LiveInfo extends StatelessWidget {
  const _LiveInfo();

  @override
  Widget build(BuildContext context) {
    final ps = context.watch<PortfolioState>();
    final live = ps.liveMeta;
    final p = ps.activeId == null ? null : ps.portfoliosForId(ps.activeId!);
    final money = NumberFormat('#,##0');
    final subtitle = live == null
        ? (p?.description ?? '系统托管 · 只读')
        : '模拟资金 · 非实盘 · 截至 ${live.asOf}'
            '${live.stale ? ' · 已落后 ${live.staleDays} 个交易日' : ' · 每日更新'}';
    final basis = live == null
        ? ''
        : '名义本金 ${_capital(live.capital)} · ${live.inception} 起按策略调仓结论模拟'
            '${live.rebalanceCount > 0 ? '（${live.rebalanceCount} 期）' : ''} · 只读';
    final pnlColor =
        (live?.pnl ?? 0) >= 0 ? AppColors.positive : AppColors.negative;

    return Container(
      key: const ValueKey('live-portfolio-banner'),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.bgRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.amber.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.amber,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('模拟',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: live?.stale == true
                          ? AppColors.warning
                          : AppColors.textSecondary,
                      fontSize: 11),
                ),
              ),
              if (ps.liveSyncing)
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: () => _openDetail(context),
                child: const Text('策略详情 ›', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          if (live != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                _kv('总资产', money.format(live.total)),
                _kv('现金', money.format(live.cash)),
                _kv(
                  '累计盈亏',
                  '${live.pnl >= 0 ? '+' : ''}${money.format(live.pnl)}'
                      '（${(live.pnlPct * 100).toStringAsFixed(2)}%）',
                  color: pnlColor,
                ),
              ],
            ),
          ],
          if (basis.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              basis,
              style: TextStyle(
                  color: AppColors.textTertiary, fontSize: 10.5, height: 1.4),
            ),
          ],
          if (ps.liveError != null) ...[
            const SizedBox(height: 4),
            Text(ps.liveError!,
                style: TextStyle(color: AppColors.textTertiary, fontSize: 11)),
          ],
        ],
      ),
    );
  }

  static String _capital(double v) => v >= 10000 && v % 10000 == 0
      ? '${(v / 10000).toStringAsFixed(0)}万'
      : NumberFormat('#,##0').format(v);

  Widget _kv(String k, String v, {Color? color}) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k,
                style: TextStyle(color: AppColors.textTertiary, fontSize: 10)),
            const SizedBox(height: 2),
            Text(v,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: color ?? AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Future<void> _openDetail(BuildContext context) async {
    Analytics.instance.track(Analytics.evLiveEntry, {'from': 'portfolio'});
    if (!await requireLogin(context)) return;
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const LiveStrategyScreen(),
    ));
  }
}

class _LoginCta extends StatelessWidget {
  const _LoginCta();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppColors.bgRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderDim),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_balance_wallet_rounded,
              color: AppColors.amber, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('策略模拟：上证50 九因子',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('模拟资金 · 非实盘。登录后自动同步到组合管理，每天更新持仓与调仓记录',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          TextButton(
            onPressed: () async {
              Analytics.instance
                  .track(Analytics.evLiveEntry, {'from': 'portfolio_login'});
              await requireLogin(context);
            },
            child: const Text('登录查看'),
          ),
        ],
      ),
    );
  }
}
