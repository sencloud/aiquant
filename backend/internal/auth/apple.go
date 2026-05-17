package auth

import (
	"context"
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

// jwk 是 Apple JWKS 中单条公钥的子集。
type jwk struct {
	Kty string `json:"kty"`
	Kid string `json:"kid"`
	Use string `json:"use"`
	Alg string `json:"alg"`
	N   string `json:"n"`
	E   string `json:"e"`
}

type jwkSet struct {
	Keys []jwk `json:"keys"`
}

// AppleVerifier 校验 Sign in with Apple identity_token。
type AppleVerifier struct {
	bundleID string
	jwksURL  string

	mu      sync.RWMutex
	keys    map[string]*rsa.PublicKey
	fetched time.Time
	httpc   *http.Client
}

func NewAppleVerifier(bundleID, jwksURL string) *AppleVerifier {
	return &AppleVerifier{
		bundleID: bundleID,
		jwksURL:  jwksURL,
		keys:     map[string]*rsa.PublicKey{},
		httpc:    &http.Client{Timeout: 5 * time.Second},
	}
}

// AppleClaims 是我们关心的字段子集。
type AppleClaims struct {
	Sub           string `json:"sub"`             // 稳定用户 id
	Aud           any    `json:"aud,omitempty"`   // 字符串或数组，用 any 兜
	Iss           string `json:"iss,omitempty"`
	Email         string `json:"email,omitempty"`
	EmailVerified any    `json:"email_verified,omitempty"`
	jwt.RegisteredClaims
}

// Verify 校验 identity_token，返回 sub。
func (v *AppleVerifier) Verify(ctx context.Context, idToken string) (*AppleClaims, error) {
	if err := v.refreshIfStale(ctx); err != nil {
		return nil, fmt.Errorf("apple jwks: %w", err)
	}
	t, err := jwt.ParseWithClaims(idToken, &AppleClaims{},
		func(t *jwt.Token) (any, error) {
			if t.Method.Alg() != "RS256" {
				return nil, errors.New("unexpected alg")
			}
			kid, _ := t.Header["kid"].(string)
			v.mu.RLock()
			key := v.keys[kid]
			v.mu.RUnlock()
			if key == nil {
				return nil, fmt.Errorf("kid %q not found", kid)
			}
			return key, nil
		},
		jwt.WithIssuer("https://appleid.apple.com"),
	)
	if err != nil {
		return nil, err
	}
	c, ok := t.Claims.(*AppleClaims)
	if !ok || !t.Valid {
		return nil, errors.New("invalid token")
	}
	// aud 检查
	if !appleAudOK(c.Aud, v.bundleID) {
		return nil, errors.New("aud mismatch")
	}
	if c.Sub == "" {
		return nil, errors.New("missing sub")
	}
	return c, nil
}

func appleAudOK(aud any, want string) bool {
	switch a := aud.(type) {
	case string:
		return a == want
	case []any:
		for _, v := range a {
			if s, ok := v.(string); ok && s == want {
				return true
			}
		}
	}
	return false
}

// refreshIfStale：JWKS 缓存 6 小时。
func (v *AppleVerifier) refreshIfStale(ctx context.Context) error {
	v.mu.RLock()
	stale := time.Since(v.fetched) > 6*time.Hour || len(v.keys) == 0
	v.mu.RUnlock()
	if !stale {
		return nil
	}
	req, err := http.NewRequestWithContext(ctx, "GET", v.jwksURL, nil)
	if err != nil {
		return err
	}
	resp, err := v.httpc.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return fmt.Errorf("jwks status %d", resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return err
	}
	var set jwkSet
	if err := json.Unmarshal(body, &set); err != nil {
		return err
	}
	keys := map[string]*rsa.PublicKey{}
	for _, k := range set.Keys {
		if k.Kty != "RSA" {
			continue
		}
		nb, err := base64.RawURLEncoding.DecodeString(k.N)
		if err != nil {
			continue
		}
		eb, err := base64.RawURLEncoding.DecodeString(k.E)
		if err != nil {
			continue
		}
		eInt := new(big.Int).SetBytes(eb).Int64()
		keys[k.Kid] = &rsa.PublicKey{
			N: new(big.Int).SetBytes(nb),
			E: int(eInt),
		}
	}
	if len(keys) == 0 {
		return errors.New("no usable rsa keys in jwks")
	}
	v.mu.Lock()
	v.keys = keys
	v.fetched = time.Now()
	v.mu.Unlock()
	return nil
}
