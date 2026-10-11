package fishing

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"time"

	"github.com/jmoiron/sqlx"
	"github.com/rs/zerolog"

	"github.com/sencloud/finme-backend/internal/billing"
	"github.com/sencloud/finme-backend/internal/store"
)

// IdentifyCredits 拍照识鱼单价（喜点）。失败或没认出鱼全额退回。
const IdentifyCredits int64 = 3

// IdentifyRefType 账本 ref_type；ref_id = "<user_id>:<request_id>"。
// credit_ledger 的唯一索引是全局 (reason, ref_type, ref_id)，带上 user_id
// 避免两个用户恰好用了同一个 request_id 时互相撞车。
const IdentifyRefType = "fishing_identify"

// IdentifyDisclaimer 每次识别结果都要展示。
const IdentifyDisclaimer = "AI 识别仅供参考。疑似国家重点保护水生野生动物请立即放流；能否带走以当地渔政规定为准。"

// MaxImageDataURL 识鱼图片 data URL 的最大长度（字符）。客户端会先压到 ≤1024px JPEG（通常 100–300KB）。
const MaxImageDataURL = 2 << 20

// 识别状态。
const (
	IdentifyPending = "pending"
	IdentifyDone    = "done"
	IdentifyFailed  = "failed"
)

var (
	ErrBadRequestID         = errors.New("request_id invalid")
	ErrBadImage             = errors.New("image invalid")
	ErrIdentifyUnavailable  = errors.New("identify unavailable")
	ErrIdentifyInProgress   = errors.New("identify in progress")
	ErrInsufficientBalance  = billing.ErrInsufficientBalance
	requestIDRe             = regexp.MustCompile(`^[A-Za-z0-9_-]{8,64}$`)
	imageDataURLPrefixRe    = regexp.MustCompile(`^data:image/(jpeg|jpg|png|webp);base64,`)
	protectedSpeciesKeyword = []string{"中华鲟", "长江鲟", "达氏鲟", "白鲟", "胭脂鱼", "川陕哲罗鲑", "松江鲈"}
)

// Vision 是识鱼需要的多模态能力（*qwen.VisionClient 实现）。
type Vision interface {
	Configured() bool
	ImageJSON(ctx context.Context, system, userText, imageDataURL string, out any) error
}

// Candidate 是一个候选鱼种。
type Candidate struct {
	Name       string  `json:"name"`
	Latin      string  `json:"latin,omitempty"`
	Confidence float64 `json:"confidence"` // 0–1
	Features   string  `json:"features,omitempty"`
	Protected  bool    `json:"protected"`
	Note       string  `json:"note,omitempty"`
}

// IdentifyResult 是模型输出（落库 result_json）。
type IdentifyResult struct {
	IsFish     bool        `json:"is_fish"`
	Candidates []Candidate `json:"candidates"`
	Tips       string      `json:"tips,omitempty"`
}

// Identification 是接口返回。
type Identification struct {
	RequestID  string          `json:"request_id"`
	Status     string          `json:"status"`
	Credits    int64           `json:"credits"`
	Refunded   bool            `json:"refunded"`
	Result     *IdentifyResult `json:"result,omitempty"`
	Error      string          `json:"error,omitempty"`
	Disclaimer string          `json:"disclaimer"`
	Replayed   bool            `json:"replayed,omitempty"` // 同一 request_id 重放，未再次扣费
}

// Identifier 拍照识鱼：先扣费后识别，失败退款；按 (user, request_id) 幂等。
type Identifier struct {
	st     *store.Store
	vision Vision
	log    *zerolog.Logger
}

// NewIdentifier 构造。
func NewIdentifier(st *store.Store, v Vision, l *zerolog.Logger) *Identifier {
	if l == nil {
		nop := zerolog.Nop()
		l = &nop
	}
	return &Identifier{st: st, vision: v, log: l}
}

type identRow struct {
	ID         int64          `db:"id"`
	UserID     int64          `db:"user_id"`
	RequestID  string         `db:"request_id"`
	Status     string         `db:"status"`
	Credits    int64          `db:"credits"`
	Refunded   bool           `db:"refunded"`
	ResultJSON sql.NullString `db:"result_json"`
	Error      sql.NullString `db:"error"`
	CreatedAt  int64          `db:"created_at"`
	UpdatedAt  int64          `db:"updated_at"`
}

func (r *identRow) view() *Identification {
	out := &Identification{
		RequestID: r.RequestID, Status: r.Status, Credits: r.Credits, Refunded: r.Refunded,
		Error: r.Error.String, Disclaimer: IdentifyDisclaimer,
	}
	if r.ResultJSON.Valid {
		var res IdentifyResult
		if json.Unmarshal([]byte(r.ResultJSON.String), &res) == nil {
			out.Result = &res
		}
	}
	return out
}

func refID(uid int64, req string) string { return fmt.Sprintf("%d:%s", uid, req) }

// Identify 执行一次识别。
//
//   - 同一 request_id 已完成 / 已失败：直接返回记录，不再扣费（Replayed=true）；
//   - 识别中：ErrIdentifyInProgress；
//   - 新请求：同一事务里扣 3 喜点 + 登记 pending（余额不足整体回滚）→ 调模型 →
//     成功落 done；模型报错 / 没认出鱼 → 退款并落 failed。
func (s *Identifier) Identify(ctx context.Context, uid int64, requestID, imageDataURL string) (*Identification, error) {
	requestID = strings.TrimSpace(requestID)
	if !requestIDRe.MatchString(requestID) {
		return nil, ErrBadRequestID
	}
	if existing, err := s.find(ctx, uid, requestID); err != nil {
		return nil, err
	} else if existing != nil {
		switch existing.Status {
		case IdentifyPending:
			return nil, ErrIdentifyInProgress
		default:
			v := existing.view()
			v.Replayed = true
			return v, nil
		}
	}
	if len(imageDataURL) > MaxImageDataURL || !imageDataURLPrefixRe.MatchString(imageDataURL) {
		return nil, ErrBadImage
	}
	if s.vision == nil || !s.vision.Configured() {
		return nil, ErrIdentifyUnavailable
	}

	now := time.Now().UnixMilli()
	row := identRow{UserID: uid, RequestID: requestID, Status: IdentifyPending,
		Credits: IdentifyCredits, CreatedAt: now, UpdatedAt: now}
	err := s.st.Tx(ctx, func(tx *sqlx.Tx) error {
		if _, err := billing.ApplyTx(ctx, tx, billing.ApplyParams{
			UserID: uid, Delta: -IdentifyCredits,
			Reason: billing.ReasonFishingIdentify, RefType: IdentifyRefType, RefID: refID(uid, requestID),
			Remark: "拍照识鱼",
		}); err != nil {
			return err
		}
		res, err := tx.ExecContext(ctx, `
			INSERT INTO fishing_identifications(user_id, request_id, status, credits, refunded, created_at, updated_at)
			VALUES(?, ?, ?, ?, 0, ?, ?)`, uid, requestID, row.Status, row.Credits, now, now)
		if err != nil {
			return err
		}
		row.ID, _ = res.LastInsertId()
		return nil
	})
	if errors.Is(err, billing.ErrLedgerDuplicate) || isUnique(err) {
		// 并发重放：另一个请求已经扣过费并登记。
		return nil, ErrIdentifyInProgress
	}
	if err != nil {
		return nil, err
	}

	// HTTP 层有 60s 超时：模型调用限 45s；之后的落库 / 退款不跟随请求取消，
	// 保证扣过的喜点一定有结果（done 或退款）。
	vctx, cancel := context.WithTimeout(ctx, 45*time.Second)
	defer cancel()
	var res IdentifyResult
	verr := s.vision.ImageJSON(vctx, identifySystemPrompt, "请识别这张照片里的鱼。", imageDataURL, &res)
	ctx = context.WithoutCancel(ctx)
	if verr != nil {
		s.log.Warn().Err(verr).Int64("user", uid).Str("req", requestID).Msg("fishing identify: vision failed, refund")
		return s.failAndRefund(ctx, &row, "识别服务暂时不可用，喜点已退回")
	}
	normalize(&res)
	if !res.IsFish || len(res.Candidates) == 0 {
		return s.failAndRefund(ctx, &row, "没有在照片里认出鱼，喜点已退回。换个角度、让鱼体完整入镜再试试")
	}
	b, _ := json.Marshal(res)
	row.Status = IdentifyDone
	row.ResultJSON = sql.NullString{String: string(b), Valid: true}
	row.UpdatedAt = time.Now().UnixMilli()
	if _, err := s.st.DB.ExecContext(ctx,
		"UPDATE fishing_identifications SET status=?, result_json=?, updated_at=? WHERE id=?",
		row.Status, row.ResultJSON, row.UpdatedAt, row.ID); err != nil {
		return nil, err
	}
	return row.view(), nil
}

func (s *Identifier) find(ctx context.Context, uid int64, req string) (*identRow, error) {
	var r identRow
	err := s.st.DB.GetContext(ctx, &r,
		"SELECT * FROM fishing_identifications WHERE user_id=? AND request_id=?", uid, req)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &r, nil
}

// failAndRefund 标记失败并退款（幂等：fishing.identify_refund + 同一 ref）。
func (s *Identifier) failAndRefund(ctx context.Context, row *identRow, msg string) (*Identification, error) {
	err := s.st.Tx(ctx, func(tx *sqlx.Tx) error {
		_, err := billing.ApplyTx(ctx, tx, billing.ApplyParams{
			UserID: row.UserID, Delta: row.Credits,
			Reason: billing.ReasonFishingIdentifyRefund, RefType: IdentifyRefType, RefID: refID(row.UserID, row.RequestID),
			Remark: "拍照识鱼失败退款", AllowNegative: true,
		})
		if err != nil && !errors.Is(err, billing.ErrLedgerDuplicate) {
			return err
		}
		row.Status, row.Refunded = IdentifyFailed, true
		row.Error = sql.NullString{String: msg, Valid: true}
		row.UpdatedAt = time.Now().UnixMilli()
		_, err = tx.ExecContext(ctx,
			"UPDATE fishing_identifications SET status=?, refunded=1, error=?, updated_at=? WHERE id=?",
			row.Status, msg, row.UpdatedAt, row.ID)
		return err
	})
	if err != nil {
		return nil, err
	}
	return row.view(), nil
}

// RecoverStale 把卡在 pending 超过 maxAge 的识别（进程在调用模型时重启）标失败并退款。
func (s *Identifier) RecoverStale(ctx context.Context, maxAge time.Duration) (int, error) {
	cut := time.Now().Add(-maxAge).UnixMilli()
	rows := []identRow{}
	if err := s.st.DB.SelectContext(ctx, &rows,
		"SELECT * FROM fishing_identifications WHERE status=? AND updated_at<?", IdentifyPending, cut); err != nil {
		return 0, err
	}
	n := 0
	for i := range rows {
		if _, err := s.failAndRefund(ctx, &rows[i], "识别超时，喜点已退回"); err == nil {
			n++
		}
	}
	return n, nil
}

func normalize(res *IdentifyResult) {
	out := res.Candidates[:0]
	for _, c := range res.Candidates {
		c.Name = strings.TrimSpace(c.Name)
		if c.Name == "" {
			continue
		}
		if c.Confidence > 1 && c.Confidence <= 100 {
			c.Confidence /= 100
		}
		if c.Confidence < 0 {
			c.Confidence = 0
		}
		for _, k := range protectedSpeciesKeyword {
			if strings.Contains(c.Name, k) {
				c.Protected = true
			}
		}
		if c.Protected && c.Note == "" {
			c.Note = "疑似国家重点保护水生野生动物，请立即放流，不得捕捞、出售"
		}
		out = append(out, c)
		if len(out) == 3 {
			break
		}
	}
	res.Candidates = out
}

func isUnique(err error) bool {
	return err != nil && strings.Contains(strings.ToLower(err.Error()), "unique constraint")
}

const identifySystemPrompt = `你是中国淡水鱼类识别助手。用户上传一张钓到的鱼或水里的鱼的照片，请识别鱼种，输出严格 JSON：
{
  "is_fish": true/false（照片里没有鱼或鱼体完全看不清时为 false）,
  "candidates": [
    {
      "name": "中文通用名（如 鲫鱼、鲤鱼、草鱼、鲢鱼、鳙鱼、翘嘴、鳜鱼、黑鱼、鲈鱼、马口、罗非鱼）",
      "latin": "拉丁学名（不确定留空）",
      "confidence": 0 到 1 之间的小数,
      "features": "用于判断的外形特征，一句话（如 体侧扁、口须两对、背鳍硬刺带锯齿）",
      "protected": 是否属于国家重点保护水生野生动物（如中华鲟、长江鲟、白鲟、胭脂鱼、川陕哲罗鲑、松江鲈等）,
      "note": "补充说明，可空"
    }
  ],
  "tips": "一句实用提示（如 鲫鱼季节性习性或食用 / 放流建议；可空）"
}
按 confidence 从高到低最多给 3 个候选。看不准就降低 confidence，不要编造。只输出 JSON。`
