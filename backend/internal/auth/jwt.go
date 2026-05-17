package auth

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// Claims 是 access / refresh 通用的 JWT payload。
type Claims struct {
	UserID   int64  `json:"uid"`
	UserUUID string `json:"sub"`
	JTI      string `json:"jti"`
	Type     string `json:"typ"` // "access" | "refresh"
	jwt.RegisteredClaims
}

func newJTI() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func (a *Service) signAccess(userID int64, userUUID string) (token, jti string, err error) {
	now := time.Now()
	jti = newJTI()
	c := Claims{
		UserID:   userID,
		UserUUID: userUUID,
		JTI:      jti,
		Type:     "access",
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    "finme",
			Subject:   userUUID,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(a.accessTTL)),
		},
	}
	t := jwt.NewWithClaims(jwt.SigningMethodHS256, c)
	signed, err := t.SignedString(a.jwtKey)
	return signed, jti, err
}

func (a *Service) signRefresh(userID int64, userUUID string) (token, jti string, err error) {
	now := time.Now()
	jti = newJTI()
	c := Claims{
		UserID:   userID,
		UserUUID: userUUID,
		JTI:      jti,
		Type:     "refresh",
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer:    "finme",
			Subject:   userUUID,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(a.refreshTTL)),
		},
	}
	t := jwt.NewWithClaims(jwt.SigningMethodHS256, c)
	signed, err := t.SignedString(a.jwtKey)
	return signed, jti, err
}

// ParseAccess 校验签名 + 过期 + type=access。
func (a *Service) ParseAccess(token string) (*Claims, error) {
	return a.parse(token, "access")
}

// ParseRefresh 校验签名 + 过期 + type=refresh。
func (a *Service) ParseRefresh(token string) (*Claims, error) {
	return a.parse(token, "refresh")
}

func (a *Service) parse(token, expectType string) (*Claims, error) {
	t, err := jwt.ParseWithClaims(token, &Claims{},
		func(t *jwt.Token) (any, error) {
			if t.Method.Alg() != jwt.SigningMethodHS256.Alg() {
				return nil, errors.New("unexpected alg")
			}
			return a.jwtKey, nil
		},
		jwt.WithIssuer("finme"),
	)
	if err != nil {
		return nil, err
	}
	c, ok := t.Claims.(*Claims)
	if !ok || !t.Valid {
		return nil, errors.New("invalid claims")
	}
	if c.Type != expectType {
		return nil, errors.New("token type mismatch")
	}
	return c, nil
}
