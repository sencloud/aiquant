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

	"github.com/sencloud/finme-backend/internal/ai/chat"
	"github.com/sencloud/finme-backend/internal/ai/qwen"
	"github.com/sencloud/finme-backend/internal/ai/calendar"
	"github.com/sencloud/finme-backend/internal/ai/cnnews"
	"github.com/sencloud/finme-backend/internal/ai/news"
	"github.com/sencloud/finme-backend/internal/ai/realtime"
	"github.com/sencloud/finme-backend/internal/ai/weather"
	"github.com/sencloud/finme-backend/internal/ai/tool"
	aitools "github.com/sencloud/finme-backend/internal/ai/tools"
	"github.com/sencloud/finme-backend/internal/ai/tushare"
	"github.com/sencloud/finme-backend/internal/api"
	"github.com/sencloud/finme-backend/internal/auth"
	"github.com/sencloud/finme-backend/internal/billing"
	"github.com/sencloud/finme-backend/internal/brief"
	"github.com/sencloud/finme-backend/internal/devices"
	"github.com/sencloud/finme-backend/internal/ding"
	"github.com/sencloud/finme-backend/internal/ingest"
	"github.com/sencloud/finme-backend/internal/invite"
	"github.com/sencloud/finme-backend/internal/live"
	"github.com/sencloud/finme-backend/internal/llm"
	"github.com/sencloud/finme-backend/internal/falsification"
	"github.com/sencloud/finme-backend/internal/onboarding"
	"github.com/sencloud/finme-backend/internal/platform"
	"github.com/sencloud/finme-backend/internal/predict"
	"github.com/sencloud/finme-backend/internal/push"
	"github.com/sencloud/finme-backend/internal/scheduler"
	"github.com/sencloud/finme-backend/internal/share"
	"github.com/sencloud/finme-backend/internal/shell"
	"github.com/sencloud/finme-backend/internal/store"
	"github.com/sencloud/finme-backend/internal/strategy"
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
	// 行情采集端缓存：api 进程接收推送并落库，scheduler 进程读同一份库，
	// 这样两个进程里的 AI 工具都能拿到本机推上来的内盘期货实时价。
	ingest.SetDefault(ingest.NewRegistry(st))
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
	// 鹦鹉螺预测市场：螺壳账本 + 市场/下注 + 邀请。
	shell.SetFrozen(cfg.Nautilus.ShellsFrozen)
	shellRepo := shell.NewRepo(st)
	predictSvc := predict.NewService(st, cfg.Nautilus.MinBet)
	// 邀请：双方各得喜点（鹦鹉螺隐藏后不再发螺壳）。
	inviteSvc := invite.NewService(st, cfg.Credits.InviteReward)

	onboardSvc := onboarding.New(
		st,
		billing.NewLedgerRepo(st),
		ding.NewTaskRepo(st),
		ding.NewNotificationRepo(st),
		shellRepo,
		cfg.Nautilus.SignupShells,
		onboarding.Options{
			SignupCredits: cfg.Credits.SignupGift,
			ChatCredits:   cfg.AI.BaseChatCredits,
			DeepBonus:     cfg.AI.DeepBonusCredits,
		},
	)

	chatSvc := buildChatService(cfg, &l, st, usersSvc)
	dingSvc := ding.NewService(st, cfg, chatSvc, billing.NewLedgerRepo(st), &l)

	// Live v2:
	//   * 读接口(rooms / messages / kline) → 直接走 RoomRepo / MessageRepo / KlineBuilder
	//   * 自动开播(SeedRooms 4 个定时窗口)→ 在 scheduler 进程跑(见 runScheduler)
	//   * 手动开播(POST /v1/live/rooms,15 分钟硬截止)→ api 进程内嵌一个 mini-runner,
	//     即时启动 liveLoop;若 LLM 未配置则 manual 端点回 503 LIVE.MANUAL_DISABLED。
	liveTu := tushare.New(cfg.Tushare)
	liveRt := realtime.New(0)
	liveRoomRepo := live.NewRoomRepo(st)
	liveMsgRepo := live.NewMessageRepo(st)
	liveSvc := live.NewService(
		liveRoomRepo,
		liveMsgRepo,
		live.NewKlineBuilder(liveTu, liveRt),
	)
	// 计费:创建直播间 / 观众发言扣喜点。
	liveSvc.SetBilling(billing.NewLedgerRepo(st),
		cfg.AI.LiveRoomCreateCredits, cfg.AI.LivePostCredits)
	if cfg.LLM.Configured() {
		ds, err := llm.NewDeepSeek(cfg.LLM.APIKey, cfg.LLM.BaseURL,
			cfg.LLM.ChatModel, cfg.LLM.ReasonModel,
			time.Duration(cfg.LLM.TimeoutSec)*time.Second)
		if err != nil {
			l.Warn().Err(err).Msg("api: live manual runner disabled (deepseek init failed)")
		} else {
			liveNw := news.New(cfg.News)
			liveCn := cnnews.New(cfg.News.TimeoutSec)
			liveCal := calendar.New(cfg.News.TimeoutSec)
			liveReg := aitools.BuildAll(aitools.Deps{
				Tushare: liveTu, News: liveNw, CNNews: liveCn, Realtime: liveRt, Calendar: liveCal,
			})
			liveExec := live.NewExecutor(ds, liveReg)
			liveHost := live.NewHostPlanner(ds)
			liveGuest := live.NewGuestSpeaker(liveExec)
			liveRunner := live.NewRunner(liveRoomRepo, liveMsgRepo, liveHost, liveGuest, liveRt, &l)
			liveSvc.SetRunner(liveRunner)
			l.Info().Msg("api: live manual runner enabled (POST /v1/live/rooms 可用)")
		}
	} else {
		l.Warn().Msg("api: llm not configured, POST /v1/live/rooms 将返回 503")
	}

	var qwenVision *qwen.VisionClient
	if cfg.Qwen.Configured() {
		qwenVision = qwen.NewVisionClient(cfg.Qwen)
		l.Info().
			Str("model", cfg.Qwen.VisionModel).
			Str("base_url", cfg.Qwen.BaseURL).
			Msg("qwen vision: enabled")
	} else {
		l.Warn().Msg("qwen vision: api key not set, /v1/portfolio/parse-screenshot disabled")
	}

	deps := &api.Deps{
		Config:     cfg,
		Logger:     l,
		Store:      st,
		Auth:       authSvc,
		Users:      usersSvc,
		Devices:    devicesSvc,
		Billing:    billingSvc,
		Ding:       dingSvc,
		Live:       liveSvc,
		Onboarding: onboardSvc,
		Chat:       chatSvc,
		Qwen:       qwenVision,
		Ingest:     ingest.Default(),
		Share:      share.NewRepo(st),
		Shell:      shellRepo,
		Predict:    predictSvc,
		Invite:     inviteSvc,
		Brief:      buildBriefService(cfg, &l, st),
		Strategy:   buildStrategyService(cfg, &l, st),

		Falsification: buildFalsificationService(cfg, &l, st),
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

// buildFalsificationService 构造证伪档案服务。
//
// 永远返回实例：alpharadar 未配置时只用内置 seed（档案仍可浏览）；
// run_enabled 关闭时「跑一次证伪」走 stub（只登记、不扣费）。
func buildFalsificationService(cfg *platform.Config, l *zerolog.Logger, st *store.Store) *falsification.Service {
	url := ""
	if cfg.AlphaRadar.Enabled {
		url = cfg.AlphaRadar.URL
	}
	var runner falsification.Runner = falsification.StubRunner{}
	if cfg.AlphaRadar.RunEnabled && url != "" {
		runner = falsification.NewHTTPRunner(url, cfg.AlphaRadar.APIKey)
	}
	return falsification.NewService(st, l, falsification.Options{
		URL:    url,
		Runner: runner,
		Prices: falsification.Prices{
			Unlock:        cfg.Credits.UnlockEntry,
			FalsifyDaily:  cfg.Credits.FalsifyDaily,
			FalsifyMinute: cfg.Credits.FalsifyMinute,
		},
	})
}

// buildStrategyService 构造「主策略」抓取/读取服务。
//
// 即便 Tushare 未配置（无法取交易日历）也要返回实例：过期判断会退化为
// 数工作日，其余功能不受影响。
func buildStrategyService(cfg *platform.Config, l *zerolog.Logger, st *store.Store) *strategy.Service {
	if !cfg.Strategy.Enabled {
		l.Info().Msg("strategy: disabled by config")
		return nil
	}
	return strategy.NewService(st, l, tushare.New(cfg.Tushare), cfg.Strategy.BaseURL)
}

// buildBriefService 构造首页「今天想聊点什么」的生成/读取服务。
//
// LLM 未配置或初始化失败时仍返回可用实例：生成退化为模板拼装，接口照常有内容。
func buildBriefService(cfg *platform.Config, l *zerolog.Logger, st *store.Store) *brief.Service {
	rt := realtime.New(0)
	if !cfg.LLM.Configured() {
		return brief.NewService(st, l, nil, rt, "")
	}
	ds, err := llm.NewDeepSeek(cfg.LLM.APIKey, cfg.LLM.BaseURL,
		cfg.LLM.ChatModel, cfg.LLM.ReasonModel,
		time.Duration(cfg.LLM.TimeoutSec)*time.Second)
	if err != nil {
		l.Warn().Err(err).Msg("brief: deepseek init failed, use template questions")
		return brief.NewService(st, l, nil, rt, "")
	}
	return brief.NewService(st, l, ds, rt, cfg.LLM.ChatModel)
}

// buildChatService 构造 /v1/ai/chat 服务，依赖 LLM + Tushare + News + tools 注册表。
//
// 任一上游缺失（无 LLM key / Tushare token）会让 Chat.Configured() 返回 false；
// HTTP handler 据此返回 AI.NOT_CONFIGURED。
func buildChatService(cfg *platform.Config, l *zerolog.Logger, st *store.Store, usersSvc *users.Service) *chat.Service {
	if !cfg.LLM.Configured() {
		l.Warn().Msg("ai chat: llm not configured, /v1/ai/chat will be disabled")
		return chat.New(chat.Deps{
			Sessions: chat.NewSessionRepo(st),
			Users:    usersSvc,
			Cfg:      cfg.AI,
		})
	}
	ds, err := llm.NewDeepSeek(cfg.LLM.APIKey, cfg.LLM.BaseURL,
		cfg.LLM.ChatModel, cfg.LLM.ReasonModel,
		time.Duration(cfg.LLM.TimeoutSec)*time.Second)
	if err != nil {
		l.Error().Err(err).Msg("ai chat: deepseek init failed")
		return chat.New(chat.Deps{
			Sessions: chat.NewSessionRepo(st),
			Users:    usersSvc,
			Cfg:      cfg.AI,
		})
	}
	registry := buildToolRegistry(cfg, l)
	return chat.New(chat.Deps{
		Sessions: chat.NewSessionRepo(st),
		Tools:    registry,
		LLM:      ds,
		Ledger:   billing.NewLedgerRepo(st),
		Users:    usersSvc,
		Cfg:      cfg.AI,
	})
}

// buildToolRegistry 构造服务端 AI 工具的统一注册表。
//
// 数据源：
//   - Tushare：A 股 / 期货历史日线、分钟、财报、行业资金、北向、两融
//   - Realtime（东方财富 push2）：实时快照、涨跌幅榜、指数实时
//   - CNNews（财联社+东财快讯+新浪滚动）：国内中文财经/期货/政策电报
//   - News（GDELT+FIRMS）：海外议题、卫星火点
func buildToolRegistry(cfg *platform.Config, l *zerolog.Logger) *tool.Registry {
	return buildToolRegistryWithIngest(cfg, l, ingest.Default())
}

// buildToolRegistryWithIngest 允许调用方注入行情采集端缓存（api 进程用它接收推送，
// scheduler 进程读同一份库；测试可传 nil 走纯内存）。
func buildToolRegistryWithIngest(
	cfg *platform.Config, l *zerolog.Logger, ig *ingest.Registry,
) *tool.Registry {
	tu := tushare.New(cfg.Tushare)
	nw := news.New(cfg.News)
	cn := cnnews.New(cfg.News.TimeoutSec)
	rt := realtime.New(0)
	cal := calendar.New(cfg.News.TimeoutSec)
	reg := aitools.BuildAll(aitools.Deps{
		Tushare:  tu,
		News:     nw,
		CNNews:   cn,
		Realtime: rt,
		Calendar: cal,
		Weather:  weather.New(0),
		Ingest:   ig,
		IngestMaxAge: func() time.Duration {
			sec := cfg.Ingest.MaxAgeSec
			if sec <= 0 {
				sec = 120
			}
			return time.Duration(sec) * time.Second
		}(),
	})
	l.Info().Strs("names", reg.Names()).Int("count", len(reg.Names())).Msg("ai tools registered")
	return reg
}

func waitForSignal() {
	ch := make(chan os.Signal, 1)
	signal.Notify(ch, syscall.SIGINT, syscall.SIGTERM)
	<-ch
}

// runScheduler 启动 finme-server scheduler 子进程：
// - 余额对账（每 5 分钟）
// - DING runner（每 30 秒抢占 due tasks → 扣费 → chat.Service 工具 loop → 写通知）
// - Live runner（每 1 分钟：日历填充 + 抢占 due 直播场次 → 选股 → 多 persona × 多股
//   逐个 tool loop → 落 live_reports）
func runScheduler(cfg *platform.Config, l zerolog.Logger, st *store.Store) {
	sch := scheduler.New(&l)
	sch.Register(scheduler.NewReconcileBalance(st, &l, 5*time.Minute))

	// 首页「今天想聊点什么」：非交易日空跑，交易日内按时段（盘前/早盘/午间/
	// 午后/收盘）各生成一次，客户端直接读最近一条。
	if cfg.AI.HomeSuggestEnabled {
		sch.Register(brief.NewJob(buildBriefService(cfg, &l, st), 10*time.Minute, &l))
		l.Info().Msg("scheduler: home suggestions job enabled")
	}

	// 主策略快照：周期抓取外部量化看板，App 的「策略」tab 直接读。
	if cfg.Strategy.Enabled {
		interval := time.Duration(cfg.Strategy.SyncMinutes) * time.Minute
		sch.Register(strategy.NewJob(buildStrategyService(cfg, &l, st), interval, &l))
		l.Info().Dur("interval", interval).Msg("scheduler: strategy sync job enabled")
	}

	// 证伪档案：周期从 alpha-radar 拉只读导出落库；api 读最新一份（没有就用内置 seed）。
	if cfg.AlphaRadar.Enabled && cfg.AlphaRadar.URL != "" {
		interval := time.Duration(cfg.AlphaRadar.SyncMinutes) * time.Minute
		sch.Register(falsification.NewJob(buildFalsificationService(cfg, &l, st), interval, &l))
		l.Info().Dur("interval", interval).Msg("scheduler: falsification sync job enabled")
	} else {
		l.Info().Msg("scheduler: alpharadar url not set, falsification uses bundled seed")
	}

	// 螺壳冻结：停止机器人下注与每日出题（已有市场照常到期结算 / 退款）。
	shell.SetFrozen(cfg.Nautilus.ShellsFrozen)

	// 鹦鹉螺：关闭到期市场 + 金融/天气类自动结算(东财行情 + Open-Meteo 判定)。
	predictSvc := predict.NewService(st, cfg.Nautilus.MinBet)
	predictRt := realtime.New(0)
	predictWx := weather.New(0)
	sch.Register(predict.NewAutoSettleJob(predictSvc, predictRt, predictWx, &l, time.Minute))

	usersSvc := users.NewService(st, cfg)

	// 鹦鹉螺：Bot 自动下注 + 每日模板出题(平台兜底供给螺壳，零人工运营)。
	if cfg.Nautilus.BotEnabled && !cfg.Nautilus.ShellsFrozen {
		sch.Register(predict.NewBotBetJob(predictSvc, shell.NewRepo(st), usersSvc, predict.BotConfig{
			Count:      cfg.Nautilus.BotCount,
			MinBet:     cfg.Nautilus.BotMinBet,
			MaxBet:     cfg.Nautilus.BotMaxBet,
			PerMarket:  cfg.Nautilus.BotPerMarket,
			ActiveFrom: cfg.Nautilus.BotActiveFrom,
			ActiveTo:   cfg.Nautilus.BotActiveTo,
			Interval:   90 * time.Second,
		}, &l))
		l.Info().Msg("scheduler: nautilus bot bet job enabled")
	}
	if cfg.Nautilus.DailyEnabled && !cfg.Nautilus.ShellsFrozen {
		sch.Register(predict.NewDailyMarketJob(predictSvc, predictRt, predictWx, predict.DailyConfig{
			Hour:     cfg.Nautilus.DailyHour,
			Interval: 30 * time.Minute,
		}, &l))
		l.Info().Msg("scheduler: nautilus daily market job enabled")
	}

	chatSvc := buildChatService(cfg, &l, st, usersSvc)
	if !chatSvc.Configured() {
		l.Warn().Msg("scheduler: chat service not configured, ding runner disabled")
	} else {
		ledger := billing.NewLedgerRepo(st)
		runner := ding.NewRunner(st, chatSvc, ledger, &l, ding.RunnerConfig{})
		sch.Register(runner)
		l.Info().Msg("scheduler: ding runner enabled (chat.Service + tools)")
	}

	// Live runner 需要自己的 LLM + tools，不复用 chat.Service（chat 带扣费 +
	// 会话持久化，对直播是无谓负担）。
	if cfg.LLM.Configured() {
		ds, err := llm.NewDeepSeek(cfg.LLM.APIKey, cfg.LLM.BaseURL,
			cfg.LLM.ChatModel, cfg.LLM.ReasonModel,
			time.Duration(cfg.LLM.TimeoutSec)*time.Second)
		if err != nil {
			l.Warn().Err(err).Msg("scheduler: live runner disabled (deepseek init failed)")
		} else {
			tu := tushare.New(cfg.Tushare)
			nw := news.New(cfg.News)
			cn := cnnews.New(cfg.News.TimeoutSec)
			rt := realtime.New(0)
			cal := calendar.New(cfg.News.TimeoutSec)
			reg := aitools.BuildAll(aitools.Deps{
				Tushare: tu, News: nw, CNNews: cn, Realtime: rt, Calendar: cal,
			})
			// Live v2 调度器:host_planner(无 tools) + guest_speaker(有 tools 走 executor)。
			exec := live.NewExecutor(ds, reg)
			host := live.NewHostPlanner(ds)
			guest := live.NewGuestSpeaker(exec)
			roomRepo := live.NewRoomRepo(st)
			msgRepo := live.NewMessageRepo(st)
			runner := live.NewRunner(roomRepo, msgRepo, host, guest, rt, &l)
			sch.Register(runner)
			l.Info().Msg("scheduler: live runner v2 enabled (host + guests realtime chat)")
		}
	} else {
		l.Warn().Msg("scheduler: llm not configured, live runner disabled")
	}

	ctx, cancel := signalCtx()
	defer cancel()
	if err := sch.Run(ctx); err != nil && err != context.Canceled {
		l.Error().Err(err).Msg("scheduler exited with error")
	}
}

// runPusher 启动 finme-server pusher 子进程：
// 轮询 notifications.push_status='pending' → 调 PushSender → 标 pushed/failed。
// 凭证齐全则走真实 APNs/FCM；缺失则回落 Mock 让 dev 仍可联调。
func runPusher(cfg *platform.Config, l zerolog.Logger, st *store.Store) {
	devSvc := devices.NewService(st)
	apns := buildAPNs(cfg, &l)
	fcm := buildFCM(cfg, &l)
	w := push.NewWorker(st, devSvc, &l, push.WorkerConfig{
		APNs:     apns,
		FCM:      fcm,
		Interval: 5 * time.Second,
	})
	ctx, cancel := signalCtx()
	defer cancel()
	if err := w.Run(ctx); err != nil && err != context.Canceled {
		l.Error().Err(err).Msg("pusher exited with error")
	}
}

func buildAPNs(cfg *platform.Config, l *zerolog.Logger) push.PushSender {
	if !cfg.APNs.Configured() {
		l.Warn().Msg("apns not configured, fall back to mock")
		return push.MockPushSender{}
	}
	pem := cfg.APNs.PrivateKey
	if pem == "" && cfg.APNs.PrivateKeyPath != "" {
		s, err := push.LoadP8(cfg.APNs.PrivateKeyPath)
		if err != nil {
			l.Error().Err(err).Msg("apns load p8 failed, fall back to mock")
			return push.MockPushSender{}
		}
		pem = s
	}
	bid := cfg.APNs.BundleID
	if bid == "" {
		bid = cfg.Apple.BundleID
	}
	useSandbox := cfg.APNs.Environment == "sandbox"
	s, err := push.NewAPNsSender(bid, cfg.APNs.TeamID, cfg.APNs.KeyID, pem, useSandbox)
	if err != nil {
		l.Error().Err(err).Msg("apns init failed, fall back to mock")
		return push.MockPushSender{}
	}
	l.Info().Bool("sandbox", useSandbox).Msg("apns sender ready")
	return s
}

func buildFCM(cfg *platform.Config, l *zerolog.Logger) push.PushSender {
	if !cfg.FCM.Configured() {
		l.Warn().Msg("fcm not configured, fall back to mock")
		return push.MockPushSender{}
	}
	saJSON := cfg.FCM.ServiceAccountJSON
	if saJSON == "" && cfg.FCM.ServiceAccountJSONPath != "" {
		s, err := push.LoadServiceAccountJSON(cfg.FCM.ServiceAccountJSONPath)
		if err != nil {
			l.Error().Err(err).Msg("fcm load service account failed, fall back to mock")
			return push.MockPushSender{}
		}
		saJSON = s
	}
	s, err := push.NewFCMSender(cfg.FCM.ProjectID, saJSON)
	if err != nil {
		l.Error().Err(err).Msg("fcm init failed, fall back to mock")
		return push.MockPushSender{}
	}
	l.Info().Str("project", cfg.FCM.ProjectID).Msg("fcm sender ready")
	return s
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
