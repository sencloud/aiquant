import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/api/auth_models.dart';
import '../models/live.dart';
import '../services/live_service.dart';

/// LiveState 管理 AI 直播 v2 的客户端状态。
///
/// 职责:
///   * 列直播间(房间列表)
///   * 进入单个房间(LiveRoomScreen):拉首屏 detail + 启动 2-3 秒轮询拉新消息
///   * 维护"当前焦点股票"和对应 K 线 HTML 缓存(focus 切换时拉新 K 线)
///   * 房间结束后自动停止轮询
///
/// 不做的事:
///   * 不主动开播(开播由后端 scheduler 进程负责,客户端只是观众)
///   * 不缓存 K 线超过当前 focus(每次切票拉一次,避免占内存)
class LiveState extends ChangeNotifier {
  LiveState({LiveService? service}) : _service = service ?? LiveService();

  final LiveService _service;

  // ── 房间列表 ────────────────────────────────────────────────────────
  final List<LiveRoom> _rooms = [];
  bool _loadingRooms = false;
  String? _lastError;

  List<LiveRoom> get rooms => List.unmodifiable(_rooms);
  bool get loadingRooms => _loadingRooms;
  String? get lastError => _lastError;

  /// 列表中"显示用"的最新一场。
  LiveRoom? get latest => _rooms.isEmpty ? null : _rooms.first;

  // ── 当前进入的房间 ──────────────────────────────────────────────────
  LiveRoom? _currentRoom;
  final List<LiveMessage> _messages = [];
  int _lastIdx = 0; // 最后看到的 idx
  String _currentFocusSymbol = '';
  String _currentFocusName = '';
  String? _currentKlineHtml;
  bool _loadingKline = false;
  bool _enteringRoom = false;
  Timer? _pollTimer;

  LiveRoom? get currentRoom => _currentRoom;
  List<LiveMessage> get messages => List.unmodifiable(_messages);
  int get lastIdx => _lastIdx;
  String get currentFocusSymbol => _currentFocusSymbol;
  String get currentFocusName => _currentFocusName;
  String? get currentKlineHtml => _currentKlineHtml;
  bool get loadingKline => _loadingKline;
  bool get enteringRoom => _enteringRoom;

  // ── 公开方法 ────────────────────────────────────────────────────────

  Future<void> refreshRooms({int limit = 20}) async {
    _loadingRooms = true;
    notifyListeners();
    try {
      final rows = await _service.listRooms(limit: limit);
      _rooms
        ..clear()
        ..addAll(rows);
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _loadingRooms = false;
      notifyListeners();
    }
  }

  /// 进入房间:重置状态,加载 detail + 启动轮询。
  ///
  /// 调用方应保证同一时刻只 enter 一个 room;LiveRoomScreen 离开时调 leaveRoom。
  Future<void> enterRoom(String uuid) async {
    await leaveRoom(); // 防御性:进新房间前先停旧轮询
    _enteringRoom = true;
    notifyListeners();
    try {
      final detail = await _service.getRoomDetail(uuid, recent: 50);
      _currentRoom = detail.room;
      _messages
        ..clear()
        ..addAll(detail.messages);
      _lastIdx =
          _messages.isEmpty ? 0 : _messages.last.idx;

      // 初始焦点:优先 room 的当前焦点,否则用最后一条有焦点的消息
      String focus = detail.room.currentFocusSymbol;
      String focusName = detail.room.currentFocusName;
      if (focus.isEmpty) {
        for (var i = _messages.length - 1; i >= 0; i--) {
          if (_messages[i].focusSymbol.isNotEmpty) {
            focus = _messages[i].focusSymbol;
            focusName = _messages[i].focusName;
            break;
          }
        }
      }
      if (focus.isNotEmpty && focus != _currentFocusSymbol) {
        _currentFocusSymbol = focus;
        _currentFocusName = focusName;
        await _loadKline(focus);
      }
      _lastError = null;
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _enteringRoom = false;
      notifyListeners();
      _startPolling();
    }
  }

  /// 离开房间:停止轮询 + 清状态。
  Future<void> leaveRoom() async {
    _stopPolling();
    _currentRoom = null;
    _messages.clear();
    _lastIdx = 0;
    _currentFocusSymbol = '';
    _currentFocusName = '';
    _currentKlineHtml = null;
    _loadingKline = false;
  }

  /// 手动重拉 K 线(下拉刷新主图时用)。
  Future<void> reloadKline() async {
    if (_currentFocusSymbol.isNotEmpty) {
      await _loadKline(_currentFocusSymbol);
    }
  }

  // ── 手动开播 ────────────────────────────────────────────────────────

  bool _creatingRoom = false;
  bool get creatingRoom => _creatingRoom;

  /// 用户在大厅点"+ 新建直播间":
  ///   * 调 POST /v1/live/rooms;成功 → 把新房间塞到列表头并返回 uuid 供 push 路由
  ///   * 已有 live (409 LIVE.ROOM_LIVE_EXISTS) → 找出列表里那个 live 房间的 uuid 返回,
  ///     调用方应据此跳到那个房间
  ///   * 其他错误 → 抛出,UI 用 SnackBar 提示
  ///
  /// 返回 (uuid, isNew):isNew=true 表示新建成功,false 表示返回的是已存在的 live 房间 uuid。
  Future<({String uuid, bool isNew})> createManualRoom({
    String? focusSymbol,
    String? focusName,
  }) async {
    _creatingRoom = true;
    notifyListeners();
    try {
      final room = await _service.createManualRoom(
        focusSymbol: focusSymbol,
        focusName: focusName,
      );
      // 插到列表头,UI 立刻能看到
      _rooms.insert(0, room);
      _lastError = null;
      return (uuid: room.uuid, isNew: true);
    } on DioException catch (e) {
      final api = e.error;
      if (api is ApiException && api.statusCode == 409) {
        // 服务端拒绝:已有 live。从本地列表找出那个 live(可能需要刷新一次)
        LiveRoom? existing = _firstLive();
        if (existing == null) {
          await refreshRooms();
          existing = _firstLive();
        }
        if (existing != null) {
          return (uuid: existing.uuid, isNew: false);
        }
      }
      rethrow;
    } finally {
      _creatingRoom = false;
      notifyListeners();
    }
  }

  // ── 内部:轮询 ──────────────────────────────────────────────────────

  void _startPolling() {
    _stopPolling();
    final room = _currentRoom;
    if (room == null || room.uuid.isEmpty) return;
    // 房间已结束,无新消息,不必持续轮询(避免 ended 房还在每 3s 请求)
    if (room.status != 'live') return;
    _pollTimer = Timer.periodic(
        const Duration(seconds: 3), (_) => _pollOnce(room.uuid));
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  Future<void> _pollOnce(String uuid) async {
    if (_currentRoom?.uuid != uuid) return; // 已离开,丢弃
    try {
      final resp = await _service.listMessagesSince(uuid, _lastIdx);
      if (_currentRoom?.uuid != uuid) return;

      bool changed = false;
      if (resp.messages.isNotEmpty) {
        _messages.addAll(resp.messages);
        _lastIdx = resp.latestIdx;
        changed = true;
      } else if (resp.latestIdx > _lastIdx) {
        _lastIdx = resp.latestIdx;
      }

      // 房间状态同步(可能 ended_abnormal)
      if (_currentRoom != null && resp.roomStatus != _currentRoom!.status) {
        _currentRoom = _copyRoomWithStatus(_currentRoom!, resp.roomStatus);
        changed = true;
        if (resp.roomStatus != 'live') {
          _stopPolling();
        }
      }

      // 焦点变更 → 拉新 K 线
      if (resp.currentSymbol.isNotEmpty &&
          resp.currentSymbol != _currentFocusSymbol) {
        _currentFocusSymbol = resp.currentSymbol;
        _currentFocusName = resp.currentName;
        changed = true;
        notifyListeners();
        await _loadKline(resp.currentSymbol);
        return; // _loadKline 内部会 notify
      }

      if (changed) notifyListeners();
    } catch (_) {
      // 网络抖动忽略,下一轮再试
    }
  }

  Future<void> _loadKline(String symbol) async {
    _loadingKline = true;
    notifyListeners();
    try {
      final html = await _service.fetchKlineHtml(symbol);
      if (symbol == _currentFocusSymbol) {
        _currentKlineHtml = html;
      }
    } catch (_) {
      // 失败保留旧的 HTML,前端展示加载失败占位即可
    } finally {
      _loadingKline = false;
      notifyListeners();
    }
  }

  LiveRoom? _firstLive() {
    for (final r in _rooms) {
      if (r.isLive) return r;
    }
    return null;
  }

  LiveRoom _copyRoomWithStatus(LiveRoom r, String status) {
    return LiveRoom(
      uuid: r.uuid,
      title: r.title,
      phase: r.phase,
      status: status,
      hostPersona: r.hostPersona,
      hostPersonaName: r.hostPersonaName,
      guestPersonas: r.guestPersonas,
      currentFocusSymbol: r.currentFocusSymbol,
      currentFocusName: r.currentFocusName,
      messageCount: r.messageCount,
      startedAt: r.startedAt,
      endedAt: r.endedAt,
      origin: r.origin,
      autoEndAt: r.autoEndAt,
    );
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }
}
