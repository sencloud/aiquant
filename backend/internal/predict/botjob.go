package predict

import (
	"context"
	"math/rand"
	"time"

	"github.com/rs/zerolog"

	"github.com/sencloud/finme-backend/internal/shell"
)

// BotProvider 抽象出"幂等保证 N 个机器人账号并返回其 id"的能力，
// 由 users.Service 实现；predict 借此避免反向依赖 users 包的领域类型。
type BotProvider interface {
	EnsureBots(ctx context.Context, n int) ([]int64, error)
}

// BotConfig 是机器人下注的风控参数。
type BotConfig struct {
	Count      int           // 机器人账号数量
	MinBet     int64         // 单笔下注下限
	MaxBet     int64         // 单笔下注上限
	PerMarket  int           // 每市场 bot 累计下注笔数上限
	ActiveFrom int           // 活跃时段起始小时(含)
	ActiveTo   int           // 活跃时段结束小时(含)
	Interval   time.Duration // 调度周期
}

// BotBetJob 是 scheduler 的周期任务：让机器人对进行中的市场自动下注，
// 给冷门盘口提供对手盘和初始热度。
//
// 经济模型：bot 用独立虚拟账号、与真人同池瓜分；bot 螺壳由平台兜底供给
// (余额不足时即时充值)，亏赢都留在 bot 账户，不影响真人之间的公平性。
type BotBetJob struct {
	svc    *Service
	shells *shell.Repo
	bots   BotProvider
	cfg    BotConfig
	logger *zerolog.Logger
	rng    *rand.Rand
}

func NewBotBetJob(svc *Service, shells *shell.Repo, bots BotProvider, cfg BotConfig, l *zerolog.Logger) *BotBetJob {
	if cfg.Interval <= 0 {
		cfg.Interval = 90 * time.Second
	}
	if cfg.MinBet <= 0 {
		cfg.MinBet = 20
	}
	if cfg.MaxBet < cfg.MinBet {
		cfg.MaxBet = cfg.MinBet
	}
	if cfg.PerMarket <= 0 {
		cfg.PerMarket = 8
	}
	if cfg.Count <= 0 {
		cfg.Count = 12
	}
	return &BotBetJob{
		svc:    svc,
		shells: shells,
		bots:   bots,
		cfg:    cfg,
		logger: l,
		rng:    rand.New(rand.NewSource(time.Now().UnixNano())),
	}
}

func (j *BotBetJob) Name() string            { return "predict_bot_bet" }
func (j *BotBetJob) Interval() time.Duration { return j.cfg.Interval }

func (j *BotBetJob) Run(ctx context.Context) error {
	hour := time.Now().Hour()
	if !inActiveWindow(hour, j.cfg.ActiveFrom, j.cfg.ActiveTo) {
		return nil
	}
	botIDs, err := j.bots.EnsureBots(ctx, j.cfg.Count)
	if err != nil {
		return err
	}
	if len(botIDs) == 0 {
		return nil
	}
	markets, err := j.svc.OpenMarkets(ctx, 100)
	if err != nil {
		return err
	}
	placed := 0
	for _, m := range markets {
		// 每个 tick 对每个市场约 60% 概率尝试一注，避免过于规律。
		if j.rng.Float64() > 0.6 {
			continue
		}
		cnt, err := j.svc.BotBetCount(ctx, m.ID)
		if err != nil {
			j.logger.Error().Err(err).Int64("market_id", m.ID).Msg("predict bot: count failed")
			continue
		}
		if cnt >= j.cfg.PerMarket {
			continue
		}
		if err := j.betOnce(ctx, m, botIDs); err != nil {
			j.logger.Error().Err(err).Int64("market_id", m.ID).Msg("predict bot: bet failed")
			continue
		}
		placed++
	}
	if placed > 0 {
		j.logger.Info().Int("bets", placed).Msg("predict bot: placed bets")
	}
	return nil
}

func (j *BotBetJob) betOnce(ctx context.Context, m MarketView, botIDs []int64) error {
	if len(m.Options) < 2 {
		return nil
	}
	botID := botIDs[j.rng.Intn(len(botIDs))]
	opt := j.pickOption(m)
	amount := j.cfg.MinBet
	if j.cfg.MaxBet > j.cfg.MinBet {
		amount += j.rng.Int63n(j.cfg.MaxBet - j.cfg.MinBet + 1)
	}

	if err := j.ensureFunds(ctx, botID, amount); err != nil {
		return err
	}
	_, err := j.svc.PlaceBet(ctx, botID, m.ID, opt.ID, amount)
	return err
}

// pickOption 倾向于押注当前池较小的选项，制造对手盘、平衡赔率。
func (j *BotBetJob) pickOption(m MarketView) Option {
	weights := make([]float64, len(m.Options))
	var sum float64
	for i, o := range m.Options {
		// 反比权重：池越小权重越大；+1 防止全 0 时退化。
		w := float64(m.TotalPool-o.PoolShells) + 1
		weights[i] = w
		sum += w
	}
	r := j.rng.Float64() * sum
	for i, w := range weights {
		r -= w
		if r <= 0 {
			return m.Options[i]
		}
	}
	return m.Options[len(m.Options)-1]
}

// ensureFunds 平台兜底：bot 余额不足以下注时即时补足。
func (j *BotBetJob) ensureFunds(ctx context.Context, botID, amount int64) error {
	bal, err := j.shells.Balance(ctx, botID)
	if err != nil {
		return err
	}
	if bal >= amount {
		return nil
	}
	// 一次补足较大额度，减少充值频率；ref 留空(不参与幂等约束)。
	topup := amount*10 + j.cfg.MaxBet
	_, err = j.shells.Apply(ctx, shell.ApplyParams{
		UserID: botID,
		Delta:  topup,
		Reason: shell.ReasonBotFunding,
		Remark: "bot funding",
	})
	return err
}

// inActiveWindow 判断当前小时是否在活跃时段内（支持跨午夜，如 from=22 to=6）。
func inActiveWindow(hour, from, to int) bool {
	if from == to {
		return true
	}
	if from < to {
		return hour >= from && hour <= to
	}
	return hour >= from || hour <= to
}
