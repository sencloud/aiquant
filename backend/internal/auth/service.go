// Package auth 提供登录/登出/刷新 token 的业务逻辑。
//
// 登录方式：
//   - Sign in with Apple（iOS 必须支持）
//   - 手机号 + SMS 验证码（mock provider 可在 dev 模式直接看日志拿码）
//
// 双 token：access (15m) + refresh (30d)；refresh 落库 jti，登出/异地登录可立即吊销。
package auth

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jmoiron/sqlx"

	"github.com/sencloud/finme-backend/internal/platform"
	"github.com/sencloud/finme-backend/internal/store"
	"github.com/sencloud/finme-backend/internal/users"
)

type Service struct {
	st         *store.Store
	users      *users.Service
	apple      *AppleVerifier
	sms        SMSProvider
	email      EmailProvider
	jwtKey     []byte
	accessTTL  time.Duration
	refreshTTL time.Duration
}

func NewService(st *store.Store, cfg *platform.Config, usersSvc *users.Service) (*Service, error) {
	jwtKey, err := platform.DecodeBase64Key(cfg.Security.JWTSecret)
	if err != nil {
		return nil, fmt.Errorf("jwt secret: %w", err)
	}
	var sms SMSProvider
	switch cfg.SMS.Provider {
	case "mock", "":
		sms = &MockSMSProvider{}
	default:
		return nil, fmt.Errorf("sms provider %q not implemented", cfg.SMS.Provider)
	}
	var email EmailProvider
	switch cfg.Email.Provider {
	case "mock", "":
		email = &MockEmailProvider{}
	case "resend":
		rp, err := NewResendProvider(cfg.Email.ResendAPIKey, cfg.Email.From, cfg.Email.FromName)
		if err != nil {
			return nil, fmt.Errorf("email provider resend: %w", err)
		}
		email = rp
	default:
		return nil, fmt.Errorf("email provider %q not implemented", cfg.Email.Provider)
	}
	return &Service{
		st:         st,
		users:      usersSvc,
		apple:      NewAppleVerifier(cfg.Apple.BundleID, cfg.Apple.JWKSURL),
		sms:        sms,
		email:      email,
		jwtKey:     jwtKey,
		accessTTL:  time.Duration(cfg.Security.AccessTokenTTLMin) * time.Minute,
		refreshTTL: time.Duration(cfg.Security.RefreshTokenTTLDay) * 24 * time.Hour,
	}, nil
}

// TokenPair 是登录/刷新接口下发给客户端的载荷。
type TokenPair struct {
	AccessToken      string `json:"access_token"`
	AccessExpiresIn  int64  `json:"access_expires_in"` // 秒
	RefreshToken     string `json:"refresh_token"`
	RefreshExpiresIn int64  `json:"refresh_expires_in"` // 秒
}

// SendSMSInput 校验后委派给 provider；同手机号 60s 限频在 DB 查询里实现。
type SendSMSInput struct {
	Phone string
	IP    string
}

func (s *Service) SendSMS(ctx context.Context, in SendSMSInput) error {
	if err := validateChinaPhone(in.Phone); err != nil {
		return platform.ErrBadRequest("AUTH.PHONE_INVALID", err.Error(), nil)
	}
	hmacIdx := s.users.PhoneHmac(in.Phone)
	now := time.Now()
	// 60s 内同手机号限发
	var lastAt sql.NullInt64
	err := s.st.DB.GetContext(ctx, &lastAt,
		"SELECT MAX(created_at) FROM sms_codes WHERE phone_hmac=? AND purpose='login'", hmacIdx)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return err
	}
	if lastAt.Valid && now.Sub(time.UnixMilli(lastAt.Int64)) < smsResendGap {
		return platform.ErrTooManyRequests("AUTH.SMS_TOO_FREQUENT", "请稍后再试")
	}

	code := generateCode()
	hashed, err := platform.HashPassword(code)
	if err != nil {
		return platform.ErrInternal("AUTH.HASH_FAILED", err)
	}
	expires := now.Add(smsCodeExpiry).UnixMilli()
	_, err = s.st.DB.ExecContext(ctx, `
		INSERT INTO sms_codes(phone_hmac, code_hash, purpose, expires_at, ip, created_at)
		VALUES (?, ?, 'login', ?, ?, ?)`,
		hmacIdx, hashed, expires, in.IP, now.UnixMilli(),
	)
	if err != nil {
		return platform.ErrInternal("AUTH.SMS_PERSIST", err)
	}
	if err := s.sms.Send(ctx, in.Phone, code); err != nil {
		return platform.ErrInternal("AUTH.SMS_SEND", err)
	}
	return nil
}

// VerifySMSInput 完成验证码登录 → 返回 TokenPair。
type VerifySMSInput struct {
	Phone, Code string
	DeviceID    string
	IP, UA      string
}

func (s *Service) VerifySMS(ctx context.Context, in VerifySMSInput) (*TokenPair, *users.User, error) {
	if err := validateChinaPhone(in.Phone); err != nil {
		return nil, nil, platform.ErrBadRequest("AUTH.PHONE_INVALID", err.Error(), nil)
	}
	if len(in.Code) != 6 {
		return nil, nil, platform.ErrBadRequest("AUTH.CODE_INVALID", "code must be 6 digits", nil)
	}
	hmacIdx := s.users.PhoneHmac(in.Phone)
	now := time.Now().UnixMilli()

	type smsRow struct {
		ID       int64         `db:"id"`
		CodeHash string        `db:"code_hash"`
		Expires  int64         `db:"expires_at"`
		Consumed sql.NullInt64 `db:"consumed_at"`
		Attempts int64         `db:"attempts"`
	}
	var row smsRow
	err := s.st.DB.GetContext(ctx, &row, `
		SELECT id, code_hash, expires_at, consumed_at, attempts FROM sms_codes
		WHERE phone_hmac=? AND purpose='login' AND consumed_at IS NULL
		ORDER BY created_at DESC LIMIT 1`, hmacIdx)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil, platform.ErrBadRequest("AUTH.CODE_NOT_FOUND", "请先发送验证码", nil)
	}
	if err != nil {
		return nil, nil, err
	}
	if row.Expires < now {
		return nil, nil, platform.ErrBadRequest("AUTH.CODE_EXPIRED", "验证码已过期", nil)
	}
	if row.Attempts >= smsMaxAttempt {
		return nil, nil, platform.ErrTooManyRequests("AUTH.CODE_TOO_MANY_ATTEMPTS", "尝试次数过多")
	}
	if !platform.VerifyPassword(in.Code, row.CodeHash) {
		_, _ = s.st.DB.ExecContext(ctx,
			"UPDATE sms_codes SET attempts=attempts+1 WHERE id=?", row.ID)
		return nil, nil, platform.ErrBadRequest("AUTH.CODE_MISMATCH", "验证码错误", nil)
	}
	if _, err := s.st.DB.ExecContext(ctx,
		"UPDATE sms_codes SET consumed_at=? WHERE id=?", now, row.ID); err != nil {
		return nil, nil, err
	}

	user, err := s.users.EnsureByPhone(ctx, in.Phone)
	if err != nil {
		return nil, nil, err
	}
	if user.Status != string(users.StatusActive) {
		return nil, nil, platform.ErrForbidden("AUTH.USER_BANNED", "账号状态异常")
	}
	pair, err := s.issuePair(ctx, user, in.DeviceID, in.IP, in.UA)
	if err != nil {
		return nil, nil, err
	}
	return pair, user, nil
}

// SendEmailCodeInput 校验后委派给 provider；同邮箱 60s 限频在 DB 查询里实现。
type SendEmailCodeInput struct {
	Email string
	IP    string
}

func (s *Service) SendEmailCode(ctx context.Context, in SendEmailCodeInput) error {
	email := normalizeEmail(in.Email)
	if err := validateEmail(email); err != nil {
		return platform.ErrBadRequest("AUTH.EMAIL_INVALID", err.Error(), nil)
	}
	hmacIdx := s.users.EmailHmac(email)
	now := time.Now()
	var lastAt sql.NullInt64
	err := s.st.DB.GetContext(ctx, &lastAt,
		"SELECT MAX(created_at) FROM email_codes WHERE email_hmac=? AND purpose='login'", hmacIdx)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return err
	}
	if lastAt.Valid && now.Sub(time.UnixMilli(lastAt.Int64)) < emailResendGap {
		return platform.ErrTooManyRequests("AUTH.EMAIL_TOO_FREQUENT", "请稍后再试")
	}

	code := generateCode()
	hashed, err := platform.HashPassword(code)
	if err != nil {
		return platform.ErrInternal("AUTH.HASH_FAILED", err)
	}
	expires := now.Add(emailCodeExpiry).UnixMilli()
	_, err = s.st.DB.ExecContext(ctx, `
		INSERT INTO email_codes(email_hmac, code_hash, purpose, expires_at, ip, created_at)
		VALUES (?, ?, 'login', ?, ?, ?)`,
		hmacIdx, hashed, expires, in.IP, now.UnixMilli(),
	)
	if err != nil {
		return platform.ErrInternal("AUTH.EMAIL_PERSIST", err)
	}
	if err := s.email.Send(ctx, email, code); err != nil {
		return platform.ErrInternal("AUTH.EMAIL_SEND", err)
	}
	return nil
}

// VerifyEmailInput 完成验证码登录 → 返回 TokenPair。
type VerifyEmailInput struct {
	Email, Code string
	DeviceID    string
	IP, UA      string
}

func (s *Service) VerifyEmail(ctx context.Context, in VerifyEmailInput) (*TokenPair, *users.User, error) {
	email := normalizeEmail(in.Email)
	if err := validateEmail(email); err != nil {
		return nil, nil, platform.ErrBadRequest("AUTH.EMAIL_INVALID", err.Error(), nil)
	}
	if len(in.Code) != 6 {
		return nil, nil, platform.ErrBadRequest("AUTH.CODE_INVALID", "code must be 6 digits", nil)
	}
	hmacIdx := s.users.EmailHmac(email)
	now := time.Now().UnixMilli()

	type codeRow struct {
		ID       int64         `db:"id"`
		CodeHash string        `db:"code_hash"`
		Expires  int64         `db:"expires_at"`
		Consumed sql.NullInt64 `db:"consumed_at"`
		Attempts int64         `db:"attempts"`
	}
	var row codeRow
	err := s.st.DB.GetContext(ctx, &row, `
		SELECT id, code_hash, expires_at, consumed_at, attempts FROM email_codes
		WHERE email_hmac=? AND purpose='login' AND consumed_at IS NULL
		ORDER BY created_at DESC LIMIT 1`, hmacIdx)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil, platform.ErrBadRequest("AUTH.CODE_NOT_FOUND", "请先获取验证码", nil)
	}
	if err != nil {
		return nil, nil, err
	}
	if row.Expires < now {
		return nil, nil, platform.ErrBadRequest("AUTH.CODE_EXPIRED", "验证码已过期", nil)
	}
	if row.Attempts >= emailMaxAttempt {
		return nil, nil, platform.ErrTooManyRequests("AUTH.CODE_TOO_MANY_ATTEMPTS", "尝试次数过多")
	}
	if !platform.VerifyPassword(in.Code, row.CodeHash) {
		_, _ = s.st.DB.ExecContext(ctx,
			"UPDATE email_codes SET attempts=attempts+1 WHERE id=?", row.ID)
		return nil, nil, platform.ErrBadRequest("AUTH.CODE_MISMATCH", "验证码错误", nil)
	}
	if _, err := s.st.DB.ExecContext(ctx,
		"UPDATE email_codes SET consumed_at=? WHERE id=?", now, row.ID); err != nil {
		return nil, nil, err
	}

	user, err := s.users.EnsureByEmail(ctx, email)
	if err != nil {
		return nil, nil, err
	}
	if user.Status != string(users.StatusActive) {
		return nil, nil, platform.ErrForbidden("AUTH.USER_BANNED", "账号状态异常")
	}
	pair, err := s.issuePair(ctx, user, in.DeviceID, in.IP, in.UA)
	if err != nil {
		return nil, nil, err
	}
	return pair, user, nil
}

func normalizeEmail(e string) string {
	return strings.ToLower(strings.TrimSpace(e))
}

type AppleLoginInput struct {
	IdentityToken string
	Nickname      string
	DeviceID      string
	IP, UA        string
}

func (s *Service) AppleLogin(ctx context.Context, in AppleLoginInput) (*TokenPair, *users.User, error) {
	c, err := s.apple.Verify(ctx, in.IdentityToken)
	if err != nil {
		return nil, nil, platform.ErrUnauthorized("AUTH.APPLE_VERIFY_FAILED", err.Error())
	}
	user, err := s.users.EnsureByApple(ctx, c.Subject, in.Nickname)
	if err != nil {
		return nil, nil, err
	}
	if user.Status != string(users.StatusActive) {
		return nil, nil, platform.ErrForbidden("AUTH.USER_BANNED", "账号状态异常")
	}
	pair, err := s.issuePair(ctx, user, in.DeviceID, in.IP, in.UA)
	if err != nil {
		return nil, nil, err
	}
	return pair, user, nil
}

// Refresh 用 refresh_token 换新 access + 旋转新的 refresh（防截获重放）。
func (s *Service) Refresh(ctx context.Context, refreshToken, ip, ua string) (*TokenPair, *users.User, error) {
	c, err := s.ParseRefresh(refreshToken)
	if err != nil {
		return nil, nil, platform.ErrUnauthorized("AUTH.REFRESH_INVALID", err.Error())
	}
	// 旧 jti 必须存在且未撤销
	var revoked sql.NullInt64
	err = s.st.DB.GetContext(ctx, &revoked,
		"SELECT revoked_at FROM refresh_tokens WHERE jti=?", c.JTI)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil, platform.ErrUnauthorized("AUTH.REFRESH_UNKNOWN", "unknown refresh token")
	}
	if err != nil {
		return nil, nil, err
	}
	if revoked.Valid {
		return nil, nil, platform.ErrUnauthorized("AUTH.REFRESH_REVOKED", "refresh token revoked")
	}
	user, err := s.users.FindByID(ctx, c.UserID)
	if err != nil || user == nil {
		return nil, nil, platform.ErrUnauthorized("AUTH.USER_NOT_FOUND", "user not found")
	}
	if user.Status != string(users.StatusActive) {
		return nil, nil, platform.ErrForbidden("AUTH.USER_BANNED", "账号状态异常")
	}
	// 旋转：撤销旧 jti，签发新对
	now := time.Now().UnixMilli()
	err = s.st.Tx(ctx, func(tx *sqlx.Tx) error {
		_, err := tx.ExecContext(ctx,
			"UPDATE refresh_tokens SET revoked_at=? WHERE jti=?", now, c.JTI)
		return err
	})
	if err != nil {
		return nil, nil, err
	}
	pair, err := s.issuePair(ctx, user, "", ip, ua)
	return pair, user, err
}

// Logout 撤销当前用户的所有 refresh_token。
// 可以扩展支持只撤销当前设备 jti（前端必须传 refresh）。
func (s *Service) Logout(ctx context.Context, userID int64) error {
	now := time.Now().UnixMilli()
	_, err := s.st.DB.ExecContext(ctx,
		"UPDATE refresh_tokens SET revoked_at=? WHERE user_id=? AND revoked_at IS NULL",
		now, userID)
	return err
}

func (s *Service) issuePair(
	ctx context.Context,
	user *users.User,
	deviceID, ip, ua string,
) (*TokenPair, error) {
	access, _, err := s.signAccess(user.ID, user.UUID)
	if err != nil {
		return nil, platform.ErrInternal("AUTH.SIGN_ACCESS", err)
	}
	refresh, refreshJTI, err := s.signRefresh(user.ID, user.UUID)
	if err != nil {
		return nil, platform.ErrInternal("AUTH.SIGN_REFRESH", err)
	}
	now := time.Now()
	_, err = s.st.DB.ExecContext(ctx, `
		INSERT INTO refresh_tokens(jti, user_id, device_id, ip, ua, expires_at, created_at)
		VALUES(?, ?, ?, ?, ?, ?, ?)`,
		refreshJTI, user.ID,
		nullStr(deviceID), nullStr(ip), nullStr(ua),
		now.Add(s.refreshTTL).UnixMilli(), now.UnixMilli(),
	)
	if err != nil {
		return nil, platform.ErrInternal("AUTH.PERSIST_REFRESH", err)
	}
	return &TokenPair{
		AccessToken:      access,
		AccessExpiresIn:  int64(s.accessTTL.Seconds()),
		RefreshToken:     refresh,
		RefreshExpiresIn: int64(s.refreshTTL.Seconds()),
	}, nil
}

func nullStr(s string) sql.NullString {
	if s == "" {
		return sql.NullString{}
	}
	return sql.NullString{String: s, Valid: true}
}
