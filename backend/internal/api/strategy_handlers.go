package api

import (
	"net/http"

	"github.com/go-chi/chi/v5"

	"github.com/sencloud/finme-backend/internal/platform"
	"github.com/sencloud/finme-backend/internal/strategy"
)

// mountStrategy 挂载策略接口（需登录）。
//
// App 的「策略」tab 只打这一个接口：一次拿到「要不要动手」+ 实盘 + 绩效 + 口径说明。
// 返回空对象而不是 404——客户端据此显示"策略数据同步中"，而不是报错。
func mountStrategy(r chi.Router, d *Deps) {
	r.Get("/strategy/primary", handlePrimaryStrategy(d))
	r.Get("/strategy/catalog", handleStrategyCatalog(d))
}

func handleStrategyCatalog(_ *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		WriteJSON(w, http.StatusOK, map[string]any{
			"primary":    strategy.PrimaryID,
			"strategies": strategy.Catalog(),
		})
	}
}

func handlePrimaryStrategy(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if d.Strategy == nil {
			WriteJSON(w, http.StatusOK, map[string]any{"available": false})
			return
		}
		snap, err := d.Strategy.Latest(r.Context())
		if err != nil {
			WriteError(w, r, platform.ErrInternal("STRATEGY.READ", err))
			return
		}
		if snap == nil {
			// 首次同步还没跑完：不是错误，客户端应显示占位态。
			WriteJSON(w, http.StatusOK, map[string]any{
				"available":   false,
				"strategy_id": strategy.PrimaryID,
				"reason":      "snapshot_not_ready",
			})
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{
			"available": true,
			"snapshot":  snap,
		})
	}
}
