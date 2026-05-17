// finme-server 是后端三种角色（api / scheduler / pusher）共用的入口。
//
// 用法：
//   finme-server api        --config ./config/config.toml
//   finme-server scheduler  --config ./config/config.toml
//   finme-server pusher     --config ./config/config.toml
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	"github.com/rs/zerolog"

	"github.com/sencloud/finme-backend/internal/api"
	"github.com/sencloud/finme-backend/internal/auth"
	"github.com/sencloud/finme-backend/internal/billing"
	"github.com/sencloud/finme-backend/internal/devices"
	"github.com/sencloud/finme-backend/internal/ding"
	"github.com/sencloud/finme-backend/internal/platform"
	"github.com/sencloud/finme-backend/internal/push"
	"github.com/sencloud/finme-backend/internal/scheduler"
	"github.com/sencloud/finme-backend/internal/store"
	"github.com/sencloud/finme-backend/internal/users"

	"time"
)

// Version 在编译时通过 -ldflags 注入。
var Version = "dev"

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	sub := os.Args[1]
	args := os.Args[2:]

	fs := flag.NewFlagSet("finme-server "+sub, flag.ExitOnError)
	configPath := fs.String("config", "./config/config.toml", "path to TOML config")
	if err := fs.Parse(args); err != nil {
		os.Exit(2)
	}

	cfg, err := platform.LoadConfig(*configPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, "load config:", err)
		os.Exit(1)
	}
	logger := platform.NewLogger(cfg.LogLevel, cfg.Env)
	logger.Info().Str("version", Version).Str("env", cfg.Env).Str("cmd", sub).
		Msg("starting finme-server")

	st, err := store.Open(cfg.DB)
	if err != nil {
		logger.Fatal().Err(err).Msg("open store")
	}
	defer func() { _ = st.Close() }()

	switch sub {
	case "api":
		runAPI(cfg, logger, st)
	case "scheduler":
		runScheduler(cfg, logger, st)
	case "pusher":
		runPusher(cfg, logger, st)
	default:
		usage()
		os.Exit(2)
	}
}

func usage() {
	fmt.Fprintln(os.Stderr, "usage: finme-server <api|scheduler|pusher> [--config path]")
}

func runAPI(cfg *platform.Config, l zerolog.Logger, st *store.Store) {
	usersSvc := users.NewService(st, cfg)
	devicesSvc := devices.NewService(st)
	authSvc, err := auth.NewService(st, cfg, usersSvc)
	if err != nil {
		l.Fatal().Err(err).Msg("init auth")
	}
	billingSvc, err := billing.NewService(st, cfg)
	if err != nil {
		l.Fatal().Err(err).Msg("init billing")
	}
	dingSvc := ding.NewService(st, cfg)

	deps := &api.Deps{
		Config:  cfg,
		Logger:  l,
		Store:   st,
		Auth:    authSvc,
		Users:   usersSvc,
		Devices: devicesSvc,
		Billing: billingSvc,
		Ding:    dingSvc,
	}
	router := api.NewRouter(deps)

	srv := &http.Server{
		Addr:         cfg.Server.Listen,
		Handler:      router,
		ReadTimeout:  cfg.Server.ReadTimeout(),
		WriteTimeout: cfg.Server.WriteTimeout(),
	}

	go func() {
		l.Info().Str("listen", cfg.Server.Listen).Msg("api listening")
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			l.Fatal().Err(err).Msg("listen and serve")
		}
	}()

	waitForSignal()
	l.Info().Msg("shutting down")
	ctx, cancel := context.WithTimeout(context.Background(), cfg.Server.ShutdownTimeout())
	defer cancel()
	if err := srv.Shutdown(ctx); err != nil {
		l.Error().Err(err).Msg("graceful shutdown failed")
	}
	l.Info().Msg("bye")
}

func waitForSignal() {
	ch := make(chan os.Signal, 1)
	signal.Notify(ch, syscall.SIGINT, syscall.SIGTERM)
	<-ch
}

// runScheduler 启动 finme-server scheduler 子进程：
// - 余额对账（每 5 分钟）
// 后续：服务端 LLM DING 任务调度
func runScheduler(_ *platform.Config, l zerolog.Logger, st *store.Store) {
	sch := scheduler.New(&l)
	sch.Register(scheduler.NewReconcileBalance(st, &l, 5*time.Minute))

	ctx, cancel := signalCtx()
	defer cancel()
	if err := sch.Run(ctx); err != nil && err != context.Canceled {
		l.Error().Err(err).Msg("scheduler exited with error")
	}
}

// runPusher 启动 finme-server pusher 子进程：
// 轮询 notifications.push_status='pending' → 调 PushSender → 标 pushed/failed。
// 当前 sender 为 Mock；接入 APNs/.p8 与 FCM service-account 后切到真实现。
func runPusher(_ *platform.Config, l zerolog.Logger, st *store.Store) {
	devSvc := devices.NewService(st)
	w := push.NewWorker(st, devSvc, &l, push.WorkerConfig{
		APNs:     push.MockPushSender{},
		FCM:      push.MockPushSender{},
		Interval: 5 * time.Second,
	})
	ctx, cancel := signalCtx()
	defer cancel()
	if err := w.Run(ctx); err != nil && err != context.Canceled {
		l.Error().Err(err).Msg("pusher exited with error")
	}
}

// signalCtx 返回一个 SIGINT/SIGTERM 取消的 context。
func signalCtx() (context.Context, context.CancelFunc) {
	ctx, cancel := context.WithCancel(context.Background())
	go func() {
		ch := make(chan os.Signal, 1)
		signal.Notify(ch, syscall.SIGINT, syscall.SIGTERM)
		<-ch
		cancel()
	}()
	return ctx, cancel
}
