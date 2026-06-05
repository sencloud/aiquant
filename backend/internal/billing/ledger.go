package billing

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jmoiron/sqlx"
	"modernc.org/sqlite"

	"github.com/sencloud/finme-backend/internal/store"
)

// 入账原因（reason 字段）— 全部明确枚举，禁止业务层传字符串。
const (
	ReasonTopup       = "topup"          // 用户充值
	ReasonRefund      = "refund"         // Apple 退款 / 客服处理
	ReasonAdminAdjust = "admin_adjust"   // 后台手动调账
	ReasonSignupGift  = "signup_gift"    // 注册赠送
	ReasonCheckin     = "checkin"        // 每日签到奖励
	ReasonConsumeAI   = "consume_ai"     // AI 助理消费
	ReasonConsumeDing = "consume_ding"   // DING 任务消费
	ReasonConsumeLive = "consume_live"   // 直播间消费(创建房间 / 观众发言)
	ReasonDevTopup    = "dev_topup"      // dev 模式直充（仅 env=dev 启用）
)

// LedgerEntry 是账本一行（不可变，单向追加）。
type LedgerEntry struct {
	ID           int64          `db:"id" json:"id"`
	UserID       int64          `db:"user_id" json:"-"`
	Delta        int64          `db:"delta" json:"delta"`
	BalanceAfter int64          `db:"balance_after" json:"balance_after"`
	Reason       string         `db:"reason" json:"reason"`
	RefType      sql.NullString `db:"ref_type" json:"ref_type,omitempty"`
	RefID        sql.NullString `db:"ref_id" json:"ref_id,omitempty"`
	Remark       sql.NullString `db:"remark" json:"remark,omitempty"`
	CreatedAt    int64          `db:"created_at" json:"created_at"`
}

// LedgerJSON 是给客户端的轻量形态。
type LedgerJSON struct {
	ID           int64  `json:"id"`
	Delta        int64  `json:"delta"`
	BalanceAfter int64  `json:"balance_after"`
	Reason       string `json:"reason"`
	RefType      string `json:"ref_type,omitempty"`
	RefID        string `json:"ref_id,omitempty"`
	Remark       string `json:"remark,omitempty"`
	CreatedAt    int64  `json:"created_at"`
}

func (e LedgerEntry) ToJSON() LedgerJSON {
	return LedgerJSON{
		ID:           e.ID,
		Delta:        e.Delta,
		BalanceAfter: e.BalanceAfter,
		Reason:       e.Reason,
		RefType:      e.RefType.String,
		RefID:        e.RefID.String,
		Remark:       e.Remark.String,
		CreatedAt:    e.CreatedAt,
	}
}

// ApplyParams 是一次余额变动的全部信息。
type ApplyParams struct {
	UserID  int64
	Delta   int64
	Reason  string
	RefType string // order / ai_session / ding_run / 空
	RefID   string // 业务 id；与 reason+ref_type 三元组幂等
	Remark  string
	// AllowNegative 仅退款 / 客服调账场景使用：用户已消费完喜点后申请退款，
	// 账本必须如实反映"用户欠我们 N 喜点"，余额可以为负。下次充值优先抵扣。
	AllowNegative bool
}

// LedgerRepo 提供账本 + 余额一致写入。
//
// 关键约束：
//   - delta 必须非零；
//   - 写入前后 users.credit_balance 与 ledger.balance_after 必须一致；
//   - 同 (reason, ref_type, ref_id) 不能重复写入（DB 唯一索引兜底）→ 幂等。
type LedgerRepo struct {
	st *store.Store
}

func NewLedgerRepo(st *store.Store) *LedgerRepo { return &LedgerRepo{st: st} }

// ErrLedgerDuplicate 表示同一笔业务已经入账过（幂等命中）。
// 上层应从 caller 角度视为成功（找回已写入的记录返回）。
var ErrLedgerDuplicate = errors.New("ledger entry duplicate")

// ErrInsufficientBalance 表示扣款时余额不足。
var ErrInsufficientBalance = errors.New("insufficient balance")

// Apply 是单笔余额变动的事务。返回写入的 LedgerEntry。
//
// 行为：
//   - 在事务中读 users.credit_balance（FOR UPDATE 在 SQLite 不支持，
//     但写事务串行化天然规避并发问题）；
//   - 检查 balance + delta >= 0；
//   - INSERT credit_ledger 并 UPDATE users.credit_balance；
//   - 唯一索引冲突 → 返回 ErrLedgerDuplicate（已存在），上层去 Find。
func (r *LedgerRepo) Apply(ctx context.Context, in ApplyParams) (*LedgerEntry, error) {
	if in.Delta == 0 {
		return nil, errors.New("ledger delta must be non-zero")
	}
	if in.Reason == "" {
		return nil, errors.New("ledger reason required")
	}

	var entry *LedgerEntry
	err := r.st.Tx(ctx, func(tx *sqlx.Tx) error {
		var balance int64
		if err := tx.GetContext(ctx, &balance,
			"SELECT credit_balance FROM users WHERE id=?", in.UserID); err != nil {
			return fmt.Errorf("read balance: %w", err)
		}
		newBalance := balance + in.Delta
		if newBalance < 0 && !in.AllowNegative {
			return ErrInsufficientBalance
		}
		now := time.Now().UnixMilli()
		res, err := tx.ExecContext(ctx, `
			INSERT INTO credit_ledger(user_id, delta, balance_after, reason, ref_type, ref_id, remark, created_at)
			VALUES(?, ?, ?, ?, ?, ?, ?, ?)`,
			in.UserID, in.Delta, newBalance, in.Reason,
			nullStr(in.RefType), nullStr(in.RefID), nullStr(in.Remark), now,
		)
		if err != nil {
			if isUniqueViolation(err) {
				return ErrLedgerDuplicate
			}
			return fmt.Errorf("insert ledger: %w", err)
		}
		id, _ := res.LastInsertId()
		if _, err := tx.ExecContext(ctx,
			"UPDATE users SET credit_balance=?, updated_at=? WHERE id=?",
			newBalance, now, in.UserID); err != nil {
			return fmt.Errorf("update balance: %w", err)
		}
		entry = &LedgerEntry{
			ID:           id,
			UserID:       in.UserID,
			Delta:        in.Delta,
			BalanceAfter: newBalance,
			Reason:       in.Reason,
			RefType:      nullStr(in.RefType),
			RefID:        nullStr(in.RefID),
			Remark:       nullStr(in.Remark),
			CreatedAt:    now,
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return entry, nil
}

// FindByRef 用于幂等场景：当 Apply 命中 ErrLedgerDuplicate 时，调用方查回原本入账记录。
func (r *LedgerRepo) FindByRef(ctx context.Context, reason, refType, refID string) (*LedgerEntry, error) {
	var e LedgerEntry
	err := r.st.DB.GetContext(ctx, &e,
		"SELECT * FROM credit_ledger WHERE reason=? AND ref_type=? AND ref_id=?",
		reason, refType, refID)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &e, nil
}

// ListByUser 分页查询用户流水（按 id desc）。cursor=0 代表从头。
func (r *LedgerRepo) ListByUser(ctx context.Context, userID int64, cursor int64, limit int) ([]LedgerEntry, int64, error) {
	if limit <= 0 || limit > 100 {
		limit = 30
	}
	q := "SELECT * FROM credit_ledger WHERE user_id=?"
	args := []any{userID}
	if cursor > 0 {
		q += " AND id < ?"
		args = append(args, cursor)
	}
	q += " ORDER BY id DESC LIMIT ?"
	args = append(args, limit)

	rows := []LedgerEntry{}
	if err := r.st.DB.SelectContext(ctx, &rows, q, args...); err != nil {
		return nil, 0, err
	}
	var next int64
	if len(rows) == limit {
		next = rows[len(rows)-1].ID
	}
	return rows, next, nil
}

func nullStr(s string) sql.NullString {
	if s == "" {
		return sql.NullString{}
	}
	return sql.NullString{String: s, Valid: true}
}

// isUniqueViolation 识别 sqlite 的"唯一索引冲突"错误。
// modernc.org/sqlite 把 SQLite extended error code 19 = SQLITE_CONSTRAINT 拆出
// SQLITE_CONSTRAINT_UNIQUE = 2067；这里用错误消息匹配，保持驱动无关。
func isUniqueViolation(err error) bool {
	if err == nil {
		return false
	}
	msg := err.Error()
	if strings.Contains(msg, "UNIQUE constraint failed") {
		return true
	}
	var sqliteErr *sqlite.Error
	if errors.As(err, &sqliteErr) {
		c := sqliteErr.Code()
		// 2067 SQLITE_CONSTRAINT_UNIQUE / 1555 SQLITE_CONSTRAINT_PRIMARYKEY
		return c == 2067 || c == 1555
	}
	return false
}
