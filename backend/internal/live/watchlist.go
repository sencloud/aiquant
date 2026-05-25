package live

import (
	"context"

	"github.com/sencloud/finme-backend/internal/store"
)

// WatchlistRepo 操作 live_watchlist 表。
type WatchlistRepo struct{ st *store.Store }

func NewWatchlistRepo(st *store.Store) *WatchlistRepo { return &WatchlistRepo{st: st} }

func (r *WatchlistRepo) List(ctx context.Context, userID int64) ([]Watch, error) {
	rows := []Watch{}
	err := r.st.DB.SelectContext(ctx, &rows, `
		SELECT * FROM live_watchlist
		WHERE user_id=?
		ORDER BY created_at DESC`, userID)
	return rows, err
}

// Add 幂等加关注（同一 user×symbol 重复添加只更新 symbol_name）。
func (r *WatchlistRepo) Add(ctx context.Context, userID int64, symbol, name string) error {
	_, err := r.st.DB.ExecContext(ctx, `
		INSERT INTO live_watchlist (user_id, symbol, symbol_name, created_at)
		VALUES (?, ?, ?, ?)
		ON CONFLICT(user_id, symbol) DO UPDATE SET symbol_name=excluded.symbol_name`,
		userID, symbol, name, nowMs())
	return err
}

func (r *WatchlistRepo) Remove(ctx context.Context, userID int64, symbol string) error {
	_, err := r.st.DB.ExecContext(ctx, `
		DELETE FROM live_watchlist WHERE user_id=? AND symbol=?`,
		userID, symbol)
	return err
}

// DistinctSymbols 给 picker 用：返回所有用户关注的并集（用于把热门关注股带进直播池）。
func (r *WatchlistRepo) DistinctSymbols(ctx context.Context, limit int) ([]Watch, error) {
	if limit <= 0 || limit > 50 {
		limit = 20
	}
	rows := []Watch{}
	err := r.st.DB.SelectContext(ctx, &rows, `
		SELECT MIN(id) AS id, 0 AS user_id, symbol,
		       MAX(symbol_name) AS symbol_name,
		       MAX(created_at) AS created_at
		FROM live_watchlist
		GROUP BY symbol
		ORDER BY COUNT(*) DESC, MAX(created_at) DESC
		LIMIT ?`, limit)
	return rows, err
}
