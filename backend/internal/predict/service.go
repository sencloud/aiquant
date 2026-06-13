package predict

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/jmoiron/sqlx"

	"github.com/sencloud/finme-backend/internal/shell"
	"github.com/sencloud/finme-backend/internal/store"
)

var (
	ErrMarketNotFound = errors.New("market not found")
	ErrMarketNotOpen  = errors.New("market not open for betting")
	ErrOptionInvalid  = errors.New("option does not belong to market")
	ErrBetTooSmall    = errors.New("bet amount below minimum")
	ErrAlreadyFinal   = errors.New("market already settled or cancelled")
	ErrDuplicateMarket = errors.New("market with same dedup_key already exists")
)

// Service 聚合市场/选项/下注的读写与结算。
type Service struct {
	st     *store.Store
	minBet int64
}

func NewService(st *store.Store, minBet int64) *Service {
	if minBet <= 0 {
		minBet = 10
	}
	return &Service{st: st, minBet: minBet}
}

func (s *Service) MinBet() int64 { return s.minBet }

// ---------- 创建 / 查询 ----------

// CreateMarketInput 管理端建市场的入参。
type CreateMarketInput struct {
	Category    string   `json:"category"`
	SubCategory string   `json:"subcategory"`
	Title       string   `json:"title"`
	Description string   `json:"description"`
	CloseAt     int64    `json:"close_at"`
	ResolveAt   int64    `json:"resolve_at"`
	ResolveKind string   `json:"resolve_kind"`
	ResolveRule string   `json:"resolve_rule"`
	RakeBps     int64    `json:"rake_bps"`
	Options     []string `json:"options"`
	DedupKey    string   `json:"dedup_key"` // 可选；非空时用唯一索引保证不重复建市场
}

func (in *CreateMarketInput) validate() error {
	if in.Category != CategoryWeather && in.Category != CategoryFinance {
		return fmt.Errorf("category must be weather|finance")
	}
	if strings.TrimSpace(in.Title) == "" {
		return fmt.Errorf("title required")
	}
	if len(in.Options) < 2 {
		return fmt.Errorf("at least 2 options required")
	}
	now := time.Now().UnixMilli()
	if in.CloseAt <= now {
		return fmt.Errorf("close_at must be in the future")
	}
	if in.ResolveAt < in.CloseAt {
		return fmt.Errorf("resolve_at must be >= close_at")
	}
	if in.ResolveKind == "" {
		in.ResolveKind = ResolveManual
	}
	if in.ResolveKind != ResolveAuto && in.ResolveKind != ResolveManual {
		return fmt.Errorf("resolve_kind must be auto|manual")
	}
	if in.ResolveKind == ResolveAuto {
		rule, err := ParseResolveRule(in.ResolveRule)
		if err != nil {
			return fmt.Errorf("resolve_rule invalid json: %w", err)
		}
		if rule.Op == "" {
			return fmt.Errorf("resolve_rule requires op")
		}
		if rule.Source == "weather" {
			if rule.City == "" || rule.Date == "" || rule.Metric == "" {
				return fmt.Errorf("weather resolve_rule requires city/date/metric")
			}
		} else if rule.Symbol == "" {
			return fmt.Errorf("resolve_rule requires symbol")
		}
		nOpt := len(in.Options)
		if rule.YesIdx < 0 || rule.YesIdx >= nOpt || rule.NoIdx < 0 || rule.NoIdx >= nOpt || rule.YesIdx == rule.NoIdx {
			return fmt.Errorf("resolve_rule yes_idx/no_idx out of range")
		}
	}
	if in.RakeBps < 0 || in.RakeBps > 3000 {
		return fmt.Errorf("rake_bps must be in [0,3000]")
	}
	return nil
}

func (s *Service) CreateMarket(ctx context.Context, in CreateMarketInput) (*MarketView, error) {
	if err := in.validate(); err != nil {
		return nil, err
	}
	now := time.Now().UnixMilli()
	var marketID int64
	err := s.st.Tx(ctx, func(tx *sqlx.Tx) error {
		res, err := tx.ExecContext(ctx, `
			INSERT INTO predict_markets(category, subcategory, title, description, status, close_at,
				resolve_at, resolve_kind, resolve_rule, rake_bps, dedup_key, created_at, updated_at)
			VALUES(?, ?, ?, ?, 'open', ?, ?, ?, ?, ?, ?, ?, ?)`,
			in.Category, strings.TrimSpace(in.SubCategory), strings.TrimSpace(in.Title),
			strings.TrimSpace(in.Description),
			in.CloseAt, in.ResolveAt, in.ResolveKind, in.ResolveRule, in.RakeBps,
			nullStr(in.DedupKey), now, now)
		if err != nil {
			if strings.Contains(err.Error(), "UNIQUE constraint failed") {
				return ErrDuplicateMarket
			}
			return err
		}
		marketID, _ = res.LastInsertId()
		for i, label := range in.Options {
			if _, err := tx.ExecContext(ctx, `
				INSERT INTO predict_options(market_id, idx, label) VALUES(?, ?, ?)`,
				marketID, i, strings.TrimSpace(label)); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return s.GetMarket(ctx, marketID)
}

// ListMarkets 按板块列市场：进行中靠前，其次最近关闭/已结算。
func (s *Service) ListMarkets(ctx context.Context, category string, limit int) ([]MarketView, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	q := `SELECT * FROM predict_markets`
	args := []any{}
	if category != "" {
		q += ` WHERE category=?`
		args = append(args, category)
	}
	q += ` ORDER BY CASE status WHEN 'open' THEN 0 WHEN 'closed' THEN 1 ELSE 2 END,
	       close_at DESC LIMIT ?`
	args = append(args, limit)

	rows := []Market{}
	if err := s.st.DB.SelectContext(ctx, &rows, q, args...); err != nil {
		return nil, err
	}
	views := make([]MarketView, 0, len(rows))
	for _, m := range rows {
		v, err := s.attachOptions(ctx, m)
		if err != nil {
			return nil, err
		}
		views = append(views, *v)
	}
	return views, nil
}

// OpenMarkets 返回当前仍可下注(status=open 且未到 close_at)的市场，供 Bot 下注使用。
func (s *Service) OpenMarkets(ctx context.Context, limit int) ([]MarketView, error) {
	if limit <= 0 || limit > 200 {
		limit = 100
	}
	now := time.Now().UnixMilli()
	rows := []Market{}
	if err := s.st.DB.SelectContext(ctx, &rows, `
		SELECT * FROM predict_markets
		WHERE status='open' AND close_at>?
		ORDER BY close_at LIMIT ?`, now, limit); err != nil {
		return nil, err
	}
	views := make([]MarketView, 0, len(rows))
	for _, m := range rows {
		v, err := s.attachOptions(ctx, m)
		if err != nil {
			return nil, err
		}
		views = append(views, *v)
	}
	return views, nil
}

// BotBetCount 统计某市场上机器人已下注的笔数（用于限制 bot 在单市场的活跃度）。
func (s *Service) BotBetCount(ctx context.Context, marketID int64) (int, error) {
	var n int
	err := s.st.DB.GetContext(ctx, &n, `
		SELECT COUNT(*) FROM predict_bets b
		JOIN users u ON u.id = b.user_id
		WHERE b.market_id=? AND u.is_bot=1`, marketID)
	return n, err
}

func (s *Service) GetMarket(ctx context.Context, id int64) (*MarketView, error) {
	var m Market
	err := s.st.DB.GetContext(ctx, &m, "SELECT * FROM predict_markets WHERE id=?", id)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrMarketNotFound
	}
	if err != nil {
		return nil, err
	}
	return s.attachOptions(ctx, m)
}

func (s *Service) attachOptions(ctx context.Context, m Market) (*MarketView, error) {
	opts := []Option{}
	if err := s.st.DB.SelectContext(ctx, &opts,
		"SELECT * FROM predict_options WHERE market_id=? ORDER BY idx", m.ID); err != nil {
		return nil, err
	}
	var total int64
	for _, o := range opts {
		total += o.PoolShells
	}
	v := &MarketView{Market: m, Options: opts, TotalPool: total}
	if m.ResolvedOptionID.Valid {
		v.ResolvedOptionID = m.ResolvedOptionID.Int64
	}
	return v, nil
}

// UserBets 用户在某个市场上的全部下注。
func (s *Service) UserBets(ctx context.Context, userID, marketID int64) ([]Bet, error) {
	rows := []Bet{}
	err := s.st.DB.SelectContext(ctx, &rows,
		"SELECT * FROM predict_bets WHERE user_id=? AND market_id=? ORDER BY id DESC",
		userID, marketID)
	return rows, err
}

// BetWithMarket 钱包页用：下注 + 市场标题/状态。
type BetWithMarket struct {
	Bet
	MarketTitle    string `db:"market_title" json:"market_title"`
	MarketStatus   string `db:"market_status" json:"market_status"`
	MarketCategory string `db:"market_category" json:"market_category"`
	OptionLabel    string `db:"option_label" json:"option_label"`
}

// ListUserBets 用户全部下注（按时间倒序），给「我的下注」页。
func (s *Service) ListUserBets(ctx context.Context, userID int64, limit int) ([]BetWithMarket, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	rows := []BetWithMarket{}
	err := s.st.DB.SelectContext(ctx, &rows, `
		SELECT b.*, m.title AS market_title, m.status AS market_status,
		       m.category AS market_category, o.label AS option_label
		FROM predict_bets b
		JOIN predict_markets m ON m.id = b.market_id
		JOIN predict_options o ON o.id = b.option_id
		WHERE b.user_id=?
		ORDER BY b.id DESC LIMIT ?`, userID, limit)
	return rows, err
}

// ---------- 下注 ----------

// PlaceBet 下注：扣螺壳 → 写 bet → 选项池累加，单事务原子完成。
func (s *Service) PlaceBet(ctx context.Context, userID, marketID, optionID, amount int64) (*Bet, error) {
	if amount < s.minBet {
		return nil, ErrBetTooSmall
	}
	now := time.Now().UnixMilli()
	var bet *Bet
	err := s.st.Tx(ctx, func(tx *sqlx.Tx) error {
		var m Market
		err := tx.GetContext(ctx, &m, "SELECT * FROM predict_markets WHERE id=?", marketID)
		if errors.Is(err, sql.ErrNoRows) {
			return ErrMarketNotFound
		}
		if err != nil {
			return err
		}
		if m.Status != StatusOpen || now >= m.CloseAt {
			return ErrMarketNotOpen
		}
		var opt Option
		err = tx.GetContext(ctx, &opt,
			"SELECT * FROM predict_options WHERE id=? AND market_id=?", optionID, marketID)
		if errors.Is(err, sql.ErrNoRows) {
			return ErrOptionInvalid
		}
		if err != nil {
			return err
		}

		res, err := tx.ExecContext(ctx, `
			INSERT INTO predict_bets(market_id, option_id, user_id, amount, created_at)
			VALUES(?, ?, ?, ?, ?)`, marketID, optionID, userID, amount, now)
		if err != nil {
			return err
		}
		betID, _ := res.LastInsertId()

		// 扣螺壳：ref 指向 bet，天然幂等。
		if _, err := shell.ApplyTx(ctx, tx, shell.ApplyParams{
			UserID:  userID,
			Delta:   -amount,
			Reason:  shell.ReasonBetStake,
			RefType: "bet",
			RefID:   strconv.FormatInt(betID, 10),
			Remark:  m.Title,
		}); err != nil {
			return err
		}

		// 选项池累加；首次在该选项下注才 +1 人数。
		var prior int
		err = tx.GetContext(ctx, &prior, `
			SELECT COUNT(*) FROM predict_bets
			WHERE option_id=? AND user_id=? AND id<>?`, optionID, userID, betID)
		if err != nil {
			return err
		}
		bump := 0
		if prior == 0 {
			bump = 1
		}
		if _, err := tx.ExecContext(ctx, `
			UPDATE predict_options SET pool_shells=pool_shells+?, bettor_count=bettor_count+?
			WHERE id=?`, amount, bump, optionID); err != nil {
			return err
		}
		bet = &Bet{
			ID: betID, MarketID: marketID, OptionID: optionID, UserID: userID,
			Amount: amount, Status: "active", CreatedAt: now,
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return bet, nil
}

// ---------- 状态推进 / 结算 ----------

// CloseDue 把过了 close_at 的 open 市场置为 closed（调度器周期调用）。
func (s *Service) CloseDue(ctx context.Context) (int64, error) {
	now := time.Now().UnixMilli()
	res, err := s.st.DB.ExecContext(ctx, `
		UPDATE predict_markets SET status='closed', updated_at=?
		WHERE status='open' AND close_at<=?`, now, now)
	if err != nil {
		return 0, err
	}
	n, _ := res.RowsAffected()
	return n, nil
}

// DueAutoMarkets 到了 resolve_at、需要自动结算的市场。
func (s *Service) DueAutoMarkets(ctx context.Context) ([]Market, error) {
	now := time.Now().UnixMilli()
	rows := []Market{}
	err := s.st.DB.SelectContext(ctx, &rows, `
		SELECT * FROM predict_markets
		WHERE status IN ('open','closed') AND resolve_kind='auto' AND resolve_at<=?
		ORDER BY resolve_at LIMIT 20`, now)
	return rows, err
}

// Settle 按获胜选项结算市场（人工/自动共用）。
//
// 单事务内：标记市场 settled → 全部 active bets 标 won/lost →
// 赢方按比例瓜分可分配奖池（写 shell_ledger 派彩）。
// 赢方池为空时全额退款（视为流局）。
func (s *Service) Settle(ctx context.Context, marketID, winningOptionID int64) error {
	now := time.Now().UnixMilli()
	return s.st.Tx(ctx, func(tx *sqlx.Tx) error {
		var m Market
		err := tx.GetContext(ctx, &m, "SELECT * FROM predict_markets WHERE id=?", marketID)
		if errors.Is(err, sql.ErrNoRows) {
			return ErrMarketNotFound
		}
		if err != nil {
			return err
		}
		if m.Status == StatusSettled || m.Status == StatusCancelled {
			return ErrAlreadyFinal
		}
		var win Option
		err = tx.GetContext(ctx, &win,
			"SELECT * FROM predict_options WHERE id=? AND market_id=?", winningOptionID, marketID)
		if errors.Is(err, sql.ErrNoRows) {
			return ErrOptionInvalid
		}
		if err != nil {
			return err
		}

		bets := []Bet{}
		if err := tx.SelectContext(ctx, &bets,
			"SELECT * FROM predict_bets WHERE market_id=? AND status='active'", marketID); err != nil {
			return err
		}

		var total, winPool int64
		for _, b := range bets {
			total += b.Amount
			if b.OptionID == winningOptionID {
				winPool += b.Amount
			}
		}

		if winPool == 0 {
			// 无人押中 → 流局，全额退款。
			if err := refundBetsTx(ctx, tx, m, bets, now); err != nil {
				return err
			}
		} else {
			rake := total * m.RakeBps / 10000
			distributable := total - rake
			for _, b := range bets {
				if b.OptionID != winningOptionID {
					if _, err := tx.ExecContext(ctx,
						"UPDATE predict_bets SET status='lost', settled_at=? WHERE id=?",
						now, b.ID); err != nil {
						return err
					}
					continue
				}
				payout := b.Amount * distributable / winPool
				if _, err := tx.ExecContext(ctx,
					"UPDATE predict_bets SET status='won', payout=?, settled_at=? WHERE id=?",
					payout, now, b.ID); err != nil {
					return err
				}
				if payout > 0 {
					if _, err := shell.ApplyTx(ctx, tx, shell.ApplyParams{
						UserID:  b.UserID,
						Delta:   payout,
						Reason:  shell.ReasonBetPayout,
						RefType: "bet",
						RefID:   strconv.FormatInt(b.ID, 10),
						Remark:  m.Title,
					}); err != nil && !errors.Is(err, shell.ErrDuplicate) {
						return err
					}
				}
			}
		}

		if _, err := tx.ExecContext(ctx, `
			UPDATE predict_markets SET status='settled', resolved_option_id=?, updated_at=?
			WHERE id=?`, winningOptionID, now, marketID); err != nil {
			return err
		}
		return nil
	})
}

// Cancel 取消市场并全额退款。
func (s *Service) Cancel(ctx context.Context, marketID int64) error {
	now := time.Now().UnixMilli()
	return s.st.Tx(ctx, func(tx *sqlx.Tx) error {
		var m Market
		err := tx.GetContext(ctx, &m, "SELECT * FROM predict_markets WHERE id=?", marketID)
		if errors.Is(err, sql.ErrNoRows) {
			return ErrMarketNotFound
		}
		if err != nil {
			return err
		}
		if m.Status == StatusSettled || m.Status == StatusCancelled {
			return ErrAlreadyFinal
		}
		bets := []Bet{}
		if err := tx.SelectContext(ctx, &bets,
			"SELECT * FROM predict_bets WHERE market_id=? AND status='active'", marketID); err != nil {
			return err
		}
		if err := refundBetsTx(ctx, tx, m, bets, now); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx,
			"UPDATE predict_markets SET status='cancelled', updated_at=? WHERE id=?",
			now, marketID); err != nil {
			return err
		}
		return nil
	})
}

func nullStr(s string) sql.NullString {
	if s == "" {
		return sql.NullString{}
	}
	return sql.NullString{String: s, Valid: true}
}

// refundBetsTx 把一组 active 下注全额退款（流局 / 取消共用）。
func refundBetsTx(ctx context.Context, tx *sqlx.Tx, m Market, bets []Bet, now int64) error {
	for _, b := range bets {
		if _, err := tx.ExecContext(ctx,
			"UPDATE predict_bets SET status='refunded', payout=amount, settled_at=? WHERE id=?",
			now, b.ID); err != nil {
			return err
		}
		if _, err := shell.ApplyTx(ctx, tx, shell.ApplyParams{
			UserID:  b.UserID,
			Delta:   b.Amount,
			Reason:  shell.ReasonBetRefund,
			RefType: "bet",
			RefID:   strconv.FormatInt(b.ID, 10),
			Remark:  m.Title,
		}); err != nil && !errors.Is(err, shell.ErrDuplicate) {
			return err
		}
	}
	return nil
}
