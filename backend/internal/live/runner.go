package live

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math/rand"
	"strings"
	"sync"
	"time"

	"github.com/rs/zerolog"

	"github.com/sencloud/finme-backend/internal/ai/realtime"
)

// Runner 是直播 v2 的调度器,每 tick 1 分钟:
//
//   1) SweepStale:扫 status='live' 但最后消息 > StaleAfter 没动的房间 → MarkAbnormal
//   2) SeedRooms :工作日特定时段若当下无 live 房间 → Create + 异步启动 liveLoop
//
// 一个 room = 一个 goroutine = 一场 N 条消息的直播,跑完自然 MarkEnded。
// 进程重启时所有 in-flight goroutine 丢失,下次 tick 的 SweepStale 会把它们标 abnormal。
type Runner struct {
	rooms    *RoomRepo
	messages *MessageRepo
	host     *HostPlanner
	guest    *GuestSpeaker
	rt       *realtime.Client
	logger   *zerolog.Logger

	// 调度参数(开放给 main.go 配置)
	TickInterval       time.Duration
	StaleAfter         time.Duration // > 这么久没新消息的 live 房间 → abnormal
	PaceInterval       time.Duration // 一条消息到下一条的间隔(模拟"直播节奏")
	PaceJitter         time.Duration // 间隔抖动 ±
	MaxMessagesPerRoom int           // 单场硬上限
	SoftCloseAfter     int           // 软上限:超过这个数主持人会倾向 close

	// 内部:已启动 loop 的房间 id → 取消函数(防止 tick 重复启动)
	mu      sync.Mutex
	running map[int64]context.CancelFunc
}

func NewRunner(
	rooms *RoomRepo,
	messages *MessageRepo,
	host *HostPlanner,
	guest *GuestSpeaker,
	rt *realtime.Client,
	l *zerolog.Logger,
) *Runner {
	return &Runner{
		rooms:              rooms,
		messages:           messages,
		host:               host,
		guest:              guest,
		rt:                 rt,
		logger:             l,
		TickInterval:       60 * time.Second,
		StaleAfter:         5 * time.Minute,
		PaceInterval:       35 * time.Second, // 平均 35s/条 — 用户能跟上节奏看历史
		PaceJitter:         10 * time.Second,
		MaxMessagesPerRoom: 60,
		SoftCloseAfter:     50,
		running:            map[int64]context.CancelFunc{},
	}
}

func (r *Runner) Name() string            { return "live_runner_v2" }
func (r *Runner) Interval() time.Duration { return r.TickInterval }

// Run 是 scheduler 每 tick 调一次。
//
// 注意:tick 本身只做"管理性动作"(扫陈旧 / 创建房间 + 启动 goroutine),
// 不在 tick 内做 LLM 调用 — 后者在 liveLoop goroutine 里。
func (r *Runner) Run(ctx context.Context) error {
	now := time.Now()

	if err := r.SweepStale(ctx, now); err != nil {
		r.logger.Warn().Err(err).Msg("live: sweep stale")
	}

	if err := r.SeedRooms(ctx, now); err != nil {
		r.logger.Warn().Err(err).Msg("live: seed rooms")
	}
	return nil
}

// SweepStale 把 live 但最后消息 > StaleAfter 的房间标为 abnormal,清理 running map。
func (r *Runner) SweepStale(ctx context.Context, now time.Time) error {
	live, err := r.rooms.ListLive(ctx)
	if err != nil {
		return err
	}
	cutoff := now.Add(-r.StaleAfter).UnixMilli()
	for _, room := range live {
		// 用 max(started_at, last_message_at) 判断陈旧
		var lastAt int64
		if err := r.rooms.st.DB.GetContext(ctx, &lastAt, `
			SELECT COALESCE(MAX(created_at), ?)
			FROM live_messages WHERE room_id=?`, room.StartedAt, room.ID); err != nil {
			r.logger.Warn().Err(err).Int64("room_id", room.ID).Msg("live: last msg time")
			continue
		}
		if lastAt < cutoff {
			// 若仍在 running map(本进程内),不算 stale,跳过
			r.mu.Lock()
			_, inflight := r.running[room.ID]
			r.mu.Unlock()
			if inflight {
				continue
			}
			_ = r.rooms.MarkAbnormal(ctx, room.ID, "stale: no new messages within "+r.StaleAfter.String())
			r.logger.Info().Int64("room_id", room.ID).Str("uuid", room.UUID).
				Msg("live: marked abnormal (stale)")
		}
	}
	return nil
}

// roomSchedule 定义工作日的开播窗口。窗口内若当下无 live 房间则启动一场。
//
// 设计为"窗口"而非"打点":避免错过整分钟时刻、避免重复触发,且支持 5 分钟内补偿。
type slotWindow struct {
	hStart, mStart int
	hEnd, mEnd     int
	phase          string
	title          string
}

var liveSlots = []slotWindow{
	{9, 30, 9, 50, PhasePre, "早盘开盘观察"},
	{11, 30, 11, 50, PhaseIntraday, "上午盘中复盘"},
	{14, 30, 14, 50, PhaseIntraday, "下午盘中观察"},
	{15, 30, 15, 50, PhasePost, "盘后龙虎榜复盘"},
}

// SeedRooms 在每个窗口内若无 live 房间则创建一场并启动 goroutine。
func (r *Runner) SeedRooms(ctx context.Context, now time.Time) error {
	if isWeekend(now) {
		return nil
	}
	for _, s := range liveSlots {
		if !inWindow(now, s) {
			continue
		}
		// 该窗口已有任意 live 或本日已结束的同 phase 房间则跳过
		exists, err := r.windowHasRoom(ctx, now, s)
		if err != nil {
			r.logger.Warn().Err(err).Msg("live: check window room")
			continue
		}
		if exists {
			continue
		}
		room, err := r.createRoom(ctx, s, now)
		if err != nil {
			r.logger.Warn().Err(err).Str("title", s.title).Msg("live: create room")
			continue
		}
		r.startLoop(room)
		r.logger.Info().Int64("room_id", room.ID).Str("uuid", room.UUID).
			Str("title", room.Title).Msg("live: room created + loop started")
	}
	return nil
}

func (r *Runner) windowHasRoom(ctx context.Context, now time.Time, s slotWindow) (bool, error) {
	dayStart := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location()).UnixMilli()
	dayEnd := dayStart + 24*3600*1000
	var n int
	err := r.rooms.st.DB.GetContext(ctx, &n, `
		SELECT COUNT(*) FROM live_rooms
		WHERE phase=? AND started_at >= ? AND started_at < ?`,
		s.phase, dayStart, dayEnd)
	if err != nil {
		return false, err
	}
	return n > 0, nil
}

func (r *Runner) createRoom(ctx context.Context, s slotWindow, now time.Time) (*Room, error) {
	host := PickHost()
	guests := PickGuests(4)
	title := fmt.Sprintf("%s · %s 主持", s.title, host.Name)
	return r.rooms.Create(ctx, CreateInput{
		Title:         title,
		Phase:         s.phase,
		HostPersona:   host.PersonaRef,
		GuestPersonas: guests,
		Origin:        OriginAuto,
	})
}

// ManualRoomOptions 是 HTTP 触发开播的入参。
type ManualRoomOptions struct {
	// FocusSymbol 可空;非空时房间元信息直接挂上焦点,host 第一条消息将聚焦它。
	FocusSymbol string
	FocusName   string
	// Phase 自动按当下时间推断,调用方一般不传。
	Phase string
}

// StartManualRoom 创建一个用户手动触发的直播间并立即启动 goroutine。
//
// 约束:全局任一时刻只允许 1 个 status='live' 房间(无论 auto / manual);
// 已有 live → 返回 ErrLiveAlreadyExists,HTTP 层映射为 409。
//
// 行为:
//   * Origin=OriginManual,AutoEndAt=now+ManualRoomDuration(15min)
//   * liveLoop 每轮检查超期 → 主动 host_close → MarkEnded(自然进入历史)
//   * 即便房间内 host LLM 提前 close,也照常 MarkEnded(更早结束,无碍)
func (r *Runner) StartManualRoom(ctx context.Context, opts ManualRoomOptions) (*Room, error) {
	now := time.Now()
	phase := opts.Phase
	if phase == "" {
		phase = guessPhase(now)
	}

	// 唯一性前置:CountLive 非事务但配合"立刻 Create + scheduler 60s tick"已足够安全
	// (并发同秒内两个 manual 请求最坏会创建 2 个房间,SweepStale 不会清,
	//  但概率极低,且本应用单用户场景,暂不引入 DB unique index)。
	n, err := r.rooms.CountLive(ctx)
	if err != nil {
		return nil, err
	}
	if n > 0 {
		return nil, ErrLiveAlreadyExists
	}

	host := PickHost()
	guests := PickGuests(4)
	title := buildManualTitle(opts.FocusName, opts.FocusSymbol, host.Name, now)
	endAt := now.Add(ManualRoomDuration).UnixMilli()
	room, err := r.rooms.Create(ctx, CreateInput{
		Title:         title,
		Phase:         phase,
		HostPersona:   host.PersonaRef,
		GuestPersonas: guests,
		Origin:        OriginManual,
		AutoEndAtMs:   endAt,
	})
	if err != nil {
		return nil, err
	}
	// 用户传了开场焦点 → 写入冗余字段,host 第一条 ask 会被强引导聚焦它
	if opts.FocusSymbol != "" {
		_ = r.rooms.UpdateFocus(ctx, room.ID, opts.FocusSymbol, opts.FocusName)
		// 重新读一次让返回值带上 focus
		if updated, _ := r.rooms.GetByID(ctx, room.ID); updated != nil {
			room = updated
		}
	}
	r.startLoop(room)
	r.logger.Info().
		Int64("room_id", room.ID).Str("uuid", room.UUID).
		Str("title", room.Title).Str("origin", OriginManual).
		Int64("auto_end_at", endAt).Msg("live: manual room created + loop started")
	return room, nil
}

// guessPhase 按当下时间推断市场阶段(给 manual 房间用)。
func guessPhase(t time.Time) string {
	cur := t.Hour()*60 + t.Minute()
	switch {
	case cur < 9*60+15: // < 09:15
		return PhasePre
	case cur < 15*60: // 09:15 ~ 14:59
		return PhaseIntraday
	default: // >= 15:00
		return PhasePost
	}
}

func buildManualTitle(focusName, focusSymbol, hostName string, t time.Time) string {
	hm := t.Format("15:04")
	if focusName != "" {
		return fmt.Sprintf("%s · 聚焦 %s · %s 主持", hm, focusName, hostName)
	}
	if focusSymbol != "" {
		return fmt.Sprintf("%s · 聚焦 %s · %s 主持", hm, focusSymbol, hostName)
	}
	return fmt.Sprintf("%s · 随时直播 · %s 主持", hm, hostName)
}

// ErrLiveAlreadyExists 由 StartManualRoom 在已有 live 房间时返回;
// HTTP 层映射为 409 Conflict。
var ErrLiveAlreadyExists = errors.New("another live room is in progress")

// startLoop 启动一个 goroutine 跑 liveLoop。父 ctx 用 background(scheduler ctx),
// 避免 scheduler tick 函数返回导致 loop 被取消。但进程退出 SIGTERM 仍会传递。
func (r *Runner) startLoop(room *Room) {
	r.mu.Lock()
	if _, ok := r.running[room.ID]; ok {
		r.mu.Unlock()
		return
	}
	loopCtx, cancel := context.WithCancel(context.Background())
	r.running[room.ID] = cancel
	r.mu.Unlock()

	go func() {
		defer func() {
			r.mu.Lock()
			delete(r.running, room.ID)
			r.mu.Unlock()
		}()
		r.liveLoop(loopCtx, room)
	}()
}

// liveLoop 是单场直播的完整生成循环。串行生成消息直到 close 或达到 MaxMessages。
func (r *Runner) liveLoop(ctx context.Context, room *Room) {
	rid := room.ID
	logger := r.logger.With().
		Int64("room_id", rid).Str("uuid", room.UUID).
		Str("host", room.HostPersonaName).Logger()
	logger.Info().Msg("live loop: start")

	candidatePool := r.buildCandidatePool(ctx, room.Phase)
	logger.Info().Int("candidates", len(candidatePool)).Msg("live loop: pool ready")

	// 本场主持人(用 room 字段而非全局 Host —— Host 已废弃,主持人池随机抽取)
	host := PersonaRef{ID: room.HostPersona, Name: room.HostPersonaName}

	guests := room.DecodeGuestPersonas()
	if len(guests) == 0 {
		_ = r.rooms.MarkAbnormal(ctx, rid, "empty guest personas")
		return
	}

	// 手动房间且用户指定了个股 → 锁定焦点:主持人全程围绕这只票,禁止 switch 到别的票
	// (修复"自己创建直播指定的股票,直播过程里没讨论")。
	pinnedSym, pinnedName := "", ""
	if room.Origin == OriginManual &&
		room.CurrentFocusSymbol.Valid && room.CurrentFocusSymbol.String != "" {
		pinnedSym = room.CurrentFocusSymbol.String
		if room.CurrentFocusName.Valid && room.CurrentFocusName.String != "" {
			pinnedName = room.CurrentFocusName.String
		} else {
			pinnedName = pinnedSym
		}
	}

	failures := 0
	for {
		select {
		case <-ctx.Done():
			_ = r.rooms.MarkAbnormal(ctx, rid, "context cancelled")
			logger.Warn().Msg("live loop: ctx done")
			return
		default:
		}

		cnt, err := r.messages.CountByRoom(ctx, rid)
		if err != nil {
			logger.Warn().Err(err).Msg("live loop: count messages")
		}
		if cnt >= r.MaxMessagesPerRoom {
			logger.Info().Int("count", cnt).Msg("live loop: max messages reached")
			break
		}

		// 手动房间硬截止:到点写一条 host_close 然后退出循环 → MarkEnded 进入历史。
		if room.AutoEndAt.Valid && nowMs() >= room.AutoEndAt.Int64 {
			focus, focusName := "", ""
			if room.CurrentFocusSymbol.Valid {
				focus = room.CurrentFocusSymbol.String
			}
			if room.CurrentFocusName.Valid {
				focusName = room.CurrentFocusName.String
			}
			closing := fmt.Sprintf("时间到了,这场 %d 分钟的临时直播就到这,感谢各位嘉宾,我们后会有期。",
				int(ManualRoomDuration.Minutes()))
			_, _ = r.messages.Append(ctx, AppendInput{
				RoomID:      rid,
				Role:        RoleHostClose,
				Persona:     host.ID,
				PersonaName: host.Name,
				FocusSymbol: focus,
				FocusName:   focusName,
				Content:     closing,
			})
			_ = r.rooms.IncMessageCount(ctx, rid)
			logger.Info().Int64("auto_end_at", room.AutoEndAt.Int64).
				Msg("live loop: manual room auto-end reached")
			break
		}

		// 1. host 决策
		history, _ := r.messages.ListRecent(ctx, rid, 12)
		focus, focusName := currentFocus(history)
		// 开场/历史里还没出现焦点时,用房间预设焦点兜底(手动房间用户指定的票)。
		if focus == "" && pinnedSym != "" {
			focus, focusName = pinnedSym, pinnedName
		}
		action, err := r.host.Plan(ctx, PlanInput{
			Host:             host,
			Guests:           guests,
			Phase:            room.Phase,
			Now:              time.Now(),
			CandidatePool:    candidatePool,
			History:          history,
			CurrentFocus:     focus,
			CurrentFocusName: focusName,
			PinnedSymbol:     pinnedSym,
			PinnedName:       pinnedName,
			MessageCount:     cnt,
			SoftCloseAfterN:  r.SoftCloseAfter,
		})
		if err != nil {
			failures++
			logger.Warn().Err(err).Int("failures", failures).Msg("live loop: host plan failed")
			if failures >= 3 {
				_ = r.rooms.MarkAbnormal(ctx, rid, "host plan failed 3x: "+err.Error())
				return
			}
			r.sleepPace(ctx)
			continue
		}

		// 1b. 去重:LLM 偶尔会跟前几轮 host 内容雷同 — 视为失败重试。
		hostContent := strings.TrimSpace(action.Content)
		if isDuplicateHost(history, hostContent, host.ID) {
			failures++
			logger.Warn().Int("failures", failures).
				Str("dup_content", snippet(hostContent, 80)).
				Msg("live loop: host content duplicates recent")
			if failures >= 3 {
				_ = r.rooms.MarkAbnormal(ctx, rid, "host duplicated content 3x")
				return
			}
			r.sleepPace(ctx)
			continue
		}
		failures = 0

		// 指定个股专场:即使 LLM 违规想 switch 到别的票,也强制把焦点锁回指定股。
		if pinnedSym != "" {
			if action.Action == "switch" {
				action.Action = "ask"
			}
			if action.FocusSymbol != "" && !strings.EqualFold(action.FocusSymbol, pinnedSym) {
				action.FocusSymbol = pinnedSym
				action.FocusName = pinnedName
			}
		}

		// 2. 写 host message
		hostRole := actionToRole(action.Action)
		hostMsg, err := r.messages.Append(ctx, AppendInput{
			RoomID:        rid,
			Role:          hostRole,
			Persona:       host.ID,
			PersonaName:   host.Name,
			TargetPersona: action.TargetPersona,
			FocusSymbol:   action.FocusSymbol,
			FocusName:     action.FocusName,
			Content:       hostContent,
		})
		if err != nil {
			logger.Warn().Err(err).Msg("live loop: append host msg")
			r.sleepPace(ctx)
			continue
		}
		_ = r.rooms.IncMessageCount(ctx, rid)
		if action.FocusSymbol != "" {
			_ = r.rooms.UpdateFocus(ctx, rid, action.FocusSymbol, action.FocusName)
		}

		// 3. close → 直接退出
		if action.Action == "close" {
			logger.Info().Msg("live loop: host closed")
			break
		}

		// 4. 由 guest 接话
		if err := r.handleGuestResponse(ctx, rid, room.Phase, action, hostMsg, guests); err != nil {
			logger.Warn().Err(err).Msg("live loop: guest response")
			// 嘉宾失败不算 fatal,继续下一轮
		}

		r.sleepPace(ctx)
	}

	_ = r.rooms.MarkEnded(ctx, rid)
	logger.Info().Msg("live loop: ended normally")
}

// handleGuestResponse 在 host 发完 ask/switch/open/react_prompt 后,生成嘉宾应答并写库。
func (r *Runner) handleGuestResponse(
	ctx context.Context,
	roomID int64,
	phase string,
	action *HostAction,
	hostMsg *Message,
	guests []PersonaRef,
) error {
	// 取目标嘉宾
	var target PersonaRef
	if action.TargetPersona != "" {
		for _, g := range guests {
			if g.ID == action.TargetPersona {
				target = g
				break
			}
		}
	}

	isReact := action.Action == "react_prompt"
	var reactTo string
	if isReact {
		// 找最近一条 guest 消息的 persona 名作为"被回应对象"
		recent, _ := r.messages.ListRecent(ctx, roomID, 10)
		for i := len(recent) - 1; i >= 0; i-- {
			if strings.HasPrefix(recent[i].Role, "guest_") {
				reactTo = recent[i].PersonaName
				if target.ID == "" {
					// react_prompt 没指定具体人,随机一个非"被回应人"
					for _, g := range guests {
						if g.Name != recent[i].PersonaName {
							target = g
							break
						}
					}
				}
				break
			}
		}
	}

	if target.ID == "" {
		// 极端 fallback:随机选一个嘉宾(避免空目标)
		if len(guests) > 0 {
			target = guests[rand.Intn(len(guests))]
		} else {
			return errors.New("no target persona")
		}
	}

	// 取历史(含 host 刚发的提问)
	history, _ := r.messages.ListRecent(ctx, roomID, 12)
	focus, focusName := currentFocus(history)

	res, err := r.guest.Speak(ctx, SpeakInput{
		Guest:        target,
		Phase:        phase,
		Now:          time.Now(),
		FocusSymbol:  focus,
		FocusName:    focusName,
		History:      history,
		HostQuestion: hostMsg.Content,
		IsReact:      isReact,
		ReactTo:      reactTo,
	})
	if err != nil {
		// 写一条 system message 占位,让前端不会"问完没人答"
		_, _ = r.messages.Append(ctx, AppendInput{
			RoomID:      roomID,
			Role:        RoleSystem,
			Persona:     "system",
			PersonaName: "系统",
			FocusSymbol: focus,
			FocusName:   focusName,
			Content:     fmt.Sprintf("(%s 信号暂时不好,稍后再说)", target.Name),
		})
		_ = r.rooms.IncMessageCount(ctx, roomID)
		return err
	}

	guestRole := RoleGuestAnswer
	if isReact {
		guestRole = RoleGuestReact
	}

	// annotations:LLM 返回的 K 线价位标注,marshal 后存 annotations 字段。
	// 空数组就不写(让 DB 列为 NULL,前端无需展示)。
	var annotJSON string
	if len(res.Annotations) > 0 {
		if buf, err := json.Marshal(res.Annotations); err == nil {
			annotJSON = string(buf)
		}
	}

	_, err = r.messages.Append(ctx, AppendInput{
		RoomID:      roomID,
		Role:        guestRole,
		Persona:     target.ID,
		PersonaName: target.Name,
		FocusSymbol: focus,
		FocusName:   focusName,
		Content:     res.Content,
		Annotations: annotJSON,
	})
	if err != nil {
		return err
	}
	_ = r.rooms.IncMessageCount(ctx, roomID)
	return nil
}

// buildCandidatePool 拉当日热门股票池(20 只)作为 host 切换 focus 的备选。
//
// 失败时返回空池子 — host 在没有候选时会用 LLM 自己想股票(可能编造,
// 但有 guest 工具兜底真实数据,问题不大)。
func (r *Runner) buildCandidatePool(ctx context.Context, phase string) []CandidateStock {
	if r.rt == nil {
		return nil
	}
	rctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	movers, err := r.rt.FetchTopMovers(rctx, realtime.MoversOptions{
		Direction: "up", Scope: "a", Limit: 20,
	})
	if err != nil {
		r.logger.Warn().Err(err).Msg("live: build candidate pool")
		return nil
	}
	out := make([]CandidateStock, 0, len(movers))
	for _, m := range movers {
		if m.TsCode == "" {
			continue
		}
		out = append(out, CandidateStock{
			Symbol: m.TsCode,
			Name:   m.Name,
			Reason: fmt.Sprintf("涨幅 %.2f%% / 换手 %.2f%%", m.PctChg, m.TurnoverRate),
		})
	}
	return out
}

// sleepPace 间隔 PaceInterval ± PaceJitter,可被 ctx 取消。
func (r *Runner) sleepPace(ctx context.Context) {
	dur := r.PaceInterval
	if r.PaceJitter > 0 {
		j := time.Duration(rand.Int63n(int64(r.PaceJitter * 2))) - r.PaceJitter
		dur += j
	}
	if dur < time.Second {
		dur = time.Second
	}
	select {
	case <-ctx.Done():
	case <-time.After(dur):
	}
}

// currentFocus 从历史里反向查最近一条非空 focus_symbol。
func currentFocus(history []Message) (string, string) {
	for i := len(history) - 1; i >= 0; i-- {
		m := history[i]
		if m.FocusSymbol.Valid && m.FocusSymbol.String != "" {
			name := m.FocusSymbol.String
			if m.FocusName.Valid && m.FocusName.String != "" {
				name = m.FocusName.String
			}
			return m.FocusSymbol.String, name
		}
	}
	return "", ""
}

func actionToRole(action string) string {
	switch action {
	case "open":
		return RoleHostOpen
	case "ask":
		return RoleHostAsk
	case "switch":
		return RoleHostSwitch
	case "react_prompt":
		return RoleHostAsk // 复用 ask 样式
	case "topic":
		return RoleHostAsk // 复用 ask 样式(无 focus 的话题切入)
	case "close":
		return RoleHostClose
	}
	return RoleHostAsk
}

// isDuplicateHost 判断 candidate 是否与最近 3 条 host 消息内容雷同。
//
// 雷同定义(任一满足):
//   * 去空白后完全相等
//   * 前 40 个字符完全相等(可能 LLM 改了后面但开头几乎一样)
//
// 用于过滤 LLM 偶发的"鹦鹉学舌"输出 — 防止直播间出现 2 条几乎一模一样的提问。
func isDuplicateHost(history []Message, candidate, hostID string) bool {
	cand := normalizeForDedup(candidate)
	if cand == "" {
		return false
	}
	checked := 0
	for i := len(history) - 1; i >= 0 && checked < 3; i-- {
		m := history[i]
		if m.Persona != hostID {
			continue
		}
		checked++
		prev := normalizeForDedup(m.Content)
		if prev == "" {
			continue
		}
		if prev == cand {
			return true
		}
		// 前 40 字符相等也算雷同
		rsCand := []rune(cand)
		rsPrev := []rune(prev)
		n := 40
		if len(rsCand) < n {
			n = len(rsCand)
		}
		if len(rsPrev) < n {
			n = len(rsPrev)
		}
		if n >= 20 && string(rsCand[:n]) == string(rsPrev[:n]) {
			return true
		}
	}
	return false
}

func normalizeForDedup(s string) string {
	s = strings.TrimSpace(s)
	// 把连续空白合并为一个,去掉换行(避免格式差异导致漏判)
	var b strings.Builder
	lastSpace := false
	for _, r := range s {
		if r == ' ' || r == '\t' || r == '\n' || r == '\r' {
			if !lastSpace {
				b.WriteRune(' ')
				lastSpace = true
			}
			continue
		}
		lastSpace = false
		b.WriteRune(r)
	}
	return b.String()
}

func isWeekend(t time.Time) bool {
	return t.Weekday() == time.Saturday || t.Weekday() == time.Sunday
}

func inWindow(t time.Time, s slotWindow) bool {
	cur := t.Hour()*60 + t.Minute()
	start := s.hStart*60 + s.mStart
	end := s.hEnd*60 + s.mEnd
	return cur >= start && cur < end
}

