-- 鹦鹉螺市场子分类：在大类(weather/finance)下再分子类，供前端筛选。
--
--   * weather 子类：city(城市) / grain(谷物油籽产区) / soft(软商品产区)；
--   * finance 子类：index(股指) / stock(个股) / forex(外汇)。
--
-- 空串表示未分类(历史数据/未打标)，前端归入「全部」。

ALTER TABLE predict_markets ADD COLUMN subcategory TEXT NOT NULL DEFAULT '';
CREATE INDEX IF NOT EXISTS idx_predict_markets_cat_sub
  ON predict_markets(category, subcategory, status);
