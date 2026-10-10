-- 实盘组合日快照：把主策略的实盘账户物化成「组合管理」里的系统托管组合。
--
-- 每个「数据截至日」一行（同日重复物化覆盖），payload 是客户端直接落库的
-- 组合文档（持仓 + 可回放的交易流水 + 现金/盈亏）。
CREATE TABLE IF NOT EXISTS live_portfolio_daily (
  portfolio_id    TEXT NOT NULL,
  as_of           TEXT NOT NULL,   -- YYYY-MM-DD
  payload_json    TEXT NOT NULL,
  materialized_at INTEGER NOT NULL,
  PRIMARY KEY (portfolio_id, as_of)
);
