package invite

import (
	"context"
	"errors"
	"fmt"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"

	"github.com/sencloud/finme-backend/internal/billing"
	"github.com/sencloud/finme-backend/internal/platform"
	"github.com/sencloud/finme-backend/internal/shell"
	"github.com/sencloud/finme-backend/internal/store"
)

func openStore(t *testing.T) *store.Store {
	t.Helper()
	st, err := store.Open(platform.DBConfig{
		Path:          filepath.Join(t.TempDir(), "invite_test.db"),
		BusyTimeoutMs: 5000, CacheKB: 4096, MaxOpenConns: 2, MaxIdleConns: 1,
	})
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	t.Cleanup(func() { _ = st.Close() })
	return st
}

// userSeq 生成唯一 uuid（Windows 上纳秒时钟分辨率不够，不能拿时间当唯一值）。
var userSeq atomic.Int64

func newUser(t *testing.T, st *store.Store, createdAt int64) int64 {
	t.Helper()
	res, err := st.DB.Exec(`INSERT INTO users(uuid, status, credit_balance, created_at, updated_at)
		VALUES(?, 'active', 0, ?, ?)`, fmt.Sprintf("u-%d", userSeq.Add(1)), createdAt, createdAt)
	if err != nil {
		t.Fatal(err)
	}
	id, _ := res.LastInsertId()
	return id
}

func balances(t *testing.T, st *store.Store, uid int64) (credits, shells int64) {
	t.Helper()
	if err := st.DB.QueryRow("SELECT credit_balance, shell_balance FROM users WHERE id=?", uid).
		Scan(&credits, &shells); err != nil {
		t.Fatal(err)
	}
	return
}

func TestRedeemGrantsCreditsToBothSidesOnce(t *testing.T) {
	shell.SetFrozen(true)
	defer shell.SetFrozen(false)
	st := openStore(t)
	svc := NewService(st, 100)
	ctx := context.Background()
	now := time.Now().UnixMilli()
	inviter := newUser(t, st, now-10*24*3600*1000)
	invitee := newUser(t, st, now)

	code, err := svc.EnsureCode(ctx, inviter)
	if err != nil {
		t.Fatal(err)
	}
	info, err := svc.Redeem(ctx, invitee, code)
	if err != nil {
		t.Fatal(err)
	}
	if !info.Redeemed || info.RewardEach != 100 || info.RewardUnit != RewardUnitCredit {
		t.Fatalf("info: %+v", info)
	}
	for _, uid := range []int64{inviter, invitee} {
		c, s := balances(t, st, uid)
		if c != 100 || s != 0 {
			t.Fatalf("user %d credits=%d shells=%d", uid, c, s)
		}
	}
	var n int
	_ = st.DB.Get(&n, "SELECT COUNT(*) FROM credit_ledger WHERE reason=?", billing.ReasonGrantInvite)
	if n != 2 {
		t.Fatalf("grant_invite rows = %d", n)
	}

	// 再兑换一次：拒绝，余额不变。
	if _, err := svc.Redeem(ctx, invitee, code); !errors.Is(err, ErrAlreadyRedeemed) {
		t.Fatalf("want ErrAlreadyRedeemed, got %v", err)
	}
	if c, _ := balances(t, st, invitee); c != 100 {
		t.Fatalf("credits changed on duplicate redeem: %d", c)
	}
	inf, _ := svc.GetInfo(ctx, inviter)
	if inf.InvitedCount != 1 || inf.TotalReward != 100 {
		t.Fatalf("inviter info: %+v", inf)
	}

	// 自己的码、老用户都不能兑。
	if _, err := svc.Redeem(ctx, inviter, code); !errors.Is(err, ErrSelfInvite) {
		t.Fatalf("self invite: %v", err)
	}
	old := newUser(t, st, now-5*24*3600*1000)
	if _, err := svc.Redeem(ctx, old, code); !errors.Is(err, ErrNotNewUser) {
		t.Fatalf("old user: %v", err)
	}
}

func TestLedgerIdempotencyForInviteGrant(t *testing.T) {
	st := openStore(t)
	uid := newUser(t, st, time.Now().UnixMilli())
	repo := billing.NewLedgerRepo(st)
	p := billing.ApplyParams{UserID: uid, Delta: 100, Reason: billing.ReasonGrantInvite,
		RefType: "invite_invitee", RefID: "42"}
	if _, err := repo.Apply(context.Background(), p); err != nil {
		t.Fatal(err)
	}
	if _, err := repo.Apply(context.Background(), p); !errors.Is(err, billing.ErrLedgerDuplicate) {
		t.Fatalf("want duplicate, got %v", err)
	}
	if c, _ := balances(t, st, uid); c != 100 {
		t.Fatalf("credits = %d", c)
	}
}
