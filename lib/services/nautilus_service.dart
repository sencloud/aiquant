import '../core/api/api_client.dart';
import '../models/nautilus.dart';

/// NautilusService 封装 /v1/nautilus/* 的 HTTP 调用。
///
/// 市场浏览(list/get)是公开接口，未登录也能调；
/// 下注 / 钱包 / 邀请需要 JWT，未登录调用会 401。
class NautilusService {
  NautilusService({ApiClient? client}) : _client = client ?? ApiClient.instance;
  final ApiClient _client;

  /// 列市场。[category] 取 weather / finance，空串拉全部。
  Future<({List<PredictMarket> items, int minBet})> listMarkets({
    String category = '',
    int limit = 50,
  }) async {
    final r = await _client.dio.get<Map<String, dynamic>>(
      '/v1/nautilus/markets',
      queryParameters: {
        if (category.isNotEmpty) 'category': category,
        'limit': limit,
      },
    );
    final data = r.data!;
    final items = (data['items'] as List<dynamic>? ?? [])
        .map((e) => PredictMarket.fromJson(e as Map<String, dynamic>))
        .toList();
    return (items: items, minBet: (data['min_bet'] as num?)?.toInt() ?? 10);
  }

  Future<PredictMarket> getMarket(int id) async {
    final r =
        await _client.dio.get<Map<String, dynamic>>('/v1/nautilus/markets/$id');
    return PredictMarket.fromJson(r.data!);
  }

  /// 下注。返回 (最新市场快照, 最新余额)。
  Future<({PredictMarket market, int balance})> placeBet({
    required int marketId,
    required int optionId,
    required int amount,
  }) async {
    final r = await _client.dio.post<Map<String, dynamic>>(
      '/v1/nautilus/markets/$marketId/bet',
      data: {'option_id': optionId, 'amount': amount},
    );
    final data = r.data!;
    return (
      market: PredictMarket.fromJson(data['market'] as Map<String, dynamic>),
      balance: (data['balance'] as num?)?.toInt() ?? 0,
    );
  }

  Future<List<ShellBet>> myMarketBets(int marketId) async {
    final r = await _client.dio
        .get<Map<String, dynamic>>('/v1/nautilus/markets/$marketId/my-bets');
    return (r.data!['items'] as List<dynamic>? ?? [])
        .map((e) => ShellBet.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 余额 + 流水。
  Future<({int balance, List<ShellLedgerEntry> items})> shells(
      {int limit = 50}) async {
    final r = await _client.dio.get<Map<String, dynamic>>(
      '/v1/nautilus/shells',
      queryParameters: {'limit': limit},
    );
    final data = r.data!;
    return (
      balance: (data['balance'] as num?)?.toInt() ?? 0,
      items: (data['items'] as List<dynamic>? ?? [])
          .map((e) => ShellLedgerEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<List<ShellBet>> myBets({int limit = 50}) async {
    final r = await _client.dio.get<Map<String, dynamic>>(
      '/v1/nautilus/bets',
      queryParameters: {'limit': limit},
    );
    return (r.data!['items'] as List<dynamic>? ?? [])
        .map((e) => ShellBet.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<InviteInfo> inviteInfo() async {
    final r =
        await _client.dio.get<Map<String, dynamic>>('/v1/nautilus/invite');
    return InviteInfo.fromJson(r.data!);
  }

  /// 填写邀请码，返回 (邀请信息, 最新余额)。
  Future<({InviteInfo info, int balance})> redeemInvite(String code) async {
    final r = await _client.dio.post<Map<String, dynamic>>(
      '/v1/nautilus/invite/redeem',
      data: {'code': code},
    );
    final data = r.data!;
    return (
      info: InviteInfo.fromJson(data['info'] as Map<String, dynamic>),
      balance: (data['balance'] as num?)?.toInt() ?? 0,
    );
  }
}
