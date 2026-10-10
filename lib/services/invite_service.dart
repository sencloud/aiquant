import '../core/api/api_client.dart';

/// 邀请好友：填码双方各得喜点（/v1/invite，需登录）。
///
/// 邀请原本挂在鹦鹉螺下、奖励螺壳；鹦鹉螺隐藏、螺壳冻结后改发喜点，
/// 接口也独立出来。
class InviteService {
  InviteService({ApiClient? client}) : _client = client ?? ApiClient.instance;
  final ApiClient _client;

  Future<CreditInviteInfo> info() async {
    final r = await _client.dio.get<Map<String, dynamic>>('/v1/invite');
    return CreditInviteInfo.fromJson(r.data ?? const {});
  }

  /// 填写好友的邀请码，返回 (邀请信息, 最新喜点余额)。
  Future<({CreditInviteInfo info, int balance})> redeem(String code) async {
    final r = await _client.dio.post<Map<String, dynamic>>(
      '/v1/invite/redeem',
      data: {'code': code},
    );
    final data = r.data ?? const {};
    return (
      info: CreditInviteInfo.fromJson(
          (data['info'] as Map?)?.cast<String, dynamic>() ?? const {}),
      balance: (data['balance'] as num?)?.toInt() ?? 0,
    );
  }
}

class CreditInviteInfo {
  const CreditInviteInfo({
    required this.code,
    required this.invitedCount,
    required this.totalReward,
    required this.rewardEach,
    required this.redeemed,
  });

  final String code;
  final int invitedCount;

  /// 累计获得的邀请奖励（喜点）。
  final int totalReward;

  /// 每成功邀请一人，双方各得多少喜点。
  final int rewardEach;

  /// 我自己是否已经填过别人的码。
  final bool redeemed;

  factory CreditInviteInfo.fromJson(Map<String, dynamic> j) => CreditInviteInfo(
        code: '${j['code'] ?? ''}',
        invitedCount: (j['invited_count'] as num?)?.toInt() ?? 0,
        totalReward: (j['total_reward'] as num?)?.toInt() ?? 0,
        rewardEach: (j['reward_each'] as num?)?.toInt() ?? 100,
        redeemed: j['redeemed'] == true,
      );
}
