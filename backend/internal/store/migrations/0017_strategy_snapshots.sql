-- 主策略快照：定时从外部策略站抓取后归一化落库，供 App 的「策略」tab 读取。
--
-- 存归一化后的 payload（而不是外部原始响应），这样外部站改结构时只需改
-- 抓取层，客户端接口保持稳定。同时天然记录了「什么时候看到的是什么数据」，
-- 便于排查「展示的调仓指令是哪一期」。
CREATE TABLE IF NOT EXISTS strategy_snapshots (
  id           INTEGER PRIMARY KEY,
  strategy_id  TEXT NOT NULL,
  data_as_of   TEXT NOT NULL,   -- 数据截至日 YYYY-MM-DD
  payload_json TEXT NOT NULL,
  fetched_at   INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_strategy_snapshots_latest
  ON strategy_snapshots(strategy_id, fetched_at DESC);
