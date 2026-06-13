-- 鹦鹉螺运营自动化：Bot 账号 + 每日出题幂等。
--
--   * users.is_bot：标记机器人账号，参与同池下注增强活跃度(平台兜底供给螺壳)；
--   * predict_markets.dedup_key：每日出题去重键(daily:<category>:<symbol>:<date>)，
--     唯一索引保证调度器重复执行不重复建市场，NULL 不参与约束。

ALTER TABLE users ADD COLUMN is_bot INTEGER NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_users_is_bot ON users(is_bot) WHERE is_bot = 1;

ALTER TABLE predict_markets ADD COLUMN dedup_key TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS uq_predict_markets_dedup
  ON predict_markets(dedup_key) WHERE dedup_key IS NOT NULL;
