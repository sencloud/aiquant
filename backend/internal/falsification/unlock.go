package falsification

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/jmoiron/sqlx"

	"github.com/sencloud/finme-backend/internal/billing"
)

var (
	// ErrEntryNotFound 档案里没有这一条。
	ErrEntryNotFound = errors.New("falsification entry not found")
)

// UnlockRefType 是解锁扣费流水的 ref_type。ref_id = "<user_id>:<entry_id>"：
// 账本的幂等索引是全局 (reason, ref_type, ref_id)，必须带上用户。
const UnlockRefType = "falsification_entry"

// UnlockResult 是一次解锁的结果。
type UnlockResult struct {
	Entry   map[string]any `json:"entry"`
	Charged int64          `json:"charged"` // 本次实际扣了多少（已解锁过 = 0）
	Already bool           `json:"already"` // 之前就解锁过
}

// UnlockedIDs 返回用户已解锁的条目 id 集合。
func (s *Service) UnlockedIDs(ctx context.Context, userID int64) (map[string]bool, error) {
	var ids []string
	if err := s.st.DB.SelectContext(ctx, &ids,
		"SELECT entry_id FROM falsification_unlocks WHERE user_id=?", userID); err != nil {
		return nil, err
	}
	out := make(map[string]bool, len(ids))
	for _, id := range ids {
		out[id] = true
	}
	return out, nil
}

// Unlock 解锁一条档案详情：扣 prices.Unlock 喜点，一人一条只扣一次、永久有效。
//
// 幂等：已解锁直接返回完整条目、不扣费；并发重复请求由 uq_falsification_unlocks
// 与账本唯一索引兜底。余额不足返回 billing.ErrInsufficientBalance。
// 没有付费内容的条目（如只有数字的研究发现）不扣费。
func (s *Service) Unlock(ctx context.Context, userID int64, entryID string) (*UnlockResult, error) {
	p, _ := s.Current(ctx)
	e, ok := FindEntry(p, entryID)
	if !ok {
		return nil, ErrEntryNotFound
	}
	full := LockedCopy(e, true)
	price := s.prices.Unlock
	if !HasPaidContent(e) {
		price = 0
	}

	res := &UnlockResult{Entry: full}
	err := s.st.Tx(ctx, func(tx *sqlx.Tx) error {
		var exists int
		err := tx.GetContext(ctx, &exists,
			"SELECT 1 FROM falsification_unlocks WHERE user_id=? AND entry_id=?", userID, entryID)
		if err == nil {
			res.Already = true
			return nil
		}
		if !errors.Is(err, sql.ErrNoRows) {
			return err
		}
		var ledgerID sql.NullInt64
		if price > 0 {
			entry, err := billing.ApplyTx(ctx, tx, billing.ApplyParams{
				UserID:  userID,
				Delta:   -price,
				Reason:  billing.ReasonConsumeUnlock,
				RefType: UnlockRefType,
				RefID:   fmt.Sprintf("%d:%s", userID, entryID),
				Remark:  "解锁证伪档案：" + str(e["strategy"]),
			})
			switch {
			case errors.Is(err, billing.ErrLedgerDuplicate):
				// 账已经记过（极少见：解锁行丢失）——只补解锁行，不再扣。
			case err != nil:
				return err
			default:
				ledgerID = sql.NullInt64{Int64: entry.ID, Valid: true}
				res.Charged = price
			}
		}
		if _, err := tx.ExecContext(ctx, `
			INSERT INTO falsification_unlocks(user_id, entry_id, credits, ledger_id, created_at)
			VALUES(?, ?, ?, ?, ?)`, userID, entryID, res.Charged, ledgerID, time.Now().UnixMilli()); err != nil {
			return err
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return res, nil
}

// Detail 返回已解锁条目的完整内容；未解锁返回 locked 视图。
func (s *Service) Detail(ctx context.Context, userID int64, entryID string) (map[string]any, error) {
	p, _ := s.Current(ctx)
	e, ok := FindEntry(p, entryID)
	if !ok {
		return nil, ErrEntryNotFound
	}
	ids, err := s.UnlockedIDs(ctx, userID)
	if err != nil {
		return nil, err
	}
	return LockedCopy(e, ids[entryID]), nil
}
