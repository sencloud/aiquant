package miniapp

import "testing"

func TestIsPromiseHeadline(t *testing.T) {
	drop := []string{
		"史上最强厄尔尼诺逼近？巴克莱：棕榈油、橡胶、咖啡或在18个月内上涨30%-40%",
		"机构：铜价有望再涨20%",
		"分析师预计明年金价将上涨15％",
		"某券商给出目标价12000元",
		"豆粕上看4000，多头剑指前高",
		"这只基金年化20%以上，稳赚不赔",
		"白银或将翻倍？",
		"涨幅 10%-15% 可期",
	}
	keep := []string{
		"印尼商品管制引发恐慌，棕榈油现货价2天暴跌超30%",
		"如何观察“超级厄尔尼诺交易”？油气“反应最快”，棕榈油、椰子油和橡胶等“热带农产品”弹性最大",
		"马棕9月产量环比下降约4%",
		"沪深300收涨2.3%，成交额放大",
		"大商所调整棕榈油期货交易保证金",
		"看盘：沪指涨1%，北向资金净流入",
		"国庆后首日开盘将涨跌互现",
		"",
	}
	for _, s := range drop {
		if !isPromiseHeadline(s) {
			t.Errorf("应剔除：%q", s)
		}
	}
	for _, s := range keep {
		if isPromiseHeadline(s) {
			t.Errorf("不应剔除（事实报道）：%q", s)
		}
	}
}

func TestFilterNewsItems(t *testing.T) {
	items := []any{
		map[string]any{"title": "巴克莱：棕榈油或在18个月内上涨30%-40%"},
		map[string]any{"title": "马棕9月产量环比下降"},
		map[string]any{"title": "机构：有望翻倍"},
		map[string]any{"title": "印度10月棕榈油进口预期回升"},
		map[string]any{"title": "ENSO 指数维持中性"},
	}
	got := filterNewsItems(items, 2)
	if len(got) != 2 {
		t.Fatalf("len=%d", len(got))
	}
	if got[0].(map[string]any)["title"] != "马棕9月产量环比下降" ||
		got[1].(map[string]any)["title"] != "印度10月棕榈油进口预期回升" {
		t.Fatalf("got %v", got)
	}
	if n := len(filterNewsItems(items, 0)); n != 3 {
		t.Fatalf("不截断时应剩 3 条，得到 %d", n)
	}
}
