package onboarding

import (
	"context"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/sencloud/finme-backend/internal/billing"
	"github.com/sencloud/finme-backend/internal/ding"
	"github.com/sencloud/finme-backend/internal/platform"
	"github.com/sencloud/finme-backend/internal/shell"
	"github.com/sencloud/finme-backend/internal/store"
	"github.com/sencloud/finme-backend/internal/users"
)

func TestSignupGrantsCreditsAndNoShellsWhenFrozen(t *testing.T) {
	shell.SetFrozen(true)
	defer shell.SetFrozen(false)
	st, err := store.Open(platform.DBConfig{
		Path:          filepath.Join(t.TempDir(), "onboarding_test.db"),
		BusyTimeoutMs: 5000, CacheKB: 4096, MaxOpenConns: 2, MaxIdleConns: 1,
	})
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	now := time.Now().UnixMilli()
	res, err := st.DB.Exec(`INSERT INTO users(uuid, status, credit_balance, created_at, updated_at)
		VALUES('u-1', 'active', 0, ?, ?)`, now, now)
	if err != nil {
		t.Fatal(err)
	}
	uid, _ := res.LastInsertId()
	svc := New(st, billing.NewLedgerRepo(st), ding.NewTaskRepo(st), ding.NewNotificationRepo(st),
		shell.NewRepo(st), 100, Options{SignupCredits: 60, ChatCredits: 1, DeepBonus: 5})
	u := &users.User{ID: uid, UUID: "u-1", Status: string(users.StatusActive)}
	for i := 0; i < 2; i++ { // 幂等：调两次只发一次
		if err := svc.OnboardIfNeeded(context.Background(), u); err != nil {
			t.Fatal(err)
		}
	}
	var credits, shells int64
	_ = st.DB.QueryRow("SELECT credit_balance, shell_balance FROM users WHERE id=?", uid).Scan(&credits, &shells)
	if credits != 60 || shells != 0 {
		t.Fatalf("credits=%d shells=%d, want 60/0", credits, shells)
	}
	var brief string
	_ = st.DB.Get(&brief, "SELECT body_brief FROM notifications WHERE user_id=?", uid)
	if !strings.Contains(brief, "60 喜点") {
		t.Fatalf("welcome brief: %q", brief)
	}
	if p := svc.welcomePayload(); !strings.Contains(p, "每轮对话消耗 **1 喜点**") || strings.Contains(p, "6 喜点") {
		t.Fatalf("welcome payload pricing wrong: %s", p)
	}
}
