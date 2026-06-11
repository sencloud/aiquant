// Package invite 实现鹦鹉螺的邀请裂变：邀请码 + 双向螺壳奖励。
//
// 规则：
//   - 每个用户有一个唯一邀请码（首次访问时懒生成，8 位去混淆字符）；
//   - 新用户在 App 里填码兑换：邀请人 / 被邀请人各得 rewardShells；
//   - 一个用户只能被邀请一次（invitee_id UNIQUE 天然幂等）；
//   - 只有「新号」（注册 72 小时内）才能兑换，防止存量号互刷。
package invite

import (
	"context"
	"crypto/rand"
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
	ErrCodeNotFound    = errors.New("invite code not found")
	ErrSelfInvite      = errors.New("cannot redeem own invite code")
	ErrAlreadyRedeemed = errors.New("user already redeemed an invite")
	ErrNotNewUser      = errors.New("only new users can redeem invite codes")
)

// redeemWindow 注册多久内算「新号」可兑换邀请码。
const redeemWindow = 72 * time.Hour

// codeAlphabet 去掉 0/O/1/I/L 等易混字符。
const codeAlphabet = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"
const codeLen = 8

type Service struct {
	st           *store.Store
	rewardShells int64
}

func NewService(st *store.Store, rewardShells int64) *Service {
	if rewardShells <= 0 {
		rewardShells = 50
	}
	return &Service{st: st, rewardShells: rewardShells}
}

func (s *Service) RewardShells() int64 { return s.rewardShells }

// Info 是「邀请页」聚合：我的码 + 成功邀请数 + 累计奖励。
type Info struct {
	Code         string `json:"code"`
	InvitedCount int64  `json:"invited_count"`
	TotalReward  int64  `json:"total_reward"`
	RewardEach   int64  `json:"reward_each"`
	Redeemed     bool   `json:"redeemed"` // 我自己是否已兑换过别人的码
}

// EnsureCode 返回用户邀请码，没有则生成并落库。
func (s *Service) EnsureCode(ctx context.Context, userID int64) (string, error) {
	var code sql.NullString
	if err := s.st.DB.GetContext(ctx, &code,
		"SELECT invite_code FROM users WHERE id=?", userID); err != nil {
		return "", err
	}
	if code.Valid && code.String != "" {
		return code.String, nil
	}
	// 生成 + 落库；唯一索引冲突时重试几次。
	for i := 0; i < 5; i++ {
		c, err := randomCode()
		if err != nil {
			return "", err
		}
		res, err := s.st.DB.ExecContext(ctx, `
			UPDATE users SET invite_code=?, updated_at=?
			WHERE id=? AND (invite_code IS NULL OR invite_code='')`,
			c, time.Now().UnixMilli(), userID)
		if err != nil {
			if strings.Contains(err.Error(), "UNIQUE constraint failed") {
				continue
			}
			return "", err
		}
		if n, _ := res.RowsAffected(); n == 0 {
			// 并发下别的请求已生成，读回即可。
			if err := s.st.DB.GetContext(ctx, &code,
				"SELECT invite_code FROM users WHERE id=?", userID); err != nil {
				return "", err
			}
			return code.String, nil
		}
		return c, nil
	}
	return "", fmt.Errorf("invite code generation exhausted retries")
}

// GetInfo 邀请页聚合数据。
func (s *Service) GetInfo(ctx context.Context, userID int64) (*Info, error) {
	code, err := s.EnsureCode(ctx, userID)
	if err != nil {
		return nil, err
	}
	var agg struct {
		Cnt   int64 `db:"cnt"`
		Total int64 `db:"total"`
	}
	if err := s.st.DB.GetContext(ctx, &agg, `
		SELECT COUNT(*) AS cnt, COALESCE(SUM(reward_shells),0) AS total
		FROM invite_redemptions WHERE inviter_id=?`, userID); err != nil {
		return nil, err
	}
	var redeemed int
	if err := s.st.DB.GetContext(ctx, &redeemed,
		"SELECT COUNT(*) FROM invite_redemptions WHERE invitee_id=?", userID); err != nil {
		return nil, err
	}
	return &Info{
		Code:         code,
		InvitedCount: agg.Cnt,
		TotalReward:  agg.Total,
		RewardEach:   s.rewardShells,
		Redeemed:     redeemed > 0,
	}, nil
}

// Redeem 被邀请人(inviteeID)填别人的邀请码，双方发奖。
func (s *Service) Redeem(ctx context.Context, inviteeID int64, code string) (*Info, error) {
	code = strings.ToUpper(strings.TrimSpace(code))
	if code == "" {
		return nil, ErrCodeNotFound
	}
	err := s.st.Tx(ctx, func(tx *sqlx.Tx) error {
		var inviter struct {
			ID int64 `db:"id"`
		}
		err := tx.GetContext(ctx, &inviter,
			"SELECT id FROM users WHERE invite_code=? AND status='active'", code)
		if errors.Is(err, sql.ErrNoRows) {
			return ErrCodeNotFound
		}
		if err != nil {
			return err
		}
		if inviter.ID == inviteeID {
			return ErrSelfInvite
		}

		// 新号校验：注册时间在 redeemWindow 内。
		var createdAt int64
		if err := tx.GetContext(ctx, &createdAt,
			"SELECT created_at FROM users WHERE id=?", inviteeID); err != nil {
			return err
		}
		if time.Now().UnixMilli()-createdAt > redeemWindow.Milliseconds() {
			return ErrNotNewUser
		}

		now := time.Now().UnixMilli()
		res, err := tx.ExecContext(ctx, `
			INSERT INTO invite_redemptions(inviter_id, invitee_id, reward_shells, created_at)
			VALUES(?, ?, ?, ?)`, inviter.ID, inviteeID, s.rewardShells, now)
		if err != nil {
			if strings.Contains(err.Error(), "UNIQUE constraint failed") {
				return ErrAlreadyRedeemed
			}
			return err
		}
		redemptionID, _ := res.LastInsertId()
		refID := strconv.FormatInt(redemptionID, 10)

		// 双向发奖：同一 redemption 两条账（ref_type 区分方向），各自幂等。
		if _, err := shell.ApplyTx(ctx, tx, shell.ApplyParams{
			UserID: inviter.ID, Delta: s.rewardShells,
			Reason: shell.ReasonInviteReward, RefType: "invite_inviter", RefID: refID,
			Remark: "邀请好友奖励",
		}); err != nil && !errors.Is(err, shell.ErrDuplicate) {
			return err
		}
		if _, err := shell.ApplyTx(ctx, tx, shell.ApplyParams{
			UserID: inviteeID, Delta: s.rewardShells,
			Reason: shell.ReasonInviteReward, RefType: "invite_invitee", RefID: refID,
			Remark: "新人填写邀请码奖励",
		}); err != nil && !errors.Is(err, shell.ErrDuplicate) {
			return err
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return s.GetInfo(ctx, inviteeID)
}

func randomCode() (string, error) {
	buf := make([]byte, codeLen)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	out := make([]byte, codeLen)
	for i, b := range buf {
		out[i] = codeAlphabet[int(b)%len(codeAlphabet)]
	}
	return string(out), nil
}
