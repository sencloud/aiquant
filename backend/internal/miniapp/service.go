package miniapp

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"math/rand"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"
	"github.com/rs/zerolog"

	"github.com/sencloud/finme-backend/internal/store"
)

// 错误。
var (
	ErrNotFound      = errors.New("mini app not found")
	ErrAppLimit      = errors.New("mini app limit reached")
	ErrMountLimit    = errors.New("mount limit reached")
	ErrBadTopic      = errors.New("bad topic")
	ErrBadRequestID  = errors.New("bad request id")
	ErrBadMessage    = errors.New("bad message")
	ErrTooFast       = errors.New("generation too fast")
	ErrDailyLimit    = errors.New("generation daily limit")
	ErrGenBusy       = errors.New("generation in progress")
	ErrUnavailable   = errors.New("generation unavailable")
	ErrRunRateLimit  = errors.New("run rate limited")
	ErrBadInput      = errors.New("bad input")
	ErrTemplateLogin = errors.New("template needs login")
)

// Prices 是喜点定价（已拍板：新建 5、修改 2，失败全额退回）。
type Prices struct {
	Create  int64
	Iterate int64
}

// Options 配置。
type Options struct {
	Prices Prices
	// CreateModel / IterateModel 为空时用 LLM 默认模型。
	CreateModel  string
	IterateModel string
	// MaxRepairs 是校验 / 试运行失败后让模型自动修复的最多轮数。
	MaxRepairs int
	// GenTimeout 是单次生成（含修复）的总时限。
	GenTimeout time.Duration
	// GensPerMinute / GensPerDay 是每用户生成频率上限。
	GensPerMinute int
	GensPerDay    int
	// RunsPerHour 是每用户（或每 IP）每小时运行上限。
	RunsPerHour int
	// Sync 为 true 时生成在请求里同步完成（测试用）。
	Sync bool
	Now  func() time.Time
}

// Service 是小应用的总入口。
type Service struct {
	st        *store.Store
	reg       *Registry
	fetcher   *Fetcher
	runner    *Runner
	llm       LLM
	opts      Options
	log       *zerolog.Logger
	templates []*Template

	rateMu sync.Mutex
	rate   map[string][]time.Time
}

// NewService 构造。llm 为 nil 时生成接口返回 ErrUnavailable，其余功能照常。
func NewService(st *store.Store, reg *Registry, f *Fetcher, l LLM, o Options, log *zerolog.Logger) *Service {
	if log == nil {
		nop := zerolog.Nop()
		log = &nop
	}
	if o.Prices.Create <= 0 {
		o.Prices.Create = 5
	}
	if o.Prices.Iterate <= 0 {
		o.Prices.Iterate = 2
	}
	if o.MaxRepairs <= 0 {
		o.MaxRepairs = 3
	}
	if o.GenTimeout <= 0 {
		o.GenTimeout = 240 * time.Second
	}
	if o.GensPerMinute <= 0 {
		o.GensPerMinute = 3
	}
	if o.GensPerDay <= 0 {
		o.GensPerDay = 50
	}
	if o.RunsPerHour <= 0 {
		o.RunsPerHour = 120
	}
	if o.Now == nil {
		o.Now = time.Now
	}
	s := &Service{st: st, reg: reg, fetcher: f, llm: l, opts: o, log: log, rate: map[string][]time.Time{}}
	s.runner = &Runner{F: f, Now: o.Now}
	tpls, errs := LoadTemplates(reg)
	for _, e := range errs {
		log.Warn().Err(e).Msg("miniapp: template skipped")
	}
	s.templates = tpls
	return s
}

// Registry 返回数据源注册表。
func (s *Service) Registry() *Registry { return s.reg }

// Prices 返回定价。
func (s *Service) Prices() Prices { return s.opts.Prices }

// LLMConfigured 生成是否可用。
func (s *Service) LLMConfigured() bool { return s.llm != nil }

// ─── 视图 ──────────────────────────────────────────────────────────────

// AppView 是小应用的接口形态。
type AppView struct {
	UUID       string         `json:"uuid"`
	Topic      string         `json:"topic"`
	Title      string         `json:"title"`
	Icon       string         `json:"icon"`
	Summary    string         `json:"summary"`
	Status     string         `json:"status"`
	Version    int            `json:"version"`
	Mounted    bool           `json:"mounted"`
	Position   int            `json:"position"`
	CardSize   string         `json:"card_size"`
	TemplateID string         `json:"template_id,omitempty"`
	SessionID  string         `json:"session_id"`
	Spec       map[string]any `json:"spec,omitempty"`
	Inputs     map[string]any `json:"inputs,omitempty"`
	State      map[string]any `json:"state,omitempty"`
	CreatedAt  int64          `json:"created_at"`
	UpdatedAt  int64          `json:"updated_at"`
}

type listRow struct {
	appRow
	SpecJSON string         `db:"spec_json"`
	Position sql.NullInt64  `db:"position"`
	CardSize sql.NullString `db:"card_size"`
	Inputs   sql.NullString `db:"inputs_json"`
	State    sql.NullString `db:"state_json"`
}

func (r *listRow) view() *AppView {
	v := &AppView{UUID: r.UUID, Topic: r.Topic, Title: r.Title, Icon: r.Icon, Summary: r.Summary,
		Status: r.Status, Version: r.CurrentVersion, SessionID: r.SessionID, CreatedAt: r.CreatedAt,
		UpdatedAt: r.UpdatedAt, TemplateID: r.TemplateID.String, CardSize: "medium"}
	if r.Position.Valid {
		v.Mounted, v.Position = true, int(r.Position.Int64)
	}
	if r.CardSize.Valid {
		v.CardSize = r.CardSize.String
	}
	_ = json.Unmarshal([]byte(r.SpecJSON), &v.Spec)
	if r.Inputs.Valid {
		_ = json.Unmarshal([]byte(r.Inputs.String), &v.Inputs)
	}
	if r.State.Valid {
		_ = json.Unmarshal([]byte(r.State.String), &v.State)
	}
	if !v.Mounted {
		if m, ok := v.Spec["meta"].(map[string]any); ok {
			if cs, ok := m["card_size"].(string); ok {
				v.CardSize = cs
			}
		}
	}
	return v
}

const listSQL = `SELECT a.*, v.spec_json, m.position, m.card_size, st.inputs_json, st.state_json
	FROM mini_apps a
	JOIN mini_app_versions v ON v.app_id=a.id AND v.version=a.current_version
	LEFT JOIN mini_app_mounts m ON m.app_id=a.id AND m.user_id=a.user_id AND m.topic=a.topic
	LEFT JOIN mini_app_state st ON st.app_id=a.id
	WHERE a.user_id=? AND a.deleted_at IS NULL`

// List 返回某主题下用户的全部小应用（已挂载的按位置在前，其余按更新时间）。
func (s *Service) List(ctx context.Context, uid int64, topic string) ([]*AppView, error) {
	if !ValidTopic(topic) {
		return nil, ErrBadTopic
	}
	rows := []listRow{}
	if err := s.st.DB.SelectContext(ctx, &rows, listSQL+" AND a.topic=?", uid, topic); err != nil {
		return nil, err
	}
	out := make([]*AppView, 0, len(rows))
	for i := range rows {
		out = append(out, rows[i].view())
	}
	sort.SliceStable(out, func(i, j int) bool {
		a, b := out[i], out[j]
		if a.Mounted != b.Mounted {
			return a.Mounted
		}
		if a.Mounted {
			return a.Position < b.Position
		}
		return a.UpdatedAt > b.UpdatedAt
	})
	return out, nil
}

// Get 返回一个小应用（含当前 spec、参数、状态）。
func (s *Service) Get(ctx context.Context, uid int64, id string) (*AppView, error) {
	rows := []listRow{}
	if err := s.st.DB.SelectContext(ctx, &rows, listSQL+" AND a.uuid=?", uid, id); err != nil {
		return nil, err
	}
	if len(rows) == 0 {
		return nil, ErrNotFound
	}
	return rows[0].view(), nil
}

// Rename 改标题 / 图标（不产生新版本，直接改 app 行与当前版本的 meta）。
func (s *Service) Rename(ctx context.Context, uid int64, id string, title, icon *string) (*AppView, error) {
	app, err := s.appByUUID(ctx, uid, id)
	if err != nil {
		return nil, err
	}
	if title != nil {
		t := strings.TrimSpace(*title)
		if t == "" || len([]rune(t)) > 20 {
			return nil, fmt.Errorf("%w: 标题 1–20 字", ErrBadInput)
		}
		for _, w := range BannedWords(app.Topic) {
			if strings.Contains(t, w) {
				return nil, fmt.Errorf("%w: 标题包含不允许的词", ErrBadInput)
			}
		}
		app.Title = t
	}
	if icon != nil {
		if !iconSet[*icon] {
			return nil, fmt.Errorf("%w: 不支持的图标", ErrBadInput)
		}
		app.Icon = *icon
	}
	ver, err := s.versionOf(ctx, app.ID, app.CurrentVersion)
	if err != nil {
		return nil, err
	}
	var spec map[string]any
	_ = json.Unmarshal([]byte(ver.SpecJSON), &spec)
	if m, ok := spec["meta"].(map[string]any); ok {
		m["title"], m["icon"] = app.Title, app.Icon
	}
	b, _ := json.Marshal(spec)
	now := s.opts.Now().UnixMilli()
	err = s.st.Tx(ctx, func(tx *sqlx.Tx) error {
		if _, err := tx.ExecContext(ctx, "UPDATE mini_apps SET title=?, icon=?, updated_at=? WHERE id=?",
			app.Title, app.Icon, now, app.ID); err != nil {
			return err
		}
		_, err := tx.ExecContext(ctx, "UPDATE mini_app_versions SET spec_json=?, spec_hash=? WHERE id=?",
			string(b), specHash(b), ver.ID)
		return err
	})
	if err != nil {
		return nil, err
	}
	return s.Get(ctx, uid, id)
}

// Delete 软删除，并取下挂载。
func (s *Service) Delete(ctx context.Context, uid int64, id string) error {
	app, err := s.appByUUID(ctx, uid, id)
	if err != nil {
		return err
	}
	now := s.opts.Now().UnixMilli()
	return s.st.Tx(ctx, func(tx *sqlx.Tx) error {
		if _, err := tx.ExecContext(ctx, "UPDATE mini_apps SET deleted_at=?, updated_at=? WHERE id=?", now, now, app.ID); err != nil {
			return err
		}
		if _, err := tx.ExecContext(ctx, "DELETE FROM mini_app_mounts WHERE app_id=?", app.ID); err != nil {
			return err
		}
		return renumberTx(ctx, tx, uid, app.Topic)
	})
}

func renumberTx(ctx context.Context, tx *sqlx.Tx, uid int64, topic string) error {
	var ids []int64
	if err := tx.SelectContext(ctx, &ids,
		"SELECT app_id FROM mini_app_mounts WHERE user_id=? AND topic=? ORDER BY position, mounted_at", uid, topic); err != nil {
		return err
	}
	for i, id := range ids {
		if _, err := tx.ExecContext(ctx, "UPDATE mini_app_mounts SET position=? WHERE user_id=? AND topic=? AND app_id=?",
			i, uid, topic, id); err != nil {
			return err
		}
	}
	return nil
}

// Mount 挂到发现页末尾（已挂载时只更新尺寸）。
func (s *Service) Mount(ctx context.Context, uid int64, id, cardSize string) (*AppView, error) {
	app, err := s.appByUUID(ctx, uid, id)
	if err != nil {
		return nil, err
	}
	if cardSize == "" {
		cardSize = "medium"
	}
	if cardSize != "small" && cardSize != "medium" && cardSize != "large" {
		return nil, fmt.Errorf("%w: card_size 只能是 small / medium / large", ErrBadInput)
	}
	now := s.opts.Now().UnixMilli()
	err = s.st.Tx(ctx, func(tx *sqlx.Tx) error {
		var exists int
		if err := tx.GetContext(ctx, &exists, "SELECT COUNT(*) FROM mini_app_mounts WHERE app_id=?", app.ID); err != nil {
			return err
		}
		if exists > 0 {
			_, err := tx.ExecContext(ctx, "UPDATE mini_app_mounts SET card_size=? WHERE app_id=?", cardSize, app.ID)
			return err
		}
		var n int
		if err := tx.GetContext(ctx, &n, "SELECT COUNT(*) FROM mini_app_mounts WHERE user_id=? AND topic=?", uid, app.Topic); err != nil {
			return err
		}
		if n >= MaxMountedPerTopic {
			return ErrMountLimit
		}
		if _, err := tx.ExecContext(ctx, `INSERT INTO mini_app_mounts(user_id, topic, app_id, position, card_size, mounted_at)
			VALUES(?,?,?,?,?,?)`, uid, app.Topic, app.ID, n, cardSize, now); err != nil {
			return err
		}
		_, err := tx.ExecContext(ctx, "UPDATE mini_apps SET status='active', updated_at=? WHERE id=?", now, app.ID)
		return err
	})
	if err != nil {
		return nil, err
	}
	return s.Get(ctx, uid, id)
}

// Unmount 从发现页取下（小应用本身保留）。
func (s *Service) Unmount(ctx context.Context, uid int64, id string) error {
	app, err := s.appByUUID(ctx, uid, id)
	if err != nil {
		return err
	}
	return s.st.Tx(ctx, func(tx *sqlx.Tx) error {
		if _, err := tx.ExecContext(ctx, "DELETE FROM mini_app_mounts WHERE app_id=?", app.ID); err != nil {
			return err
		}
		return renumberTx(ctx, tx, uid, app.Topic)
	})
}

// Reorder 按给定顺序重排已挂载的小应用（列表必须恰好是当前已挂载的集合）。
func (s *Service) Reorder(ctx context.Context, uid int64, topic string, ids []string) ([]*AppView, error) {
	if !ValidTopic(topic) {
		return nil, ErrBadTopic
	}
	err := s.st.Tx(ctx, func(tx *sqlx.Tx) error {
		cur := []struct {
			AppID int64  `db:"app_id"`
			UUID  string `db:"uuid"`
		}{}
		if err := tx.SelectContext(ctx, &cur, `SELECT m.app_id, a.uuid FROM mini_app_mounts m JOIN mini_apps a ON a.id=m.app_id
			WHERE m.user_id=? AND m.topic=?`, uid, topic); err != nil {
			return err
		}
		byUUID := map[string]int64{}
		for _, c := range cur {
			byUUID[c.UUID] = c.AppID
		}
		if len(ids) != len(byUUID) {
			return fmt.Errorf("%w: 顺序列表与已挂载的小应用不一致", ErrBadInput)
		}
		seen := map[string]bool{}
		for i, id := range ids {
			appID, ok := byUUID[id]
			if !ok || seen[id] {
				return fmt.Errorf("%w: 顺序列表与已挂载的小应用不一致", ErrBadInput)
			}
			seen[id] = true
			if _, err := tx.ExecContext(ctx, "UPDATE mini_app_mounts SET position=? WHERE app_id=?", i, appID); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return s.List(ctx, uid, topic)
}

// Versions 返回历史版本（不含 spec 正文）。
func (s *Service) Versions(ctx context.Context, uid int64, id string) ([]map[string]any, error) {
	app, err := s.appByUUID(ctx, uid, id)
	if err != nil {
		return nil, err
	}
	rows := []versionRow{}
	if err := s.st.DB.SelectContext(ctx, &rows,
		"SELECT * FROM mini_app_versions WHERE app_id=? ORDER BY version DESC", app.ID); err != nil {
		return nil, err
	}
	out := make([]map[string]any, 0, len(rows))
	for _, r := range rows {
		out = append(out, map[string]any{"version": r.Version, "summary": r.ChangeSummary, "author": r.Author,
			"created_at": r.CreatedAt, "current": r.Version == app.CurrentVersion})
	}
	return out, nil
}

// Restore 把某个历史版本复制成新的当前版本（重新校验，防止旧 spec 与新规则冲突）。
func (s *Service) Restore(ctx context.Context, uid int64, id string, version int) (*AppView, error) {
	app, err := s.appByUUID(ctx, uid, id)
	if err != nil {
		return nil, err
	}
	ver, err := s.versionOf(ctx, app.ID, version)
	if err != nil {
		return nil, err
	}
	c, issues := ValidateJSON([]byte(ver.SpecJSON), app.Topic, s.reg)
	if len(issues) > 0 {
		return nil, fmt.Errorf("%w: 这个版本已不兼容（%s）", ErrBadInput, issues[0].String())
	}
	now := s.opts.Now().UnixMilli()
	err = s.st.Tx(ctx, func(tx *sqlx.Tx) error {
		_, _, err := insertVersionTx(ctx, tx, app, c, fmt.Sprintf("恢复到第 %d 版", version), "restore", "", now)
		return err
	})
	if err != nil {
		return nil, err
	}
	return s.Get(ctx, uid, id)
}

// SaveState 保存用户参数与状态（参数按定义校验，不合法的丢弃）。
func (s *Service) SaveState(ctx context.Context, uid int64, id string, inputs, state map[string]any) (*AppView, error) {
	app, err := s.appByUUID(ctx, uid, id)
	if err != nil {
		return nil, err
	}
	ver, err := s.versionOf(ctx, app.ID, app.CurrentVersion)
	if err != nil {
		return nil, err
	}
	c, issues := ValidateJSON([]byte(ver.SpecJSON), app.Topic, s.reg)
	if len(issues) > 0 {
		return nil, fmt.Errorf("%w: %s", ErrBadInput, issues[0].String())
	}
	clean := map[string]any{}
	for k, v := range inputs {
		if d, ok := c.Inputs[k]; ok && inputOK(d, v) {
			clean[k] = v
		}
	}
	if state == nil {
		state = map[string]any{}
	}
	ib, _ := json.Marshal(clean)
	sb, _ := json.Marshal(state)
	if len(sb) > 8<<10 {
		return nil, fmt.Errorf("%w: state 太大", ErrBadInput)
	}
	_, err = s.st.DB.ExecContext(ctx, `INSERT INTO mini_app_state(app_id, user_id, inputs_json, state_json, updated_at)
		VALUES(?,?,?,?,?) ON CONFLICT(app_id) DO UPDATE SET inputs_json=excluded.inputs_json,
		state_json=excluded.state_json, updated_at=excluded.updated_at`,
		app.ID, uid, string(ib), string(sb), s.opts.Now().UnixMilli())
	if err != nil {
		return nil, err
	}
	return s.Get(ctx, uid, id)
}

// ─── 运行 ──────────────────────────────────────────────────────────────

func (s *Service) allowRun(who string) bool {
	s.rateMu.Lock()
	defer s.rateMu.Unlock()
	now := s.opts.Now()
	cut := now.Add(-time.Hour)
	ts := s.rate[who]
	k := 0
	for _, t := range ts {
		if t.After(cut) {
			ts[k] = t
			k++
		}
	}
	ts = ts[:k]
	limit := s.opts.RunsPerHour
	if strings.HasPrefix(who, "ip:") {
		limit = limit / 4
	}
	if len(ts) >= limit {
		s.rate[who] = ts
		return false
	}
	s.rate[who] = append(ts, now)
	return true
}

// Run 打开小应用时取数（inputs 为空时用保存的参数）。
func (s *Service) Run(ctx context.Context, uid int64, id string, inputs map[string]any) (*RunResult, error) {
	who := fmt.Sprintf("u:%d", uid)
	if !s.allowRun(who) {
		return nil, ErrRunRateLimit
	}
	app, err := s.appByUUID(ctx, uid, id)
	if err != nil {
		return nil, err
	}
	ver, err := s.versionOf(ctx, app.ID, app.CurrentVersion)
	if err != nil {
		return nil, err
	}
	c, issues := ValidateJSON([]byte(ver.SpecJSON), app.Topic, s.reg)
	if len(issues) > 0 {
		return nil, fmt.Errorf("%w: %s", ErrBadInput, issues[0].String())
	}
	var state map[string]any
	if inputs == nil {
		var st struct {
			Inputs string `db:"inputs_json"`
			State  string `db:"state_json"`
		}
		if err := s.st.DB.GetContext(ctx, &st, "SELECT inputs_json, state_json FROM mini_app_state WHERE app_id=?", app.ID); err == nil {
			_ = json.Unmarshal([]byte(st.Inputs), &inputs)
			_ = json.Unmarshal([]byte(st.State), &state)
		}
	}
	start := s.opts.Now()
	res := s.runner.Run(ctx, c, inputs, state, uid, who)
	s.recordRun(ctx, &app.ID, "", &uid, app.CurrentVersion, "open", res, start)
	return res, nil
}

func (s *Service) recordRun(ctx context.Context, appID *int64, tplID string, uid *int64, version int, trig string, res *RunResult, start time.Time) {
	status := "ok"
	var errMsg any
	if len(res.Errors) > 0 {
		status = "partial"
		if len(res.Errors) >= len(res.Stats) && len(res.Stats) > 0 {
			status = "error"
		}
		for _, e := range res.Errors {
			errMsg = shorten(e, 200)
			break
		}
	}
	sb, _ := json.Marshal(res.Stats)
	if res.Stats == nil {
		sb = []byte("[]")
	}
	ctx = context.WithoutCancel(ctx)
	_, err := s.st.DB.ExecContext(ctx, `INSERT INTO mini_app_runs(app_id, template_id, user_id, version, run_trigger, status,
		duration_ms, sources_json, cost_units, error, created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)`,
		appID, nullIfEmpty(tplID), uid, version, trig, status, s.opts.Now().Sub(start).Milliseconds(),
		string(sb), res.Cost, errMsg, s.opts.Now().UnixMilli())
	if err != nil {
		s.log.Warn().Err(err).Msg("miniapp: record run failed")
	}
	if rand.Intn(200) == 0 {
		cut := s.opts.Now().Add(-30 * 24 * time.Hour).UnixMilli()
		_, _ = s.st.DB.ExecContext(ctx, "DELETE FROM mini_app_runs WHERE created_at<?", cut)
	}
	s.log.Info().Str("trigger", trig).Str("status", status).Int("cost", res.Cost).
		Int("sources", len(res.Stats)).Dur("took", s.opts.Now().Sub(start)).Msg("miniapp run")
}

// ─── 模板 ──────────────────────────────────────────────────────────────

// Templates 返回某主题的官方模板。
func (s *Service) Templates(topic string) []*Template {
	var out []*Template
	for _, t := range s.templates {
		if t.Topic == topic {
			out = append(out, t)
		}
	}
	return out
}

func (s *Service) template(id string) *Template {
	for _, t := range s.templates {
		if t.ID == id {
			return t
		}
	}
	return nil
}

// RunTemplate 运行官方模板（未登录也可以：私有数据源返回空）。
func (s *Service) RunTemplate(ctx context.Context, uid int64, ip, id string, inputs map[string]any) (*RunResult, error) {
	t := s.template(id)
	if t == nil {
		return nil, ErrNotFound
	}
	who := fmt.Sprintf("u:%d", uid)
	if uid <= 0 {
		who = "ip:" + ip
	}
	if !s.allowRun(who) {
		return nil, ErrRunRateLimit
	}
	start := s.opts.Now()
	res := s.runner.Run(ctx, t.compiled, inputs, nil, uid, who)
	var up *int64
	if uid > 0 {
		up = &uid
	}
	s.recordRun(ctx, nil, t.ID, up, 0, "template", res, start)
	return res, nil
}

// FromTemplate 把官方模板复制成自己的小应用并挂到发现页（免费；计入 20 个上限）。
func (s *Service) FromTemplate(ctx context.Context, uid int64, id string) (*AppView, error) {
	t := s.template(id)
	if t == nil {
		return nil, ErrNotFound
	}
	now := s.opts.Now().UnixMilli()
	var appUUID string
	err := s.st.Tx(ctx, func(tx *sqlx.Tx) error {
		n, err := s.countApps(ctx, tx, uid, t.Topic)
		if err != nil {
			return err
		}
		if n >= MaxAppsPerTopic {
			return ErrAppLimit
		}
		app, err := createAppTx(ctx, tx, uid, t.Topic, "", t.ID, now)
		if err != nil {
			return err
		}
		if _, _, err := insertVersionTx(ctx, tx, app, t.compiled, "来自官方模板", "template", "", now); err != nil {
			return err
		}
		appUUID = app.UUID
		var m int
		if err := tx.GetContext(ctx, &m, "SELECT COUNT(*) FROM mini_app_mounts WHERE user_id=? AND topic=?", uid, t.Topic); err != nil {
			return err
		}
		if m < MaxMountedPerTopic {
			cs, _ := t.Spec["meta"].(map[string]any)["card_size"].(string)
			if _, err := tx.ExecContext(ctx, `INSERT INTO mini_app_mounts(user_id, topic, app_id, position, card_size, mounted_at)
				VALUES(?,?,?,?,?,?)`, uid, t.Topic, app.ID, m, cs, now); err != nil {
				return err
			}
			_, err = tx.ExecContext(ctx, "UPDATE mini_apps SET status='active' WHERE id=?", app.ID)
			return err
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return s.Get(ctx, uid, appUUID)
}

func createAppTx(ctx context.Context, tx *sqlx.Tx, uid int64, topic, session, templateID string, now int64) (*appRow, error) {
	app := &appRow{UUID: uuid.NewString(), UserID: uid, Topic: topic, Title: "新小应用", Icon: "apps",
		Status: "draft", SessionID: session, CreatedAt: now, UpdatedAt: now}
	res, err := tx.ExecContext(ctx, `INSERT INTO mini_apps(uuid, user_id, topic, title, icon, summary, status, current_version,
		session_id, template_id, created_at, updated_at) VALUES(?,?,?,?,?,'',?,0,?,?,?,?)`,
		app.UUID, uid, topic, app.Title, app.Icon, app.Status, session, nullIfEmpty(templateID), now, now)
	if err != nil {
		return nil, err
	}
	app.ID, _ = res.LastInsertId()
	return app, nil
}

var idRe = regexp.MustCompile(`^[A-Za-z0-9_-]{8,64}$`)
