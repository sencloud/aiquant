package shell

import (
	"context"
	"errors"
	"path/filepath"
	"testing"
	"time"

	"github.com/sencloud/finme-backend/internal/platform"
	"github.com/sencloud/finme-backend/internal/store"
)

func TestFrozenBlocksEarnAndSpendButKeepsRefunds(t *testing.T) {
	st, err := store.Open(platform.DBConfig{
		Path:          filepath.Join(t.TempDir(), "shell_test.db"),
		BusyTimeoutMs: 5000, CacheKB: 4096, MaxOpenConns: 2, MaxIdleConns: 1,
	})
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	now := time.Now().UnixMilli()
	res, _ := st.DB.Exec(`INSERT INTO users(uuid, status, credit_balance, shell_balance, created_at, updated_at)
		VALUES('u', 'active', 0, 80, ?, ?)`, now, now)
	uid, _ := res.LastInsertId()
	repo := NewRepo(st)
	ctx := context.Background()

	SetFrozen(true)
	defer SetFrozen(false)
	for _, reason := range []string{ReasonSignupGift, ReasonInviteReward, ReasonBotFunding} {
		if _, err := repo.Apply(ctx, ApplyParams{UserID: uid, Delta: 10, Reason: reason, RefType: "t", RefID: reason}); !errors.Is(err, ErrFrozen) {
			t.Fatalf("%s: want ErrFrozen, got %v", reason, err)
		}
	}
	if _, err := repo.Apply(ctx, ApplyParams{UserID: uid, Delta: -10, Reason: ReasonBetStake, RefType: "bet", RefID: "1"}); !errors.Is(err, ErrFrozen) {
		t.Fatalf("bet stake: want ErrFrozen, got %v", err)
	}
	// 已下注的退款照常（不吞用户的螺壳）。
	if _, err := repo.Apply(ctx, ApplyParams{UserID: uid, Delta: 10, Reason: ReasonBetRefund, RefType: "bet", RefID: "0"}); err != nil {
		t.Fatalf("refund should pass: %v", err)
	}
	if b, _ := repo.Balance(ctx, uid); b != 90 {
		t.Fatalf("balance = %d, want 90 (retained + refund)", b)
	}
}
