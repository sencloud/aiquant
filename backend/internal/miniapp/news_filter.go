package miniapp

import (
	"regexp"
	"strings"
)

// 小应用「中文财经资讯」（news.cn）的标题过滤。
//
// 小应用是用户放在发现页、每天自动刷新的看板，新闻标题会原样显示。像
// 「巴克莱：棕榈油、橡胶、咖啡或在18个月内上涨30%-40%」这种**预测涨跌幅 /
// 目标价 / 收益承诺**式的标题，放在看板上很像本 App 在喊涨，也不符合
// 「不构成投资建议」的定位，所以在这个数据源里剔除。
//
// 只剔除「向前看」的说法，**不剔除事实报道**：
//   - 剔除：或/将/有望/预计/料/可能… + 涨跌 + 百分比（「或上涨30%-40%」「有望翻倍」）
//   - 剔除：目标价、上看/下看/剑指 + 数字（「目标价 12000」「上看 1 万」）
//   - 剔除：收益承诺（稳赚、保本、必涨、躺赚、暴富、收益率高达…）
//   - 保留：已发生的涨跌（「现货价2天暴跌超30%」「收涨 2.3%」）
//
// 这里只过滤小应用的新闻块；AI 对话里的新闻工具不过滤（AI 会自己转述并带风险提示）。
var newsPromisePatterns = []*regexp.Regexp{
	// 前瞻词 + （若干字）+ 涨跌词 + （若干字）+ 百分比 / 倍
	regexp.MustCompile(`(或|或将|将|有望|预计|预期|料将?|可能)[^，。；！？,;!?]{0,10}(上涨|下跌|大涨|大跌|暴涨|暴跌|涨|跌|上行|下行|反弹|回落|升|降)[^，。；！？,;!?]{0,8}\d+(\.\d+)?\s*(%|％|倍)`),
	// 「上涨 30%-40%」这类涨跌幅区间
	regexp.MustCompile(`(上涨|下跌|涨|跌|涨幅|跌幅|收益|回报)[^，。；！？,;!?]{0,6}\d+(\.\d+)?\s*(%|％)?\s*[-–—~～至到]\s*\d+(\.\d+)?\s*(%|％)`),
	// 「有望翻倍」「或将翻番」
	regexp.MustCompile(`(或|或将|将|有望|预计|料将?|可能)[^，。；！？,;!?]{0,6}(翻倍|翻番)`),
	// 目标价 / 上看 / 下看 / 剑指 / 看至 + 数字
	regexp.MustCompile(`(目标价|目标位|上看|下看|剑指|看至|看到)\s*\d`),
	// 收益承诺
	regexp.MustCompile(`稳赚|保本|必涨|必跌|躺赚|暴富|收益率?高达|年化\s*\d+(\.\d+)?\s*(%|％)以上`),
}

// isPromiseHeadline 判断标题是不是「预测涨跌幅 / 目标价 / 收益承诺」式。
func isPromiseHeadline(title string) bool {
	t := strings.TrimSpace(title)
	if t == "" {
		return false
	}
	for _, re := range newsPromisePatterns {
		if re.MatchString(t) {
			return true
		}
	}
	return false
}

// filterNewsItems 去掉 promise 式标题，最多保留 limit 条（limit<=0 表示不截断）。
func filterNewsItems(items []any, limit int) []any {
	out := make([]any, 0, len(items))
	for _, e := range items {
		if m, ok := e.(map[string]any); ok {
			if s, _ := m["title"].(string); isPromiseHeadline(s) {
				continue
			}
		}
		out = append(out, e)
		if limit > 0 && len(out) >= limit {
			break
		}
	}
	return out
}
