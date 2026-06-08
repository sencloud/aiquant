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

	Server    ServerConfig    `toml:"server"`
	DB        DBConfig        `toml:"db"`
	Security  SecurityConfig  `toml:"security"`
	Apple     AppleConfig     `toml:"apple"`
	AppleIAP  AppleIAPConfig  `toml:"apple_iap"`
	APNs      APNsConfig      `toml:"apns"`
	FCM       FCMConfig       `toml:"fcm"`
	LLM       LLMConfig       `toml:"llm"`
	SMS       SMSConfig       `toml:"sms"`
	Tushare   TushareConfig   `toml:"tushare"`
	News      NewsConfig      `toml:"news"`
	AI        AIConfig        `toml:"ai"`
	Qwen      QwenConfig      `toml:"qwen"`
	RateLimit RateLimitConfig `toml:"ratelimit"`
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

// AppleIAPConfig 用于 App Store Server API 验签 IAP 收据。
//
// `private_key` 为 .p8 文件的 PEM 全文（推荐通过 FINME_APPLE_IAP__PRIVATE_KEY
// 注入避免落 git）；`private_key_path` 为本地路径，二者任一即可。
//
// `environment` 控制 base url：
//   - sandbox    → https://api.storekit-sandbox.itunes.apple.com
//   - production → https://api.storekit.itunes.apple.com
//   - auto       → 先 production，404 自动 fallback sandbox（TestFlight/Sandbox 共存）
type AppleIAPConfig struct {
	BundleID       string `toml:"bundle_id"`
	IssuerID       string `toml:"issuer_id"`
	KeyID          string `toml:"key_id"`
	PrivateKey     string `toml:"private_key"`
	PrivateKeyPath string `toml:"private_key_path"`
	Environment    string `toml:"environment"`
}

func (c AppleIAPConfig) Configured() bool {
	return c.IssuerID != "" && c.KeyID != "" && (c.PrivateKey != "" || c.PrivateKeyPath != "")
}

// APNsConfig 用于 APNs HTTP/2 Provider API。
//
// `environment`：sandbox / production；development build 走 sandbox，TestFlight 与
// App Store 走 production。
type APNsConfig struct {
	BundleID       string `toml:"bundle_id"`
	TeamID         string `toml:"team_id"`
	KeyID          string `toml:"key_id"`
	PrivateKey     string `toml:"private_key"`
	PrivateKeyPath string `toml:"private_key_path"`
	Environment    string `toml:"environment"`
}

func (c APNsConfig) Configured() bool {
	return c.TeamID != "" && c.KeyID != "" && (c.PrivateKey != "" || c.PrivateKeyPath != "")
}

// FCMConfig 用于 Firebase Cloud Messaging HTTP v1。
type FCMConfig struct {
	ProjectID              string `toml:"project_id"`
	ServiceAccountJSON     string `toml:"service_account_json"`
	ServiceAccountJSONPath string `toml:"service_account_json_path"`
}

func (c FCMConfig) Configured() bool {
	return c.ProjectID != "" && (c.ServiceAccountJSON != "" || c.ServiceAccountJSONPath != "")
}

// LLMConfig 服务端 DING 任务执行用。
type LLMConfig struct {
	Provider     string `toml:"provider"` // 仅支持 deepseek
	APIKey       string `toml:"api_key"`
	BaseURL      string `toml:"base_url"`
	ChatModel    string `toml:"chat_model"`
	ReasonModel  string `toml:"reason_model"`
	TimeoutSec   int    `toml:"timeout_sec"`
	MaxToolLoops int    `toml:"max_tool_loops"`
}

func (c LLMConfig) Configured() bool { return c.APIKey != "" }

// TushareConfig 服务端持有 Tushare token，客户端不再直连。
//
// `token` 的安全等级：等同于密钥 — 一定要走 EnvironmentFile 注入或写入
// /server/secrets/.tushare（chmod 600），不能进 git。
type TushareConfig struct {
	Token             string `toml:"token"`
	BaseURL           string `toml:"base_url"`
	TimeoutSec        int    `toml:"timeout_sec"`
	BasicCacheTTLSec  int    `toml:"basic_cache_ttl_sec"`  // stock_basic 等大表内存缓存 TTL
	HTTPMaxConcurrent int    `toml:"http_max_concurrent"`  // tushare 个人版有 QPM 限制
}

func (c TushareConfig) Configured() bool { return c.Token != "" }

// NewsConfig 各类新闻 / 卫星 / 地缘事件数据源。
//
// FIRMS map_key 也是密钥级别，只走服务端持有；GDELT / Google News 都是公开
// RSS / API 不需要 key。
type NewsConfig struct {
	GdeltBaseURL  string `toml:"gdelt_base_url"`
	GoogleRSSBase string `toml:"google_rss_base"`
	FirmsBaseURL  string `toml:"firms_base_url"`
	FirmsMapKey   string `toml:"firms_map_key"`
	TimeoutSec    int    `toml:"timeout_sec"`
}

// QwenConfig 阿里百炼 DashScope（OpenAI 兼容模式）配置；
// 当前仅用于多模态 vision 解析（券商持仓截图 → JSON）。
//
// API key 走 EnvironmentFile 注入：DASHSCOPE_API_KEY。
// 文档：https://help.aliyun.com/zh/model-studio/use-qwen-by-calling-api
type QwenConfig struct {
	APIKey      string `toml:"api_key"`
	BaseURL     string `toml:"base_url"`
	VisionModel string `toml:"vision_model"`
	TimeoutSec  int    `toml:"timeout_sec"`
}

func (c QwenConfig) Configured() bool { return c.APIKey != "" }

// AIConfig 服务端 AI 助理 chat 接口的运行参数。
type AIConfig struct {
	MaxToolLoops    int   `toml:"max_tool_loops"`
	MaxContextMsgs  int   `toml:"max_context_msgs"`
	BaseChatCredits int64 `toml:"base_chat_credits"`     // 一次普通 chat 基础消耗
	DeepBonusCredits int64 `toml:"deep_bonus_credits"`   // 深度模式额外
	LiveRoomCreateCredits int64 `toml:"live_room_create_credits"` // 创建一个直播间消耗
	LivePostCredits       int64 `toml:"live_post_credits"`        // 观众在直播间发一条言消耗
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
		AppleIAP: AppleIAPConfig{
			BundleID:    "com.aiquant.app",
			Environment: "auto",
		},
		APNs: APNsConfig{
			BundleID:    "com.aiquant.app",
			Environment: "production",
		},
		LLM: LLMConfig{
			Provider:     "deepseek",
			BaseURL:      "https://api.deepseek.com",
			ChatModel:    "deepseek-chat",
			ReasonModel:  "deepseek-reasoner",
			TimeoutSec:   180,
			MaxToolLoops: 60,
		},
		SMS: SMSConfig{Provider: "mock"},
		Tushare: TushareConfig{
			BaseURL:           "http://api.tushare.pro",
			TimeoutSec:        20,
			BasicCacheTTLSec:  86400,
			HTTPMaxConcurrent: 4,
		},
		News: NewsConfig{
			GdeltBaseURL:  "https://api.gdeltproject.org/api/v2/doc/doc",
			GoogleRSSBase: "https://news.google.com/rss/search",
			FirmsBaseURL:  "https://firms.modaps.eosdis.nasa.gov/api/area/csv",
			TimeoutSec:    20,
		},
		Qwen: QwenConfig{
			BaseURL:     "https://dashscope.aliyuncs.com/compatible-mode/v1",
			VisionModel: "qwen-vl-max",
			TimeoutSec:  60,
		},
		AI: AIConfig{
			// 工具循环轮次：LLM 每轮可能并发调多个 tool，60 轮足够支撑
			// 跨多个行业/标的的链式查询，又不会因为模型陷入循环烧太多喜点。
			MaxToolLoops: 60,
			// 历史上下文条数：覆盖 30+ 轮多工具对话仍然能保留前文要点。
			MaxContextMsgs:   60,
			BaseChatCredits:  1,
			DeepBonusCredits: 5,
			LiveRoomCreateCredits: 1,
			LivePostCredits:       1,
		},
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
	if v := os.Getenv("FINME_APPLE_IAP__BUNDLE_ID"); v != "" {
		c.AppleIAP.BundleID = v
	}
	if v := os.Getenv("FINME_APPLE_IAP__ISSUER_ID"); v != "" {
		c.AppleIAP.IssuerID = v
	}
	if v := os.Getenv("FINME_APPLE_IAP__KEY_ID"); v != "" {
		c.AppleIAP.KeyID = v
	}
	if v := os.Getenv("FINME_APPLE_IAP__PRIVATE_KEY"); v != "" {
		c.AppleIAP.PrivateKey = v
	}
	if v := os.Getenv("FINME_APPLE_IAP__PRIVATE_KEY_PATH"); v != "" {
		c.AppleIAP.PrivateKeyPath = v
	}
	if v := os.Getenv("FINME_APPLE_IAP__ENVIRONMENT"); v != "" {
		c.AppleIAP.Environment = v
	}
	if v := os.Getenv("FINME_APNS__TEAM_ID"); v != "" {
		c.APNs.TeamID = v
	}
	if v := os.Getenv("FINME_APNS__KEY_ID"); v != "" {
		c.APNs.KeyID = v
	}
	if v := os.Getenv("FINME_APNS__PRIVATE_KEY"); v != "" {
		c.APNs.PrivateKey = v
	}
	if v := os.Getenv("FINME_APNS__PRIVATE_KEY_PATH"); v != "" {
		c.APNs.PrivateKeyPath = v
	}
	if v := os.Getenv("FINME_APNS__ENVIRONMENT"); v != "" {
		c.APNs.Environment = v
	}
	if v := os.Getenv("FINME_FCM__PROJECT_ID"); v != "" {
		c.FCM.ProjectID = v
	}
	if v := os.Getenv("FINME_FCM__SERVICE_ACCOUNT_JSON"); v != "" {
		c.FCM.ServiceAccountJSON = v
	}
	if v := os.Getenv("FINME_FCM__SERVICE_ACCOUNT_JSON_PATH"); v != "" {
		c.FCM.ServiceAccountJSONPath = v
	}
	if v := os.Getenv("FINME_LLM__API_KEY"); v != "" {
		c.LLM.APIKey = v
	}
	if v := os.Getenv("FINME_LLM__BASE_URL"); v != "" {
		c.LLM.BaseURL = v
	}
	if v := os.Getenv("FINME_LLM__CHAT_MODEL"); v != "" {
		c.LLM.ChatModel = v
	}
	if v := os.Getenv("FINME_LLM__REASON_MODEL"); v != "" {
		c.LLM.ReasonModel = v
	}
	if v := os.Getenv("FINME_TUSHARE__TOKEN"); v != "" {
		c.Tushare.Token = v
	}
	if v := os.Getenv("FINME_TUSHARE__BASE_URL"); v != "" {
		c.Tushare.BaseURL = v
	}
	if v := os.Getenv("FINME_NEWS__FIRMS_MAP_KEY"); v != "" {
		c.News.FirmsMapKey = v
	}
	if v := os.Getenv("DASHSCOPE_API_KEY"); v != "" {
		c.Qwen.APIKey = v
	}
	if v := os.Getenv("FINME_QWEN__API_KEY"); v != "" {
		c.Qwen.APIKey = v
	}
	if v := os.Getenv("FINME_QWEN__BASE_URL"); v != "" {
		c.Qwen.BaseURL = v
	}
	if v := os.Getenv("FINME_QWEN__VISION_MODEL"); v != "" {
		c.Qwen.VisionModel = v
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
