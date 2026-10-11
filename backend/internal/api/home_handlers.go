package api

import (
	"net/http"

	"github.com/go-chi/chi/v5"

	"github.com/sencloud/finme-backend/internal/platform"
	"github.com/sencloud/finme-backend/internal/topic"
)

// mountAIHomePublic 挂载首页内容接口。
//
// /v1/ai/home-suggestions 是公开的（未登录也能看到首页那 3 条提问），内容
// 由 scheduler 定时生成，不含任何用户数据；未生成时返回空数组，客户端自行
// 回退到本地按行情拼装。
func mountAIHomePublic(r chi.Router, d *Deps) {
	r.Get("/ai/home-suggestions", handleHomeSuggestions(d))
}

func handleHomeSuggestions(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		// ?topic= 缺省 = money（市场简报）；其它主题用主题自带的静态提问。
		tp, err := topic.Resolve(r.URL.Query().Get("topic"))
		if err != nil {
			WriteError(w, r, platform.ErrBadRequest("AI.TOPIC_INVALID", "未知主题", nil))
			return
		}
		if tp.ID != topic.Money {
			qs := tp.HomeSuggestions
			if qs == nil {
				qs = []string{}
			}
			WriteJSON(w, http.StatusOK, map[string]any{"questions": qs, "topic": tp.ID})
			return
		}
		if d.Brief == nil {
			WriteJSON(w, http.StatusOK, map[string]any{"questions": []string{}})
			return
		}
		sug, err := d.Brief.Latest(r.Context())
		if err != nil {
			WriteError(w, r, platform.ErrInternal("AI.HOME_SUGGEST", err))
			return
		}
		if sug == nil || len(sug.Questions) == 0 {
			WriteJSON(w, http.StatusOK, map[string]any{"questions": []string{}})
			return
		}
		WriteJSON(w, http.StatusOK, sug)
	}
}
