// Package users 管理 users 表的读写。其它模块（auth/billing/ding）通过
// Service 拿到稳定的领域对象，永远不直接操作 SQL。
package users

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/jmoiron/sqlx"

	"github.com/sencloud/finme-backend/internal/platform"
	"github.com/sencloud/finme-backend/internal/store"
)

type Status string

const (
	StatusActive  Status = "active"
	StatusBanned  Status = "banned"
	StatusDeleted Status = "deleted"
)

type User struct {
	ID            int64  `db:"id"`
	UUID          string `db:"uuid"`
	PhoneHmac     sql.NullString `db:"phone_hmac"`
	PhoneEnc      []byte `db:"phone_enc"`
	AppleSub      sql.NullString `db:"apple_sub"`
	WechatUnionID sql.NullString `db:"wechat_unionid"`
	Nickname      sql.NullString `db:"nickname"`
	Status        string `db:"status"`
	CreditBalance int64  `db:"credit_balance"`
	RiskScore     int64  `db:"risk_score"`
	CreatedAt     int64  `db:"created_at"`
	UpdatedAt     int64  `db:"updated_at"`
}

// PublicProfile 是下发给客户端的安全字段子集。
type PublicProfile struct {
	UUID          string `json:"uuid"`
	Nickname      string `json:"nickname"`
	Status        string `json:"status"`
	CreditBalance int64  `json:"credit_balance"`
	HasPhone      bool   `json:"has_phone"`
	HasApple      bool   `json:"has_apple"`
	CreatedAt     int64  `json:"created_at"`
}

func (u *User) ToPublic() *PublicProfile {
	nick := ""
	if u.Nickname.Valid {
		nick = u.Nickname.String
	}
	return &PublicProfile{
		UUID:          u.UUID,
		Nickname:      nick,
		Status:        u.Status,
		CreditBalance: u.CreditBalance,
		HasPhone:      u.PhoneHmac.Valid,
		HasApple:      u.AppleSub.Valid,
		CreatedAt:     u.CreatedAt,
	}
}

// Service 提供 users 表的领域操作。
type Service struct {
	st  *store.Store
	pc  *platform.PhoneCrypto
	cfg *platform.Config
}

func NewService(st *store.Store, cfg *platform.Config) *Service {
	pc, err := platform.NewPhoneCrypto(cfg.Security.PhoneHMACKey, cfg.Security.PhoneAESKey)
	if err != nil {
		// 配置在 LoadConfig 已校验过；这里再 panic 是兜底防御。
		panic(fmt.Errorf("init phone crypto: %w", err))
	}
	return &Service{st: st, pc: pc, cfg: cfg}
}

func (s *Service) PhoneHmac(phone string) string {
	return s.pc.HMAC(phone)
}

// FindByUUID 不存在返回 nil（不是 error）。
func (s *Service) FindByUUID(ctx context.Context, uuid string) (*User, error) {
	var u User
	err := s.st.DB.GetContext(ctx, &u, "SELECT * FROM users WHERE uuid=?", uuid)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &u, nil
}

func (s *Service) FindByID(ctx context.Context, id int64) (*User, error) {
	var u User
	err := s.st.DB.GetContext(ctx, &u, "SELECT * FROM users WHERE id=?", id)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &u, nil
}

func (s *Service) FindByPhone(ctx context.Context, phone string) (*User, error) {
	var u User
	err := s.st.DB.GetContext(ctx, &u,
		"SELECT * FROM users WHERE phone_hmac=?", s.pc.HMAC(phone))
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &u, nil
}

func (s *Service) FindByAppleSub(ctx context.Context, sub string) (*User, error) {
	var u User
	err := s.st.DB.GetContext(ctx, &u, "SELECT * FROM users WHERE apple_sub=?", sub)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &u, nil
}

// EnsureByPhone：手机号登录时使用。已存在直接返回，否则插入。
// 注意 phone 是明文（仅在内存中），落库时只存 HMAC + 密文。
func (s *Service) EnsureByPhone(ctx context.Context, phone string) (*User, error) {
	if u, err := s.FindByPhone(ctx, phone); err != nil || u != nil {
		return u, err
	}
	now := time.Now().UnixMilli()
	enc, err := s.pc.Encrypt(phone)
	if err != nil {
		return nil, err
	}
	uuid := platform.NewUUID()
	hmacIdx := s.pc.HMAC(phone)

	var id int64
	err = s.st.Tx(ctx, func(tx *sqlx.Tx) error {
		res, err := tx.ExecContext(ctx, `
			INSERT INTO users(uuid, phone_hmac, phone_enc, status, credit_balance, created_at, updated_at)
			VALUES (?, ?, ?, 'active', 0, ?, ?)`,
			uuid, hmacIdx, enc, now, now,
		)
		if err != nil {
			return err
		}
		id, err = res.LastInsertId()
		return err
	})
	if err != nil {
		// 并发情况下另一个连接刚插入完，本次回退查询
		if u2, err2 := s.FindByPhone(ctx, phone); err2 == nil && u2 != nil {
			return u2, nil
		}
		return nil, fmt.Errorf("insert user by phone: %w", err)
	}
	return s.FindByID(ctx, id)
}

// EnsureByApple：Sign in with Apple 登录。sub 是 Apple 的稳定用户标识。
func (s *Service) EnsureByApple(ctx context.Context, sub, nickname string) (*User, error) {
	if u, err := s.FindByAppleSub(ctx, sub); err != nil || u != nil {
		return u, err
	}
	now := time.Now().UnixMilli()
	uuid := platform.NewUUID()
	var id int64
	err := s.st.Tx(ctx, func(tx *sqlx.Tx) error {
		res, err := tx.ExecContext(ctx, `
			INSERT INTO users(uuid, apple_sub, nickname, status, credit_balance, created_at, updated_at)
			VALUES (?, ?, ?, 'active', 0, ?, ?)`,
			uuid, sub, sql.NullString{String: nickname, Valid: nickname != ""}, now, now,
		)
		if err != nil {
			return err
		}
		id, err = res.LastInsertId()
		return err
	})
	if err != nil {
		if u2, err2 := s.FindByAppleSub(ctx, sub); err2 == nil && u2 != nil {
			return u2, nil
		}
		return nil, fmt.Errorf("insert user by apple: %w", err)
	}
	return s.FindByID(ctx, id)
}

// UpdateNickname 修改昵称（最多 32 字符，已在 handler 层校验）。
func (s *Service) UpdateNickname(ctx context.Context, userID int64, nick string) error {
	now := time.Now().UnixMilli()
	_, err := s.st.DB.ExecContext(ctx,
		"UPDATE users SET nickname=?, updated_at=? WHERE id=?",
		sql.NullString{String: nick, Valid: nick != ""}, now, userID)
	return err
}
