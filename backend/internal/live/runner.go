package live

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/rs/zerolog"
)

// Runner 是直播调度器。
//
// 一个 scheduler 进程里跑一个 Runner，每分钟跑一次：
//
//  1. SeedCalendar：把"今天还没插入的整点 / 半点直播场次"统一 INSERT pending；
//  2. AcquireDue：找一条 due 的 pending 场次，CAS 标 running；
//  3. RunSession：选股 → 对每只票顺序跑全部 persona → 落 live_reports；
//  4. MarkDone：写 finished_at + status。
//
// 调度时间表（北京时间，仅工作日 9:30-15:00 共 6 场）：
//
//	09:30 盘前
//	10:30 盘中
//	11:30 盘中
//	13:30 盘中
//	14:30 盘中
//	15:00 盘后
type Runner struct {
	sessions *SessionRepo
	reports  *ReportRepo
	picker   *Picker
	exec     *Executor
	logger   *zerolog.Logger

	tickInterval time.Duration
}

func NewRunner(
	sessions *SessionRepo,
	reports *ReportRepo,
	picker *Picker,
	exec *Executor,
	l *zerolog.Logger,
) *Runner {
	return &Runner{
		sessions:     sessions,
		reports:      reports,
		picker:       picker,
		exec:         exec,
		logger:       l,
		tickInterval: 60 * time.Second,
	}
}

func (r *Runner) Name() string            { return "live_runner" }
func (r *Runner) Interval() time.Duration { return r.tickInterval }

// Run 每分钟调用一次。
func (r *Runner) Run(ctx context.Context) error {
	now := time.Now()

	// 1) 日历填充：保证今天剩余场次都有 pending 行
	if err := r.SeedCalendar(ctx, now); err != nil {
		r.logger.Warn().Err(err).Msg("live: seed calendar")
	}

	// 2) 一次最多抢一条 due，避免单 tick 跑太久阻塞下一个 tick
	sess, err := r.sessions.AcquireDue(ctx, now.UnixMilli())
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil
		}
		return fmt.Errorf("acquire due: %w", err)
	}
	r.logger.Info().Str("uuid", sess.UUID).Str("phase", sess.Phase).
		Int64("sched_ms", sess.ScheduledAt).Msg("live: session acquired")

	if err := r.runSession(ctx, sess); err != nil {
		_ = r.sessions.MarkDone(ctx, sess.ID, false, err.Error())
		r.logger.Error().Err(err).Str("uuid", sess.UUID).Msg("live: session failed")
		return nil
	}
	_ = r.sessions.MarkDone(ctx, sess.ID, true, "")
	r.logger.Info().Str("uuid", sess.UUID).Msg("live: session done")
	return nil
}

// runSession 选股 + 逐 (symbol × persona) 串行生成报告并落库。
//
// 异常处理策略：
//   - 选股全失败 → 整场标 failed
//   - 单只票 / 单个 persona 失败 → 跳过，只要至少一份成功就把场次标 done
func (r *Runner) runSession(ctx context.Context, s *Session) error {
	pick, err := r.picker.Pick(ctx, s.Phase, time.UnixMilli(s.ScheduledAt))
	if err != nil {
		return fmt.Errorf("pick: %w", err)
	}
	if pick == nil || len(pick.Symbols) == 0 {
		return errors.New("picked 0 symbols")
	}
	if err := r.sessions.MarkPicked(ctx, s.ID, PickedSymbolsJSON(pick.Symbols), pick.Reason); err != nil {
		r.logger.Warn().Err(err).Msg("live: mark picked")
	}

	success := 0
	for _, sym := range pick.Symbols {
		for _, p := range LivePersonas {
			select {
			case <-ctx.Done():
				return ctx.Err()
			default:
			}
			if err := r.runOne(ctx, s, sym, p); err != nil {
				r.logger.Warn().Err(err).
					Str("symbol", sym.Symbol).Str("persona", p.ID).
					Msg("live: one report failed")
				continue
			}
			success++
		}
	}
	if success == 0 {
		return errors.New("no successful reports in session")
	}
	return nil
}

// runOne 跑「单只票 × 单分析师」一份报告。
func (r *Runner) runOne(ctx context.Context, s *Session, sym Picked, p PersonaSpec) error {
	sys := "你是一名严谨的中国市场投研分析师。回答必须基于工具拉取的真实数据，禁止编造价格、估值、新闻。" +
		"必须严格按用户给出的输出格式契约（===META===/===REPORT===）生成，不得添加任何额外文字。"
	user := buildLiveUserPrompt(p, sym.Symbol, sym.Name, sym.Source, s.Phase, time.UnixMilli(s.ScheduledAt))

	res, err := r.exec.Run(ctx, sys, user)
	if err != nil {
		return fmt.Errorf("exec: %w", err)
	}
	if strings.TrimSpace(res.FinalText) == "" {
		return errors.New("empty llm output")
	}

	meta, body, perr := ParseLLMOutput(res.FinalText)
	if perr != nil {
		// JSON 头解析失败也照样存：meta 字段空，body 用全文兜底
		r.logger.Debug().Err(perr).Str("symbol", sym.Symbol).Str("persona", p.ID).
			Msg("live: parse meta failed, fallback to raw body")
	}
	if meta == nil {
		meta = &ExtractedMeta{}
	}

	htmlStr := RenderReportHTML(RenderInput{
		PersonaName:    p.Name,
		PersonaTitle:   personaTitleOf(p.ID),
		SymbolName:     sym.Name,
		SymbolCode:     sym.Symbol,
		Summary:        meta.Summary,
		View:           meta.View,
		Rating:         meta.Rating,
		TargetPrice:    meta.TargetPrice,
		StopLoss:       meta.StopLoss,
		TakeProfit:     meta.TakeProfit,
		PositionHint:   meta.PositionHint,
		MarkdownBody:   body,
		CreatedAtLabel: time.UnixMilli(s.ScheduledAt).Format("2006-01-02 15:04"),
	})

	_, err = r.reports.Insert(ctx, CreateReportInput{
		SessionID:    s.ID,
		Symbol:       sym.Symbol,
		SymbolName:   sym.Name,
		PersonaID:    p.ID,
		PersonaName:  p.Name,
		View:         meta.View,
		Rating:       meta.Rating,
		TargetPrice:  meta.TargetPrice,
		StopLoss:     meta.StopLoss,
		TakeProfit:   meta.TakeProfit,
		PositionHint: meta.PositionHint,
		Summary:      meta.Summary,
		HTMLBody:     htmlStr,
		ToolCalls:    res.ToolCalls,
		DurationMs:   res.DurationMs,
	})
	return err
}

// SeedCalendar 把今天 09:30/10:30/11:30/13:30/14:30/15:00 还没有的 pending 场次插上。
//
// 周末跳过；节假日不在本期处理（后续可对接交易日历）。
func (r *Runner) SeedCalendar(ctx context.Context, now time.Time) error {
	if isWeekend(now) {
		return nil
	}
	loc := now.Location()
	y, m, d := now.Year(), now.Month(), now.Day()
	type slot struct {
		h, mi int
		phase string
	}
	slots := []slot{
		{9, 30, PhasePre},
		{10, 30, PhaseIntraday},
		{11, 30, PhaseIntraday},
		{13, 30, PhaseIntraday},
		{14, 30, PhaseIntraday},
		{15, 0, PhasePost},
	}
	for _, s := range slots {
		t := time.Date(y, m, d, s.h, s.mi, 0, 0, loc)
		if err := r.sessions.SeedIfAbsent(ctx, t.UnixMilli(), s.phase); err != nil {
			return err
		}
	}
	return nil
}

func isWeekend(t time.Time) bool {
	return t.Weekday() == time.Saturday || t.Weekday() == time.Sunday
}

// personaTitleOf 返回与客户端 lib/models/persona.dart 对齐的 persona 副标题，
// 用于 RenderReportHTML 的 header 副标。
func personaTitleOf(id string) string {
	switch id {
	case "buffett":
		return "价值投资 · 长期持有 · 护城河"
	case "graham":
		return "深度价值 · 安全边际 · 净流动资产"
	case "lynch":
		return "成长投资 · 行业研究 · PEG"
	case "munger":
		return "多元思维 · 反向 · 第一性原理"
	case "dalio":
		return "宏观周期 · 全天候 · 风险平价"
	case "soros":
		return "反身性 · 宏观对冲 · 趋势捕捉"
	}
	return ""
}
