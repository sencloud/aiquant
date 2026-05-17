// Package billing 实现喜点收费系统的全部业务逻辑：
// - SKU 套餐管理与查询
// - 订单创建 / 状态机 / IAP 校验
// - 喜点账本（ledger）+ 用户余额一致性
// - dev 模式专属直充接口（env=dev）
package billing

import (
	"context"
	"database/sql"
	"errors"

	"github.com/sencloud/finme-backend/internal/store"
)

// SKU 是充值套餐配置。
type SKU struct {
	Code           string `db:"code" json:"code"`
	AppleProductID string `db:"apple_product_id" json:"apple_product_id"`
	BaseCredits    int64  `db:"base_credits" json:"base_credits"`
	BonusCredits   int64  `db:"bonus_credits" json:"bonus_credits"`
	PriceCentsCNY  int64  `db:"price_cents_cny" json:"price_cents_cny"`
	Active         int    `db:"active" json:"-"`
	Sort           int    `db:"sort" json:"sort"`
}

func (s SKU) IsActive() bool      { return s.Active != 0 }
func (s SKU) TotalCredits() int64 { return s.BaseCredits + s.BonusCredits }

// PriceYuan 用于客户端展示的"X 元"，整数。这里数据库存的是分。
func (s SKU) PriceYuan() float64 { return float64(s.PriceCentsCNY) / 100.0 }

// SKURepo 提供 SKU 的读写。
type SKURepo struct {
	st *store.Store
}

func NewSKURepo(st *store.Store) *SKURepo { return &SKURepo{st: st} }

// ListActive 返回前端需要展示的 SKU（active=1，按 sort 升序）。
func (r *SKURepo) ListActive(ctx context.Context) ([]SKU, error) {
	rows := []SKU{}
	err := r.st.DB.SelectContext(ctx, &rows,
		"SELECT * FROM credit_skus WHERE active=1 ORDER BY sort ASC, base_credits ASC")
	if err != nil {
		return nil, err
	}
	return rows, nil
}

// FindByCode 按业务 code 取一条；不存在返回 (nil, nil)。
func (r *SKURepo) FindByCode(ctx context.Context, code string) (*SKU, error) {
	var s SKU
	err := r.st.DB.GetContext(ctx, &s, "SELECT * FROM credit_skus WHERE code=?", code)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &s, nil
}

// FindByAppleProductID 用于 IAP 流程：客户端只发 product_id，服务端反查 sku。
func (r *SKURepo) FindByAppleProductID(ctx context.Context, pid string) (*SKU, error) {
	var s SKU
	err := r.st.DB.GetContext(ctx, &s,
		"SELECT * FROM credit_skus WHERE apple_product_id=? AND active=1", pid)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &s, nil
}

// Upsert 写入/更新 SKU 配置。冷启动 seed 用。
func (r *SKURepo) Upsert(ctx context.Context, s SKU) error {
	_, err := r.st.DB.ExecContext(ctx, `
		INSERT INTO credit_skus(code, apple_product_id, base_credits, bonus_credits, price_cents_cny, active, sort)
		VALUES(?,?,?,?,?,?,?)
		ON CONFLICT(code) DO UPDATE SET
			apple_product_id=excluded.apple_product_id,
			base_credits=excluded.base_credits,
			bonus_credits=excluded.bonus_credits,
			price_cents_cny=excluded.price_cents_cny,
			active=excluded.active,
			sort=excluded.sort`,
		s.Code, s.AppleProductID, s.BaseCredits, s.BonusCredits, s.PriceCentsCNY, s.Active, s.Sort,
	)
	return err
}

// SeedDefault 在启动时 seed 默认 4 个套餐。已存在则更新（幂等）。
//
// apple_product_id 必须与 App Store Connect 配置一致；上线前在那边创建：
//   - credit_60   ¥6   60 喜点
//   - credit_500  ¥28  500 + 50 = 550 喜点
//   - credit_1000 ¥58  1000 + 200 = 1200 喜点
//   - credit_5000 ¥288 5000 + 1500 = 6500 喜点
func SeedDefault(ctx context.Context, repo *SKURepo) error {
	pkgs := []SKU{
		{Code: "credit_60", AppleProductID: "com.aiquant.app.credit60",
			BaseCredits: 60, BonusCredits: 0, PriceCentsCNY: 600, Active: 1, Sort: 1},
		{Code: "credit_500", AppleProductID: "com.aiquant.app.credit500",
			BaseCredits: 500, BonusCredits: 50, PriceCentsCNY: 2800, Active: 1, Sort: 2},
		{Code: "credit_1000", AppleProductID: "com.aiquant.app.credit1000",
			BaseCredits: 1000, BonusCredits: 200, PriceCentsCNY: 5800, Active: 1, Sort: 3},
		{Code: "credit_5000", AppleProductID: "com.aiquant.app.credit5000",
			BaseCredits: 5000, BonusCredits: 1500, PriceCentsCNY: 28800, Active: 1, Sort: 4},
	}
	for _, p := range pkgs {
		if err := repo.Upsert(ctx, p); err != nil {
			return err
		}
	}
	return nil
}
