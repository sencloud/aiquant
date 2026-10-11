package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"strings"
	"testing"

	"github.com/rs/zerolog"

	"github.com/sencloud/finme-backend/internal/platform"
	"github.com/sencloud/finme-backend/internal/topic"
)

// TestTopicToolWhitelistOnRealRegistry 用生产同一份注册表验证主题白名单：
// 钓鱼主题只拿到钓鱼工具 + 天气，钱主题拿不到钓鱼工具，白名单外的调用被拒绝。
func TestTopicToolWhitelistOnRealRegistry(t *testing.T) {
	b64 := base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{7}, 32))
	t.Setenv("FINME_SECURITY__JWT_SECRET", b64)
	t.Setenv("FINME_SECURITY__PHONE_HMAC_KEY", b64)
	t.Setenv("FINME_SECURITY__PHONE_AES_KEY", b64)
	cfg, err := platform.LoadConfig("")
	if err != nil {
		t.Fatal(err)
	}
	l := zerolog.Nop()
	reg := buildToolRegistryWithIngest(cfg, &l, nil)
	all := reg.Names()

	fish := topic.MustGet(topic.Fishing)
	got := strings.Join(fish.AllowedTools(all), ",")
	if got != "get_fishing_forecast,get_fishing_regulations,get_region_weather" {
		t.Fatalf("fishing tools = %s", got)
	}
	money := topic.MustGet(topic.Money)
	mt := money.AllowedTools(all)
	for _, n := range mt {
		if strings.HasPrefix(n, "get_fishing_") {
			t.Fatalf("money topic leaked %s", n)
		}
	}
	if len(mt) != len(all)-len(topic.FishingOnlyTools) {
		t.Fatalf("money tools %d, all %d", len(mt), len(all))
	}

	view := reg.Subset(fish.ID, fish.AllowedTools(all))
	out := view.Dispatch(context.Background(), "get_quote", `{"symbol":"600519.SH"}`)
	if !strings.Contains(out, "error") {
		t.Fatalf("fishing view should reject get_quote: %s", out)
	}
	out = view.Dispatch(context.Background(), "get_fishing_regulations", `{"date":"2026-05-20"}`)
	if !strings.Contains(out, "以当地渔政部门公告为准") {
		t.Fatalf("regulations via fishing view: %s", out)
	}
}
