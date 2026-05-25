import 'package:flutter/foundation.dart';

import '../models/live.dart';
import '../services/live_service.dart';

/// LiveState — 客户端只做拉取 / 缓存 / 简单订阅交互；直播场次本身由后端
/// scheduler 进程按整点自动生成（每天 09:30/10:30/11:30/13:30/14:30/15:00）。
class LiveState extends ChangeNotifier {
  LiveState({LiveService? service}) : _service = service ?? LiveService();

  final LiveService _service;

  // ── State ───────────────────────────────────────────────────────────
  final List<LiveSession> _sessions = [];
  final List<LiveWatchItem> _watch = [];
  final Map<String, LiveSession> _sessionDetail = {};
  final Map<int, LiveReportFull> _reportCache = {};
  // 按股票查的报告（搜索后展示）
  final Map<String, List<LiveReportBrief>> _symbolReports = {};

  bool _loadingSessions = false;
  bool _loadingWatch = false;
  String? _lastError;

  // ── Getters ─────────────────────────────────────────────────────────
  List<LiveSession> get sessions => List.unmodifiable(_sessions);
  List<LiveWatchItem> get watchlist => List.unmodifiable(_watch);
  bool get loadingSessions => _loadingSessions;
  bool get loadingWatch => _loadingWatch;
  String? get lastError => _lastError;

  LiveSession? sessionByUUID(String uuid) => _sessionDetail[uuid];
  LiveReportFull? cachedReport(int id) => _reportCache[id];
  List<LiveReportBrief>? cachedSymbolReports(String symbol) =>
      _symbolReports[symbol.toUpperCase()];

  /// 直播列表中"显示用"的最新一场（done 优先；fallback 到 running / failed）。
  LiveSession? get latest =>
      _sessions.isEmpty ? null : _sessions.first;

  // ── Public API ──────────────────────────────────────────────────────

  Future<void> refreshSessions({int limit = 20}) async {
    _loadingSessions = true;
    notifyListeners();
    try {
      final rows = await _service.listSessions(limit: limit);
      _sessions
        ..clear()
        ..addAll(rows);
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _loadingSessions = false;
      notifyListeners();
    }
  }

  Future<LiveSession?> loadSessionDetail(String uuid, {bool force = false}) async {
    if (!force && _sessionDetail.containsKey(uuid)) {
      return _sessionDetail[uuid];
    }
    try {
      final s = await _service.getSession(uuid);
      _sessionDetail[uuid] = s;
      // 同步缓存里的概要（report_count 可能更新）
      final i = _sessions.indexWhere((x) => x.uuid == uuid);
      if (i >= 0) _sessions[i] = s;
      notifyListeners();
      return s;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<LiveReportFull?> loadReport(int id, {bool force = false}) async {
    if (!force && _reportCache.containsKey(id)) return _reportCache[id];
    try {
      final r = await _service.getReport(id);
      _reportCache[id] = r;
      notifyListeners();
      return r;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      return null;
    }
  }

  Future<List<LiveReportBrief>> loadSymbolReports(String symbol,
      {int limit = 12}) async {
    final key = symbol.toUpperCase();
    try {
      final rows = await _service.listReportsBySymbol(symbol, limit: limit);
      _symbolReports[key] = rows;
      notifyListeners();
      return rows;
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      return const [];
    }
  }

  // ── Watchlist ───────────────────────────────────────────────────────

  Future<void> refreshWatch() async {
    _loadingWatch = true;
    notifyListeners();
    try {
      final rows = await _service.listWatch();
      _watch
        ..clear()
        ..addAll(rows);
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _loadingWatch = false;
      notifyListeners();
    }
  }

  Future<void> addWatch(String symbol, {String name = ''}) async {
    try {
      await _service.addWatch(symbol, name: name);
      await refreshWatch();
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> removeWatch(String symbol) async {
    try {
      await _service.removeWatch(symbol);
      _watch.removeWhere((w) => w.symbol.toUpperCase() == symbol.toUpperCase());
      notifyListeners();
    } catch (e) {
      _lastError = e.toString();
      notifyListeners();
      rethrow;
    }
  }
}
