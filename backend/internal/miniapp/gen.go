package miniapp

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/jmoiron/sqlx"

	"github.com/sencloud/finme-backend/internal/billing"
	"github.com/sencloud/finme-backend/internal/llm"
)

// LLM 是生成用的模型接口（生产是 DeepSeek JSON 模式，测试用假的）。
type LLM interface {
	Complete(ctx context.Context, model string, msgs []llm.Message) (string, llm.Usage, error)
}

// DeepSeekLLM 把 llm.DeepSeek 适配成 LLM（JSON 模式、低温度）。
type DeepSeekLLM struct {
	C         *llm.DeepSeek
	MaxTokens int
}

// Complete 实现 LLM。
func (d *DeepSeekLLM) Complete(ctx context.Context, model string, msgs []llm.Message) (string, llm.Usage, error) {
	mt := d.MaxTokens
	if mt <= 0 {
		mt = 8000
	}
	r, err := d.C.ChatWith(ctx, model, msgs, llm.ChatOptions{JSON: true, Temperature: 0.3, MaxTokens: mt})
	if r == nil {
		return "", llm.Usage{}, err
	}
	return r.Content, r.Usage, err
}

// 生成状态。
const (
	GenPending = "pending"
	GenDone    = "done"
	GenFailed  = "failed"

	OutcomeAsk    = "ask"
	OutcomeSpec   = "spec"
	OutcomeRefuse = "refuse"
	OutcomeFail   = "fail"

	GenRefType = "miniapp_gen"
)

// GenRequest 是一次生成请求。
type GenRequest struct {
	RequestID string `json:"request_id"`
	Topic     string `json:"topic"`
	Message   string `json:"message"`
	// AppUUID 非空表示修改已有小应用（2 喜点），否则新建（5 喜点）。
	AppUUID string `json:"app_uuid"`
	// SessionID 继续同一个工坊对话（回答澄清问题时带上）；空则新开。
	SessionID string `json:"session_id"`
}

// Question 是澄清问题。
type Question struct {
	Q       string   `json:"q"`
	Options []string `json:"options"`
}

// GenResult 是生成成功 / 澄清 / 拒绝时的结果。
type GenResult struct {
	Message   string     `json:"message,omitempty"`
	Questions []Question `json:"questions,omitempty"`
	AppUUID   string     `json:"app_uuid,omitempty"`
	Version   int        `json:"version,omitempty"`
	Summary   string     `json:"summary,omitempty"`
	Warnings  []string   `json:"warnings,omitempty"`
}

// GenView 是生成记录的接口形态。
type GenView struct {
	RequestID string     `json:"request_id"`
	SessionID string     `json:"session_id"`
	Topic     string     `json:"topic"`
	Kind      string     `json:"kind"`
	Status    string     `json:"status"`
	Stage     string     `json:"stage"`
	Outcome   string     `json:"outcome,omitempty"`
	Message   string     `json:"message"`
	Result    *GenResult `json:"result,omitempty"`
	Error     string     `json:"error,omitempty"`
	Credits   int64      `json:"credits"`
	Refunded  bool       `json:"refunded"`
	Replayed  bool       `json:"replayed,omitempty"`
	CreatedAt int64      `json:"created_at"`
	UpdatedAt int64      `json:"updated_at"`
}

func (r *genRow) view() *GenView {
	v := &GenView{RequestID: r.RequestID, SessionID: r.SessionID, Topic: r.Topic, Kind: r.Kind, Status: r.Status,
		Stage: r.Stage, Outcome: r.Outcome, Message: r.Message, Error: r.Error.String, Credits: r.Credits,
		Refunded: r.Refunded, CreatedAt: r.CreatedAt, UpdatedAt: r.UpdatedAt}
	if r.ResultJSON.Valid {
		var res GenResult
		if json.Unmarshal([]byte(r.ResultJSON.String), &res) == nil {
			v.Result = &res
		}
	}
	return v
}

func genRefID(uid int64, req string) string { return fmt.Sprintf("%d:%s", uid, req) }

func reasons(topic, kind string) (charge, refund string) {
	if topic == "fishing" {
		if kind == "iterate" {
			return billing.ReasonFishingMiniAppIterate, billing.ReasonFishingMiniAppRefund
		}
		return billing.ReasonFishingMiniAppCreate, billing.ReasonFishingMiniAppRefund
	}
	if kind == "iterate" {
		return billing.ReasonMiniAppIterate, billing.ReasonMiniAppRefund
	}
	return billing.ReasonMiniAppCreate, billing.ReasonMiniAppRefund
}

func (s *Service) findGen(ctx context.Context, uid int64, req string) (*genRow, error) {
	var r genRow
	err := s.st.DB.GetContext(ctx, &r, "SELECT * FROM mini_app_gens WHERE user_id=? AND request_id=?", uid, req)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &r, nil
}

// Gen 查询一次生成（轮询用）。
func (s *Service) Gen(ctx context.Context, uid int64, req string) (*GenView, error) {
	r, err := s.findGen(ctx, uid, req)
	if err != nil {
		return nil, err
	}
	if r == nil {
		return nil, ErrNotFound
	}
	return r.view(), nil
}

// Session 返回一个工坊对话的全部轮次（旧→新）。
func (s *Service) Session(ctx context.Context, uid int64, session string) ([]*GenView, error) {
	rows := []genRow{}
	if err := s.st.DB.SelectContext(ctx, &rows,
		"SELECT * FROM mini_app_gens WHERE user_id=? AND session_id=? ORDER BY id", uid, session); err != nil {
		return nil, err
	}
	out := make([]*GenView, 0, len(rows))
	for i := range rows {
		out = append(out, rows[i].view())
	}
	return out, nil
}

// Generate 扣费并登记一次生成，随后异步调用模型；返回 pending 记录，客户端轮询 Gen。
// 同一个 request_id 重放返回原记录，不重复扣费。
func (s *Service) Generate(ctx context.Context, uid int64, in GenRequest) (*GenView, error) {
	if !idRe.MatchString(in.RequestID) {
		return nil, ErrBadRequestID
	}
	if existing, err := s.findGen(ctx, uid, in.RequestID); err != nil {
		return nil, err
	} else if existing != nil {
		v := existing.view()
		v.Replayed = true
		return v, nil
	}
	if !ValidTopic(in.Topic) {
		return nil, ErrBadTopic
	}
	in.Message = strings.TrimSpace(in.Message)
	if in.Message == "" || utf8.RuneCountInString(in.Message) > MaxMessageRunes {
		return nil, ErrBadMessage
	}
	if in.SessionID != "" && !idRe.MatchString(in.SessionID) {
		return nil, ErrBadInput
	}
	if s.llm == nil {
		return nil, ErrUnavailable
	}
	if err := s.checkGenQuota(ctx, uid); err != nil {
		return nil, err
	}

	kind, price := "create", s.opts.Prices.Create
	var app *appRow
	if in.AppUUID != "" {
		a, err := s.appByUUID(ctx, uid, in.AppUUID)
		if err != nil {
			return nil, err
		}
		if a.Topic != in.Topic {
			return nil, ErrBadTopic
		}
		app, kind, price = a, "iterate", s.opts.Prices.Iterate
		if in.SessionID == "" {
			in.SessionID = a.SessionID
		}
	} else {
		n, err := s.countApps(ctx, s.st.DB, uid, in.Topic)
		if err != nil {
			return nil, err
		}
		if n >= MaxAppsPerTopic {
			return nil, ErrAppLimit
		}
	}
	if in.SessionID == "" {
		in.SessionID = strings.ReplaceAll(uuid.NewString(), "-", "")
	}
	var busy int
	if err := s.st.DB.GetContext(ctx, &busy, "SELECT COUNT(*) FROM mini_app_gens WHERE user_id=? AND session_id=? AND status=?",
		uid, in.SessionID, GenPending); err != nil {
		return nil, err
	}
	if busy > 0 {
		return nil, ErrGenBusy
	}

	now := s.opts.Now().UnixMilli()
	row := genRow{RequestID: in.RequestID, UserID: uid, Topic: in.Topic, SessionID: in.SessionID, Kind: kind,
		Status: GenPending, Stage: "thinking", Message: in.Message, Credits: price, CreatedAt: now, UpdatedAt: now}
	if app != nil {
		row.AppID = sql.NullInt64{Int64: app.ID, Valid: true}
	}
	charge, _ := reasons(in.Topic, kind)
	remark := "新建小应用"
	if kind == "iterate" {
		remark = "修改小应用：" + app.Title
	}
	err := s.st.Tx(ctx, func(tx *sqlx.Tx) error {
		if _, err := billing.ApplyTx(ctx, tx, billing.ApplyParams{UserID: uid, Delta: -price, Reason: charge,
			RefType: GenRefType, RefID: genRefID(uid, in.RequestID), Remark: remark}); err != nil {
			return err
		}
		res, err := tx.ExecContext(ctx, `INSERT INTO mini_app_gens(request_id, user_id, topic, session_id, app_id, kind, status,
			stage, message, credits, created_at, updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)`,
			row.RequestID, uid, row.Topic, row.SessionID, row.AppID, row.Kind, row.Status, row.Stage, row.Message,
			row.Credits, now, now)
		if err != nil {
			return err
		}
		row.ID, _ = res.LastInsertId()
		return nil
	})
	if errors.Is(err, billing.ErrLedgerDuplicate) || isUnique(err) {
		// 并发重放：另一个请求已登记。
		if r, _ := s.findGen(ctx, uid, in.RequestID); r != nil {
			v := r.view()
			v.Replayed = true
			return v, nil
		}
		return nil, ErrGenBusy
	}
	if err != nil {
		return nil, err
	}

	run := func() {
		gctx, cancel := context.WithTimeout(context.Background(), s.opts.GenTimeout)
		defer cancel()
		s.pipeline(gctx, &row, app)
	}
	if s.opts.Sync {
		run()
		r, err := s.findGen(ctx, uid, in.RequestID)
		if err != nil {
			return nil, err
		}
		return r.view(), nil
	}
	go run()
	return row.view(), nil
}

func isUnique(err error) bool {
	return err != nil && strings.Contains(err.Error(), "UNIQUE constraint failed")
}

func (s *Service) checkGenQuota(ctx context.Context, uid int64) error {
	now := s.opts.Now()
	var minute, day int
	if err := s.st.DB.GetContext(ctx, &minute, "SELECT COUNT(*) FROM mini_app_gens WHERE user_id=? AND created_at>=?",
		uid, now.Add(-time.Minute).UnixMilli()); err != nil {
		return err
	}
	if minute >= s.opts.GensPerMinute {
		return ErrTooFast
	}
	if err := s.st.DB.GetContext(ctx, &day, "SELECT COUNT(*) FROM mini_app_gens WHERE user_id=? AND created_at>=?",
		uid, now.Add(-24*time.Hour).UnixMilli()); err != nil {
		return err
	}
	if day >= s.opts.GensPerDay {
		return ErrDailyLimit
	}
	return nil
}

func (s *Service) setStage(row *genRow, stage string) {
	row.Stage = stage
	_, _ = s.st.DB.Exec("UPDATE mini_app_gens SET stage=?, updated_at=? WHERE id=?", stage, s.opts.Now().UnixMilli(), row.ID)
}

// envelope 是模型输出。
type envelope struct {
	Action    string          `json:"action"`
	Message   string          `json:"message"`
	Summary   string          `json:"summary"`
	Questions []Question      `json:"questions"`
	Spec      json.RawMessage `json:"spec"`
}

func parseEnvelope(s string) (*envelope, error) {
	s = strings.TrimSpace(s)
	s = strings.TrimPrefix(s, "```json")
	s = strings.TrimPrefix(s, "```")
	s = strings.TrimSuffix(s, "```")
	if i := strings.IndexByte(s, '{'); i > 0 {
		s = s[i:]
	}
	var e envelope
	if err := json.Unmarshal([]byte(strings.TrimSpace(s)), &e); err != nil {
		return nil, fmt.Errorf("不是合法的 JSON：%v", err)
	}
	switch e.Action {
	case "ask", "refuse":
		if strings.TrimSpace(e.Message) == "" && len(e.Questions) == 0 {
			return nil, errors.New("message 不能为空")
		}
	case "spec":
		if len(e.Spec) == 0 || string(e.Spec) == "null" {
			return nil, errors.New("action=spec 时必须给出 spec 对象")
		}
	default:
		return nil, fmt.Errorf("action 只能是 ask / spec / refuse，收到 %q", e.Action)
	}
	return &e, nil
}

func cleanQuestions(qs []Question) []Question {
	var out []Question
	for _, q := range qs {
		q.Q = shorten(strings.TrimSpace(q.Q), 60)
		if q.Q == "" {
			continue
		}
		var opts []string
		for _, o := range q.Options {
			if o = shorten(strings.TrimSpace(o), 30); o != "" && len(opts) < 4 {
				opts = append(opts, o)
			}
		}
		q.Options = opts
		out = append(out, q)
		if len(out) == 3 {
			break
		}
	}
	return out
}

// history 把同一会话之前的轮次还原成对话消息（最多 6 轮）。
func (s *Service) history(ctx context.Context, row *genRow) []llm.Message {
	rows := []genRow{}
	_ = s.st.DB.SelectContext(ctx, &rows, `SELECT * FROM mini_app_gens WHERE user_id=? AND session_id=? AND id<? AND status!=?
		ORDER BY id DESC LIMIT 6`, row.UserID, row.SessionID, row.ID, GenPending)
	var out []llm.Message
	for i := len(rows) - 1; i >= 0; i-- {
		r := rows[i]
		out = append(out, llm.Message{Role: "user", Content: r.Message})
		v := r.view()
		if v.Result == nil {
			continue
		}
		var a string
		switch r.Outcome {
		case OutcomeAsk:
			b, _ := json.Marshal(map[string]any{"action": "ask", "message": v.Result.Message, "questions": v.Result.Questions})
			a = string(b)
		case OutcomeRefuse:
			b, _ := json.Marshal(map[string]any{"action": "refuse", "message": v.Result.Message})
			a = string(b)
		case OutcomeSpec:
			a = fmt.Sprintf(`{"action":"spec","summary":%q,"spec":"（已生成第 %d 版，见下方当前 spec）"}`, v.Result.Summary, v.Result.Version)
		default:
			continue
		}
		out = append(out, llm.Message{Role: "assistant", Content: a})
	}
	return out
}

func (s *Service) currentSpec(ctx context.Context, appID int64) string {
	var spec string
	_ = s.st.DB.GetContext(ctx, &spec, `SELECT v.spec_json FROM mini_apps a JOIN mini_app_versions v
		ON v.app_id=a.id AND v.version=a.current_version WHERE a.id=?`, appID)
	return spec
}

func (s *Service) exampleFor(topic string) *Template {
	for _, t := range s.templates {
		if t.Topic == topic {
			return t
		}
	}
	return nil
}

// pipeline：模型 → 解析 → 校验 → 试运行 → 修复（≤MaxRepairs 轮）→ 落库 / 退款。
func (s *Service) pipeline(ctx context.Context, row *genRow, app *appRow) {
	start := s.opts.Now()
	model := s.opts.CreateModel
	if row.Kind == "iterate" {
		model = s.opts.IterateModel
	}
	row.Model = model
	defer func() {
		if p := recover(); p != nil {
			s.log.Error().Interface("panic", p).Str("req", row.RequestID).Msg("miniapp gen panic")
			s.finishFail(row, "生成出错了，喜点已退回", fmt.Sprint(p), start)
		}
	}()

	msgs := []llm.Message{{Role: "system", Content: SystemPrompt(row.Topic, s.reg, s.exampleFor(row.Topic))}}
	msgs = append(msgs, s.history(ctx, row)...)
	if row.AppID.Valid {
		if cur := s.currentSpec(ctx, row.AppID.Int64); cur != "" {
			msgs = append(msgs, llm.Message{Role: "user", Content: "当前小应用的 spec（请在此基础上修改，输出完整 spec）：\n" + cur})
		}
	}
	msgs = append(msgs, llm.Message{Role: "user", Content: row.Message})

	var lastIssues string
	for round := 0; round <= s.opts.MaxRepairs; round++ {
		row.RepairRounds = round
		if round > 0 {
			s.setStage(row, "repairing")
		}
		out, usage, err := s.llm.Complete(ctx, model, msgs)
		row.PromptTokens += usage.PromptTokens
		row.CompletionTokens += usage.CompletionTokens
		if err != nil && !errors.Is(err, llm.ErrTruncated) {
			s.log.Warn().Err(err).Str("req", row.RequestID).Msg("miniapp gen: llm failed")
			s.finishFail(row, "生成服务暂时不可用，喜点已退回", shorten(err.Error(), 200), start)
			return
		}
		msgs = append(msgs, llm.Message{Role: "assistant", Content: out})
		env, perr := parseEnvelope(out)
		if errors.Is(err, llm.ErrTruncated) && perr != nil {
			perr = errors.New("输出太长被截断了，请精简 spec（减少组件和绑定）后重新输出完整 JSON")
		}
		if perr != nil {
			lastIssues = perr.Error()
			msgs = append(msgs, llm.Message{Role: "user", Content: "上一次输出有问题：" + lastIssues + "\n请只输出一个合法的 JSON 对象。"})
			continue
		}
		switch env.Action {
		case "ask":
			s.finishRefunded(row, OutcomeAsk, &GenResult{Message: shorten(env.Message, 200), Questions: cleanQuestions(env.Questions)}, start)
			return
		case "refuse":
			s.finishRefunded(row, OutcomeRefuse, &GenResult{Message: shorten(env.Message, 300)}, start)
			return
		}
		s.setStage(row, "validating")
		c, issues := ValidateJSON(env.Spec, row.Topic, s.reg)
		if len(issues) > 0 {
			lastIssues = issueText(issues)
			msgs = append(msgs, llm.Message{Role: "user", Content: "spec 没通过校验，请修正下面的问题后输出完整 JSON：\n" + lastIssues})
			continue
		}
		s.setStage(row, "dry_run")
		rep := s.runner.DryRun(ctx, c, row.UserID, fmt.Sprintf("u:%d", row.UserID))
		if rep.Run != nil {
			s.recordRun(ctx, nil, "", &row.UserID, 0, "dryrun", rep.Run, s.opts.Now())
		}
		if len(rep.Problem) > 0 && round < s.opts.MaxRepairs {
			shapes, _ := json.Marshal(rep.Shapes)
			lastIssues = strings.Join(rep.Problem, "\n")
			msgs = append(msgs, llm.Message{Role: "user", Content: "spec 校验通过了，但试运行有问题：\n" + lastIssues +
				"\n各数据绑定实际返回的数据结构（只有字段和类型）：\n" + shorten(string(shapes), 3000) +
				"\n请据此修正字段名 / 参数后输出完整 JSON。"})
			continue
		}
		summary := shorten(strings.TrimSpace(env.Summary), 60)
		if summary == "" {
			summary = c.Summary
		}
		if err := s.finishSpec(ctx, row, app, c, summary, rep.Problem, start); err != nil {
			msg := "保存失败，喜点已退回"
			if errors.Is(err, ErrAppLimit) {
				msg = fmt.Sprintf("这个主题最多 %d 个小应用，先删掉不用的再来，喜点已退回", MaxAppsPerTopic)
			}
			s.finishFail(row, msg, err.Error(), start)
		}
		return
	}
	s.finishFail(row, "这次没能做出来，喜点已退回。换个说法，或者把需求拆小一点再试试", shorten(lastIssues, 500), start)
}

func issueText(issues []Issue) string {
	var b strings.Builder
	for i, is := range issues {
		if i == 12 {
			fmt.Fprintf(&b, "……还有 %d 个问题\n", len(issues)-12)
			break
		}
		b.WriteString("- " + is.String() + "\n")
	}
	return b.String()
}

func (s *Service) finishSpec(ctx context.Context, row *genRow, app *appRow, c *Compiled, summary string, warnings []string, start time.Time) error {
	ctx = context.WithoutCancel(ctx)
	now := s.opts.Now().UnixMilli()
	res := &GenResult{Summary: summary, Warnings: warnings}
	err := s.st.Tx(ctx, func(tx *sqlx.Tx) error {
		a := app
		if a == nil {
			// 同一会话里第一次成功生成之后，后续轮次视为修改同一个小应用。
			var existing appRow
			err := tx.GetContext(ctx, &existing, `SELECT * FROM mini_apps WHERE user_id=? AND session_id=? AND deleted_at IS NULL
				ORDER BY id DESC LIMIT 1`, row.UserID, row.SessionID)
			if err == nil {
				a = &existing
			} else if !errors.Is(err, sql.ErrNoRows) {
				return err
			}
		}
		if a == nil {
			n, err := s.countApps(ctx, tx, row.UserID, row.Topic)
			if err != nil {
				return err
			}
			if n >= MaxAppsPerTopic {
				return ErrAppLimit
			}
			if a, err = createAppTx(ctx, tx, row.UserID, row.Topic, row.SessionID, "", now); err != nil {
				return err
			}
		}
		v, _, err := insertVersionTx(ctx, tx, a, c, summary, "llm", row.RequestID, now)
		if err != nil {
			return err
		}
		res.AppUUID, res.Version = a.UUID, v
		b, _ := json.Marshal(res)
		row.Status, row.Outcome, row.Stage = GenDone, OutcomeSpec, ""
		row.ResultJSON = sql.NullString{String: string(b), Valid: true}
		row.AppID = sql.NullInt64{Int64: a.ID, Valid: true}
		return s.saveGenTx(ctx, tx, row, start)
	})
	if err == nil {
		s.log.Info().Str("req", row.RequestID).Str("topic", row.Topic).Str("kind", row.Kind).Int("repairs", row.RepairRounds).
			Int64("in_tok", row.PromptTokens).Int64("out_tok", row.CompletionTokens).Msg("miniapp gen done")
	}
	return err
}

func (s *Service) saveGenTx(ctx context.Context, tx *sqlx.Tx, row *genRow, start time.Time) error {
	row.UpdatedAt = s.opts.Now().UnixMilli()
	row.LatencyMs = s.opts.Now().Sub(start).Milliseconds()
	_, err := tx.ExecContext(ctx, `UPDATE mini_app_gens SET status=?, stage=?, outcome=?, result_json=?, error=?, refunded=?,
		app_id=?, model=?, prompt_tokens=?, completion_tokens=?, repair_rounds=?, latency_ms=?, updated_at=? WHERE id=?`,
		row.Status, row.Stage, row.Outcome, row.ResultJSON, row.Error, row.Refunded, row.AppID, row.Model,
		row.PromptTokens, row.CompletionTokens, row.RepairRounds, row.LatencyMs, row.UpdatedAt, row.ID)
	return err
}

// refundTx 全额退回（幂等）。
func refundTx(ctx context.Context, tx *sqlx.Tx, row *genRow) error {
	_, refund := reasons(row.Topic, row.Kind)
	_, err := billing.ApplyTx(ctx, tx, billing.ApplyParams{UserID: row.UserID, Delta: row.Credits, Reason: refund,
		RefType: GenRefType, RefID: genRefID(row.UserID, row.RequestID), Remark: "小应用未生成，喜点退回", AllowNegative: true})
	if err != nil && !errors.Is(err, billing.ErrLedgerDuplicate) {
		return err
	}
	row.Refunded = true
	return nil
}

func (s *Service) finishRefunded(row *genRow, outcome string, res *GenResult, start time.Time) {
	ctx := context.Background()
	b, _ := json.Marshal(res)
	row.Status, row.Outcome, row.Stage = GenDone, outcome, ""
	row.ResultJSON = sql.NullString{String: string(b), Valid: true}
	err := s.st.Tx(ctx, func(tx *sqlx.Tx) error {
		if err := refundTx(ctx, tx, row); err != nil {
			return err
		}
		return s.saveGenTx(ctx, tx, row, start)
	})
	if err != nil {
		s.log.Error().Err(err).Str("req", row.RequestID).Msg("miniapp gen: finish failed")
	}
}

func (s *Service) finishFail(row *genRow, msg, detail string, start time.Time) {
	ctx := context.Background()
	row.Status, row.Outcome, row.Stage = GenFailed, OutcomeFail, ""
	row.Error = sql.NullString{String: msg, Valid: true}
	err := s.st.Tx(ctx, func(tx *sqlx.Tx) error {
		if err := refundTx(ctx, tx, row); err != nil {
			return err
		}
		return s.saveGenTx(ctx, tx, row, start)
	})
	if err != nil {
		s.log.Error().Err(err).Str("req", row.RequestID).Msg("miniapp gen: refund failed")
	}
	s.log.Warn().Str("req", row.RequestID).Str("detail", detail).Int("repairs", row.RepairRounds).Msg("miniapp gen failed")
}

// RecoverStale 把卡在 pending 超过 maxAge 的生成（进程重启）标失败并退款。
func (s *Service) RecoverStale(ctx context.Context, maxAge time.Duration) (int, error) {
	cut := s.opts.Now().Add(-maxAge).UnixMilli()
	rows := []genRow{}
	if err := s.st.DB.SelectContext(ctx, &rows,
		"SELECT * FROM mini_app_gens WHERE status=? AND updated_at<?", GenPending, cut); err != nil {
		return 0, err
	}
	for i := range rows {
		s.finishFail(&rows[i], "生成超时，喜点已退回", "stale", time.UnixMilli(rows[i].CreatedAt))
	}
	return len(rows), nil
}
