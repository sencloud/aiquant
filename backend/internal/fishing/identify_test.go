package fishing

import (
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"

	"github.com/sencloud/finme-backend/internal/billing"
	"github.com/sencloud/finme-backend/internal/platform"
	"github.com/sencloud/finme-backend/internal/store"
)

func openStore(t *testing.T) *store.Store {
	t.Helper()
	st, err := store.Open(platform.DBConfig{
		Path:          filepath.Join(t.TempDir(), "fishing_test.db"),
		BusyTimeoutMs: 5000, CacheKB: 4096, MaxOpenConns: 2, MaxIdleConns: 1,
	})
	if err != nil {
		t.Fatalf("open store: %v", err)
	}
	t.Cleanup(func() { _ = st.Close() })
	return st
}

var userSeq atomic.Int64

func newUser(t *testing.T, st *store.Store, balance int64) int64 {
	t.Helper()
	now := time.Now().UnixMilli()
	res, err := st.DB.Exec(`INSERT INTO users(uuid, status, credit_balance, created_at, updated_at)
		VALUES(?, 'active', ?, ?, ?)`, fmt.Sprintf("fu-%d", userSeq.Add(1)), balance, now, now)
	if err != nil {
		t.Fatalf("insert user: %v", err)
	}
	id, _ := res.LastInsertId()
	return id
}

func balanceOf(t *testing.T, st *store.Store, uid int64) int64 {
	t.Helper()
	var b int64
	if err := st.DB.Get(&b, "SELECT credit_balance FROM users WHERE id=?", uid); err != nil {
		t.Fatal(err)
	}
	return b
}

func ledgerCount(t *testing.T, st *store.Store, uid int64, reason string) int {
	t.Helper()
	var n int
	if err := st.DB.Get(&n, "SELECT COUNT(*) FROM credit_ledger WHERE user_id=? AND reason=?", uid, reason); err != nil {
		t.Fatal(err)
	}
	return n
}

type fakeVision struct {
	calls int
	res   IdentifyResult
	err   error
}

func (f *fakeVision) Configured() bool { return true }
func (f *fakeVision) ImageJSON(_ context.Context, _, _, _ string, out any) error {
	f.calls++
	if f.err != nil {
		return f.err
	}
	*(out.(*IdentifyResult)) = f.res
	return nil
}

var img = "data:image/jpeg;base64," + base64.StdEncoding.EncodeToString([]byte("fake-jpeg"))

func TestIdentifyChargesOnceAndReplays(t *testing.T) {
	st := openStore(t)
	uid := newUser(t, st, 10)
	v := &fakeVision{res: IdentifyResult{IsFish: true, Candidates: []Candidate{
		{Name: "鲫鱼", Confidence: 92}, {Name: "胭脂鱼", Confidence: 0.05}, {Name: ""},
	}}}
	id := NewIdentifier(st, v, nil)
	ctx := context.Background()

	r1, err := id.Identify(ctx, uid, "req-aaaaaaaa", img)
	if err != nil {
		t.Fatal(err)
	}
	if r1.Status != IdentifyDone || r1.Credits != 3 || r1.Replayed || r1.Disclaimer == "" {
		t.Fatalf("r1 %+v", r1)
	}
	if len(r1.Result.Candidates) != 2 || r1.Result.Candidates[0].Confidence != 0.92 || !r1.Result.Candidates[1].Protected {
		t.Fatalf("normalize %+v", r1.Result.Candidates)
	}
	if balanceOf(t, st, uid) != 7 {
		t.Fatalf("balance %d", balanceOf(t, st, uid))
	}
	// 同一 request_id 重放：不再扣费，不再调模型
	r2, err := id.Identify(ctx, uid, "req-aaaaaaaa", img)
	if err != nil || !r2.Replayed || r2.Status != IdentifyDone || v.calls != 1 {
		t.Fatalf("replay %+v %v calls=%d", r2, err, v.calls)
	}
	if balanceOf(t, st, uid) != 7 || ledgerCount(t, st, uid, billing.ReasonFishingIdentify) != 1 {
		t.Fatal("replay charged again")
	}
	// 另一个用户用同一个 request_id：各扣各的（ref_id 带 user_id）
	uid2 := newUser(t, st, 3)
	if r, err := id.Identify(ctx, uid2, "req-aaaaaaaa", img); err != nil || r.Status != IdentifyDone {
		t.Fatalf("user2 %+v %v", r, err)
	}
	if balanceOf(t, st, uid2) != 0 {
		t.Fatal("user2 balance")
	}
	// 余额不足：整体回滚，不留 pending
	if _, err := id.Identify(ctx, uid2, "req-bbbbbbbb", img); !errors.Is(err, billing.ErrInsufficientBalance) {
		t.Fatalf("want insufficient, got %v", err)
	}
	var n int
	_ = st.DB.Get(&n, "SELECT COUNT(*) FROM fishing_identifications WHERE user_id=?", uid2)
	if n != 1 {
		t.Fatalf("rows %d", n)
	}
}

func TestIdentifyRefundsOnFailure(t *testing.T) {
	st := openStore(t)
	uid := newUser(t, st, 5)
	ctx := context.Background()

	v := &fakeVision{err: errors.New("upstream 500")}
	id := NewIdentifier(st, v, nil)
	r, err := id.Identify(ctx, uid, "req-fail0001", img)
	if err != nil || r.Status != IdentifyFailed || !r.Refunded || r.Error == "" {
		t.Fatalf("fail %+v %v", r, err)
	}
	if balanceOf(t, st, uid) != 5 {
		t.Fatalf("not refunded: %d", balanceOf(t, st, uid))
	}
	// 不是鱼也退款
	v.err, v.res = nil, IdentifyResult{IsFish: false}
	r, _ = id.Identify(ctx, uid, "req-fail0002", img)
	if r.Status != IdentifyFailed || balanceOf(t, st, uid) != 5 {
		t.Fatalf("not-fish %+v bal=%d", r, balanceOf(t, st, uid))
	}
	// 失败重放：不扣不退
	r, _ = id.Identify(ctx, uid, "req-fail0002", img)
	if !r.Replayed || r.Status != IdentifyFailed || balanceOf(t, st, uid) != 5 {
		t.Fatal("failed replay")
	}
	if ledgerCount(t, st, uid, billing.ReasonFishingIdentify) != 2 || ledgerCount(t, st, uid, billing.ReasonFishingIdentifyRefund) != 2 {
		t.Fatal("ledger rows")
	}
	// 退款幂等：重复 failAndRefund 不会多退
	row, _ := id.find(ctx, uid, "req-fail0001")
	if _, err := id.failAndRefund(ctx, row, "again"); err != nil {
		t.Fatal(err)
	}
	if balanceOf(t, st, uid) != 5 || ledgerCount(t, st, uid, billing.ReasonFishingIdentifyRefund) != 2 {
		t.Fatal("double refund")
	}
}

func TestIdentifyValidationAndPending(t *testing.T) {
	st := openStore(t)
	uid := newUser(t, st, 10)
	ctx := context.Background()
	id := NewIdentifier(st, &fakeVision{}, nil)
	if _, err := id.Identify(ctx, uid, "short", img); !errors.Is(err, ErrBadRequestID) {
		t.Fatal(err)
	}
	if _, err := id.Identify(ctx, uid, "req-cccccccc", "data:text/plain;base64,aGk="); !errors.Is(err, ErrBadImage) {
		t.Fatal(err)
	}
	if NewIdentifier(st, nil, nil) == nil {
		t.Fatal("nil")
	}
	if _, err := NewIdentifier(st, nil, nil).Identify(ctx, uid, "req-cccccccc", img); !errors.Is(err, ErrIdentifyUnavailable) {
		t.Fatal(err)
	}
	// 模拟进程在调用模型时崩溃：留下 pending
	now := time.Now().Add(-10 * time.Minute).UnixMilli()
	if _, err := billing.NewLedgerRepo(st).Apply(ctx, billing.ApplyParams{UserID: uid, Delta: -3,
		Reason: billing.ReasonFishingIdentify, RefType: IdentifyRefType, RefID: refID(uid, "req-pending1")}); err != nil {
		t.Fatal(err)
	}
	_, _ = st.DB.Exec(`INSERT INTO fishing_identifications(user_id, request_id, status, credits, created_at, updated_at)
		VALUES(?, 'req-pending1', 'pending', 3, ?, ?)`, uid, now, now)
	if _, err := id.Identify(ctx, uid, "req-pending1", img); !errors.Is(err, ErrIdentifyInProgress) {
		t.Fatalf("pending: %v", err)
	}
	if n, err := id.RecoverStale(ctx, 5*time.Minute); err != nil || n != 1 {
		t.Fatalf("recover %d %v", n, err)
	}
	if balanceOf(t, st, uid) != 10 {
		t.Fatalf("recover refund %d", balanceOf(t, st, uid))
	}
}
