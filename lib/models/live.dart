// AI 直播 v2 DTO,与后端 internal/live/service.go 一一对应。
//
// 形态:
//   * LiveRoom         单场直播间(列表项)
//   * LiveRoomDetail   = LiveRoom + 最近 N 条消息(首屏初始化用)
//   * LiveMessage      房间内单条聊天
//   * LivePersonaRef   主持人 / 嘉宾的轻量名片
//   * LiveMessagesResponse 增量轮询接口的返回(messages + latest_idx + room_status)

class LivePersonaRef {
  const LivePersonaRef({required this.id, required this.name});

  final String id;
  final String name;

  factory LivePersonaRef.fromJson(Map<String, dynamic> json) => LivePersonaRef(
        id: (json['id'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
      );
}

class LiveRoom {
  const LiveRoom({
    required this.uuid,
    required this.title,
    required this.phase,
    required this.status,
    required this.hostPersona,
    required this.hostPersonaName,
    this.guestPersonas = const [],
    this.currentFocusSymbol = '',
    this.currentFocusName = '',
    this.messageCount = 0,
    required this.startedAt,
    this.endedAt,
  });

  final String uuid;
  final String title;
  final String phase;                  // pre / intraday / post
  final String status;                 // live / ended / ended_abnormal
  final String hostPersona;
  final String hostPersonaName;
  final List<LivePersonaRef> guestPersonas;
  final String currentFocusSymbol;
  final String currentFocusName;
  final int messageCount;
  final int startedAt;                 // unix ms
  final int? endedAt;

  bool get isLive => status == 'live';
  bool get isEnded => status == 'ended';
  bool get isEndedAbnormal => status == 'ended_abnormal';

  String get phaseLabel => switch (phase) {
        'pre' => '盘前',
        'intraday' => '盘中',
        'post' => '盘后',
        _ => phase,
      };

  factory LiveRoom.fromJson(Map<String, dynamic> json) {
    final guestsRaw = (json['guest_personas'] as List?) ?? const [];
    return LiveRoom(
      uuid: (json['uuid'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      phase: (json['phase'] as String?) ?? '',
      status: (json['status'] as String?) ?? '',
      hostPersona: (json['host_persona'] as String?) ?? '',
      hostPersonaName: (json['host_persona_name'] as String?) ?? '',
      guestPersonas: guestsRaw
          .cast<Map<String, dynamic>>()
          .map(LivePersonaRef.fromJson)
          .toList(),
      currentFocusSymbol: (json['current_focus_symbol'] as String?) ?? '',
      currentFocusName: (json['current_focus_name'] as String?) ?? '',
      messageCount: ((json['message_count'] as num?) ?? 0).toInt(),
      startedAt: ((json['started_at'] as num?) ?? 0).toInt(),
      endedAt: (json['ended_at'] as num?)?.toInt(),
    );
  }
}

class LiveMessage {
  const LiveMessage({
    required this.idx,
    required this.role,
    required this.persona,
    required this.personaName,
    this.targetPersona = '',
    this.focusSymbol = '',
    this.focusName = '',
    required this.content,
    required this.createdAt,
  });

  final int idx;
  final String role;            // host_open / host_ask / host_switch / host_close / guest_answer / guest_react / system
  final String persona;
  final String personaName;
  final String targetPersona;
  final String focusSymbol;
  final String focusName;
  final String content;
  final int createdAt;

  bool get isHost => role.startsWith('host_');
  bool get isGuest => role.startsWith('guest_');
  bool get isSystem => role == 'system';
  bool get isOpen => role == 'host_open';
  bool get isClose => role == 'host_close';

  factory LiveMessage.fromJson(Map<String, dynamic> json) => LiveMessage(
        idx: ((json['idx'] as num?) ?? 0).toInt(),
        role: (json['role'] as String?) ?? '',
        persona: (json['persona'] as String?) ?? '',
        personaName: (json['persona_name'] as String?) ?? '',
        targetPersona: (json['target_persona'] as String?) ?? '',
        focusSymbol: (json['focus_symbol'] as String?) ?? '',
        focusName: (json['focus_name'] as String?) ?? '',
        content: (json['content'] as String?) ?? '',
        createdAt: ((json['created_at'] as num?) ?? 0).toInt(),
      );
}

class LiveRoomDetail {
  const LiveRoomDetail({required this.room, this.messages = const []});

  final LiveRoom room;
  final List<LiveMessage> messages;

  factory LiveRoomDetail.fromJson(Map<String, dynamic> json) {
    final msgsRaw = (json['messages'] as List?) ?? const [];
    return LiveRoomDetail(
      room: LiveRoom.fromJson(json),
      messages: msgsRaw
          .cast<Map<String, dynamic>>()
          .map(LiveMessage.fromJson)
          .toList(),
    );
  }
}

class LiveMessagesResponse {
  const LiveMessagesResponse({
    this.messages = const [],
    required this.latestIdx,
    required this.roomStatus,
    this.currentSymbol = '',
    this.currentName = '',
  });

  final List<LiveMessage> messages;
  final int latestIdx;
  final String roomStatus;
  final String currentSymbol;
  final String currentName;

  factory LiveMessagesResponse.fromJson(Map<String, dynamic> json) {
    final msgsRaw = (json['messages'] as List?) ?? const [];
    return LiveMessagesResponse(
      messages: msgsRaw
          .cast<Map<String, dynamic>>()
          .map(LiveMessage.fromJson)
          .toList(),
      latestIdx: ((json['latest_idx'] as num?) ?? 0).toInt(),
      roomStatus: (json['room_status'] as String?) ?? '',
      currentSymbol: (json['current_symbol'] as String?) ?? '',
      currentName: (json['current_name'] as String?) ?? '',
    );
  }
}
