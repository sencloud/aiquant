/// 鹦鹉螺预测市场的数据模型，对应后端 /v1/nautilus/*。
library;

int _asInt(dynamic v) => v is int ? v : (v as num?)?.toInt() ?? 0;
String _asStr(dynamic v) => v as String? ?? '';

/// 市场选项（互斥结果之一）。
class MarketOption {
  const MarketOption({
    required this.id,
    required this.idx,
    required this.label,
    required this.poolShells,
    required this.bettorCount,
  });

  final int id;
  final int idx;
  final String label;
  final int poolShells;
  final int bettorCount;

  factory MarketOption.fromJson(Map<String, dynamic> j) => MarketOption(
        id: _asInt(j['id']),
        idx: _asInt(j['idx']),
        label: _asStr(j['label']),
        poolShells: _asInt(j['pool_shells']),
        bettorCount: _asInt(j['bettor_count']),
      );
}

/// 一个预测市场（含选项与池子聚合）。
class PredictMarket {
  const PredictMarket({
    required this.id,
    required this.category,
    required this.title,
    required this.description,
    required this.status,
    required this.closeAt,
    required this.resolveAt,
    required this.resolveKind,
    required this.options,
    required this.totalPool,
    required this.resolvedOptionId,
    required this.rakeBps,
  });

  final int id;
  final String category; // weather / finance
  final String title;
  final String description;
  final String status; // open / closed / settled / cancelled
  final int closeAt;
  final int resolveAt;
  final String resolveKind;
  final List<MarketOption> options;
  final int totalPool;
  final int resolvedOptionId;
  final int rakeBps;

  bool get isOpen =>
      status == 'open' && DateTime.now().millisecondsSinceEpoch < closeAt;
  bool get isSettled => status == 'settled';
  bool get isCancelled => status == 'cancelled';

  /// 全部选项的下注人数合计（热度）。
  int get totalBettors => options.fold(0, (s, o) => s + o.bettorCount);

  /// 是否临近截止（6 小时内），用于高亮提醒。
  bool get closingSoon {
    if (!isOpen) return false;
    final left = closeAt - DateTime.now().millisecondsSinceEpoch;
    return left > 0 && left <= 6 * 60 * 60 * 1000;
  }

  /// 是否天气类自动结算（用于详情页展示结算来源）。
  bool get isWeatherAuto => category == 'weather' && resolveKind == 'auto';

  /// 选项当前的隐含赔率（含本金倍数）。池子为空时返回 0 表示"待定"。
  double oddsFor(MarketOption o) {
    if (o.poolShells <= 0) return 0;
    final distributable = totalPool * (1 - rakeBps / 10000);
    return distributable / o.poolShells;
  }

  /// 选项占总池比例 0~1。
  double shareFor(MarketOption o) =>
      totalPool <= 0 ? 0 : o.poolShells / totalPool;

  factory PredictMarket.fromJson(Map<String, dynamic> j) => PredictMarket(
        id: _asInt(j['id']),
        category: _asStr(j['category']),
        title: _asStr(j['title']),
        description: _asStr(j['description']),
        status: _asStr(j['status']),
        closeAt: _asInt(j['close_at']),
        resolveAt: _asInt(j['resolve_at']),
        resolveKind: _asStr(j['resolve_kind']),
        options: (j['options'] as List<dynamic>? ?? [])
            .map((e) => MarketOption.fromJson(e as Map<String, dynamic>))
            .toList(),
        totalPool: _asInt(j['total_pool']),
        resolvedOptionId: _asInt(j['resolved_option_id']),
        rakeBps: _asInt(j['rake_bps']),
      );
}

/// 我的一笔下注。
class ShellBet {
  const ShellBet({
    required this.id,
    required this.marketId,
    required this.optionId,
    required this.amount,
    required this.payout,
    required this.status,
    required this.createdAt,
    this.marketTitle = '',
    this.marketStatus = '',
    this.marketCategory = '',
    this.optionLabel = '',
  });

  final int id;
  final int marketId;
  final int optionId;
  final int amount;
  final int payout;
  final String status; // active / won / lost / refunded
  final int createdAt;
  final String marketTitle;
  final String marketStatus;
  final String marketCategory;
  final String optionLabel;

  factory ShellBet.fromJson(Map<String, dynamic> j) => ShellBet(
        id: _asInt(j['id']),
        marketId: _asInt(j['market_id']),
        optionId: _asInt(j['option_id']),
        amount: _asInt(j['amount']),
        payout: _asInt(j['payout']),
        status: _asStr(j['status']),
        createdAt: _asInt(j['created_at']),
        marketTitle: _asStr(j['market_title']),
        marketStatus: _asStr(j['market_status']),
        marketCategory: _asStr(j['market_category']),
        optionLabel: _asStr(j['option_label']),
      );
}

/// 螺壳流水。
class ShellLedgerEntry {
  const ShellLedgerEntry({
    required this.id,
    required this.delta,
    required this.balanceAfter,
    required this.reason,
    required this.remark,
    required this.createdAt,
  });

  final int id;
  final int delta;
  final int balanceAfter;
  final String reason;
  final String remark;
  final int createdAt;

  String get reasonLabel => switch (reason) {
        'signup_gift' => '注册赠送',
        'invite_reward' => '邀请奖励',
        'bet_stake' => '下注',
        'bet_payout' => '赢得奖池',
        'bet_refund' => '退款',
        'admin_adjust' => '运营调整',
        _ => reason,
      };

  factory ShellLedgerEntry.fromJson(Map<String, dynamic> j) =>
      ShellLedgerEntry(
        id: _asInt(j['id']),
        delta: _asInt(j['delta']),
        balanceAfter: _asInt(j['balance_after']),
        reason: _asStr(j['reason']),
        remark: _asStr(j['remark']),
        createdAt: _asInt(j['created_at']),
      );
}

/// 邀请页聚合信息。
class InviteInfo {
  const InviteInfo({
    required this.code,
    required this.invitedCount,
    required this.totalReward,
    required this.rewardEach,
    required this.redeemed,
  });

  final String code;
  final int invitedCount;
  final int totalReward;
  final int rewardEach;
  final bool redeemed;

  factory InviteInfo.fromJson(Map<String, dynamic> j) => InviteInfo(
        code: _asStr(j['code']),
        invitedCount: _asInt(j['invited_count']),
        totalReward: _asInt(j['total_reward']),
        rewardEach: _asInt(j['reward_each']),
        redeemed: j['redeemed'] as bool? ?? false,
      );
}
