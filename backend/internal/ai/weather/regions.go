package weather

import "strings"

// regionAliases：模型常用的口语化叫法 → 内置地点 key。
//
// 线上日志里 get_region_weather 失败的主要原因是模型传「马来·柔佛州」「印尼·廖内」
// 这种自拟的名字，而旧实现只认精确的 key / 中文名，于是整次调用返回
// 「没有匹配到任何产区」。这里补一层别名 + 作物 + 子串匹配。
var regionAliases = map[string][]string{
	"my_palm_johor":        {"柔佛", "johor", "马来西亚半岛", "西马"},
	"my_palm_pahang":       {"彭亨", "pahang"},
	"my_palm_sabah":        {"沙巴", "sabah", "东马"},
	"my_palm_sarawak":      {"砂拉越", "沙捞越", "砂劳越", "sarawak"},
	"id_palm_riau":         {"廖内", "riau"},
	"id_palm_ssumatra":     {"南苏门答腊", "南苏", "south sumatra"},
	"id_palm_nsumatra":     {"北苏门答腊", "北苏", "north sumatra", "苏门答腊", "sumatra"},
	"id_palm_ckalimantan":  {"中加里曼丹", "加里曼丹", "kalimantan", "婆罗洲", "borneo"},
	"id_palm_wkalimantan":  {"西加里曼丹", "west kalimantan"},
	"th_rubber_south":      {"泰国南部", "泰南", "宋卡", "合艾", "泰国橡胶"},
	"cn_rubber_hainan":     {"海南"},
	"cn_rubber_yunnan":     {"西双版纳", "云南"},
	"us_corn_belt":         {"玉米带", "爱荷华", "艾奥瓦", "iowa", "corn belt", "美国中西部"},
	"us_soy_illinois":      {"伊利诺伊", "illinois"},
	"us_corn_nebraska":     {"内布拉斯加", "nebraska"},
	"us_wheat_kansas":      {"堪萨斯", "kansas", "美国平原", "hrw"},
	"us_cotton_texas":      {"得州", "德州", "得克萨斯", "texas"},
	"brazil_soy_mt":        {"马托格罗索", "mato grosso", "巴西中西部"},
	"brazil_soy_parana":    {"巴拉那", "parana", "巴西南部"},
	"brazil_soy_goias":     {"戈亚斯", "goias"},
	"brazil_coffee_mg":     {"米纳斯", "minas gerais", "巴西咖啡"},
	"brazil_sugar_sp":      {"圣保罗", "sao paulo", "巴西甘蔗", "巴西糖"},
	"argentina_pampas":     {"潘帕斯", "pampas", "布宜诺斯艾利斯", "阿根廷"},
	"argentina_cordoba":    {"科尔多瓦", "cordoba"},
	"blacksea_wheat":       {"黑海", "乌克兰", "ukraine"},
	"russia_wheat_south":   {"俄罗斯", "russia", "罗斯托夫", "克拉斯诺达尔"},
	"canada_canola":        {"萨斯喀彻温", "加拿大", "canada", "saskatchewan"},
	"australia_wheat_nsw":  {"新南威尔士", "澳大利亚", "澳洲", "australia"},
	"india_sugar_up":       {"北方邦", "uttar pradesh", "印度北部"},
	"india_soy_mp":         {"中央邦", "madhya pradesh", "印度大豆"},
	"thailand_sugar":       {"泰国东北", "泰国甘蔗", "泰国糖"},
	"vietnam_coffee":       {"越南", "vietnam", "中部高原", "多乐"},
	"ivorycoast_cocoa":     {"科特迪瓦", "象牙海岸", "ivory coast", "西非"},
	"cn_corn_heilongjiang": {"黑龙江", "东北"},
	"cn_corn_jilin":        {"吉林"},
	"cn_wheat_henan":       {"河南", "黄淮", "华北"},
	"cn_wheat_shandong":    {"山东"},
	"cn_cotton_xinjiang":   {"新疆", "南疆", "阿克苏"},
	"cn_sugar_guangxi":     {"广西"},
	"cn_apple_shaanxi":     {"陕西", "洛川"},
	"cn_rapeseed_hubei":    {"湖北", "长江流域"},
	"cn_hog_sichuan":       {"四川"},
}

// cropAliases：按作物/品种问时展开成一组产区（例如「棕榈油产区」）。
var cropAliases = map[string][]string{
	"棕榈":    {"my_palm_johor", "my_palm_sabah", "my_palm_sarawak", "id_palm_riau", "id_palm_ssumatra", "id_palm_ckalimantan"},
	"palm":  {"my_palm_johor", "my_palm_sabah", "my_palm_sarawak", "id_palm_riau", "id_palm_ssumatra", "id_palm_ckalimantan"},
	"马来西亚":  {"my_palm_johor", "my_palm_pahang", "my_palm_sabah", "my_palm_sarawak"},
	"大马":    {"my_palm_johor", "my_palm_pahang", "my_palm_sabah", "my_palm_sarawak"},
	"印尼":    {"id_palm_riau", "id_palm_ssumatra", "id_palm_nsumatra", "id_palm_ckalimantan", "id_palm_wkalimantan"},
	"印度尼西亚": {"id_palm_riau", "id_palm_ssumatra", "id_palm_nsumatra", "id_palm_ckalimantan", "id_palm_wkalimantan"},
	"东南亚":   {"my_palm_johor", "my_palm_sabah", "id_palm_riau", "id_palm_ssumatra", "th_rubber_south"},
	"橡胶":    {"th_rubber_south", "cn_rubber_yunnan", "cn_rubber_hainan", "id_palm_ssumatra"},
	"大豆":    {"us_corn_belt", "us_soy_illinois", "brazil_soy_mt", "brazil_soy_parana", "argentina_pampas", "cn_corn_heilongjiang"},
	"美豆":    {"us_corn_belt", "us_soy_illinois", "us_corn_nebraska"},
	"巴西":    {"brazil_soy_mt", "brazil_soy_parana", "brazil_soy_goias", "brazil_coffee_mg", "brazil_sugar_sp"},
	"美国":    {"us_corn_belt", "us_soy_illinois", "us_wheat_kansas", "us_cotton_texas"},
	"玉米":    {"us_corn_belt", "us_corn_nebraska", "brazil_soy_parana", "cn_corn_heilongjiang", "cn_corn_jilin"},
	"小麦":    {"us_wheat_kansas", "blacksea_wheat", "russia_wheat_south", "australia_wheat_nsw", "cn_wheat_henan"},
	"棉花":    {"us_cotton_texas", "cn_cotton_xinjiang", "india_sugar_up"},
	"白糖":    {"brazil_sugar_sp", "india_sugar_up", "thailand_sugar", "cn_sugar_guangxi"},
	"原糖":    {"brazil_sugar_sp", "india_sugar_up", "thailand_sugar"},
	"甘蔗":    {"brazil_sugar_sp", "india_sugar_up", "thailand_sugar", "cn_sugar_guangxi"},
	"咖啡":    {"brazil_coffee_mg", "vietnam_coffee"},
	"可可":    {"ivorycoast_cocoa"},
	"菜籽":    {"canada_canola", "cn_rapeseed_hubei"},
	"油菜":    {"canada_canola", "cn_rapeseed_hubei"},
	"豆粕":    {"us_corn_belt", "brazil_soy_mt", "argentina_pampas"},
	"豆油":    {"us_corn_belt", "brazil_soy_mt", "argentina_pampas"},
	"油脂":    {"my_palm_johor", "id_palm_riau", "us_corn_belt", "brazil_soy_mt", "canada_canola"},
	"苹果":    {"cn_apple_shaanxi", "cn_wheat_shandong"},
	"中国":    {"cn_corn_heilongjiang", "cn_wheat_henan", "cn_cotton_xinjiang", "cn_sugar_guangxi"},
	"国内":    {"cn_corn_heilongjiang", "cn_wheat_henan", "cn_cotton_xinjiang", "cn_sugar_guangxi"},
}

// Resolve 把一个自由输入（key / 中文名 / 别名 / 作物 / 名称片段）解析成内置地点。
// 可能返回多个（按作物展开时）；完全没匹配到返回 nil，调用方可再走 Geocode。
func Resolve(input string) []City {
	q := strings.TrimSpace(input)
	if q == "" {
		return nil
	}
	lq := strings.ToLower(q)
	if c, ok := CityByKey(lq); ok {
		return []City{c}
	}
	for _, c := range Cities {
		if c.Name == q {
			return []City{c}
		}
	}
	// 1) 具体地名别名：取「最长命中」的那个，避免「苏门答腊」盖过「南苏门答腊」。
	bestKey, bestLen := "", 0
	for key, aliases := range regionAliases {
		for _, a := range aliases {
			if strings.Contains(lq, strings.ToLower(a)) && len(a) > bestLen {
				bestKey, bestLen = key, len(a)
			}
		}
	}
	// 2) 内置名称的地名段（「·」后半段，如「柔佛」「堪萨斯」）出现在输入里。
	for _, c := range Cities {
		parts := strings.Split(c.Name, "·")
		place := parts[len(parts)-1]
		if len([]rune(place)) >= 2 && strings.Contains(q, place) && len(place) > bestLen {
			bestKey, bestLen = c.Key, len(place)
		}
	}
	if bestKey != "" {
		if c, ok := CityByKey(bestKey); ok {
			return []City{c}
		}
	}
	// 3) 作物 / 国家：展开成一组产区。
	for word, keys := range cropAliases {
		if strings.Contains(lq, strings.ToLower(word)) {
			out := make([]City, 0, len(keys))
			for _, k := range keys {
				if c, ok := CityByKey(k); ok {
					out = append(out, c)
				}
			}
			return out
		}
	}
	return nil
}

// RegionKeys 列出全部内置地点（key → 名称），供工具在没匹配时提示模型。
func RegionKeys() []string {
	out := make([]string, 0, len(Cities))
	for _, c := range Cities {
		out = append(out, c.Key+"("+c.Name+")")
	}
	return out
}
