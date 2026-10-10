package strategy

import (
	"context"
	"time"

	"github.com/sencloud/finme-backend/internal/ai/tushare"
)

// tushareSource 用 Tushare 日线（不复权）与分红送转数据给模拟供价。
// 客户端组合页也用不复权日线估值，两边口径一致。
type tushareSource struct {
	tu *tushare.Client
}

func (t *tushareSource) DailyCloses(ctx context.Context, code string, start, end time.Time) ([]DailyClose, error) {
	rows, err := t.tu.HistoryFor(ctx, code, start, end)
	if err != nil {
		return nil, err
	}
	out := make([]DailyClose, 0, len(rows))
	for _, r := range rows {
		if len(r.TradeDate) != 8 {
			continue
		}
		out = append(out, DailyClose{Date: dash(r.TradeDate), Close: r.Close})
	}
	return out, nil
}

func (t *tushareSource) Dividends(ctx context.Context, code string) ([]Dividend, error) {
	rows, err := t.tu.Query(ctx, "dividend", map[string]any{"ts_code": code},
		[]string{"ts_code", "end_date", "div_proc", "stk_div", "cash_div_tax", "ex_date"})
	if err != nil {
		return nil, err
	}
	seen := map[string]bool{}
	var out []Dividend
	for _, r := range rows {
		if tushare.AsString(r["div_proc"]) != "实施" {
			continue
		}
		ex := tushare.AsString(r["ex_date"])
		if len(ex) != 8 || seen[ex] {
			continue
		}
		seen[ex] = true
		out = append(out, Dividend{
			ExDate:        dash(ex),
			CashPerShare:  tushare.AsFloat(r["cash_div_tax"]),
			StockPerShare: tushare.AsFloat(r["stk_div"]),
		})
	}
	return out, nil
}

func dash(ymd string) string { return ymd[:4] + "-" + ymd[4:6] + "-" + ymd[6:] }
