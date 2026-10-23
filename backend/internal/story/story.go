// Package story 是《喜爱 · 天亮以前》二次元试用版的服务端。
//
// 内容（七个夜晚、选项、结局）在客户端的内容包里；服务端只做三件事：
//  1. 跨设备保存 run 进度与聊天消息；
//  2. 用当前场景 + 最近对话跑 AI 自由聊天（不推进剧情、不剧透）；
//  3. 记录已解锁结局。
//
// 这样改文案不需要迁移，也不会把三套剧本复制到 Go 里。
package story

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"

	"github.com/sencloud/finme-backend/internal/llm"
	"github.com/sencloud/finme-backend/internal/platform"
	"github.com/sencloud/finme-backend/internal/store"
)

const (
	// SeasonID 是第一季「临海七日」。
	SeasonID = "before_dawn_s1"
	// MaxTurns 是每夜自由聊天的硬上限，控制成本。
	MaxTurns = 40
)

var allowedCharacters = map[string]bool{
	"linxia": true,
	"suyu":   true,
	"chenye": true,
}

// Run 是 story_runs 的一行。
type Run struct {
	ID            string         `db:"id"`
	UserID        int64          `db:"user_id"`
	SeasonID      string         `db:"season_id"`
	CharacterID   string         `db:"character_id"`
	Night         int            `db:"night"`
	Beat          int            `db:"beat"`
	Hearts        int            `db:"hearts"`
	FlagsJSON     string         `db:"flags"`
	NightComplete int            `db:"night_complete"`
	Finished      int            `db:"finished"`
	EndingID      sql.NullString `db:"ending_id"`
	CreatedAt     int64          `db:"created_at"`
	UpdatedAt     int64          `db:"updated_at"`
}

// Message 是 story_messages 的一行。
type Message struct {
	ID        int64  `db:"id"`
	RunID     string `db:"run_id"`
	Role      string `db:"role"`
	Content   string `db:"content"`
	Safety    int    `db:"safety"`
	CreatedAt int64  `db:"created_at"`
}

// RunView 是给客户端的 run 形状。
type RunView struct {
	ID            string   `json:"id"`
	SeasonID      string   `json:"season_id"`
	CharacterID   string   `json:"character_id"`
	Night         int      `json:"night"`
	Beat          int      `json:"beat"`
	Hearts        int      `json:"hearts"`
	Flags         []string `json:"flags"`
	NightComplete bool     `json:"night_complete"`
	Finished      bool     `json:"finished"`
	EndingID      string   `json:"ending_id,omitempty"`
	UpdatedAt     int64    `json:"updated_at"`
}

// MessageView 是给客户端的消息形状。
type MessageView struct {
	ID        int64  `json:"id"`
	Role      string `json:"role"`
	Content   string `json:"content"`
	Safety    bool   `json:"safety"`
	CreatedAt int64  `json:"created_at"`
}

// StateView 是「当前状态」响应。
type StateView struct {
	Run      *RunView      `json:"run"`
	Messages []MessageView `json:"messages"`
	Endings  []string      `json:"endings"`
}

// SaveInput 是客户端同步 run 的请求体。
type SaveInput struct {
	SeasonID      string   `json:"season_id"`
	CharacterID   string   `json:"character_id"`
	Night         int      `json:"night"`
	Beat          int      `json:"beat"`
	Hearts        int      `json:"hearts"`
	Flags         []string `json:"flags"`
	NightComplete bool     `json:"night_complete"`
	Finished      bool     `json:"finished"`
	EndingID      string   `json:"ending_id"`
}

// Config 是试用版的远程开关（一行，运营可直接改库或用 admin key 更新）。
type Config struct {
	Enabled      bool     `json:"enabled"`
	Characters   []string `json:"characters"`
	ShareEnabled bool     `json:"share_enabled"`
	MaxTurns     int      `json:"max_turns"`
	Notice       string   `json:"notice"`
	UpdatedAt    int64    `json:"updated_at"`
}

// ConfigInput 是管理端更新开关的请求体。
type ConfigInput struct {
	Enabled      bool     `json:"enabled"`
	Characters   []string `json:"characters"`
	ShareEnabled bool     `json:"share_enabled"`
	MaxTurns     int      `json:"max_turns"`
	Notice       string   `json:"notice"`
}

// SceneContext 是客户端带来的当前场景信息（客户端是内容作者）。
type SceneContext struct {
	Night    int      `json:"night"`
	Beat     int      `json:"beat"`
	BeatID   string   `json:"beat_id"`
	Place    string   `json:"place"`
	Scene    string   `json:"scene"`
	BeatNote string   `json:"beat_note"`
	Opening  []string `json:"opening"`
}

// ChatInput 是流式聊天请求体。
type ChatInput struct {
	Message string       `json:"message"`
	Scene   SceneContext `json:"scene"`
}

// Streamer 是 story 对 LLM 的最小依赖；测试可注入假实现。
type Streamer interface {
	ChatStream(ctx context.Context, req llm.StreamRequest, emit func(llm.StreamEvent) error) error
}

// Repo 是 story 的持久层。
type Repo struct {
	st *store.Store
}

func NewRepo(st *store.Store) *Repo { return &Repo{st: st} }

func (r *Repo) Get(ctx context.Context, userID int64, id string) (*Run, error) {
	var run Run
	err := r.st.DB.GetContext(ctx, &run,
		`SELECT * FROM story_runs WHERE id=? AND user_id=?`, id, userID)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("load story run: %w", err)
	}
	return &run, nil
}

func (r *Repo) Latest(ctx context.Context, userID int64) (*Run, error) {
	var run Run
	err := r.st.DB.GetContext(ctx, &run,
		`SELECT * FROM story_runs WHERE user_id=? ORDER BY updated_at DESC LIMIT 1`, userID)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("load latest story run: %w", err)
	}
	return &run, nil
}

func (r *Repo) Messages(ctx context.Context, runID string, limit int) ([]Message, error) {
	if limit <= 0 {
		limit = 100
	}
	var rows []Message
	if err := r.st.DB.SelectContext(ctx, &rows, `
		SELECT * FROM story_messages WHERE run_id=? ORDER BY id DESC LIMIT ?`,
		runID, limit); err != nil {
		return nil, fmt.Errorf("load story messages: %w", err)
	}
	for i, j := 0, len(rows)-1; i < j; i, j = i+1, j-1 {
		rows[i], rows[j] = rows[j], rows[i]
	}
	return rows, nil
}

func (r *Repo) AddMessage(ctx context.Context, runID, role, content string, safety bool) error {
	s := 0
	if safety {
		s = 1
	}
	_, err := r.st.DB.ExecContext(ctx, `
		INSERT INTO story_messages(run_id, role, content, safety, created_at)
		VALUES(?,?,?,?,?)`, runID, role, content, s, time.Now().UnixMilli())
	if err != nil {
		return fmt.Errorf("insert story message: %w", err)
	}
	return nil
}

func (r *Repo) CountUserMessages(ctx context.Context, runID string) (int, error) {
	var n int
	if err := r.st.DB.GetContext(ctx, &n,
		`SELECT COUNT(*) FROM story_messages WHERE run_id=? AND role='user'`, runID); err != nil {
		return 0, err
	}
	return n, nil
}

func (r *Repo) Upsert(ctx context.Context, userID int64, id string, in SaveInput) (*Run, error) {
	if err := validateSave(id, in); err != nil {
		return nil, err
	}
	flags, _ := json.Marshal(in.Flags)
	ending := any(nil)
	if strings.TrimSpace(in.EndingID) != "" {
		ending = strings.TrimSpace(in.EndingID)
	}
	now := time.Now().UnixMilli()
	season := strings.TrimSpace(in.SeasonID)
	if season == "" {
		season = SeasonID
	}
	res, err := r.st.DB.ExecContext(ctx, `
		INSERT INTO story_runs(
			id, user_id, season_id, character_id, night, beat, hearts, flags,
			night_complete, finished, ending_id, created_at, updated_at)
		VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
		ON CONFLICT(id) DO UPDATE SET
			season_id=excluded.season_id,
			character_id=excluded.character_id,
			night=excluded.night,
			beat=excluded.beat,
			hearts=excluded.hearts,
			flags=excluded.flags,
			night_complete=excluded.night_complete,
			finished=excluded.finished,
			ending_id=excluded.ending_id,
			updated_at=excluded.updated_at
		WHERE story_runs.user_id=excluded.user_id`,
		id, userID, season, in.CharacterID, in.Night, in.Beat, in.Hearts, string(flags),
		boolInt(in.NightComplete), boolInt(in.Finished), ending, now, now)
	if err != nil {
		return nil, fmt.Errorf("upsert story run: %w", err)
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return nil, platform.ErrNotFound("STORY.RUN_NOT_FOUND", "这条故事线不存在，或属于另一个账号")
	}
	if in.Finished && strings.TrimSpace(in.EndingID) != "" {
		if err := r.UnlockEnding(ctx, userID, season, in.EndingID, id); err != nil {
			return nil, err
		}
	}
	return r.Get(ctx, userID, id)
}

func (r *Repo) UnlockEnding(ctx context.Context, userID int64, season, endingID, runID string) error {
	_, err := r.st.DB.ExecContext(ctx, `
		INSERT OR IGNORE INTO story_endings(user_id, season_id, ending_id, run_id, unlocked_at)
		VALUES(?,?,?,?,?)`, userID, season, endingID, runID, time.Now().UnixMilli())
	if err != nil {
		return fmt.Errorf("unlock story ending: %w", err)
	}
	return nil
}

func (r *Repo) Endings(ctx context.Context, userID int64) ([]string, error) {
	var out []string
	if err := r.st.DB.SelectContext(ctx, &out, `
		SELECT ending_id FROM story_endings WHERE user_id=? ORDER BY unlocked_at`, userID); err != nil {
		return nil, fmt.Errorf("list story endings: %w", err)
	}
	return out, nil
}

func (r *Repo) Delete(ctx context.Context, userID int64, id string) error {
	return r.st.Tx(ctx, func(tx *sqlx.Tx) error {
		var owner int64
		if err := tx.GetContext(ctx, &owner,
			`SELECT user_id FROM story_runs WHERE id=?`, id); err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				return platform.ErrNotFound("STORY.RUN_NOT_FOUND", "这条故事线不存在")
			}
			return err
		}
		if owner != userID {
			return platform.ErrNotFound("STORY.RUN_NOT_FOUND", "这条故事线不存在")
		}
		// 不依赖 PRAGMA foreign_keys 一定开着：显式删子表，避免留下孤儿消息。
		if _, err := tx.ExecContext(ctx, `DELETE FROM story_messages WHERE run_id=?`, id); err != nil {
			return fmt.Errorf("delete story messages: %w", err)
		}
		if _, err := tx.ExecContext(ctx, `DELETE FROM story_endings WHERE run_id=?`, id); err != nil {
			return fmt.Errorf("delete story endings: %w", err)
		}
		if _, err := tx.ExecContext(ctx, `DELETE FROM story_runs WHERE id=? AND user_id=?`, id, userID); err != nil {
			return fmt.Errorf("delete story run: %w", err)
		}
		return nil
	})
}

func (r *Repo) Config(ctx context.Context) (Config, error) {
	var row struct {
		Enabled      int    `db:"enabled"`
		Characters   string `db:"characters"`
		ShareEnabled int    `db:"share_enabled"`
		MaxTurns     int    `db:"max_turns"`
		Notice       string `db:"notice"`
		UpdatedAt    int64  `db:"updated_at"`
	}
	err := r.st.DB.GetContext(ctx, &row, `
		SELECT enabled, characters, share_enabled, max_turns, notice, updated_at
		FROM story_config WHERE id='default'`)
	if errors.Is(err, sql.ErrNoRows) {
		return Config{
			Enabled: true, Characters: []string{"linxia", "suyu", "chenye"},
			ShareEnabled: true, MaxTurns: MaxTurns,
		}, nil
	}
	if err != nil {
		return Config{}, fmt.Errorf("load story config: %w", err)
	}
	return Config{
		Enabled:      row.Enabled == 1,
		Characters:   splitCharacters(row.Characters),
		ShareEnabled: row.ShareEnabled == 1,
		MaxTurns:     row.MaxTurns,
		Notice:       row.Notice,
		UpdatedAt:    row.UpdatedAt,
	}, nil
}

func (r *Repo) SetConfig(ctx context.Context, in ConfigInput) (Config, error) {
	chars := normalizeCharacters(in.Characters)
	maxTurns := in.MaxTurns
	if maxTurns < 1 || maxTurns > 80 {
		maxTurns = MaxTurns
	}
	notice := truncateRunes(strings.TrimSpace(in.Notice), 200)
	_, err := r.st.DB.ExecContext(ctx, `
		INSERT INTO story_config(id, enabled, characters, share_enabled, max_turns, notice, updated_at)
		VALUES('default',?,?,?,?,?,?)
		ON CONFLICT(id) DO UPDATE SET
			enabled=excluded.enabled,
			characters=excluded.characters,
			share_enabled=excluded.share_enabled,
			max_turns=excluded.max_turns,
			notice=excluded.notice,
			updated_at=excluded.updated_at`,
		boolInt(in.Enabled), strings.Join(chars, ","), boolInt(in.ShareEnabled),
		maxTurns, notice, time.Now().UnixMilli())
	if err != nil {
		return Config{}, fmt.Errorf("update story config: %w", err)
	}
	return r.Config(ctx)
}

func splitCharacters(s string) []string {
	var out []string
	for _, part := range strings.Split(s, ",") {
		part = strings.TrimSpace(part)
		if allowedCharacters[part] {
			out = append(out, part)
		}
	}
	return out
}

func normalizeCharacters(in []string) []string {
	seen := map[string]bool{}
	out := make([]string, 0, len(in))
	for _, id := range in {
		id = strings.TrimSpace(id)
		if !allowedCharacters[id] || seen[id] {
			continue
		}
		seen[id] = true
		out = append(out, id)
	}
	return out
}

func truncateRunes(s string, n int) string {
	if utf8.RuneCountInString(s) <= n {
		return s
	}
	return string([]rune(s)[:n])
}

func boolInt(v bool) int {
	if v {
		return 1
	}
	return 0
}

func validID(id string) bool {
	if len(id) < 8 || len(id) > 64 {
		return false
	}
	for _, c := range id {
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
			(c >= '0' && c <= '9') || c == '-' || c == '_' {
			continue
		}
		return false
	}
	return true
}

func validateSave(id string, in SaveInput) error {
	if !validID(id) {
		return platform.ErrBadRequest("STORY.RUN_ID_INVALID", "run id 不合法", nil)
	}
	if !allowedCharacters[in.CharacterID] {
		return platform.ErrBadRequest("STORY.CHARACTER_INVALID", "这一季只开放林夏 / 苏予 / 陈野", nil)
	}
	if in.Night < 1 || in.Night > 7 {
		return platform.ErrBadRequest("STORY.NIGHT_INVALID", "night 必须在 1–7", nil)
	}
	if in.Beat < 0 || in.Beat > 64 {
		return platform.ErrBadRequest("STORY.BEAT_INVALID", "beat 不合法", nil)
	}
	if in.Hearts < 0 || in.Hearts > 5 {
		return platform.ErrBadRequest("STORY.HEARTS_INVALID", "心级必须在 0–5", nil)
	}
	if len(in.Flags) > 64 {
		return platform.ErrBadRequest("STORY.FLAGS_TOO_MANY", "flag 太多", nil)
	}
	for _, f := range in.Flags {
		if len(f) > 96 {
			return platform.ErrBadRequest("STORY.FLAG_INVALID", "flag 太长", nil)
		}
	}
	if utf8.RuneCountInString(in.EndingID) > 96 {
		return platform.ErrBadRequest("STORY.ENDING_INVALID", "ending_id 太长", nil)
	}
	return nil
}

// Service 是 story 的业务入口。
type Service struct {
	repo     *Repo
	llm      Streamer
	model    string
	maxTurns int
}

func New(st *store.Store, streamer Streamer, model string) *Service {
	if model == "" {
		model = "deepseek-flash"
	}
	return &Service{
		repo:     NewRepo(st),
		llm:      streamer,
		model:    model,
		maxTurns: MaxTurns,
	}
}

func (s *Service) Configured() bool { return s.llm != nil }

func (s *Service) Save(ctx context.Context, userID int64, id string, in SaveInput) (*RunView, error) {
	if err := s.ensureOpen(ctx, in.CharacterID); err != nil {
		return nil, err
	}
	run, err := s.repo.Upsert(ctx, userID, id, in)
	if err != nil {
		return nil, err
	}
	return viewOf(run), nil
}

// ensureOpen 是远程开关的服务端兜底：客户端隐藏入口之外，伪造请求也进不来。
func (s *Service) ensureOpen(ctx context.Context, characterID string) error {
	cfg, err := s.repo.Config(ctx)
	if err != nil {
		return nil // 开关读失败时放行，避免配置表异常把整季关死。
	}
	if !cfg.Enabled {
		return platform.ErrForbidden("STORY.DISABLED", "今晚不营业")
	}
	for _, id := range cfg.Characters {
		if id == characterID {
			return nil
		}
	}
	return platform.ErrForbidden("STORY.CHARACTER_CLOSED", "这条线暂时没开")
}

func (s *Service) State(ctx context.Context, userID int64, runID string) (*StateView, error) {
	var run *Run
	var err error
	if strings.TrimSpace(runID) == "" {
		run, err = s.repo.Latest(ctx, userID)
	} else {
		run, err = s.repo.Get(ctx, userID, runID)
	}
	if err != nil {
		return nil, err
	}
	endings, err := s.repo.Endings(ctx, userID)
	if err != nil {
		return nil, err
	}
	out := &StateView{Messages: []MessageView{}, Endings: endings}
	if run == nil {
		return out, nil
	}
	out.Run = viewOf(run)
	msgs, err := s.repo.Messages(ctx, run.ID, 100)
	if err != nil {
		return nil, err
	}
	for _, m := range msgs {
		out.Messages = append(out.Messages, MessageView{
			ID: m.ID, Role: m.Role, Content: m.Content,
			Safety: m.Safety == 1, CreatedAt: m.CreatedAt,
		})
	}
	return out, nil
}

func (s *Service) Endings(ctx context.Context, userID int64) ([]string, error) {
	return s.repo.Endings(ctx, userID)
}

func (s *Service) Config(ctx context.Context) (Config, error) {
	return s.repo.Config(ctx)
}

func (s *Service) SetConfig(ctx context.Context, in ConfigInput) (Config, error) {
	return s.repo.SetConfig(ctx, in)
}

func (s *Service) Delete(ctx context.Context, userID int64, runID string) error {
	return s.repo.Delete(ctx, userID, runID)
}

func viewOf(r *Run) *RunView {
	var flags []string
	_ = json.Unmarshal([]byte(r.FlagsJSON), &flags)
	if flags == nil {
		flags = []string{}
	}
	ending := ""
	if r.EndingID.Valid {
		ending = r.EndingID.String
	}
	return &RunView{
		ID:            r.ID,
		SeasonID:      r.SeasonID,
		CharacterID:   r.CharacterID,
		Night:         r.Night,
		Beat:          r.Beat,
		Hearts:        r.Hearts,
		Flags:         flags,
		NightComplete: r.NightComplete == 1,
		Finished:      r.Finished == 1,
		EndingID:      ending,
		UpdatedAt:     r.UpdatedAt,
	}
}

// Chat 是 SSE 的流式入口。
//
// 客户端只发「这一句 + 当前场景」，服务端从库里拼历史和 run 状态；
// 因此即使换设备，角色也记得上一夜说过什么。
func (s *Service) Chat(
	ctx context.Context,
	userID int64,
	runID string,
	in ChatInput,
	emit func(event string, data any) error,
) error {
	text := strings.TrimSpace(in.Message)
	if text == "" {
		return emit("error", map[string]any{"code": "STORY.EMPTY_MESSAGE", "message": "说点什么"})
	}
	if utf8.RuneCountInString(text) > 1000 {
		return emit("error", map[string]any{"code": "STORY.MESSAGE_TOO_LONG", "message": "一句话太长了"})
	}
	run, err := s.repo.Get(ctx, userID, runID)
	if err != nil {
		return err
	}
	if run == nil {
		return emit("error", map[string]any{"code": "STORY.RUN_NOT_FOUND", "message": "这条故事线不存在"})
	}
	if err := s.ensureOpen(ctx, run.CharacterID); err != nil {
		return err
	}
	if run.Finished == 1 {
		return emit("error", map[string]any{"code": "STORY.FINISHED", "message": "故事已经结束了"})
	}
	turns, err := s.repo.CountUserMessages(ctx, runID)
	if err != nil {
		return emit("error", map[string]any{"code": "STORY.STATE", "message": "读取进度失败"})
	}
	maxTurns := s.maxTurns
	if cfg, cfgErr := s.repo.Config(ctx); cfgErr == nil && cfg.MaxTurns > 0 {
		maxTurns = cfg.MaxTurns
	}
	if turns >= maxTurns {
		return emit("error", map[string]any{"code": "STORY.TURN_LIMIT", "message": "这一夜说得够多了，先收个尾"})
	}

	if err := s.repo.AddMessage(ctx, runID, "user", text, false); err != nil {
		return emit("error", map[string]any{"code": "STORY.SAVE", "message": "消息没有存下来"})
	}

	// 安全优先：命中即用作者写的安全回复，不交给模型自由发挥。
	if safe, ok := safetyReply(text); ok {
		if err := s.repo.AddMessage(ctx, runID, "assistant", safe, true); err != nil {
			return err
		}
		if err := emit("text_delta", map[string]any{"delta": safe}); err != nil {
			return err
		}
		return emit("done", map[string]any{
			"text": safe, "safety": true, "run_id": runID,
		})
	}

	if s.llm == nil {
		return emit("error", map[string]any{
			"code":    "STORY.AI_NOT_CONFIGURED",
			"message": "AI 还没接上；你可以先用本地脚本继续试玩",
		})
	}

	history, err := s.repo.Messages(ctx, runID, 12)
	if err != nil {
		return err
	}
	msgs := make([]llm.MessageWithTools, 0, len(history)+2)
	msgs = append(msgs, llm.MessageWithTools{
		Role:    "system",
		Content: buildSystemPrompt(run, in.Scene),
	})
	for _, m := range history {
		if m.Role != "user" && m.Role != "assistant" {
			continue
		}
		msgs = append(msgs, llm.MessageWithTools{Role: m.Role, Content: m.Content})
	}
	// history 已含刚插入的 user 消息；不要重复 append。

	var b strings.Builder
	err = s.llm.ChatStream(ctx, llm.StreamRequest{
		Model:       s.model,
		Messages:    msgs,
		Temperature: 0.75,
	}, func(ev llm.StreamEvent) error {
		switch ev.Type {
		case "text_delta":
			if ev.TextDelta == "" {
				return nil
			}
			b.WriteString(ev.TextDelta)
			return emit("text_delta", map[string]any{"delta": ev.TextDelta})
		case "error":
			return emit("error", map[string]any{
				"code": "STORY.LLM", "message": ev.ErrorMsg,
			})
		default:
			return nil
		}
	})
	if err != nil {
		if b.Len() > 0 {
			_ = s.repo.AddMessage(ctx, runID, "assistant", b.String(), false)
		}
		return err
	}

	reply := strings.TrimSpace(b.String())
	if reply == "" {
		reply = "……（她没有说话，只是把杯子往你这边推了推。）"
	}
	if utf8.RuneCountInString(reply) > 600 {
		reply = string([]rune(reply)[:600])
	}
	if err := s.repo.AddMessage(ctx, runID, "assistant", reply, false); err != nil {
		return err
	}
	return emit("done", map[string]any{
		"text": reply, "safety": false, "run_id": runID,
	})
}

var (
	selfHarmRe = regexp.MustCompile(`自杀|不想活|想死|自残|活着没意思|结束自己`)
	minorRe    = regexp.MustCompile(`未成年|16\s*岁|17\s*岁|高中生|初中生`)
)

func safetyReply(text string) (string, bool) {
	if selfHarmRe.MatchString(text) {
		return "先别一个人扛着。把手机放下，去敲隔壁的门，或者打给一个你信得过的人。" +
			"如果你现在有伤害自己的念头，请联系当地心理援助热线或 120。" +
			"故事可以停在这里，真的。", true
	}
	if minorRe.MatchString(text) {
		return "这个故事是成年人向的。如果你还未满 18 岁，先退出；等你长大一点，我们再见。", true
	}
	return "", false
}

var characterBible = map[string]string{
	"linxia": "林夏，27 岁，杭州摄影师，来临海拍要拆的街区。温柔但直球，句子短，" +
		"会记得对方提过的小事。她下个月去厦门；她在大堂见过你，还拍过你一张照片，" +
		"但她不会主动把这两件事都说完。",
	"suyu": "苏予，29 岁，上海品牌策划，来临海做快闪。清醒、有点毒舌，但心是软的；" +
		"不喜欢被查户口、不喜欢对方急着拉近关系。她刚辞掉一份很好的工作，没告诉家里；" +
		"她不会用这件事换同情。",
	"chenye": "陈野，28 岁，北京纪录片编导，在临海拍「离开的人」。话少，观察细，" +
		"习惯用画面说话。他的片子拍不下去，因为他自己也不会告别；" +
		"他不会主动解释，只会把镜头放下。",
}

func buildSystemPrompt(run *Run, scene SceneContext) string {
	name := map[string]string{"linxia": "林夏", "suyu": "苏予", "chenye": "陈野"}[run.CharacterID]
	bible := characterBible[run.CharacterID]
	place := clip(scene.Place, 80)
	sceneName := clip(scene.Scene, 80)
	note := clip(scene.BeatNote, 160)
	opening := ""
	for i, line := range scene.Opening {
		if i >= 3 {
			break
		}
		opening += "  " + clip(line, 120) + "\n"
	}
	flags := "无"
	var fs []string
	_ = json.Unmarshal([]byte(run.FlagsJSON), &fs)
	if len(fs) > 0 {
		flags = strings.Join(fs, "、")
	}

	return fmt.Sprintf(`【世界】临海市，十一月，连续下雨。你只能通过手机联系对方。
【你是谁】%s
【这一夜】第 %d 夜，第 %d 个节拍。地点：%s。场景：%s。
【刚才】%s
【这一拍的开场】%s
【进度】心级 %d/5；关键选择：%s。
【你不能做】不推进剧情、不替对方做选择、不剧透后面的夜晚、不解释结局。
【说话】像微信聊天：短句，1–3 句；可以停顿、反问、开玩笑；不要客服腔、不要列清单、不要总结。
【硬边界】所有角色都是成年人；不生成色情/性暗示；不索要转账、账号、住址、验证码；
不引导现实见面；不冒充真人；被问身份时承认「我是 AI，在这个故事里演%s」。
对方情绪低落时先接住情绪，不做心理诊断；遇到未成年人或自伤内容，立刻停止故事并建议求助。
输出语言：简体中文。只输出角色的话；动作放在（）里，最多一处。`,
		bible, run.Night, scene.Beat+1, place, sceneName, note, opening,
		run.Hearts, flags, name)
}

func clip(s string, n int) string {
	s = strings.TrimSpace(s)
	if s == "" {
		return "（没写）"
	}
	if utf8.RuneCountInString(s) <= n {
		return s
	}
	return string([]rune(s)[:n]) + "…"
}

// NewRunID 给客户端 / 测试生成一个合法 run id。
func NewRunID() string { return uuid.NewString() }
