package api

import (
	"context"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/go-chi/chi/v5"

	"github.com/sencloud/finme-backend/internal/billing"
	"github.com/sencloud/finme-backend/internal/fishing"
	"github.com/sencloud/finme-backend/internal/platform"
)

// mountFishingPublic 喜爱钓鱼公开接口（免登录，无用户数据）。
//
//	GET /v1/fishing/forecast?place=千岛湖[&days=3]   或 ?lat=..&lon=..[&name=..]
//	GET /v1/fishing/regulations[?date=YYYY-MM-DD]
func mountFishingPublic(r chi.Router, d *Deps) {
	r.Get("/fishing/forecast", handleFishingForecast(d))
	r.Get("/fishing/regulations", handleFishingRegulations(d))
}

// mountFishingPrivate 喜爱钓鱼需登录的接口（识鱼扣喜点；日记 / 钓点按用户私有）。
func mountFishingPrivate(r chi.Router, d *Deps) {
	r.Post("/fishing/identify", handleFishingIdentify(d))
	r.Get("/fishing/catches", handleFishingListCatches(d))
	r.Post("/fishing/catches", handleFishingCreateCatch(d))
	r.Delete("/fishing/catches/{id}", handleFishingDeleteCatch(d))
	r.Get("/fishing/catches/{id}/photo", handleFishingCatchPhoto(d))
	r.Get("/fishing/spots", handleFishingListSpots(d))
	r.Post("/fishing/spots", handleFishingCreateSpot(d))
	r.Patch("/fishing/spots/{id}", handleFishingUpdateSpot(d))
	r.Delete("/fishing/spots/{id}", handleFishingDeleteSpot(d))
}

func fishingDisabled(w http.ResponseWriter, r *http.Request, d *Deps) bool {
	if d.Fishing == nil {
		WriteError(w, r, platform.ErrUnavailable("FISHING.DISABLED", errors.New("fishing disabled")))
		return true
	}
	return false
}

func handleFishingForecast(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if fishingDisabled(w, r, d) {
			return
		}
		q := r.URL.Query()
		days, _ := strconv.Atoi(q.Get("days"))
		ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
		defer cancel()
		var (
			fc  *fishing.Forecast
			err error
		)
		if q.Get("lat") != "" || q.Get("lon") != "" {
			lat, e1 := strconv.ParseFloat(q.Get("lat"), 64)
			lon, e2 := strconv.ParseFloat(q.Get("lon"), 64)
			if e1 != nil || e2 != nil {
				WriteError(w, r, platform.ErrBadRequest("FISHING.BAD_COORD", "坐标格式不正确", nil))
				return
			}
			fc, err = d.Fishing.Forecast.ForCoord(ctx, strings.TrimSpace(q.Get("name")), lat, lon, days)
		} else {
			place := strings.TrimSpace(q.Get("place"))
			if place == "" {
				WriteError(w, r, platform.ErrBadRequest("FISHING.PLACE_REQUIRED", "请输入地名或使用定位", nil))
				return
			}
			fc, err = d.Fishing.Forecast.ForPlace(ctx, place, days)
		}
		switch {
		case errors.Is(err, fishing.ErrBadCoord):
			WriteError(w, r, platform.ErrBadRequest("FISHING.BAD_COORD", "坐标不正确", err))
			return
		case errors.Is(err, fishing.ErrPlaceNotFound):
			WriteError(w, r, platform.ErrNotFound("FISHING.PLACE_NOT_FOUND", "没找到这个地名，换成城市或区县名试试"))
			return
		case err != nil:
			WriteError(w, r, platform.ErrUnavailable("FISHING.WEATHER_UNAVAILABLE", err))
			return
		}
		w.Header().Set("Cache-Control", "public, max-age=600")
		WriteJSON(w, http.StatusOK, fc)
	}
}

func handleFishingRegulations(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		day, err := fishing.ParseDate(r.URL.Query().Get("date"), time.Now())
		if err != nil {
			WriteError(w, r, platform.ErrBadRequest("FISHING.BAD_DATE", "日期格式应为 YYYY-MM-DD", err))
			return
		}
		WriteJSON(w, http.StatusOK, fishing.RegulationsResponse(day))
	}
}

// maxIdentifyBody 识鱼请求体上限（base64 图片 + 少量字段）。
const maxIdentifyBody = 3 << 20

func handleFishingIdentify(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if fishingDisabled(w, r, d) {
			return
		}
		uc := MustUser(r)
		var body struct {
			RequestID string `json:"request_id"`
			Image     string `json:"image"`
		}
		if err := decodeJSONLarge(r, &body, maxIdentifyBody); err != nil {
			WriteError(w, r, err)
			return
		}
		res, err := d.Fishing.Identify.Identify(r.Context(), uc.UserID, body.RequestID, body.Image)
		switch {
		case errors.Is(err, fishing.ErrBadRequestID):
			WriteError(w, r, platform.ErrBadRequest("FISHING.BAD_REQUEST_ID", "request_id 无效", err))
			return
		case errors.Is(err, fishing.ErrBadImage):
			WriteError(w, r, platform.ErrBadRequest("FISHING.BAD_IMAGE", "图片格式不支持或太大，请重新拍一张", err))
			return
		case errors.Is(err, fishing.ErrIdentifyUnavailable):
			WriteError(w, r, platform.ErrUnavailable("FISHING.IDENTIFY_UNAVAILABLE", err))
			return
		case errors.Is(err, fishing.ErrIdentifyInProgress):
			WriteError(w, r, platform.ErrConflict("FISHING.IDENTIFY_IN_PROGRESS", "正在识别中，请稍候"))
			return
		case errors.Is(err, billing.ErrInsufficientBalance):
			WriteError(w, r, platform.ErrPaymentRequired("FISHING.INSUFFICIENT_BALANCE", "喜点不足，拍照识鱼需要 3 喜点"))
			return
		case err != nil:
			WriteError(w, r, platform.ErrInternal("FISHING.IDENTIFY", err))
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{
			"identification": res,
			"balance":        creditBalance(r.Context(), d, uc.UserID),
		})
	}
}

func handleFishingListCatches(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if fishingDisabled(w, r, d) {
			return
		}
		uc := MustUser(r)
		before, _ := strconv.ParseInt(r.URL.Query().Get("before"), 10, 64)
		limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
		items, err := d.Fishing.Journal.ListCatches(r.Context(), uc.UserID, before, limit)
		if err != nil {
			WriteError(w, r, platform.ErrInternal("FISHING.CATCHES", err))
			return
		}
		out := map[string]any{"items": items}
		if before <= 0 {
			if st, err := d.Fishing.Journal.Stats(r.Context(), uc.UserID); err == nil {
				out["stats"] = st
			}
		}
		WriteJSON(w, http.StatusOK, out)
	}
}

func handleFishingCreateCatch(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if fishingDisabled(w, r, d) {
			return
		}
		uc := MustUser(r)
		var in fishing.CatchInput
		if err := decodeJSONLarge(r, &in, maxIdentifyBody); err != nil {
			WriteError(w, r, err)
			return
		}
		c, err := d.Fishing.Journal.CreateCatch(r.Context(), uc.UserID, in)
		if writeJournalErr(w, r, err) {
			return
		}
		WriteJSON(w, http.StatusCreated, map[string]any{"catch": c})
	}
}

func handleFishingDeleteCatch(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if fishingDisabled(w, r, d) {
			return
		}
		uc := MustUser(r)
		if writeJournalErr(w, r, d.Fishing.Journal.DeleteCatch(r.Context(), uc.UserID, chi.URLParam(r, "id"))) {
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"ok": true})
	}
}

func handleFishingCatchPhoto(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if fishingDisabled(w, r, d) {
			return
		}
		uc := MustUser(r)
		b, mime, err := d.Fishing.Journal.CatchPhoto(r.Context(), uc.UserID, chi.URLParam(r, "id"))
		if errors.Is(err, fishing.ErrNoPhoto) {
			WriteError(w, r, platform.ErrNotFound("FISHING.NO_PHOTO", "这条渔获没有照片"))
			return
		}
		if writeJournalErr(w, r, err) {
			return
		}
		w.Header().Set("Content-Type", mime)
		w.Header().Set("Cache-Control", "private, max-age=86400")
		w.Header().Set("Content-Length", strconv.Itoa(len(b)))
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(b)
	}
}

func handleFishingListSpots(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if fishingDisabled(w, r, d) {
			return
		}
		uc := MustUser(r)
		items, err := d.Fishing.Journal.ListSpots(r.Context(), uc.UserID)
		if writeJournalErr(w, r, err) {
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"items": items})
	}
}

func handleFishingCreateSpot(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if fishingDisabled(w, r, d) {
			return
		}
		uc := MustUser(r)
		var in fishing.SpotInput
		if err := DecodeJSON(r, &in); err != nil {
			WriteError(w, r, err)
			return
		}
		s, err := d.Fishing.Journal.CreateSpot(r.Context(), uc.UserID, in)
		if writeJournalErr(w, r, err) {
			return
		}
		WriteJSON(w, http.StatusCreated, map[string]any{"spot": s})
	}
}

func handleFishingUpdateSpot(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if fishingDisabled(w, r, d) {
			return
		}
		uc := MustUser(r)
		var in fishing.SpotInput
		if err := DecodeJSON(r, &in); err != nil {
			WriteError(w, r, err)
			return
		}
		s, err := d.Fishing.Journal.UpdateSpot(r.Context(), uc.UserID, chi.URLParam(r, "id"), in)
		if writeJournalErr(w, r, err) {
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"spot": s})
	}
}

func handleFishingDeleteSpot(d *Deps) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if fishingDisabled(w, r, d) {
			return
		}
		uc := MustUser(r)
		if writeJournalErr(w, r, d.Fishing.Journal.DeleteSpot(r.Context(), uc.UserID, chi.URLParam(r, "id"))) {
			return
		}
		WriteJSON(w, http.StatusOK, map[string]any{"ok": true})
	}
}

// writeJournalErr 把日记 / 钓点错误映射成 HTTP；返回 true 表示已写响应。
func writeJournalErr(w http.ResponseWriter, r *http.Request, err error) bool {
	switch {
	case err == nil:
		return false
	case errors.Is(err, fishing.ErrNotFound):
		WriteError(w, r, platform.ErrNotFound("FISHING.NOT_FOUND", "记录不存在"))
	case errors.Is(err, fishing.ErrInvalidInput):
		WriteError(w, r, platform.ErrBadRequest("FISHING.INVALID_INPUT", "填写内容不完整或超出长度", err))
	case errors.Is(err, fishing.ErrBadImage):
		WriteError(w, r, platform.ErrBadRequest("FISHING.BAD_IMAGE", "照片格式不支持或太大", err))
	default:
		WriteError(w, r, platform.ErrInternal("FISHING.JOURNAL", err))
	}
	return true
}
