package live

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"

	"github.com/google/uuid"

	"github.com/sencloud/finme-backend/internal/store"
)

// RoomRepo 封装 live_rooms 的 CRUD。
type RoomRepo struct{ st *store.Store }

func NewRoomRepo(st *store.Store) *RoomRepo { return &RoomRepo{st: st} }

// CreateInput 描述一场新直播间的初始化参数。
type CreateInput struct {
	Title           string
	Phase           string
	HostPersona     PersonaRef
	GuestPersonas   []PersonaRef
}

// Create 写一行 status='live' 的房间,返回完整 Room。
func (r *RoomRepo) Create(ctx context.Context, in CreateInput) (*Room, error) {
	guestJSON, err := json.Marshal(in.GuestPersonas)
	if err != nil {
		return nil, err
	}
	now := nowMs()
	id, err := r.st.DB.ExecContext(ctx, `
		INSERT INTO live_rooms
		  (uuid, title, phase, status, host_persona, host_persona_name,
		   guest_personas, message_count, started_at, created_at)
		VALUES (?, ?, ?, 'live', ?, ?, ?, 0, ?, ?)`,
		uuid.NewString(),
		in.Title, in.Phase,
		in.HostPersona.ID, in.HostPersona.Name,
		string(guestJSON),
		now, now,
	)
	if err != nil {
		return nil, err
	}
	rid, err := id.LastInsertId()
	if err != nil {
		return nil, err
	}
	return r.GetByID(ctx, rid)
}

// GetByID 取单个房间(包含 status='ended' 的历史)。
func (r *RoomRepo) GetByID(ctx context.Context, id int64) (*Room, error) {
	var room Room
	err := r.st.DB.GetContext(ctx, &room, `SELECT * FROM live_rooms WHERE id=?`, id)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return &room, nil
}

// GetByUUID 按 UUID 取单个房间(API 暴露层用)。
func (r *RoomRepo) GetByUUID(ctx context.Context, u string) (*Room, error) {
	var room Room
	err := r.st.DB.GetContext(ctx, &room, `SELECT * FROM live_rooms WHERE uuid=?`, u)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, nil
		}
		return nil, err
	}
	return &room, nil
}

// List 列最近 N 场(含 live + ended,按开始时间倒序)。
func (r *RoomRepo) List(ctx context.Context, limit int) ([]Room, error) {
	if limit <= 0 || limit > 100 {
		limit = 20
	}
	rows := []Room{}
	err := r.st.DB.SelectContext(ctx, &rows, `
		SELECT * FROM live_rooms
		ORDER BY started_at DESC
		LIMIT ?`, limit)
	return rows, err
}

// ListLive 列所有当前 status='live' 的房间(给首页 / runner 自检用)。
func (r *RoomRepo) ListLive(ctx context.Context) ([]Room, error) {
	rows := []Room{}
	err := r.st.DB.SelectContext(ctx, &rows, `
		SELECT * FROM live_rooms WHERE status='live'
		ORDER BY started_at ASC`)
	return rows, err
}

// UpdateFocus 写入"当前讨论的股票"冗余字段。
func (r *RoomRepo) UpdateFocus(ctx context.Context, id int64, symbol, name string) error {
	_, err := r.st.DB.ExecContext(ctx, `
		UPDATE live_rooms
		SET current_focus_symbol=?, current_focus_name=?
		WHERE id=?`, nullStr(symbol), nullStr(name), id)
	return err
}

// IncMessageCount 把 message_count + 1。在新消息插入后调用。
func (r *RoomRepo) IncMessageCount(ctx context.Context, id int64) error {
	_, err := r.st.DB.ExecContext(ctx, `
		UPDATE live_rooms SET message_count = message_count + 1 WHERE id=?`, id)
	return err
}

// MarkEnded 标房间正常结束。
func (r *RoomRepo) MarkEnded(ctx context.Context, id int64) error {
	_, err := r.st.DB.ExecContext(ctx, `
		UPDATE live_rooms SET status='ended', ended_at=? WHERE id=?`,
		nowMs(), id)
	return err
}

// MarkAbnormal 标房间异常结束,记录原因。
func (r *RoomRepo) MarkAbnormal(ctx context.Context, id int64, errMsg string) error {
	_, err := r.st.DB.ExecContext(ctx, `
		UPDATE live_rooms SET status='ended_abnormal', ended_at=?, error=? WHERE id=?`,
		nowMs(), nullStr(errMsg), id)
	return err
}

// DecodeGuestPersonas 把 guest_personas JSON 解为 PersonaRef 数组。
// 解析失败返回空数组(便于上层渲染)。
func (rm *Room) DecodeGuestPersonas() []PersonaRef {
	if rm == nil || rm.GuestPersonas == "" {
		return nil
	}
	var arr []PersonaRef
	_ = json.Unmarshal([]byte(rm.GuestPersonas), &arr)
	return arr
}

func nullStr(s string) any {
	if s == "" {
		return nil
	}
	return s
}
