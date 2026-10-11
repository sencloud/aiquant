package main

import (
	"bytes"
	"context"
	"errors"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/rs/zerolog"

	"github.com/sencloud/finme-backend/internal/platform"
	"github.com/sencloud/finme-backend/internal/store"
)

func gateDB(t *testing.T) platform.DBConfig {
	return platform.DBConfig{
		Path: filepath.Join(t.TempDir(), "g.db"), BusyTimeoutMs: 5000,
		CacheKB: 2048, MaxOpenConns: 4, MaxIdleConns: 2,
	}
}

// scheduler / pusher 绝不执行迁移：库是空的时候等到超时退出，且库保持为空。
func TestNonAPIProcessesNeverMigrate(t *testing.T) {
	for _, sub := range []string{"scheduler", "pusher"} {
		t.Run(sub, func(t *testing.T) {
			db := gateDB(t)
			var buf bytes.Buffer
			l := zerolog.New(&buf)
			_, err := openStoreNoMigrate(context.Background(), sub, db, l, 120*time.Millisecond, 20*time.Millisecond)
			if !errors.Is(err, store.ErrSchemaNotReady) {
				t.Fatalf("err=%v, want ErrSchemaNotReady", err)
			}
			if !strings.Contains(buf.String(), "waiting for api to apply db migrations") {
				t.Fatalf("missing wait log: %s", buf.String())
			}
			st, err := store.OpenNoMigrate(db)
			if err != nil {
				t.Fatal(err)
			}
			defer st.Close()
			var n int
			_ = st.DB.Get(&n, `SELECT COUNT(*) FROM sqlite_master WHERE type='table'`)
			if n != 0 {
				t.Fatalf("%s created %d tables", sub, n)
			}
		})
	}
}

// api 先执行迁移后，scheduler / pusher 顺利启动并打出"不迁移"的日志。
func TestNonAPIProcessStartsAfterAPIMigrates(t *testing.T) {
	db := gateDB(t)
	cfg := &platform.Config{DB: db}
	var apiLog bytes.Buffer
	api, err := openStore("api", cfg, zerolog.New(&apiLog), time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer api.Close()
	if !strings.Contains(apiLog.String(), "db migrations applied") {
		t.Fatalf("api log: %s", apiLog.String())
	}

	var buf bytes.Buffer
	st, err := openStore("pusher", cfg, zerolog.New(&buf), time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer st.Close()
	if !strings.Contains(buf.String(), "migrations are owned by api") {
		t.Fatalf("pusher log: %s", buf.String())
	}
	if strings.Contains(buf.String(), "db migrations applied") {
		t.Fatalf("pusher must not migrate")
	}

	// 第二次 api 启动：无事可做。
	var again bytes.Buffer
	api2, err := openStore("api", cfg, zerolog.New(&again), time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer api2.Close()
	if !strings.Contains(again.String(), "no migrations to apply") {
		t.Fatalf("api2 log: %s", again.String())
	}
}
