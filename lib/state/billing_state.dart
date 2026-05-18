import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../core/api/api_client.dart';
import '../core/api/billing_models.dart';
import '../core/storage/hive_setup.dart';
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

  /// 当前正在购买的 sku.code；null 表示空闲。配合 UI 区分单个 tile 的 loading
  /// 与"全局购买中"的禁用态。
  String? _purchasingSku;
  String? get purchasingSku => _purchasingSku;
  bool get purchasing => _purchasingSku != null;
  bool isPurchasingSku(String code) => _purchasingSku == code;

  String? _lastError;
  String? get lastError => _lastError;

  /// 当 IAP 已经从 StoreKit 拿到 receipt，但后端 verify 失败时，
  /// receipt 会落 prefsBox 持久化。下次启动 / 进充值页时尝试自动重投。
  static const String _kPendingReceiptPrefix = 'iap_pending_receipt:';
  int _restoredCount = 0;
  int get restoredCount => _restoredCount;

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
    // 顺手补一次未到账订单。失败会保留在 prefsBox 等下次再投。
    unawaited(restoreUnverifiedPurchases());
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
    if (purchasing) return false;
    _purchasingSku = sku.code;
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

      // 拿到 receipt 后立刻持久化：哪怕后续 verify 失败、网络断、应用被 kill，
      // 下次进入充值页或者 App 启动时仍能重投，避免「钱扣了喜点没到账」。
      await _persistPendingReceipt(order.orderNo, iap.jwsReceipt);

      try {
        final r = await _service.verifyIap(
          orderNo: order.orderNo,
          jwsReceipt: iap.jwsReceipt,
        );
        _balance = r.balance;
        _pendingOrder = r.order;
        _lastError = null;
        await apple?.confirm();
        await _clearPendingReceipt(order.orderNo);
        notifyListeners();
        await refreshLedger(reset: true);
        return true;
      } catch (e) {
        // verify 失败：保留 receipt 在 prefsBox，等待后续重投。
        // 不调 apple.abort（避免提前 finishTransaction 让 Apple 不再重发回调）。
        rethrow;
      }
    } catch (e) {
      _lastError = _msg(e);
      return false;
    } finally {
      _purchasingSku = null;
      notifyListeners();
    }
  }

  // ── 待补单（receipt 已拿到、后端 verify 未确认）持久化 ──────────────

  Future<void> _persistPendingReceipt(String orderNo, String jws) async {
    await prefsBox.put(_kPendingReceiptPrefix + orderNo, jsonEncode({
      'order_no': orderNo,
      'jws': jws,
      'ts': DateTime.now().millisecondsSinceEpoch,
    }));
  }

  Future<void> _clearPendingReceipt(String orderNo) async {
    await prefsBox.delete(_kPendingReceiptPrefix + orderNo);
  }

  List<MapEntry<String, Map<String, dynamic>>> _listPendingReceipts() {
    final out = <MapEntry<String, Map<String, dynamic>>>[];
    for (final k in prefsBox.keys) {
      if (k is! String || !k.startsWith(_kPendingReceiptPrefix)) continue;
      final raw = prefsBox.get(k);
      if (raw is! String) continue;
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        out.add(MapEntry(k, m));
      } catch (_) {
        // 数据格式异常的单条，忽略并清理。
        prefsBox.delete(k);
      }
    }
    return out;
  }

  /// 重投本地待补订单（receipt 已拿到、后端 verify 未到账的）。
  ///
  /// 返回成功补到账的订单数。被调用方：
  /// - App 启动后第一次刷新（`refreshAll` 链路）
  /// - 用户进入充值页时手动触发
  Future<int> restoreUnverifiedPurchases() async {
    final pendings = _listPendingReceipts();
    if (pendings.isEmpty) return 0;
    int recovered = 0;
    for (final e in pendings) {
      final m = e.value;
      final orderNo = m['order_no'] as String?;
      final jws = m['jws'] as String?;
      if (orderNo == null || jws == null || orderNo.isEmpty || jws.isEmpty) {
        await prefsBox.delete(e.key);
        continue;
      }
      try {
        final r = await _service.verifyIap(orderNo: orderNo, jwsReceipt: jws);
        _balance = r.balance;
        _pendingOrder = r.order;
        await prefsBox.delete(e.key);
        recovered++;
      } catch (err) {
        final api = extractApiException(err);
        // 已经入账过 / 订单作废 / 商品配置异常等终态：清理本地 receipt 不再重投。
        if (api != null) {
          const terminal = {
            'BILLING.LEDGER_DUPLICATE',
            'BILLING.PRODUCT_MISMATCH',
            'BILLING.TXID_CONSUMED',
            'BILLING.ORDER_NOT_FOUND',
            'BILLING.ORDER_FINAL',
          };
          if (terminal.contains(api.code)) {
            await prefsBox.delete(e.key);
            continue;
          }
        }
        // 其它错误（网络 / IAP 配置 / Apple 临时不可用）：保留 receipt 等下次重投。
      }
    }
    if (recovered > 0) {
      _restoredCount = recovered;
      notifyListeners();
      await refreshLedger(reset: true);
    }
    return recovered;
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
    _restoredCount = 0;
    // 清掉本地待补 receipt：它们都属于上一个账号，到新账号下重投只会 403。
    final stale = prefsBox.keys
        .where((k) => k is String && k.startsWith(_kPendingReceiptPrefix))
        .toList();
    for (final k in stale) {
      prefsBox.delete(k);
    }
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
