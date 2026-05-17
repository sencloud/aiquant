/// IapService —— 把 App Store 内购 / Google Play Billing 抽象到接口后面。
///
/// 当前阶段：
/// - 默认绑定 [MockIapService]：纯客户端模拟，用于 backend env=dev + MockIAPVerifier 联调；
/// - 上线前：替换为基于 in_app_purchase 的真实实现，并把 backend 的 IAP verifier
///   切到 AppleIAPVerifier。
library;

class IapPurchaseResult {
  IapPurchaseResult({
    required this.transactionId,
    required this.productId,
    required this.jwsReceipt,
    required this.purchasedAtMs,
  });

  /// 渠道交易号（Apple transactionId）。Mock 实现里就是随机字符串。
  final String transactionId;

  /// 实际购买的 product_id（与 SKU.appleProductId 对齐）。
  final String productId;

  /// 验签时上送给后端的 receipt：
  /// - Apple 真实环境：transaction JWS（App Store Server API 风格）；
  /// - Mock：`mock_<transactionId>_<productId>_<purchasedAtMs>`。
  final String jwsReceipt;

  final int purchasedAtMs;
}

class IapException implements Exception {
  IapException(this.message, {this.userCanceled = false});
  final String message;
  final bool userCanceled;

  @override
  String toString() => 'IapException($message)';
}

abstract class IapService {
  /// 执行一次性购买。
  ///
  /// - [productId] 与 SKU.appleProductId 对齐；
  /// - 返回 [IapPurchaseResult]，由 BillingService 上送 backend 验签发币；
  /// - 用户主动取消 → 抛 [IapException]，且 userCanceled=true，UI 不应提示错误。
  Future<IapPurchaseResult> purchase(String productId);
}

/// MockIapService：客户端不弹 IAP 弹窗，直接构造一个 backend MockIAPVerifier
/// 能识别的 receipt。配合 backend env=dev 使用。
class MockIapService implements IapService {
  @override
  Future<IapPurchaseResult> purchase(String productId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final tx = 'mocktx$now';
    return IapPurchaseResult(
      transactionId: tx,
      productId: productId,
      jwsReceipt: 'mock_${tx}_${productId}_$now',
      purchasedAtMs: now,
    );
  }
}
