package live

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
)

// Service 是 live v2 模块对外的 facade,给 HTTP handler 用。
//
// 数据形态:
//   * Room  → 直播间(等同于一场直播会话)
//   * Message → 房间内的单条聊天
//   * KlineHTML → 主图 K 线的 self-contained HTML(给 webview 用)
type Service struct {
	rooms    *RoomRepo
	messages *MessageRepo
	kline    *KlineBuilder
	// runner 可选;非 nil 时支持 CreateManualRoom 即时启动 liveLoop。
	// api 进程注入(已有 LLM + tools);scheduler 进程内自己持有 Runner,不需 Service.runner。
	runner *Runner
}

func NewService(rooms *RoomRepo, messages *MessageRepo, kline *KlineBuilder) *Service {
	return &Service{rooms: rooms, messages: messages, kline: kline}
}

// SetRunner 在 api 进程构造完 live.Runner 后注入,启用 CreateManualRoom。
// scheduler 进程不需要调用。
func (s *Service) SetRunner(r *Runner) { s.runner = r }

// ErrManualNotEnabled 表示当前进程没有挂载 Runner,无法处理手动开播。
var ErrManualNotEnabled = errors.New("manual live not enabled in this process")

// ErrRoomNotFound 删除/查询时房间不存在。
var ErrRoomNotFound = errors.New("live room not found")

// ErrCannotDeleteLive 不允许删除正在直播中的房间。
var ErrCannotDeleteLive = errors.New("cannot delete a live room")

// ── DTO ────────────────────────────────────────────────────────────────

// RoomBrief 是房间列表项。
type RoomBrief struct {
	UUID               string       `json:"uuid"`
	Title              string       `json:"title"`
	Phase              string       `json:"phase"`
	Status             string       `json:"status"`
	HostPersona        string       `json:"host_persona"`
	HostPersonaName    string       `json:"host_persona_name"`
	GuestPersonas      []PersonaRef `json:"guest_personas"`
	CurrentFocusSymbol string       `json:"current_focus_symbol,omitempty"`
	CurrentFocusName   string       `json:"current_focus_name,omitempty"`
	MessageCount       int          `json:"message_count"`
	StartedAt          int64        `json:"started_at"`
	EndedAt            *int64       `json:"ended_at,omitempty"`
	Origin             string       `json:"origin"`                 // auto / manual
	AutoEndAt          *int64       `json:"auto_end_at,omitempty"`  // manual 房间硬截止
}

// CreateManualInput 是 HTTP 触发开播的入参。
type CreateManualInput struct {
	FocusSymbol string `json:"focus_symbol"`
	FocusName   string `json:"focus_name"`
}

// RoomDetail = RoomBrief + 最近 N 条消息(首屏初始化用)。
type RoomDetail struct {
	RoomBrief
	Messages []MessageDTO `json:"messages"`
}

// MessageDTO 是单条消息的客户端形态。
type MessageDTO struct {
	Idx           int          `json:"idx"`
	Role          string       `json:"role"`
	Persona       string       `json:"persona"`
	PersonaName   string       `json:"persona_name"`
	TargetPersona string       `json:"target_persona,omitempty"`
	FocusSymbol   string       `json:"focus_symbol,omitempty"`
	FocusName     string       `json:"focus_name,omitempty"`
	Content       string       `json:"content"`
	// Annotations 是嘉宾本条发言的 K 线价位标注(已解析为对象数组)。
	// 前端把当前焦点的所有 annotations 聚合后注入主图 webview 的 markLine。
	Annotations []Annotation `json:"annotations,omitempty"`
	CreatedAt   int64        `json:"created_at"`
}

// MessagesResponse 是增量轮询接口的返回。
type MessagesResponse struct {
	Messages       []MessageDTO `json:"messages"`
	LatestIdx      int          `json:"latest_idx"`        // 房间当前最大 idx(供客户端下次 since_idx 用)
	RoomStatus     string       `json:"room_status"`       // live / ended / ended_abnormal
	CurrentSymbol  string       `json:"current_symbol,omitempty"`
	CurrentName    string       `json:"current_name,omitempty"`
}

// ── facade ─────────────────────────────────────────────────────────────

func (s *Service) ListRooms(ctx context.Context, limit int) ([]RoomBrief, error) {
	rows, err := s.rooms.List(ctx, limit)
	if err != nil {
		return nil, err
	}
	out := make([]RoomBrief, 0, len(rows))
	for _, r := range rows {
		out = append(out, toRoomBrief(r))
	}
	return out, nil
}

func (s *Service) GetRoomDetail(ctx context.Context, uuid string, recentN int) (*RoomDetail, error) {
	room, err := s.rooms.GetByUUID(ctx, uuid)
	if err != nil {
		return nil, err
	}
	if room == nil {
		return nil, nil
	}
	if recentN <= 0 {
		recentN = 30
	}
	msgs, err := s.messages.ListRecent(ctx, room.ID, recentN)
	if err != nil {
		return nil, err
	}
	dtos := make([]MessageDTO, 0, len(msgs))
	for _, m := range msgs {
		dtos = append(dtos, toMessageDTO(m))
	}
	return &RoomDetail{
		RoomBrief: toRoomBrief(*room),
		Messages:  dtos,
	}, nil
}

// MessagesSince 增量拉取(轮询接口主力)。
//
// 返回:
//   * messages: idx > sinceIdx 的全部新消息(上限 200 条)
//   * latest_idx: 房间至今最大 idx(若 messages 非空 = messages 末元素 idx)
//   * room_status: 客户端据此判断"还在直播 / 已结束 / 异常结束"
func (s *Service) MessagesSince(ctx context.Context, uuid string, sinceIdx int) (*MessagesResponse, error) {
	room, err := s.rooms.GetByUUID(ctx, uuid)
	if err != nil {
		return nil, err
	}
	if room == nil {
		return nil, nil
	}
	rows, err := s.messages.ListSince(ctx, room.ID, sinceIdx, 200)
	if err != nil {
		return nil, err
	}
	dtos := make([]MessageDTO, 0, len(rows))
	for _, m := range rows {
		dtos = append(dtos, toMessageDTO(m))
	}
	latest := sinceIdx
	if len(dtos) > 0 {
		latest = dtos[len(dtos)-1].Idx
	} else {
		// 没新消息时也回当前最大 idx,客户端可校准
		cnt, _ := s.messages.CountByRoom(ctx, room.ID)
		if cnt > 0 {
			latest = cnt
		}
	}
	resp := &MessagesResponse{
		Messages:   dtos,
		LatestIdx:  latest,
		RoomStatus: room.Status,
	}
	if room.CurrentFocusSymbol.Valid {
		resp.CurrentSymbol = room.CurrentFocusSymbol.String
	}
	if room.CurrentFocusName.Valid {
		resp.CurrentName = room.CurrentFocusName.String
	}
	return resp, nil
}

// CreateManualRoom 处理"用户随时新建直播间"请求。
//
// 失败映射:
//   * runner 未挂载            → ErrManualNotEnabled       (HTTP 503)
//   * 已存在 live 房间(任何来源) → ErrLiveAlreadyExists      (HTTP 409)
//   * 其他                     → DB / 创建错误             (HTTP 500)
func (s *Service) CreateManualRoom(ctx context.Context, in CreateManualInput) (*RoomBrief, error) {
	if s.runner == nil {
		return nil, ErrManualNotEnabled
	}
	focusSym := strings.ToUpper(strings.TrimSpace(in.FocusSymbol))
	focusName := strings.TrimSpace(in.FocusName)
	// 把用户自由输入(代码 / 名称 / 北交所旧码)解析为当前有效 ts_code,
	// 否则 daily 查不到数据 → K 线空白,且主持人也拿不到正确焦点。
	if (focusSym != "" || focusName != "") && s.kline != nil && s.kline.tu != nil {
		if code, name, found := s.kline.tu.ResolveEquity(ctx, focusSym, focusName); found {
			focusSym = code
			focusName = name
		}
	}
	room, err := s.runner.StartManualRoom(ctx, ManualRoomOptions{
		FocusSymbol: focusSym,
		FocusName:   focusName,
	})
	if err != nil {
		return nil, err
	}
	b := toRoomBrief(*room)
	return &b, nil
}

// DeleteRoom 删除一个**已结束**的直播间(连同其全部聊天消息)。
//
// 约束:正在直播(status='live')的房间不允许删除 → ErrCannotDeleteLive。
// 找不到房间 → ErrRoomNotFound。
//
// 删除顺序:先删消息再删房间(live_messages 无 FK 级联,需手动清)。
func (s *Service) DeleteRoom(ctx context.Context, uuid string) error {
	room, err := s.rooms.GetByUUID(ctx, uuid)
	if err != nil {
		return err
	}
	if room == nil {
		return ErrRoomNotFound
	}
	if room.Status == RoomLive {
		return ErrCannotDeleteLive
	}
	if err := s.messages.DeleteByRoomID(ctx, room.ID); err != nil {
		return err
	}
	return s.rooms.DeleteByUUID(ctx, uuid)
}

// KlineHTML 拼装主图 K 线 HTML,返回 self-contained 字符串。
func (s *Service) KlineHTML(ctx context.Context, symbol string) (string, error) {
	if s.kline == nil {
		return "", errors.New("kline builder not configured")
	}
	symbol = strings.ToUpper(strings.TrimSpace(symbol))
	if symbol == "" {
		return "", errors.New("symbol required")
	}
	return s.kline.Build(ctx, symbol), nil
}

// ── helpers ────────────────────────────────────────────────────────────

func toRoomBrief(r Room) RoomBrief {
	b := RoomBrief{
		UUID:            r.UUID,
		Title:           r.Title,
		Phase:           r.Phase,
		Status:          r.Status,
		HostPersona:     r.HostPersona,
		HostPersonaName: r.HostPersonaName,
		GuestPersonas:   r.DecodeGuestPersonas(),
		MessageCount:    r.MessageCount,
		StartedAt:       r.StartedAt,
		Origin:          r.Origin,
	}
	if r.CurrentFocusSymbol.Valid {
		b.CurrentFocusSymbol = r.CurrentFocusSymbol.String
	}
	if r.CurrentFocusName.Valid {
		b.CurrentFocusName = r.CurrentFocusName.String
	}
	if r.EndedAt.Valid {
		v := r.EndedAt.Int64
		b.EndedAt = &v
	}
	if r.AutoEndAt.Valid {
		v := r.AutoEndAt.Int64
		b.AutoEndAt = &v
	}
	return b
}

func toMessageDTO(m Message) MessageDTO {
	d := MessageDTO{
		Idx:         m.Idx,
		Role:        m.Role,
		Persona:     m.Persona,
		PersonaName: m.PersonaName,
		Content:     m.Content,
		CreatedAt:   m.CreatedAt,
	}
	if m.TargetPersona.Valid {
		d.TargetPersona = m.TargetPersona.String
	}
	if m.FocusSymbol.Valid {
		d.FocusSymbol = m.FocusSymbol.String
	}
	if m.FocusName.Valid {
		d.FocusName = m.FocusName.String
	}
	// Annotations:数据库存 JSON 字符串,反序列化回对象数组给前端
	// (解析失败时静默忽略,不影响消息文本本身)
	if m.Annotations.Valid && strings.TrimSpace(m.Annotations.String) != "" {
		var anns []Annotation
		if err := json.Unmarshal([]byte(m.Annotations.String), &anns); err == nil {
			d.Annotations = anns
		}
	}
	return d
}
