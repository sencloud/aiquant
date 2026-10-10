package api

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/rs/zerolog"

	"github.com/sencloud/finme-backend/internal/auth"
	"github.com/sencloud/finme-backend/internal/falsification"
	"github.com/sencloud/finme-backend/internal/invite"
	"github.com/sencloud/finme-backend/internal/platform"
	"github.com/sencloud/finme-backend/internal/store"
	"github.com/sencloud/finme-backend/internal/users"
)

type testEnv struct {
	router http.Handler
	st     *store.Store
	key    []byte
}

func newTestEnv(t *testing.T) *testEnv {
	t.Helper()
	key := bytes.Repeat([]byte{7}, 32)
	b64 := base64.StdEncoding.EncodeToString(key)
	t.Setenv("FINME_SECURITY__JWT_SECRET", b64)
	t.Setenv("FINME_SECURITY__PHONE_HMAC_KEY", b64)
	t.Setenv("FINME_SECURITY__PHONE_AES_KEY", b64)
	cfg, err := platform.LoadConfig("")
	if err != nil {
		t.Fatal(err)
	}
	st, err := store.Open(platform.DBConfig{
		Path:          filepath.Join(t.TempDir(), "api_test.db"),
		BusyTimeoutMs: 5000, CacheKB: 4096, MaxOpenConns: 2, MaxIdleConns: 1,
	})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = st.Close() })
	usersSvc := users.NewService(st, cfg)
	authSvc, err := auth.NewService(st, cfg, usersSvc)
	if err != nil {
		t.Fatal(err)
	}
	l := zerolog.Nop()
	d := &Deps{
		Config: cfg, Logger: l, Store: st, Auth: authSvc, Users: usersSvc,
		Invite: invite.NewService(st, cfg.Credits.InviteReward),
		Falsification: falsification.NewService(st, &l, falsification.Options{Prices: falsification.Prices{
			Unlock: cfg.Credits.UnlockEntry, FalsifyDaily: cfg.Credits.FalsifyDaily, FalsifyMinute: cfg.Credits.FalsifyMinute,
		}}),
	}
	return &testEnv{router: NewRouter(d), st: st, key: key}
}

// userSeq 生成唯一 uuid（Windows 上纳秒时钟分辨率不够，不能拿时间当唯一值）。
var userSeq atomic.Int64

func (e *testEnv) user(t *testing.T, balance int64) (int64, string) {
	t.Helper()
	now := time.Now()
	uuid := fmt.Sprintf("u-%d", userSeq.Add(1))
	res, err := e.st.DB.Exec(`INSERT INTO users(uuid, status, credit_balance, created_at, updated_at)
		VALUES(?, 'active', ?, ?, ?)`, uuid, balance, now.UnixMilli(), now.UnixMilli())
	if err != nil {
		t.Fatal(err)
	}
	id, _ := res.LastInsertId()
	tok := jwt.NewWithClaims(jwt.SigningMethodHS256, auth.Claims{
		UserID: id, UserUUID: uuid, JTI: "j", Type: "access",
		RegisteredClaims: jwt.RegisteredClaims{
			Issuer: "finme", Subject: uuid,
			IssuedAt:  jwt.NewNumericDate(now),
			ExpiresAt: jwt.NewNumericDate(now.Add(time.Hour)),
		},
	})
	signed, err := tok.SignedString(e.key)
	if err != nil {
		t.Fatal(err)
	}
	return id, signed
}

func (e *testEnv) do(t *testing.T, method, path, token string, body any) (*httptest.ResponseRecorder, map[string]any) {
	t.Helper()
	var buf bytes.Buffer
	if body != nil {
		_ = json.NewEncoder(&buf).Encode(body)
	}
	req := httptest.NewRequest(method, path, &buf)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	rec := httptest.NewRecorder()
	e.router.ServeHTTP(rec, req)
	var out map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	return rec, out
}

func TestFalsificationPublicEndpointNoAuth(t *testing.T) {
	e := newTestEnv(t)
	rec, out := e.do(t, http.MethodGet, "/v1/strategy/falsification", "", nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d: %s", rec.Code, rec.Body.String())
	}
	if strings.Contains(rec.Body.String(), "report_url") {
		t.Fatal("report_url leaked")
	}
	if out["origin"] != falsification.OriginSeed {
		t.Fatalf("origin = %v, want seed fallback", out["origin"])
	}
	arch, _ := out["archive"].([]any)
	if len(arch) == 0 {
		t.Fatal("empty archive")
	}
	for _, a := range arch {
		m := a.(map[string]any)
		if m["locked"] == true && (m["mechanism"] != nil || m["yearly"] != nil || m["command"] != nil) {
			t.Fatalf("paid fields leaked for anonymous: %v", m["id"])
		}
	}
	if p, _ := out["prices"].(map[string]any); p["unlock"] != float64(5) {
		t.Fatalf("prices = %v", out["prices"])
	}
	rec, _ = e.do(t, http.MethodGet, "/v1/strategy/falsification/run-options", "", nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("run-options status %d", rec.Code)
	}
}

func TestFalsificationPrivateEndpointsRequireAuth(t *testing.T) {
	e := newTestEnv(t)
	for _, c := range []struct{ m, p string }{
		{http.MethodGet, "/v1/strategy/falsification/unlocks"},
		{http.MethodPost, "/v1/strategy/falsification/utbot-5min/unlock"},
		{http.MethodGet, "/v1/strategy/falsification/utbot-5min/detail"},
		{http.MethodPost, "/v1/strategy/falsification/runs"},
		{http.MethodGet, "/v1/strategy/falsification/runs"},
		{http.MethodGet, "/v1/invite"},
		{http.MethodPost, "/v1/invite/redeem"},
	} {
		rec, _ := e.do(t, c.m, c.p, "", nil)
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("%s %s: status %d, want 401", c.m, c.p, rec.Code)
		}
	}
}

func TestFalsificationUnlockFlow(t *testing.T) {
	e := newTestEnv(t)
	_, tok := e.user(t, 7)

	rec, out := e.do(t, http.MethodPost, "/v1/strategy/falsification/utbot-5min/unlock", tok, nil)
	if rec.Code != http.StatusOK || out["charged"] != float64(5) || out["balance"] != float64(2) {
		t.Fatalf("unlock: %d %v", rec.Code, out)
	}
	rec, out = e.do(t, http.MethodPost, "/v1/strategy/falsification/utbot-5min/unlock", tok, nil)
	if rec.Code != http.StatusOK || out["charged"] != float64(0) || out["already"] != true {
		t.Fatalf("re-unlock: %d %v", rec.Code, out)
	}
	// 带 token 读公开接口：已解锁条目带上付费字段。
	_, out = e.do(t, http.MethodGet, "/v1/strategy/falsification", tok, nil)
	found := false
	for _, a := range out["archive"].([]any) {
		m := a.(map[string]any)
		if m["id"] == "utbot-5min" {
			found = true
			if m["locked"] != false || m["mechanism"] == nil {
				t.Fatalf("unlocked entry should include paid fields: %v", m)
			}
		}
	}
	if !found {
		t.Fatal("utbot-5min missing")
	}
	// 余额不足 → 402。
	rec, out = e.do(t, http.MethodPost, "/v1/strategy/falsification/orb-5min/unlock", tok, nil)
	if rec.Code != http.StatusPaymentRequired || out["code"] != "FALSIFICATION.INSUFFICIENT_BALANCE" {
		t.Fatalf("insufficient: %d %v", rec.Code, out)
	}
	rec, _ = e.do(t, http.MethodPost, "/v1/strategy/falsification/nope/unlock", tok, nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("not found: %d", rec.Code)
	}
	// 跑一次证伪：stub → 202 unsupported，不扣费。
	rec, out = e.do(t, http.MethodPost, "/v1/strategy/falsification/runs", tok,
		map[string]string{"strategy": "utbot", "symbol": "P.DCE", "freq": "1d"})
	if rec.Code != http.StatusAccepted || out["balance"] != float64(2) {
		t.Fatalf("run: %d %v", rec.Code, out)
	}
	run := out["run"].(map[string]any)
	if run["status"] != falsification.RunUnsupported {
		t.Fatalf("run status = %v", run["status"])
	}
	rec, _ = e.do(t, http.MethodGet, "/v1/strategy/falsification/runs/"+run["id"].(string), tok, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("get run: %d", rec.Code)
	}
}

func TestInviteEndpointGrantsCredits(t *testing.T) {
	e := newTestEnv(t)
	_, inviterTok := e.user(t, 0)
	_, inviteeTok := e.user(t, 0)
	rec, out := e.do(t, http.MethodGet, "/v1/invite", inviterTok, nil)
	if rec.Code != http.StatusOK || out["reward_each"] != float64(100) || out["reward_unit"] != "credit" {
		t.Fatalf("invite info: %d %v", rec.Code, out)
	}
	rec, out = e.do(t, http.MethodPost, "/v1/invite/redeem", inviteeTok, map[string]string{"code": out["code"].(string)})
	if rec.Code != http.StatusOK || out["balance"] != float64(100) {
		t.Fatalf("redeem: %d %v", rec.Code, out)
	}
}
