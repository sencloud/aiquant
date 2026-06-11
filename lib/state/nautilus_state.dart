import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/api/auth_models.dart';
import '../models/nautilus.dart';
import '../services/nautilus_service.dart';

/// NautilusState 管理鹦鹉螺预测市场的客户端状态。
///
/// 职责：
///   * 按板块(全球天气/金融市场)拉市场列表
///   * 螺壳余额 / 流水 / 我的下注（登录后）
///   * 下注、填邀请码后同步本地余额与市场快照
class NautilusState extends ChangeNotifier {
  NautilusState({NautilusService? service})
      : _service = service ?? NautilusService();

  final NautilusService _service;

  // ── 市场列表 ──────────────────────────────────────────────────────
  final List<PredictMarket> _markets = [];
  bool _loadingMarkets = false;
  String? _lastError;
  int _minBet = 10;

  List<PredictMarket> get markets => List.unmodifiable(_markets);
  bool get loadingMarkets => _loadingMarkets;
  String? get lastError => _lastError;
  int get minBet => _minBet;

  List<PredictMarket> byCategory(String category) =>
      _markets.where((m) => m.category == category).toList();

  Future<void> refreshMarkets() async {
    _loadingMarkets = true;
    notifyListeners();
    try {
      final r = await _service.listMarkets();
      _markets
        ..clear()
        ..addAll(r.items);
      _minBet = r.minBet;
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _loadingMarkets = false;
      notifyListeners();
    }
  }

  /// 详情页用：拉单个市场并同步进列表。
  Future<PredictMarket?> loadMarket(int id) async {
    try {
      final m = await _service.getMarket(id);
      _replaceMarket(m);
      notifyListeners();
      return m;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      return null;
    }
  }

  // ── 螺壳钱包（登录后） ────────────────────────────────────────────
  int _balance = 0;
  bool _walletLoaded = false;
  final List<ShellLedgerEntry> _ledger = [];
  final List<ShellBet> _myBets = [];

  int get balance => _balance;
  bool get walletLoaded => _walletLoaded;
  List<ShellLedgerEntry> get ledger => List.unmodifiable(_ledger);
  List<ShellBet> get myBets => List.unmodifiable(_myBets);

  Future<void> refreshWallet() async {
    try {
      final r = await _service.shells();
      _balance = r.balance;
      _ledger
        ..clear()
        ..addAll(r.items);
      final bets = await _service.myBets();
      _myBets
        ..clear()
        ..addAll(bets);
      _walletLoaded = true;
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
    } finally {
      notifyListeners();
    }
  }

  /// 登出时清掉用户态数据（市场列表保留，公开内容）。
  void clearUserData() {
    _balance = 0;
    _walletLoaded = false;
    _ledger.clear();
    _myBets.clear();
    _inviteInfo = null;
    notifyListeners();
  }

  // ── 下注 ──────────────────────────────────────────────────────────
  bool _betting = false;
  bool get betting => _betting;

  /// 下注成功返回 null，失败返回用户可读错误文案。
  Future<String?> placeBet({
    required int marketId,
    required int optionId,
    required int amount,
  }) async {
    if (_betting) return '操作太快，请稍候';
    _betting = true;
    notifyListeners();
    try {
      final r = await _service.placeBet(
          marketId: marketId, optionId: optionId, amount: amount);
      _balance = r.balance;
      _walletLoaded = true;
      _replaceMarket(r.market);
      _lastError = null;
      return null;
    } catch (e) {
      return _friendlyError(e);
    } finally {
      _betting = false;
      notifyListeners();
    }
  }

  // ── 邀请 ──────────────────────────────────────────────────────────
  InviteInfo? _inviteInfo;
  InviteInfo? get inviteInfo => _inviteInfo;

  Future<void> refreshInvite() async {
    try {
      _inviteInfo = await _service.inviteInfo();
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
    } finally {
      notifyListeners();
    }
  }

  /// 填邀请码。成功返回 null，失败返回用户可读文案。
  Future<String?> redeemInvite(String code) async {
    try {
      final r = await _service.redeemInvite(code);
      _inviteInfo = r.info;
      _balance = r.balance;
      _walletLoaded = true;
      notifyListeners();
      return null;
    } catch (e) {
      return _friendlyError(e);
    }
  }

  // ── 内部 ──────────────────────────────────────────────────────────

  void _replaceMarket(PredictMarket m) {
    final i = _markets.indexWhere((x) => x.id == m.id);
    if (i >= 0) {
      _markets[i] = m;
    } else {
      _markets.insert(0, m);
    }
  }

  /// 把 DioException/ApiException 转成用户可读文案。
  String _friendlyError(Object e) {
    if (e is DioException && e.error is ApiException) {
      return (e.error as ApiException).message;
    }
    if (e is ApiException) return e.message;
    return '网络异常，请稍后再试';
  }
}
