// Package users 管理 users 表的读写。其它模块（auth/billing/ding）通过
// Service 拿到稳定的领域对象，永远不直接操作 SQL。
package users

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"math/rand"
	"strings"
	"time"

	"github.com/jmoiron/sqlx"

	"github.com/sencloud/finme-backend/internal/platform"
	"github.com/sencloud/finme-backend/internal/store"
)

// nickPrefixes 随机昵称词库。生成形如「掘金3823」的友好默认昵称,
// 避免所有 Apple 用户显示成同一个「Apple 用户」。
var nickPrefixes = []string{
	"宽友", "牛友", "量友", "掘金", "趋势", "价投", "龙头", "阿尔法",
	"小宽", "盈盈", "操盘手", "策略师", "看多", "稳健", "复利", "弄潮儿",
}

// genRandomNickname 生成「词 + 4 位数」随机昵称。
func genRandomNickname() string {
	return fmt.Sprintf("%s%04d", nickPrefixes[rand.Intn(len(nickPrefixes))], 1000+rand.Intn(9000))
}

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
	ShellBalance  int64  `db:"shell_balance"`
	InviteCode    sql.NullString `db:"invite_code"`
	IsBot         bool   `db:"is_bot"`
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
//
// 昵称策略:
//   - 新用户:优先用 Apple 首次授权返回的姓名;为空则随机生成,避免「Apple 用户」。
//   - 已存在用户:若昵称为空(历史遗留),本次登录顺手回填(Apple 姓名 / 随机)。
func (s *Service) EnsureByApple(ctx context.Context, sub, nickname string) (*User, error) {
	nickname = strings.TrimSpace(nickname)
	if u, err := s.FindByAppleSub(ctx, sub); err != nil || u != nil {
		if u != nil && (!u.Nickname.Valid || strings.TrimSpace(u.Nickname.String) == "") {
			nn := nickname
			if nn == "" {
				nn = genRandomNickname()
			}
			if uerr := s.UpdateNickname(ctx, u.ID, nn); uerr == nil {
				u.Nickname = sql.NullString{String: nn, Valid: true}
			}
		}
		return u, err
	}
	if nickname == "" {
		nickname = genRandomNickname()
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

// EnsureBots 幂等保证存在至少 n 个机器人账号，返回全部 bot 用户 id。
//
// Bot 账号无登录凭证(无 phone/apple)，uuid 用确定性的 "bot-0001" 形式保证
// 重复执行不会重复创建；昵称沿用随机词库，混入真实用户里更自然。
func (s *Service) EnsureBots(ctx context.Context, n int) ([]int64, error) {
	ids := []int64{}
	if err := s.st.DB.SelectContext(ctx, &ids,
		"SELECT id FROM users WHERE is_bot=1 ORDER BY id"); err != nil {
		return nil, err
	}
	now := time.Now().UnixMilli()
	for i := len(ids); i < n; i++ {
		uuid := fmt.Sprintf("bot-%04d", i+1)
		nick := genRandomNickname()
		var id int64
		err := s.st.Tx(ctx, func(tx *sqlx.Tx) error {
			res, err := tx.ExecContext(ctx, `
				INSERT INTO users(uuid, nickname, status, credit_balance, is_bot, created_at, updated_at)
				VALUES (?, ?, 'active', 0, 1, ?, ?)`,
				uuid, sql.NullString{String: nick, Valid: true}, now, now)
			if err != nil {
				return err
			}
			id, err = res.LastInsertId()
			return err
		})
		if err != nil {
			if u, e := s.FindByUUID(ctx, uuid); e == nil && u != nil {
				ids = append(ids, u.ID)
				continue
			}
			return nil, fmt.Errorf("create bot %s: %w", uuid, err)
		}
		ids = append(ids, id)
	}
	return ids, nil
}

// ListBotIDs 返回全部机器人账号 id。
func (s *Service) ListBotIDs(ctx context.Context) ([]int64, error) {
	ids := []int64{}
	err := s.st.DB.SelectContext(ctx, &ids,
		"SELECT id FROM users WHERE is_bot=1 ORDER BY id")
	return ids, err
}

// CreditBalance 单独读余额（避免 chat 服务为了一个数字加载完整 User）。
func (s *Service) CreditBalance(ctx context.Context, userID int64) (int64, error) {
	var b int64
	if err := s.st.DB.GetContext(ctx, &b,
		"SELECT credit_balance FROM users WHERE id=?", userID); err != nil {
		return 0, err
	}
	return b, nil
}

// UpdateNickname 修改昵称（最多 32 字符，已在 handler 层校验）。
func (s *Service) UpdateNickname(ctx context.Context, userID int64, nick string) error {
	now := time.Now().UnixMilli()
	_, err := s.st.DB.ExecContext(ctx,
		"UPDATE users SET nickname=?, updated_at=? WHERE id=?",
		sql.NullString{String: nick, Valid: nick != ""}, now, userID)
	return err
}

// SoftDelete 注销账户：保留订单/账本（财务可追溯），但抹除可识别身份字段，
// 撤销所有 refresh_token，删除设备/任务等纯运营数据。
//
// 设计选择：硬删 users 行会破坏 orders/credit_ledger 的外键引用（这两张表
// 不能 ON DELETE CASCADE，否则与监管要求的"流水可追溯"冲突）。所以：
//   - users.status='deleted'，把 phone_hmac/apple_sub/wechat_unionid 置 NULL
//     （释放唯一索引，让该手机号/Apple sub 之后能注册新账号）
//   - phone_enc 清零、nickname 置 NULL
//   - 设备、refresh_tokens、ding_tasks 全删（CASCADE 已配置；此处显式 DELETE 兜底）
//   - notifications 不删（用户可能截图作为凭证）但解绑 user 不到该流水
func (s *Service) SoftDelete(ctx context.Context, userID int64) error {
	now := time.Now().UnixMilli()
	return s.st.Tx(ctx, func(tx *sqlx.Tx) error {
		var u User
		if err := tx.GetContext(ctx, &u, "SELECT * FROM users WHERE id=?", userID); err != nil {
			return fmt.Errorf("load user: %w", err)
		}
		if u.Status == string(StatusDeleted) {
			return nil
		}
		if _, err := tx.ExecContext(ctx, `
			UPDATE users SET
				status='deleted',
				phone_hmac=NULL,
				phone_enc=NULL,
				apple_sub=NULL,
				wechat_unionid=NULL,
				nickname=NULL,
				updated_at=?
			WHERE id=?`, now, userID); err != nil {
			return fmt.Errorf("anonymize user: %w", err)
		}
		if _, err := tx.ExecContext(ctx,
			"UPDATE refresh_tokens SET revoked_at=? WHERE user_id=? AND revoked_at IS NULL",
			now, userID); err != nil {
			return fmt.Errorf("revoke refresh: %w", err)
		}
		if _, err := tx.ExecContext(ctx,
			"DELETE FROM devices WHERE user_id=?", userID); err != nil {
			return fmt.Errorf("delete devices: %w", err)
		}
		if _, err := tx.ExecContext(ctx,
			"DELETE FROM ding_tasks WHERE user_id=?", userID); err != nil {
			return fmt.Errorf("delete ding tasks: %w", err)
		}
		return nil
	})
}
