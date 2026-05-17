import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../core/api/billing_models.dart';
import '../services/billing_service.dart';
import '../services/iap_service.dart';

/// BillingState 统一持有：
/// - 用户喜点余额
/// - 套餐列表
/// - 当前订单 / 错误
/// - 流水分页缓存
///
/// 它只在用户已登录时才被刷新；登出由 AuthState 通知 reset()。
class BillingState extends ChangeNotifier {
  BillingState({BillingService? service, IapService? iap})
      : _service = service ?? BillingService(),
        _iap = iap ?? _defaultIap() {
    _logoutSub = ApiClient.instance.onForcedLogout.listen((_) => reset());
  }

  static IapService _defaultIap() {
    if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
      return AppleIapService();
    }
    return MockIapService();
  }

  final BillingService _service;
  final IapService _iap;
  StreamSubscription<void>? _logoutSub;

  // ── 公开状态 ──────────────────────────────────────────────────────────
  int _balance = 0;
  int get balance => _balance;

  List<CreditSku> _skus = const [];
  List<CreditSku> get skus => _skus;

  bool _loadingSkus = false;
  bool get loadingSkus => _loadingSkus;

  bool _loadingBalance = false;
  bool get loadingBalance => _loadingBalance;

  CreditOrder? _pendingOrder;
  CreditOrder? get pendingOrder => _pendingOrder;

  bool _purchasing = false;
  bool get purchasing => _purchasing;

  String? _lastError;
  String? get lastError => _lastError;

  final List<CreditLedgerItem> _ledger = [];
  List<CreditLedgerItem> get ledger => List.unmodifiable(_ledger);
  int _ledgerCursor = 0;
  bool _ledgerHasMore = true;
  bool _loadingLedger = false;
  bool get loadingLedger => _loadingLedger;
  bool get ledgerHasMore => _ledgerHasMore;

  // ── 操作 ──────────────────────────────────────────────────────────────

  Future<void> refreshAll() async {
    await Future.wait([refreshBalance(), refreshSkus()]);
  }

  Future<void> refreshSkus() async {
    if (_loadingSkus) return;
    _loadingSkus = true;
    notifyListeners();
    try {
      _skus = await _service.listSkus();
      _lastError = null;
    } catch (e) {
      _lastError = _msg(e);
    } finally {
      _loadingSkus = false;
      notifyListeners();
    }
  }

  Future<void> refreshBalance() async {
    if (_loadingBalance) return;
    _loadingBalance = true;
    notifyListeners();
    try {
      _balance = await _service.getBalance();
      _lastError = null;
    } catch (e) {
      _lastError = _msg(e);
    } finally {
      _loadingBalance = false;
      notifyListeners();
    }
  }

  /// 创建订单（IAP 流程第一步）。
  Future<CreditOrder?> createOrder(String skuCode) async {
    try {
      final order = await _service.createOrder(skuCode: skuCode);
      _pendingOrder = order;
      _lastError = null;
      notifyListeners();
      return order;
    } catch (e) {
      _lastError = _msg(e);
      notifyListeners();
      return null;
    }
  }

  /// 凭 IAP receipt 完成发币。成功后立即刷新本地余额。
  Future<bool> verifyIap({
    required String orderNo,
    required String jwsReceipt,
  }) async {
    try {
      final r = await _service.verifyIap(
        orderNo: orderNo,
        jwsReceipt: jwsReceipt,
      );
      _balance = r.balance;
      _pendingOrder = r.order;
      _lastError = null;
      notifyListeners();
      // 顺手刷一下 ledger 头部
      await refreshLedger(reset: true);
      return true;
    } catch (e) {
      _lastError = _msg(e);
      notifyListeners();
      return false;
    }
  }

  /// 一键购买：创建订单 → 调起 IAP → 把 receipt 上传后端验签发币。
  ///
  /// 任一步失败 → lastError 已置好，UI 显示中文。返回是否成功到账。
  Future<bool> purchase(CreditSku sku) async {
    if (_purchasing) return false;
    _purchasing = true;
    _lastError = null;
    notifyListeners();
    try {
      final order = await _service.createOrder(skuCode: sku.code);
      _pendingOrder = order;
      notifyListeners();

      late final IapPurchaseResult iap;
      final apple = _iap is AppleIapService ? _iap : null;
      try {
        iap = await _iap.purchase(sku.appleProductId);
      } on IapException catch (e) {
        if (e.userCanceled) {
          _lastError = null;
        } else {
          _lastError = e.message;
        }
        apple?.abort();
        return false;
      }

      try {
        final r = await _service.verifyIap(
          orderNo: order.orderNo,
          jwsReceipt: iap.jwsReceipt,
        );
        _balance = r.balance;
        _pendingOrder = r.order;
        _lastError = null;
        await apple?.confirm();
        notifyListeners();
        await refreshLedger(reset: true);
        return true;
      } catch (e) {
        apple?.abort();
        rethrow;
      }
    } catch (e) {
      _lastError = _msg(e);
      return false;
    } finally {
      _purchasing = false;
      notifyListeners();
    }
  }

  /// dev 模式直冲，跳过 IAP（仅 backend env=dev）。
  Future<bool> devTopup({required int credits, String remark = ''}) async {
    try {
      _balance = await _service.devTopup(credits: credits, remark: remark);
      _lastError = null;
      notifyListeners();
      await refreshLedger(reset: true);
      return true;
    } catch (e) {
      _lastError = _msg(e);
      notifyListeners();
      return false;
    }
  }

  Future<void> refreshLedger({bool reset = false}) async {
    if (_loadingLedger) return;
    if (reset) {
      _ledger.clear();
      _ledgerCursor = 0;
      _ledgerHasMore = true;
    }
    if (!_ledgerHasMore) return;
    _loadingLedger = true;
    notifyListeners();
    try {
      final r = await _service.listLedger(cursor: _ledgerCursor);
      _ledger.addAll(r.items);
      _ledgerCursor = r.nextCursor;
      _ledgerHasMore = r.nextCursor > 0;
      _lastError = null;
    } catch (e) {
      _lastError = _msg(e);
    } finally {
      _loadingLedger = false;
      notifyListeners();
    }
  }

  /// 登出 / 切账号时清空。
  void reset() {
    _balance = 0;
    _skus = const [];
    _pendingOrder = null;
    _lastError = null;
    _ledger.clear();
    _ledgerCursor = 0;
    _ledgerHasMore = true;
    notifyListeners();
  }

  @override
  void dispose() {
    _logoutSub?.cancel();
    super.dispose();
  }

  String _msg(Object e) {
    final api = extractApiException(e);
    if (api != null) return api.message;
    return e.toString();
  }
}
