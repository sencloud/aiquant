package platform

import (
	"encoding/base64"
	"errors"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/pelletier/go-toml/v2"
)

// Config 是后端运行配置的"单一真相"。
//
// 优先级：环境变量 > 配置文件 > 默认值。环境变量名规则 `FINME_<UPPER_TOML_KEY>`，
// 嵌套用 `__` 分隔（例：FINME_SERVER__LISTEN）。
type Config struct {
	Env      string `toml:"env"`
	LogLevel string `toml:"log_level"`

	Server     ServerConfig     `toml:"server"`
	DB         DBConfig         `toml:"db"`
	Security   SecurityConfig   `toml:"security"`
	Apple      AppleConfig      `toml:"apple"`
	SMS        SMSConfig        `toml:"sms"`
	RateLimit  RateLimitConfig  `toml:"ratelimit"`
}

type ServerConfig struct {
	Listen            string   `toml:"listen"`
	ReadTimeoutMs     int      `toml:"read_timeout_ms"`
	WriteTimeoutMs    int      `toml:"write_timeout_ms"`
	ShutdownTimeoutMs int      `toml:"shutdown_timeout_ms"`
	TrustProxyIPs     []string `toml:"trust_proxy_ips"`
}

func (s ServerConfig) ReadTimeout() time.Duration {
	return time.Duration(s.ReadTimeoutMs) * time.Millisecond
}
func (s ServerConfig) WriteTimeout() time.Duration {
	return time.Duration(s.WriteTimeoutMs) * time.Millisecond
}
func (s ServerConfig) ShutdownTimeout() time.Duration {
	return time.Duration(s.ShutdownTimeoutMs) * time.Millisecond
}

type DBConfig struct {
	Path          string `toml:"path"`
	BusyTimeoutMs int    `toml:"busy_timeout_ms"`
	CacheKB       int    `toml:"cache_kb"`
	MaxOpenConns  int    `toml:"max_open_conns"`
	MaxIdleConns  int    `toml:"max_idle_conns"`
}

type SecurityConfig struct {
	JWTSecret          string `toml:"jwt_secret"`
	PhoneHMACKey       string `toml:"phone_hmac_key"`
	PhoneAESKey        string `toml:"phone_aes_key"`
	AccessTokenTTLMin  int    `toml:"access_token_ttl_min"`
	RefreshTokenTTLDay int    `toml:"refresh_token_ttl_day"`
}

type AppleConfig struct {
	BundleID string `toml:"bundle_id"`
	JWKSURL  string `toml:"jwks_url"`
}

type SMSConfig struct {
	Provider        string `toml:"provider"`
	SignName        string `toml:"sign_name"`
	TemplateCode    string `toml:"template_code"`
	AccessKeyID     string `toml:"access_key_id"`
	AccessKeySecret string `toml:"access_key_secret"`
}

type RateLimitConfig struct {
	APIPerIPRPM       int `toml:"api_per_ip_rpm"`
	APIPerUserRPM     int `toml:"api_per_user_rpm"`
	SMSPerPhonePerMin int `toml:"sms_per_phone_per_min"`
	SMSPerIPPerHour   int `toml:"sms_per_ip_per_hour"`
	OrderPerUserRPM   int `toml:"order_per_user_rpm"`
}

// LoadConfig 读取 TOML 配置 → 应用默认值 → 应用环境变量覆盖 → 校验。
func LoadConfig(path string) (*Config, error) {
	c := defaultConfig()
	if path != "" {
		raw, err := os.ReadFile(path)
		if err != nil {
			return nil, fmt.Errorf("read config: %w", err)
		}
		if err := toml.Unmarshal(raw, c); err != nil {
			return nil, fmt.Errorf("parse config: %w", err)
		}
	}
	applyEnv(c)
	if err := c.validate(); err != nil {
		return nil, err
	}
	return c, nil
}

func defaultConfig() *Config {
	return &Config{
		Env:      "dev",
		LogLevel: "info",
		Server: ServerConfig{
			Listen:            "127.0.0.1:8080",
			ReadTimeoutMs:     15000,
			WriteTimeoutMs:    60000,
			ShutdownTimeoutMs: 15000,
			TrustProxyIPs:     []string{"127.0.0.1"},
		},
		DB: DBConfig{
			Path:          "./data/finme.db",
			BusyTimeoutMs: 5000,
			CacheKB:       65536,
			MaxOpenConns:  16,
			MaxIdleConns:  4,
		},
		Security: SecurityConfig{
			AccessTokenTTLMin:  15,
			RefreshTokenTTLDay: 30,
		},
		Apple: AppleConfig{
			BundleID: "com.aiquant.app",
			JWKSURL:  "https://appleid.apple.com/auth/keys",
		},
		SMS: SMSConfig{Provider: "mock"},
		RateLimit: RateLimitConfig{
			APIPerIPRPM:       100,
			APIPerUserRPM:     30,
			SMSPerPhonePerMin: 1,
			SMSPerIPPerHour:   5,
			OrderPerUserRPM:   5,
		},
	}
}

func (c *Config) validate() error {
	if c.Env != "dev" && c.Env != "prod" {
		return errors.New("env must be dev or prod")
	}
	for _, k := range []struct {
		name string
		val  string
	}{
		{"jwt_secret", c.Security.JWTSecret},
		{"phone_hmac_key", c.Security.PhoneHMACKey},
		{"phone_aes_key", c.Security.PhoneAESKey},
	} {
		if k.val == "" || strings.HasPrefix(k.val, "REPLACE_ME") {
			return fmt.Errorf("security.%s must be set (32 bytes base64)", k.name)
		}
		decoded, err := base64.StdEncoding.DecodeString(k.val)
		if err != nil {
			return fmt.Errorf("security.%s base64 decode: %w", k.name, err)
		}
		if len(decoded) < 32 {
			return fmt.Errorf("security.%s must be at least 32 bytes after base64 decode (got %d)", k.name, len(decoded))
		}
	}
	if c.Apple.BundleID == "" {
		return errors.New("apple.bundle_id must be set")
	}
	if c.DB.Path == "" {
		return errors.New("db.path must be set")
	}
	return nil
}

// applyEnv 简单的扁平环境变量覆盖。仅覆盖最关键、生产中常用的几项；
// 其余仍走配置文件，避免环境变量爆炸。
func applyEnv(c *Config) {
	if v := os.Getenv("FINME_ENV"); v != "" {
		c.Env = v
	}
	if v := os.Getenv("FINME_LOG_LEVEL"); v != "" {
		c.LogLevel = v
	}
	if v := os.Getenv("FINME_SERVER__LISTEN"); v != "" {
		c.Server.Listen = v
	}
	if v := os.Getenv("FINME_DB__PATH"); v != "" {
		c.DB.Path = v
	}
	if v := os.Getenv("FINME_SECURITY__JWT_SECRET"); v != "" {
		c.Security.JWTSecret = v
	}
	if v := os.Getenv("FINME_SECURITY__PHONE_HMAC_KEY"); v != "" {
		c.Security.PhoneHMACKey = v
	}
	if v := os.Getenv("FINME_SECURITY__PHONE_AES_KEY"); v != "" {
		c.Security.PhoneAESKey = v
	}
	if v := os.Getenv("FINME_APPLE__BUNDLE_ID"); v != "" {
		c.Apple.BundleID = v
	}
	if v := os.Getenv("FINME_SMS__PROVIDER"); v != "" {
		c.SMS.Provider = v
	}
	if v := os.Getenv("FINME_SMS__ACCESS_KEY_ID"); v != "" {
		c.SMS.AccessKeyID = v
	}
	if v := os.Getenv("FINME_SMS__ACCESS_KEY_SECRET"); v != "" {
		c.SMS.AccessKeySecret = v
	}
}

// DecodeBase64Key 把配置中的 base64 字符串解成原始字节，并保证至少 32 字节。
func DecodeBase64Key(s string) ([]byte, error) {
	b, err := base64.StdEncoding.DecodeString(s)
	if err != nil {
		return nil, err
	}
	if len(b) < 32 {
		return nil, fmt.Errorf("key length %d < 32", len(b))
	}
	return b, nil
}
