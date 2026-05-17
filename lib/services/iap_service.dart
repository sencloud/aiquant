/// IapService —— 把 App Store 内购 / Google Play Billing 抽象到接口后面。
///
/// - [MockIapService]：纯客户端模拟，用于 backend env=dev + MockIAPVerifier 联调；
/// - [AppleIapService]：基于 `in_app_purchase` 的真实 StoreKit 实现，配合后端
///   AppleIAPVerifier。仅 iOS 启用。
library;

import 'dart:async';
import 'dart:io' show Platform;

import 'package:in_app_purchase/in_app_purchase.dart';

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
  /// - Apple 真实环境：`PurchaseDetails.verificationData.serverVerificationData`
  ///   （StoreKit 2 JWS / StoreKit 1 base64 收据）
  /// - Mock：`mock_<transactionId>_<productId>_<purchasedAtMs>`
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

/// AppleIapService —— iOS StoreKit 1/2 真实实现。
///
/// 工作流：
///  1. `queryProductDetails` 校验后端 SKU 与 App Store Connect 配置一致；
///  2. `buyConsumable(...)` 弹出 StoreKit；
///  3. 通过 `purchaseStream` 监听最终 PurchaseStatus；
///  4. 拿 `verificationData.serverVerificationData`（base64 JWS）→ 上送后端；
///  5. 后端验签成功后再 `completePurchase` 让 StoreKit 标这笔交易已 finalize。
///
/// 注意：
/// - **必须**在调起后端验签**成功**后再调 `completePurchase`，否则 Apple 会持续
///   返回 pending；
/// - 这里只对外暴露 [purchase] 同步语义；BillingState 上送验签的步骤需要把
///   completion 通过 [confirm] 显式回调。
///
/// 为简化主流程，本实现里 [purchase] 内部已经把"等待 PurchaseStatus
/// .purchased / .restored → 取 receipt"的部分串好，BillingState 验签成功后
/// 调 [confirm] 完成 finalize。
class AppleIapService implements IapService {
  AppleIapService();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  Completer<IapPurchaseResult>? _pending;
  PurchaseDetails? _pendingDetails;
  String? _pendingProductId;

  bool _initialized = false;

  Future<void> _ensureInit() async {
    if (_initialized) return;
    if (!Platform.isIOS && !Platform.isMacOS) {
      throw IapException('当前平台不支持内购，请在 iOS 设备上购买。');
    }
    final available = await _iap.isAvailable();
    if (!available) {
      throw IapException('App Store 不可用，请检查登录状态后重试。');
    }
    _sub = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (Object e) {
        final c = _pending;
        if (c != null && !c.isCompleted) {
          c.completeError(IapException('内购出错：$e'));
        }
      },
    );
    _initialized = true;
  }

  @override
  Future<IapPurchaseResult> purchase(String productId) async {
    await _ensureInit();
    if (_pending != null) {
      throw IapException('已有进行中的购买，请稍候。');
    }
    final detail = await _iap.queryProductDetails({productId});
    if (detail.error != null) {
      throw IapException('查询商品失败：${detail.error!.message}');
    }
    if (detail.notFoundIDs.contains(productId) ||
        detail.productDetails.isEmpty) {
      throw IapException('App Store 未找到该商品：$productId');
    }
    final product = detail.productDetails.first;

    _pending = Completer<IapPurchaseResult>();
    _pendingProductId = productId;
    _pendingDetails = null;

    final ok = await _iap.buyConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
      autoConsume: false,
    );
    if (!ok) {
      _pending = null;
      _pendingProductId = null;
      throw IapException('App Store 拒绝了购买请求。');
    }
    return _pending!.future;
  }

  /// BillingState 在后端验签成功后调用，最终让 StoreKit 把这笔交易标 finalized。
  Future<void> confirm() async {
    final d = _pendingDetails;
    if (d == null) return;
    if (d.pendingCompletePurchase) {
      await _iap.completePurchase(d);
    }
    _pendingDetails = null;
    _pending = null;
    _pendingProductId = null;
  }

  /// 验签失败 / 中途取消时调用，把内部 pending 清掉，等下次再发起。
  void abort() {
    _pendingDetails = null;
    _pending = null;
    _pendingProductId = null;
  }

  void _handlePurchaseUpdates(List<PurchaseDetails> updates) {
    for (final pd in updates) {
      if (_pendingProductId != null && pd.productID != _pendingProductId) {
        // 不是当前正在等待的商品（比如未 finalize 的旧交易），如果还没
        // complete，也调 completePurchase 防止队列卡住。
        if (pd.pendingCompletePurchase) {
          _iap.completePurchase(pd);
        }
        continue;
      }
      switch (pd.status) {
        case PurchaseStatus.pending:
          break;
        case PurchaseStatus.canceled:
          final c = _pending;
          _pending = null;
          _pendingDetails = null;
          _pendingProductId = null;
          if (c != null && !c.isCompleted) {
            c.completeError(
              IapException('用户取消购买', userCanceled: true),
            );
          }
          break;
        case PurchaseStatus.error:
          final c = _pending;
          _pending = null;
          _pendingDetails = null;
          _pendingProductId = null;
          if (c != null && !c.isCompleted) {
            c.completeError(
              IapException(pd.error?.message ?? '内购失败'),
            );
          }
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          _pendingDetails = pd;
          final c = _pending;
          if (c != null && !c.isCompleted) {
            final txId = pd.purchaseID ??
                pd.transactionDate ??
                'unknown_${DateTime.now().millisecondsSinceEpoch}';
            final tsStr = pd.transactionDate ?? '';
            int ts;
            try {
              ts = int.parse(tsStr);
            } catch (_) {
              ts = DateTime.now().millisecondsSinceEpoch;
            }
            c.complete(
              IapPurchaseResult(
                transactionId: txId,
                productId: pd.productID,
                jwsReceipt: pd.verificationData.serverVerificationData,
                purchasedAtMs: ts,
              ),
            );
          }
          break;
      }
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _initialized = false;
  }
}
