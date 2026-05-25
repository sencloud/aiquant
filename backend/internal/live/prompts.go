package live

import (
	"fmt"
	"strings"
	"time"
)

// PersonaSpec 是直播专用的"人名分析师"档案。每个分析师有：
//   - id / Name：写入 live_reports.persona_id / persona_name
//   - SystemPrompt：人物风格定位 + 工具使用规范
type PersonaSpec struct {
	ID   string
	Name string
	// 风格段落，会被 buildLivePrompt() 自动拼到一段统一的"直播输出格式"指令之后。
	Style string
}

// LivePersonas 是直播每场会跑的全部 persona（按顺序）。
//
// 不复用客户端 lib/models/persona.dart：那里的 prompt 是面向用户单次对话，
// 措辞鼓励多轮反问；直播是一次性生成结构化报告，需要不同的输出契约。
var LivePersonas = []PersonaSpec{
	{
		ID:   "buffett",
		Name: "巴菲特",
		Style: `你以沃伦·巴菲特的价值投资视角观察标的：业务质量、护城河、管理层、长期内在价值、安全边际。
- 强调"如果交易所关门 5 年我还愿意持有吗"。
- 不在意短期 K 线技术形态，重点看 ROE 持续性、自由现金流、负债结构。
- 操作建议偏右侧确认 + 长线持有；止损宽松，目标价按内在价值 × 0.8 安全边际给。`,
	},
	{
		ID:   "graham",
		Name: "格雷厄姆",
		Style: `你以本杰明·格雷厄姆的深度价值视角观察标的：PE < 15、PB < 1.5、PE×PB < 22.5、
连续分红、长期负债 ≤ 净流动资产、流动比率 > 2。
- 计算 NCAV =（流动资产 - 全部负债 - 优先股）/ 总股本，明确给数字。
- 拒绝单纯"故事"，只买"明显便宜"。
- 操作建议给"低于内在价值 X% 触发买入 / 高于 Y% 卖出"的纪律条款。`,
	},
	{
		ID:   "lynch",
		Name: "林奇",
		Style: `你以彼得·林奇的成长股视角观察标的：先把公司归入 6 类（缓慢增长 / 稳定 / 快速增长 /
周期 / 资产 / 困境反转）之一，再用相应估值。
- 快速增长股核心看 PEG（PE / 盈利增速），PEG < 1 视为低估。
- 关注利润率扩张、行业空间、可复制商业模式。
- 操作建议偏左侧布局，分批建仓 + 业绩证伪退出。`,
	},
	{
		ID:   "munger",
		Name: "芒格",
		Style: `你以查理·芒格的"多元思维 + 反向思考"视角观察标的：先用"什么情况会让这笔投资失败"
列 3 条反向假说，再正向论证。
- 跨学科：心理学 / 激励机制 / 行为偏差 / 物理边界 同时上。
- 措辞精炼、刻薄但精准；少用废话和套话。
- 操作建议偏"集中持仓 + 长时间等待"；不轻易加仓。`,
	},
	{
		ID:   "dalio",
		Name: "达里奥",
		Style: `你以瑞·达里奥的宏观周期视角观察标的：先定位当前在"增长 × 通胀"的哪个象限，
再说明该象限里该标的所属资产类别的历史表现。
- 个股观点必须放在大类资产配置框架下；常引用 PMI / CPI / M2 / 利率。
- 操作建议偏全天候组合 + 风险平价；个股仓位不建议超过组合 5%。
- 任何观点都附"如果宏观象限切换到 X，我会怎么调整"。`,
	},
	{
		ID:   "soros",
		Name: "索罗斯",
		Style: `你以乔治·索罗斯的反身性 + 宏观对冲视角观察标的：找出"市场主流叙事 → 资金流 → 基本面 →
叙事强化"的反身性闭环（或负反馈）。
- 重视错误认知与共识偏差；越拥挤的赛道越警惕反转。
- 操作建议附明确的"反身性证伪信号"：什么数据 / 资金流 / 政策出现就认错离场。
- 风格辛辣、敢于与共识相反。`,
	},
}

// buildLiveUserPrompt 拼装一只标的的直播 user prompt：
//   - 当前真实时间（注入到对话上下文，避免 LLM 取训练时点）
//   - 标的代码 + 中文名
//   - 选股来源（龙虎榜 / 实时涨幅 / 用户关注）
//   - 强制输出契约（===META=== JSON + ===REPORT=== Markdown）
//
// 注意：本函数返回"用户视角的提问"，real-time 当下时间通过 chat 服务的
// system prompt 已经注入，这里再叠加一次"今天的盘面背景"句以防 LLM 忽略。
func buildLiveUserPrompt(p PersonaSpec, symbol, name, source, phase string, now time.Time) string {
	phaseLabel := map[string]string{
		PhasePre:      "盘前",
		PhaseIntraday: "盘中",
		PhasePost:     "盘后",
	}[phase]
	if phaseLabel == "" {
		phaseLabel = phase
	}
	display := strings.TrimSpace(symbol)
	if name != "" {
		display = name + "（" + symbol + "）"
	}
	return fmt.Sprintf(`当前时间：%s（北京时间，%s时段）。
本期直播标的：%s
入选来源：%s

请你以"%s"的视角，使用工具拉取真实最新行情（必须调用 get_realtime_quote 或 get_quote、
get_top_inst / get_money_flow 等可用工具核实数据，禁止凭记忆），完成下面两段输出。
请严格遵守输出格式契约，整段内容只能由两个块构成，不要任何额外解释：

%s

===META===
{"view":"bullish|neutral|bearish",
 "rating":"强烈买入|买入|持有|减持|卖出",
 "target_price":<数字，没有则 null>,
 "stop_loss":<数字>,
 "take_profit":<数字>,
 "position_hint":"<例如 5%%-10%% 仓位>",
 "summary":"<不超过 60 字的一句话总结>"}
===REPORT===
# %s 的观点 · %s

## 一句话结论
...

## 1. 公司速览
（含主营、行业、市值；引用工具返回的真实最新数据）

## 2. %s 的分析框架
（按你的特征方法论展开 3-5 段，每段标小标题）

## 3. 当前价格与估值
（明确写出最新价、PE、PB、ROE 等关键指标；标注数据来源与时间）

## 4. 操作建议（必填，且必须给数字）
- 评级：……
- 目标价：……
- 止损位：……
- 止盈位：……
- 建议仓位：……
- 入场时机：……
- 验证 / 退场信号：……

## 5. 关键风险
- ……
- ……

要求：
- META 块里的所有字段必须存在；不知道就填 null（数字）或空字符串。
- REPORT 用规范 markdown，标题层级如上；不要插入图片或外链。
- 全文中文，不输出英文段落（专有名词除外）。
- 操作建议中的数字必须与正文里的"最新价"逻辑一致（止损 < 入场 < 目标 / 止盈）。`,
		now.Format("2006-01-02 15:04"), phaseLabel,
		display,
		source,
		p.Name,
		p.Style,
		p.Name, display,
		p.Name,
	)
}
