// Package shell 实现「螺壳」虚拟货币的账本与余额。
//
// 螺壳是鹦鹉螺预测市场的下注货币，与喜点(credit)完全隔离：
//   - 不可购买，只能通过注册赠送 / 邀请好友获得；
//   - 余额冗余在 users.shell_balance，账本 shell_ledger 只插入不更新；
//   - (reason, ref_type, ref_id) 唯一索引保证业务幂等。
//
// 结构与 billing.LedgerRepo 同构，便于复用对账思路。
package shell

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

// 入账原因 — 全部明确枚举，禁止业务层传裸字符串。
const (
	ReasonSignupGift   = "signup_gift"   // 注册赠送
	ReasonInviteReward = "invite_reward" // 邀请奖励(邀请人/被邀请人)
	ReasonBetStake     = "bet_stake"     // 下注扣除
	ReasonBetPayout    = "bet_payout"    // 结算派彩
	ReasonBetRefund    = "bet_refund"    // 市场取消 / 无对手盘退款
	ReasonAdminAdjust  = "admin_adjust"  // 后台手动调账
)

// Entry 是账本一行（不可变，单向追加）。
type Entry struct {
	ID           int64          `db:"id" json:"id"`
	UserID       int64          `db:"user_id" json:"-"`
	Delta        int64          `db:"delta" json:"delta"`
	BalanceAfter int64          `db:"balance_after" json:"balance_after"`
	Reason       string         `db:"reason" json:"reason"`
	RefType      sql.NullString `db:"ref_type" json:"-"`
	RefID        sql.NullString `db:"ref_id" json:"-"`
	Remark       sql.NullString `db:"remark" json:"-"`
	CreatedAt    int64          `db:"created_at" json:"created_at"`
}

// EntryJSON 是给客户端的轻量形态。
type EntryJSON struct {
	ID           int64  `json:"id"`
	Delta        int64  `json:"delta"`
	BalanceAfter int64  `json:"balance_after"`
	Reason       string `json:"reason"`
	Remark       string `json:"remark,omitempty"`
	CreatedAt    int64  `json:"created_at"`
}

func (e Entry) ToJSON() EntryJSON {
	return EntryJSON{
		ID:           e.ID,
		Delta:        e.Delta,
		BalanceAfter: e.BalanceAfter,
		Reason:       e.Reason,
		Remark:       e.Remark.String,
		CreatedAt:    e.CreatedAt,
	}
}

// ApplyParams 是一次螺壳余额变动的全部信息。
type ApplyParams struct {
	UserID  int64
	Delta   int64
	Reason  string
	RefType string
	RefID   string
	Remark  string
}

// ErrDuplicate 表示同一笔业务已经入账过（幂等命中）。
var ErrDuplicate = errors.New("shell ledger entry duplicate")

// ErrInsufficient 表示扣螺壳时余额不足。
var ErrInsufficient = errors.New("insufficient shell balance")

// Repo 提供账本 + 余额一致写入。
type Repo struct {
	st *store.Store
}

func NewRepo(st *store.Store) *Repo { return &Repo{st: st} }

// Apply 单笔余额变动（独立事务）。
func (r *Repo) Apply(ctx context.Context, in ApplyParams) (*Entry, error) {
	var entry *Entry
	err := r.st.Tx(ctx, func(tx *sqlx.Tx) error {
		var err error
		entry, err = ApplyTx(ctx, tx, in)
		return err
	})
	if err != nil {
		return nil, err
	}
	return entry, nil
}

// ApplyTx 在调用方已有的事务里执行余额变动。
//
// 结算等多笔联动场景必须共用一个事务保证原子性，所以把核心逻辑
// 提出来供事务内复用；Apply 只是 st.Tx 的薄封装。
func ApplyTx(ctx context.Context, tx *sqlx.Tx, in ApplyParams) (*Entry, error) {
	if in.Delta == 0 {
		return nil, errors.New("shell delta must be non-zero")
	}
	if in.Reason == "" {
		return nil, errors.New("shell reason required")
	}
	var balance int64
	if err := tx.GetContext(ctx, &balance,
		"SELECT shell_balance FROM users WHERE id=?", in.UserID); err != nil {
		return nil, fmt.Errorf("read shell balance: %w", err)
	}
	newBalance := balance + in.Delta
	if newBalance < 0 {
		return nil, ErrInsufficient
	}
	now := time.Now().UnixMilli()
	res, err := tx.ExecContext(ctx, `
		INSERT INTO shell_ledger(user_id, delta, balance_after, reason, ref_type, ref_id, remark, created_at)
		VALUES(?, ?, ?, ?, ?, ?, ?, ?)`,
		in.UserID, in.Delta, newBalance, in.Reason,
		nullStr(in.RefType), nullStr(in.RefID), nullStr(in.Remark), now,
	)
	if err != nil {
		if isUniqueViolation(err) {
			return nil, ErrDuplicate
		}
		return nil, fmt.Errorf("insert shell ledger: %w", err)
	}
	id, _ := res.LastInsertId()
	if _, err := tx.ExecContext(ctx,
		"UPDATE users SET shell_balance=?, updated_at=? WHERE id=?",
		newBalance, now, in.UserID); err != nil {
		return nil, fmt.Errorf("update shell balance: %w", err)
	}
	return &Entry{
		ID:           id,
		UserID:       in.UserID,
		Delta:        in.Delta,
		BalanceAfter: newBalance,
		Reason:       in.Reason,
		RefType:      nullStr(in.RefType),
		RefID:        nullStr(in.RefID),
		Remark:       nullStr(in.Remark),
		CreatedAt:    now,
	}, nil
}

// Balance 当前用户螺壳余额。
func (r *Repo) Balance(ctx context.Context, userID int64) (int64, error) {
	var b int64
	err := r.st.DB.GetContext(ctx, &b,
		"SELECT shell_balance FROM users WHERE id=?", userID)
	return b, err
}

// ListByUser 分页查询用户螺壳流水（按 id desc）。cursor=0 代表从头。
func (r *Repo) ListByUser(ctx context.Context, userID int64, cursor int64, limit int) ([]Entry, int64, error) {
	if limit <= 0 || limit > 100 {
		limit = 30
	}
	q := "SELECT * FROM shell_ledger WHERE user_id=?"
	args := []any{userID}
	if cursor > 0 {
		q += " AND id < ?"
		args = append(args, cursor)
	}
	q += " ORDER BY id DESC LIMIT ?"
	args = append(args, limit)

	rows := []Entry{}
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

// isUniqueViolation 识别 sqlite 的"唯一索引冲突"错误(与 billing 同款实现)。
func isUniqueViolation(err error) bool {
	if err == nil {
		return false
	}
	if strings.Contains(err.Error(), "UNIQUE constraint failed") {
		return true
	}
	var sqliteErr *sqlite.Error
	if errors.As(err, &sqliteErr) {
		c := sqliteErr.Code()
		return c == 2067 || c == 1555
	}
	return false
}
