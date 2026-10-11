package fishing

import (
	"time"
)

// Regulation 是一条全国层面公开发布的禁渔 / 休渔制度（农业农村部通告）。
//
// 只收录全国性的流域制度，不编造任何省份细则：各地会在此基础上另行规定
// 禁渔区、禁钓区、钓具钓法限制，**一律以当地渔政部门公告为准**。
type Regulation struct {
	ID        string `json:"id"`
	Name      string `json:"name"`
	Waters    string `json:"waters"`  // 适用水域（摘要）
	Period    string `json:"period"`  // 时间
	Scope     string `json:"scope"`   // 禁止的作业类型
	Angling   string `json:"angling"` // 对休闲垂钓的说明
	Source    string `json:"source"`  // 文号
	YearRound bool   `json:"year_round"`
	// Provinces 是该流域流经的省级行政区（简称）。出钓指数只提示所在省份涉及的
	// 制度；省级粒度偏粗（例如四川同时涉及长江和黄河上游），宁可多提示，不漏提示。
	Provinces []string `json:"provinces"`
	// 季节性窗口（月日，含端点；YearRound 时忽略）。
	FromMonth, FromDay, ToMonth, ToDay int `json:"-"`
}

// Disclaimer 每次展示禁渔信息都要带上。
const RegulationDisclaimer = "以上为农业农村部公布的全国性流域禁渔制度摘要，各地另有禁渔区、禁钓区和钓具钓法规定，以当地渔政部门公告为准。电鱼、炸鱼、毒鱼在任何时间、任何水域都违法。"

// Regulations 全国性流域禁渔 / 休渔制度（按发布文件整理，2026 年有效）。
var Regulations = []Regulation{
	{
		ID:        "yangtze_10y",
		Name:      "长江十年禁渔",
		Waters:    "长江干流、重要支流和大型通江湖泊（鄱阳湖、洞庭湖）等重点水域",
		Period:    "自 2021 年 1 月 1 日 0 时起，暂定 10 年常年禁捕",
		Scope:     "禁止天然渔业资源的生产性捕捞",
		Angling:   "休闲垂钓由各地规范管理（禁钓区、钓具数量、钓法等各地不同）",
		Source:    "农业农村部关于长江流域重点水域禁捕范围和时间的通告（2019 年第 4 号）",
		YearRound: true,
		Provinces: []string{"青海", "西藏", "四川", "云南", "重庆", "贵州", "湖北", "湖南", "江西", "安徽", "江苏", "上海", "陕西", "甘肃", "河南"},
	},
	{
		ID:        "huai_spring",
		Name:      "淮河干流禁渔期",
		Waters:    "淮河干流河段",
		Period:    "每年 3 月 1 日 0 时至 6 月 30 日 24 时",
		Scope:     "禁止除娱乐性垂钓和休闲渔业以外的捕捞作业",
		Angling:   "允许娱乐性垂钓，具体以当地规定为准",
		Source:    "农业农村部流域禁渔期制度",
		FromMonth: 3, FromDay: 1, ToMonth: 6, ToDay: 30,
		Provinces: []string{"河南", "安徽", "江苏"},
	},
	{
		ID:        "pearl_spring",
		Name:      "珠江、闽江及海南内陆水域春季禁渔期",
		Waters:    "珠江、闽江流域及海南省内陆水域",
		Period:    "每年 3 月 1 日 0 时至 6 月 30 日 24 时",
		Scope:     "禁止除娱乐性垂钓和休闲渔业以外的所有捕捞作业",
		Angling:   "允许娱乐性垂钓，具体以当地规定为准",
		Source:    "农业农村部流域禁渔期制度",
		FromMonth: 3, FromDay: 1, ToMonth: 6, ToDay: 30,
		Provinces: []string{"广东", "广西", "云南", "贵州", "福建", "海南"},
	},
	{
		ID:        "qiantang_spring",
		Name:      "钱塘江禁渔期",
		Waters:    "钱塘江干流",
		Period:    "每年 3 月 1 日 0 时至 6 月 30 日 24 时",
		Scope:     "禁止除娱乐性垂钓和休闲渔业以外的捕捞作业",
		Angling:   "允许娱乐性垂钓，具体以当地规定为准",
		Source:    "农业农村部通告〔2019〕1 号",
		FromMonth: 3, FromDay: 1, ToMonth: 6, ToDay: 30,
		Provinces: []string{"浙江", "安徽"},
	},
	{
		ID:        "yellow_upper",
		Name:      "黄河上游全年禁渔",
		Waters:    "黄河河源区及上游（青海段、四川段、甘肃段等）",
		Period:    "2026 年 1 月 1 日至 2030 年 12 月 31 日全年禁渔",
		Scope:     "禁止生产性捕捞作业",
		Angling:   "休闲垂钓以当地规定为准",
		Source:    "农业农村部通告〔2025〕2 号",
		YearRound: true,
		Provinces: []string{"青海", "四川", "甘肃"},
	},
	{
		ID:        "yellow_lower",
		Name:      "黄河中下游休渔期",
		Waters:    "黄河宁夏段至入海口",
		Period:    "每年 4 月 1 日至 7 月 31 日",
		Scope:     "禁止生产性捕捞作业",
		Angling:   "休闲垂钓以当地规定为准",
		Source:    "农业农村部通告〔2025〕2 号",
		FromMonth: 4, FromDay: 1, ToMonth: 7, ToDay: 31,
		Provinces: []string{"宁夏", "内蒙古", "陕西", "山西", "河南", "山东"},
	},
	{
		ID:        "north_summer",
		Name:      "海河、辽河、松花江禁渔期",
		Waters:    "海河、辽河、松花江流域",
		Period:    "每年 5 月 16 日 12 时至 7 月 31 日 12 时",
		Scope:     "禁止除钓具之外的所有作业方式",
		Angling:   "允许钓具作业，具体以当地规定为准",
		Source:    "农业农村部通告〔2019〕1 号",
		FromMonth: 5, FromDay: 16, ToMonth: 7, ToDay: 31,
		Provinces: []string{"北京", "天津", "河北", "山西", "山东", "河南", "内蒙古", "辽宁", "吉林", "黑龙江"},
	},
}

// ActiveOn 判断某制度在 t（北京时间日期）是否处于禁渔 / 休渔期。
func (r Regulation) ActiveOn(t time.Time) bool {
	if r.YearRound {
		return true
	}
	md := int(t.Month())*100 + t.Day()
	return md >= r.FromMonth*100+r.FromDay && md <= r.ToMonth*100+r.ToDay
}

// RegulationView 是带「今天是否生效」标记的输出。
type RegulationView struct {
	Regulation
	Active bool `json:"active"`
}

// RegulationsOn 返回全部制度，标出 t 当天生效的；生效的排在前面。
func RegulationsOn(t time.Time) []RegulationView {
	var active, rest []RegulationView
	for _, r := range Regulations {
		v := RegulationView{Regulation: r, Active: r.ActiveOn(t)}
		if v.Active {
			active = append(active, v)
		} else {
			rest = append(rest, v)
		}
	}
	return append(active, rest...)
}

// AppliesTo 判断制度是否涉及某省（简称）。province 为空（国外 / 认不出）时不提示。
func (r Regulation) AppliesTo(province string) bool {
	for _, p := range r.Provinces {
		if p == province {
			return true
		}
	}
	return false
}

// ActiveBansFor 返回 t 当天生效、且涉及 province 的制度名称。
func ActiveBansFor(t time.Time, province string) []string {
	if province == "" {
		return nil
	}
	var out []string
	for _, r := range Regulations {
		if r.ActiveOn(t) && r.AppliesTo(province) {
			out = append(out, r.Name)
		}
	}
	return out
}
