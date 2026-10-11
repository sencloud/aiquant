package store

import (
	"context"
	"errors"
	"path/filepath"
	"testing"
	"time"

	"github.com/sencloud/finme-backend/internal/platform"
)

func testDBConfig(t *testing.T) platform.DBConfig {
	t.Helper()
	return platform.DBConfig{
		Path:          filepath.Join(t.TempDir(), "t.db"),
		BusyTimeoutMs: 5000,
		CacheKB:       2048,
		MaxOpenConns:  4,
		MaxIdleConns:  2,
	}
}

func TestOpenNoMigrateDoesNotTouchSchema(t *testing.T) {
	cfg := testDBConfig(t)
	st, err := OpenNoMigrate(cfg)
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()

	var n int
	if err := st.DB.Get(&n, `SELECT COUNT(*) FROM sqlite_master WHERE type='table'`); err != nil {
		t.Fatal(err)
	}
	if n != 0 {
		t.Fatalf("OpenNoMigrate created %d tables, want 0", n)
	}
	files, err := EmbeddedMigrations()
	if err != nil {
		t.Fatal(err)
	}
	pending, err := st.PendingMigrations(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if len(pending) != len(files) || len(files) == 0 {
		t.Fatalf("pending=%d embedded=%d", len(pending), len(files))
	}
	// PendingMigrations 是只读的：检查之后依然没有建表。
	if err := st.DB.Get(&n, `SELECT COUNT(*) FROM sqlite_master WHERE type='table'`); err != nil {
		t.Fatal(err)
	}
	if n != 0 {
		t.Fatalf("PendingMigrations created tables")
	}
}

func TestMigrateIsIdempotentAndReportsRan(t *testing.T) {
	cfg := testDBConfig(t)
	st, err := OpenNoMigrate(cfg)
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	files, _ := EmbeddedMigrations()
	ran, err := st.Migrate()
	if err != nil {
		t.Fatal(err)
	}
	if len(ran) != len(files) {
		t.Fatalf("first Migrate ran %d, want %d", len(ran), len(files))
	}
	ran, err = st.Migrate()
	if err != nil {
		t.Fatal(err)
	}
	if len(ran) != 0 {
		t.Fatalf("second Migrate ran %v, want none", ran)
	}
	pending, err := st.PendingMigrations(context.Background())
	if err != nil || len(pending) != 0 {
		t.Fatalf("pending=%v err=%v", pending, err)
	}
}

func TestWaitForSchemaTimesOutWhenNobodyMigrates(t *testing.T) {
	cfg := testDBConfig(t)
	st, err := OpenNoMigrate(cfg)
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	waits := 0
	start := time.Now()
	err = st.WaitForSchema(context.Background(), 150*time.Millisecond, 20*time.Millisecond,
		func([]string) { waits++ })
	if !errors.Is(err, ErrSchemaNotReady) {
		t.Fatalf("err=%v, want ErrSchemaNotReady", err)
	}
	if time.Since(start) < 150*time.Millisecond {
		t.Fatalf("returned before timeout")
	}
	if waits == 0 {
		t.Fatalf("onWait never called")
	}
	var n int
	_ = st.DB.Get(&n, `SELECT COUNT(*) FROM sqlite_master WHERE type='table'`)
	if n != 0 {
		t.Fatalf("waiting process created %d tables", n)
	}
}

func TestWaitForSchemaReturnsOnceAnotherProcessMigrates(t *testing.T) {
	cfg := testDBConfig(t)
	waiter, err := OpenNoMigrate(cfg)
	if err != nil {
		t.Fatal(err)
	}
	defer waiter.Close()

	go func() {
		time.Sleep(100 * time.Millisecond)
		api, err := Open(cfg) // api 路径：执行迁移
		if err == nil {
			_ = api.Close()
		}
	}()
	if err := waiter.WaitForSchema(context.Background(), 10*time.Second, 20*time.Millisecond, nil); err != nil {
		t.Fatalf("WaitForSchema: %v", err)
	}
}

func TestWaitForSchemaHonoursContext(t *testing.T) {
	cfg := testDBConfig(t)
	st, err := OpenNoMigrate(cfg)
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()
	err = st.WaitForSchema(ctx, time.Minute, 10*time.Millisecond, nil)
	if !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("err=%v", err)
	}
}
