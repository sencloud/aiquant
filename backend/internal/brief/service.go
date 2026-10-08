package brief

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/rs/zerolog"

	"github.com/sencloud/finme-backend/internal/ai/realtime"
	"github.com/sencloud/finme-backend/internal/llm"
	"github.com/sencloud/finme-backend/internal/store"
)

// indexCodes 生成提问时参考的宽基指数（与客户端本地兜底保持同一组）。
var indexCodes = []string{"000001.SH", "399001.SZ", "399006.SZ", "000300.SH", "000688.SH"}

// Suggestion 是首页一次可用的快捷提问集合。
type Suggestion struct {
	Phase      string   `json:"phase"`
	PhaseLabel string   `json:"phase_label"`
	TradeDate  string   `json:"trade_date"`
	Questions  []string `json:"questions"`
	UpdatedAt  int64    `json:"updated_at"`
	Source     string   `json:"source"` // llm / template
	// Stale 表示这条不是今天生成的（隔夜 / 周末 / 今天还没到第一个时段），
	// 客户端据此决定是否改用本地按当前行情拼装的提问。
	Stale bool `json:"stale"`
}

// Snapshot 是生成时点参考的行情，随提问一起落库，便于排查「提问和当时行情对不上」。
type Snapshot struct {
	Code   string  `json:"code"`
	Name   string  `json:"name"`
	Open   float64 `json:"open"`
	Last   float64 `json:"last"`
	High   float64 `json:"high"`
	Low    float64 `json:"low"`
	PctChg float64 `json:"pct_chg"`
}

// Service 负责「取行情 → 让模型写提问 → 落库 / 读取」。
// llm 为 nil 时退化为模板生成，接口依然可用。
type Service struct {
	st     *store.Store
	llm    *llm.DeepSeek
	rt     *realtime.Client
	model  string
	logger *zerolog.Logger
}

func NewService(st *store.Store, l *zerolog.Logger, llmClient *llm.DeepSeek, rt *realtime.Client, model string) *Service {
	return &Service{st: st, llm: llmClient, rt: rt, model: model, logger: l}
}

// EnsureSlot 生成并落库「当前时段」的提问；已存在则直接跳过（幂等）。
// 返回是否真的新生成了一条。
func (s *Service) EnsureSlot(ctx context.Context, now time.Time) (bool, error) {
	bj := now.In(ShanghaiLoc)
	key := SlotKey(bj)
	var exists int
	if err := s.st.DB.GetContext(ctx, &exists,
		`SELECT COUNT(*) FROM ai_home_suggestions WHERE slot_key=?`, key); err != nil {
		return false, fmt.Errorf("check slot: %w", err)
	}
	if exists > 0 {
		return false, nil
	}

	phase := PhaseAt(bj)
	snaps := s.fetchSnapshot(ctx)
	questions, source := s.generate(ctx, phase, snaps)
	if len(questions) == 0 {
		return false, errors.New("empty questions")
	}

	qJSON, err := json.Marshal(questions)
	if err != nil {
		return false, err
	}
	snapJSON, _ := json.Marshal(snaps)
	if _, err := s.st.DB.ExecContext(ctx, `
		INSERT INTO ai_home_suggestions(
			slot_key, trade_date, phase, questions_json, snapshot_json, source, created_at)
		VALUES(?, ?, ?, ?, ?, ?, ?)`,
		key, bj.Format("2006-01-02"), string(phase),
		string(qJSON), string(snapJSON), source, time.Now().UnixMilli()); err != nil {
		return false, fmt.Errorf("insert suggestion: %w", err)
	}
	s.logger.Info().
		Str("slot", key).Str("source", source).Int("n", len(questions)).
		Msg("brief: home suggestions generated")
	return true, nil
}

// Latest 取最近生成的一条；表为空时返回 nil。
func (s *Service) Latest(ctx context.Context) (*Suggestion, error) {
	var row struct {
		Phase         string `db:"phase"`
		TradeDate     string `db:"trade_date"`
		QuestionsJSON string `db:"questions_json"`
		Source        string `db:"source"`
		CreatedAt     int64  `db:"created_at"`
	}
	err := s.st.DB.GetContext(ctx, &row, `
		SELECT phase, trade_date, questions_json, source, created_at
		FROM ai_home_suggestions ORDER BY created_at DESC, id DESC LIMIT 1`)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var questions []string
	if err := json.Unmarshal([]byte(row.QuestionsJSON), &questions); err != nil {
		return nil, fmt.Errorf("decode questions: %w", err)
	}
	phase := Phase(row.Phase)
	return &Suggestion{
		Phase:      row.Phase,
		PhaseLabel: phase.Label(),
		TradeDate:  row.TradeDate,
		Questions:  questions,
		UpdatedAt:  row.CreatedAt,
		Source:     row.Source,
		Stale:      row.TradeDate != time.Now().In(ShanghaiLoc).Format("2006-01-02"),
	}, nil
}

// ── 生成 ────────────────────────────────────────────────────────────────

func (s *Service) generate(ctx context.Context, phase Phase, snaps []Snapshot) ([]string, string) {
	if s.llm != nil && len(snaps) > 0 {
		qs, err := s.generateLLM(ctx, phase, snaps)
		if err == nil && len(qs) > 0 {
			return qs, "llm"
		}
		s.logger.Warn().Err(err).Msg("brief: llm generation failed, fallback to template")
	}
	return templateQuestions(phase, snaps), "template"
}

const suggestSystemPrompt = `你是中国 A 股投研 App 的运营编辑。用户打开 App 首页时会看到「今天想聊点什么？」
以及 3 条快捷提问，点一下就把这句话发给 AI 投研助理。

你要根据给定的「当前时段 + 宽基指数行情」写出这 3 条提问：
1. 必须结合当日/当下的真实点位与涨跌幅（数据已给出，不要自己编造数字）；
2. 每条是一句口语化的中文提问，像投资者随口问的，不超过 32 个字；
3. 三条角度各不相同（例如：大盘复盘 / 领涨领跌结构 / 明日或后市应对）；
4. 每条都以问号「？」结尾；提到点位写成「3811.90 点」这种形式；
5. 不要编号、不要解释、不要 Emoji、不要出现「作为 AI」之类的措辞。

只输出一个 JSON 字符串数组，形如 ["...","...","..."]，不要任何其他文字。`

func (s *Service) generateLLM(ctx context.Context, phase Phase, snaps []Snapshot) ([]string, error) {
	res, err := s.llm.ChatOnce(ctx, s.model, []llm.Message{
		{Role: "system", Content: suggestSystemPrompt},
		{Role: "user", Content: buildPrompt(phase, snaps)},
	})
	if err != nil {
		return nil, err
	}
	qs := parseQuestions(res.Content)
	if len(qs) == 0 {
		return nil, fmt.Errorf("unparsable model output: %s", truncateRunes(res.Content, 120))
	}
	if len(qs) > 3 {
		qs = qs[:3]
	}
	return qs, nil
}

func buildPrompt(phase Phase, snaps []Snapshot) string {
	var b strings.Builder
	now := time.Now().In(ShanghaiLoc)
	b.WriteString(fmt.Sprintf("当前时间：%s（北京时间）\n", now.Format("2006-01-02 15:04")))
	b.WriteString(fmt.Sprintf("当前时段：%s\n", phase.Label()))
	b.WriteString("宽基指数快照（开盘点位 / 最新价 / 当日涨跌幅）：\n")
	for _, s := range snaps {
		b.WriteString(fmt.Sprintf("- %s：开 %.2f，现 %.2f（%+.2f%%）\n",
			s.Name, s.Open, s.Last, s.PctChg))
	}
	b.WriteString("\n请按系统要求输出 3 条提问的 JSON 数组。")
	return b.String()
}

// parseQuestions 从模型输出里抠出字符串数组；容忍 ```json 包裹与前后废话。
func parseQuestions(out string) []string {
	text := strings.TrimSpace(out)
	if text == "" {
		return nil
	}
	start := strings.IndexByte(text, '[')
	end := strings.LastIndexByte(text, ']')
	if start >= 0 && end > start {
		var arr []string
		if err := json.Unmarshal([]byte(text[start:end+1]), &arr); err == nil {
			return cleanQuestions(arr)
		}
	}
	// 兜底：模型偶尔会输出编号列表（1. xxx / - xxx）。
	var lines []string
	for _, line := range strings.Split(text, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		line = strings.TrimLeft(line, "-*0123456789.、) ")
		lines = append(lines, line)
	}
	return cleanQuestions(lines)
}

func cleanQuestions(in []string) []string {
	out := make([]string, 0, len(in))
	for _, q := range in {
		q = strings.TrimSpace(strings.Trim(q, `"'`))
		if q == "" {
			continue
		}
		out = append(out, q)
	}
	return out
}

// templateQuestions 是模型不可用时的兜底：直接用行情数字拼，保证接口始终有内容。
func templateQuestions(phase Phase, snaps []Snapshot) []string {
	if len(snaps) == 0 {
		return []string{
			"帮我梳理今天 A 股的盘面情况",
			"今天有哪些板块值得关注？",
			"结合当前行情，帮我理一下接下来的操作思路",
		}
	}
	sh := snaps[0]
	for _, s := range snaps {
		if strings.Contains(s.Name, "上证") {
			sh = s
			break
		}
	}
	lead, lag := snaps[0], snaps[0]
	for _, s := range snaps {
		if s.PctChg > lead.PctChg {
			lead = s
		}
		if s.PctChg < lag.PctChg {
			lag = s
		}
	}
	breadth := fmt.Sprintf("%s最强（%+.2f%%）、%s最弱（%+.2f%%）",
		lead.Name, lead.PctChg, lag.Name, lag.PctChg)
	switch phase {
	case PhasePreOpen:
		return []string{
			fmt.Sprintf("昨天%s收于 %.2f 点（%+.2f%%），今天开盘前要注意什么？", sh.Name, sh.Last, sh.PctChg),
			fmt.Sprintf("昨日主要指数里%s，今天开盘这些方向怎么跟？", breadth),
			"帮我梳理今天开盘前的关注要点和风险",
		}
	case PhaseMorning:
		return []string{
			fmt.Sprintf("今天早盘%s现报 %.2f 点（%+.2f%%），现在市场情绪怎么样？", sh.Name, sh.Last, sh.PctChg),
			fmt.Sprintf("今天%s开在 %.2f、现价 %.2f，帮我看看早盘资金流向", sh.Name, sh.Open, sh.Last),
			fmt.Sprintf("早盘%s，现在该关注哪些方向？", breadth),
		}
	case PhaseNoon:
		return []string{
			fmt.Sprintf("今天上午%s收于 %.2f 点（%+.2f%%），帮我复盘上午盘面", sh.Name, sh.Last, sh.PctChg),
			fmt.Sprintf("上午%s，午后哪些板块值得盯？", breadth),
			"结合上午收盘情况，帮我梳理下午的操作要点",
		}
	case PhaseAfternoon:
		return []string{
			fmt.Sprintf("今天%s现报 %.2f 点（%+.2f%%），尾盘会怎么走？", sh.Name, sh.Last, sh.PctChg),
			fmt.Sprintf("今天%s开盘 %.2f、现价 %.2f，帮我分析下午的走势", sh.Name, sh.Open, sh.Last),
			fmt.Sprintf("今天%s，尾盘该加仓还是减仓？", breadth),
		}
	default:
		return []string{
			fmt.Sprintf("今天%s收于 %.2f 点（%+.2f%%），帮我复盘今天 A 股走势", sh.Name, sh.Last, sh.PctChg),
			fmt.Sprintf("今天%s，明天可以关注什么？", breadth),
			fmt.Sprintf("今天%s开 %.2f、收 %.2f，成交和资金面说明了什么？", sh.Name, sh.Open, sh.Last),
		}
	}
}

func (s *Service) fetchSnapshot(ctx context.Context) []Snapshot {
	if s.rt == nil {
		return nil
	}
	quotes, err := s.rt.FetchIndexes(ctx, indexCodes)
	if err != nil {
		s.logger.Warn().Err(err).Msg("brief: fetch index snapshot failed")
		return nil
	}
	out := make([]Snapshot, 0, len(quotes))
	for _, q := range quotes {
		if q.Last <= 0 {
			continue
		}
		out = append(out, Snapshot{
			Code: q.TsCode, Name: q.Name,
			Open: q.Open, Last: q.Last, High: q.High, Low: q.Low, PctChg: q.PctChg,
		})
	}
	return out
}

func truncateRunes(s string, n int) string {
	rs := []rune(s)
	if len(rs) <= n {
		return s
	}
	return string(rs[:n]) + "..."
}
