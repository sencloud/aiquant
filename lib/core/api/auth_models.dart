/// 后端鉴权接口的请求/响应模型。
///
/// 命名风格保持与服务端 JSON 字段一致（snake_case），通过 fromJson/toJson 与
/// Dart 侧 camelCase 字段对齐。
class TokenPair {
  TokenPair({
    required this.accessToken,
    required this.accessExpiresIn,
    required this.refreshToken,
    required this.refreshExpiresIn,
    required this.issuedAt,
  });

  final String accessToken;
  final int accessExpiresIn;
  final String refreshToken;
  final int refreshExpiresIn;
  final DateTime issuedAt;

  DateTime get accessExpiresAt =>
      issuedAt.add(Duration(seconds: accessExpiresIn));
  DateTime get refreshExpiresAt =>
      issuedAt.add(Duration(seconds: refreshExpiresIn));

  /// access 提前 60s 视为过期，避免临界态请求被中断。
  bool get accessNearlyExpired =>
      DateTime.now().isAfter(accessExpiresAt.subtract(const Duration(seconds: 60)));
  bool get refreshExpired => DateTime.now().isAfter(refreshExpiresAt);

  factory TokenPair.fromJson(Map<String, dynamic> j, {DateTime? issuedAt}) =>
      TokenPair(
        accessToken: j['access_token'] as String,
        accessExpiresIn: (j['access_expires_in'] as num).toInt(),
        refreshToken: j['refresh_token'] as String,
        refreshExpiresIn: (j['refresh_expires_in'] as num).toInt(),
        issuedAt: issuedAt ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'access_expires_in': accessExpiresIn,
        'refresh_token': refreshToken,
        'refresh_expires_in': refreshExpiresIn,
        'issued_at_ms': issuedAt.millisecondsSinceEpoch,
      };

  factory TokenPair.fromStored(Map<String, dynamic> j) => TokenPair(
        accessToken: j['access_token'] as String,
        accessExpiresIn: (j['access_expires_in'] as num).toInt(),
        refreshToken: j['refresh_token'] as String,
        refreshExpiresIn: (j['refresh_expires_in'] as num).toInt(),
        issuedAt:
            DateTime.fromMillisecondsSinceEpoch((j['issued_at_ms'] as num).toInt()),
      );
}

class UserPublic {
  UserPublic({
    required this.uuid,
    required this.nickname,
    required this.status,
    required this.creditBalance,
    required this.hasPhone,
    required this.hasApple,
    required this.createdAt,
  });

  final String uuid;
  final String nickname;
  final String status;
  final int creditBalance;
  final bool hasPhone;
  final bool hasApple;
  final DateTime createdAt;

  bool get isActive => status == 'active';

  factory UserPublic.fromJson(Map<String, dynamic> j) => UserPublic(
        uuid: j['uuid'] as String,
        nickname: (j['nickname'] as String?) ?? '',
        status: j['status'] as String,
        creditBalance: (j['credit_balance'] as num).toInt(),
        hasPhone: j['has_phone'] as bool? ?? false,
        hasApple: j['has_apple'] as bool? ?? false,
        createdAt:
            DateTime.fromMillisecondsSinceEpoch((j['created_at'] as num).toInt()),
      );

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'nickname': nickname,
        'status': status,
        'credit_balance': creditBalance,
        'has_phone': hasPhone,
        'has_apple': hasApple,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  UserPublic copyWith({String? nickname, int? creditBalance, String? status}) =>
      UserPublic(
        uuid: uuid,
        nickname: nickname ?? this.nickname,
        status: status ?? this.status,
        creditBalance: creditBalance ?? this.creditBalance,
        hasPhone: hasPhone,
        hasApple: hasApple,
        createdAt: createdAt,
      );
}

/// 服务端统一错误形态。
class ApiException implements Exception {
  ApiException({
    required this.code,
    required this.message,
    required this.statusCode,
    this.requestId,
  });

  final String code;
  final String message;
  final int statusCode;
  final String? requestId;

  bool get isUnauthorized => statusCode == 401;
  bool get isRateLimited => statusCode == 429;

  @override
  String toString() => '[$statusCode] $code: $message';
}
