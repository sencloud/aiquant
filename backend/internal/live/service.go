package live

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/sencloud/finme-backend/internal/billing"
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
	// 计费(api 进程注入);nil 时创建房间/发言不扣费(理论不会发生)。
	ledger           *billing.LedgerRepo
	roomCreateCredits int64
	postCredits       int64
}

func NewService(rooms *RoomRepo, messages *MessageRepo, kline *KlineBuilder) *Service {
	return &Service{rooms: rooms, messages: messages, kline: kline}
}

// SetRunner 在 api 进程构造完 live.Runner 后注入,启用 CreateManualRoom。
// scheduler 进程不需要调用。
func (s *Service) SetRunner(r *Runner) { s.runner = r }

// SetBilling 注入账本与计费额度(api 进程)。
//   - roomCreate:创建一个直播间消耗的喜点
//   - post:观众发一条言消耗的喜点
func (s *Service) SetBilling(ledger *billing.LedgerRepo, roomCreate, post int64) {
	s.ledger = ledger
	s.roomCreateCredits = roomCreate
	s.postCredits = post
}

// ErrManualNotEnabled 表示当前进程没有挂载 Runner,无法处理手动开播。
var ErrManualNotEnabled = errors.New("manual live not enabled in this process")

// ErrRoomNotFound 删除/查询时房间不存在。
var ErrRoomNotFound = errors.New("live room not found")

// ErrCannotDeleteLive 不允许删除正在直播中的房间。
var ErrCannotDeleteLive = errors.New("cannot delete a live room")

// ErrNotRoomOwner 非创建者操作(删除 / 发言)他人房间。
var ErrNotRoomOwner = errors.New("not the room owner")

// ErrRoomNotLive 房间已结束,不能再发言。
var ErrRoomNotLive = errors.New("room is not live")

// ErrInsufficientCredits 喜点余额不足(创建房间 / 发言)。
var ErrInsufficientCredits = errors.New("insufficient credits")

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
	Visibility         string       `json:"visibility"`             // public / private
	Mine               bool         `json:"mine"`                   // 是否当前请求用户创建
}

// CreateManualInput 是 HTTP 触发开播的入参。
type CreateManualInput struct {
	FocusSymbol string `json:"focus_symbol"`
	FocusName   string `json:"focus_name"`
	// Visibility 'public' / 'private';空按 public。
	Visibility string `json:"visibility"`
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

func (s *Service) ListRooms(ctx context.Context, userID int64, limit int) ([]RoomBrief, error) {
	rows, err := s.rooms.ListVisible(ctx, userID, limit)
	if err != nil {
		return nil, err
	}
	out := make([]RoomBrief, 0, len(rows))
	for _, r := range rows {
		out = append(out, toRoomBrief(r, userID))
	}
	return out, nil
}

func (s *Service) GetRoomDetail(ctx context.Context, uuid string, recentN int, userID int64) (*RoomDetail, error) {
	room, err := s.rooms.GetByUUID(ctx, uuid)
	if err != nil {
		return nil, err
	}
	if room == nil {
		return nil, nil
	}
	// 私密房间仅创建者可见;非创建者按"不存在"处理。
	if !roomVisibleTo(room, userID) {
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
		RoomBrief: toRoomBrief(*room, userID),
		Messages:  dtos,
	}, nil
}

// MessagesSince 增量拉取(轮询接口主力)。
//
// 返回:
//   * messages: idx > sinceIdx 的全部新消息(上限 200 条)
//   * latest_idx: 房间至今最大 idx(若 messages 非空 = messages 末元素 idx)
//   * room_status: 客户端据此判断"还在直播 / 已结束 / 异常结束"
func (s *Service) MessagesSince(ctx context.Context, uuid string, sinceIdx int, userID int64) (*MessagesResponse, error) {
	room, err := s.rooms.GetByUUID(ctx, uuid)
	if err != nil {
		return nil, err
	}
	if room == nil {
		return nil, nil
	}
	if !roomVisibleTo(room, userID) {
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
//   * runner 未挂载              → ErrManualNotEnabled     (HTTP 503)
//   * 本人已有进行中的房间        → ErrLiveAlreadyExists    (HTTP 409)
//   * 喜点不足                   → ErrInsufficientCredits  (HTTP 402)
//   * 其他                       → DB / 创建错误           (HTTP 500)
func (s *Service) CreateManualRoom(ctx context.Context, in CreateManualInput, userID int64) (*RoomBrief, error) {
	if s.runner == nil {
		return nil, ErrManualNotEnabled
	}
	visibility := VisibilityPrivate
	if strings.TrimSpace(in.Visibility) != VisibilityPrivate {
		visibility = VisibilityPublic
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

	// 创建前先判重(不收费):用户已有进行中的房间 → 409。
	if n, err := s.rooms.CountLiveByCreator(ctx, userID); err != nil {
		return nil, err
	} else if n > 0 {
		return nil, ErrLiveAlreadyExists
	}

	// 扣费:创建直播间消耗 roomCreateCredits 喜点。余额不足直接拒绝。
	charged := false
	if s.ledger != nil && s.roomCreateCredits > 0 {
		refID := fmt.Sprintf("create/%d/%d", userID, time.Now().UnixNano())
		_, err := s.ledger.Apply(ctx, billing.ApplyParams{
			UserID:  userID,
			Delta:   -s.roomCreateCredits,
			Reason:  billing.ReasonConsumeLive,
			RefType: "live_room_create",
			RefID:   refID,
			Remark:  "create live room",
		})
		if err != nil {
			if errors.Is(err, billing.ErrInsufficientBalance) {
				return nil, ErrInsufficientCredits
			}
			if !errors.Is(err, billing.ErrLedgerDuplicate) {
				return nil, err
			}
		}
		charged = true
	}

	room, err := s.runner.StartManualRoom(ctx, ManualRoomOptions{
		FocusSymbol:   focusSym,
		FocusName:     focusName,
		CreatorUserID: userID,
		Visibility:    visibility,
	})
	if err != nil {
		// 开播失败 → 退回刚扣的喜点(best-effort)。
		if charged {
			_, _ = s.ledger.Apply(ctx, billing.ApplyParams{
				UserID:  userID,
				Delta:   s.roomCreateCredits,
				Reason:  billing.ReasonRefund,
				RefType: "live_room_create_refund",
				RefID:   fmt.Sprintf("refund/%d/%d", userID, time.Now().UnixNano()),
				Remark:  "refund: start manual room failed",
			})
		}
		return nil, err
	}
	b := toRoomBrief(*room, userID)
	return &b, nil
}

// PostUserMessage 观众(房间创建者)在自己的直播间发言参与讨论。
//
// 约束:
//   - 房间必须存在且 status='live'    → ErrRoomNotLive
//   - 仅房间创建者本人可发言            → ErrNotRoomOwner
//   - 按 postCredits 扣费,余额不足拒绝 → ErrInsufficientCredits
//
// 发言落库后 Nudge 一下 runner,主持人会尽快优先回应。
func (s *Service) PostUserMessage(ctx context.Context, uuid string, userID int64, nickname, content string) (*MessageDTO, error) {
	content = strings.TrimSpace(content)
	if content == "" {
		return nil, errors.New("empty content")
	}
	if len([]rune(content)) > 500 {
		content = string([]rune(content)[:500])
	}
	room, err := s.rooms.GetByUUID(ctx, uuid)
	if err != nil {
		return nil, err
	}
	if room == nil {
		return nil, ErrRoomNotFound
	}
	if !room.CreatorUserID.Valid || room.CreatorUserID.Int64 != userID {
		return nil, ErrNotRoomOwner
	}
	if room.Status != RoomLive {
		return nil, ErrRoomNotLive
	}

	// 扣费
	charged := false
	if s.ledger != nil && s.postCredits > 0 {
		refID := fmt.Sprintf("post/%s/%d", uuid, time.Now().UnixNano())
		_, err := s.ledger.Apply(ctx, billing.ApplyParams{
			UserID:  userID,
			Delta:   -s.postCredits,
			Reason:  billing.ReasonConsumeLive,
			RefType: "live_post",
			RefID:   refID,
			Remark:  "live room user message",
		})
		if err != nil {
			if errors.Is(err, billing.ErrInsufficientBalance) {
				return nil, ErrInsufficientCredits
			}
			if !errors.Is(err, billing.ErrLedgerDuplicate) {
				return nil, err
			}
		}
		charged = true
	}

	if nickname == "" {
		nickname = "观众"
	}
	msg, err := s.messages.Append(ctx, AppendInput{
		RoomID:      room.ID,
		Role:        RoleUser,
		Persona:     "user",
		PersonaName: nickname,
		Content:     content,
		UserID:      userID,
	})
	if err != nil {
		if charged {
			_, _ = s.ledger.Apply(ctx, billing.ApplyParams{
				UserID:  userID,
				Delta:   s.postCredits,
				Reason:  billing.ReasonRefund,
				RefType: "live_post_refund",
				RefID:   fmt.Sprintf("postrefund/%s/%d", uuid, time.Now().UnixNano()),
				Remark:  "refund: append user message failed",
			})
		}
		return nil, err
	}
	_ = s.rooms.IncMessageCount(ctx, room.ID)

	// 唤醒该房间的 liveLoop,让主持人优先回应。
	if s.runner != nil {
		s.runner.Nudge(room.ID)
	}

	dto := toMessageDTO(*msg)
	return &dto, nil
}

// DeleteRoom 删除一个**已结束**的直播间(连同其全部聊天消息)。
//
// 约束:正在直播(status='live')的房间不允许删除 → ErrCannotDeleteLive。
// 找不到房间 → ErrRoomNotFound。
//
// 删除顺序:先删消息再删房间(live_messages 无 FK 级联,需手动清)。
func (s *Service) DeleteRoom(ctx context.Context, uuid string, userID int64) error {
	room, err := s.rooms.GetByUUID(ctx, uuid)
	if err != nil {
		return err
	}
	if room == nil {
		return ErrRoomNotFound
	}
	// 仅创建者本人可删除自己的房间(自动场次 creator 为 NULL,用户不可删)。
	if !room.CreatorUserID.Valid || room.CreatorUserID.Int64 != userID {
		return ErrNotRoomOwner
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

// roomVisibleTo 判断房间是否对某用户可见(公开 / 本人私密)。
func roomVisibleTo(r *Room, userID int64) bool {
	if r.Visibility != VisibilityPrivate {
		return true
	}
	return r.CreatorUserID.Valid && r.CreatorUserID.Int64 == userID
}

func toRoomBrief(r Room, requesterID int64) RoomBrief {
	visibility := r.Visibility
	if visibility == "" {
		visibility = VisibilityPublic
	}
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
		Visibility:      visibility,
		Mine:            r.CreatorUserID.Valid && r.CreatorUserID.Int64 == requesterID,
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
