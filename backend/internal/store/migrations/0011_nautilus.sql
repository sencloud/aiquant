-- 鹦鹉螺预测市场：螺壳虚拟货币 + 奖池瓜分制下注 + 邀请裂变。
--
-- 设计对齐 credit_ledger 的成熟模式：
--   * 余额冗余在 users.shell_balance，账本 shell_ledger 只插入不更新；
--   * (reason, ref_type, ref_id) 唯一索引保证业务幂等；
--   * 金额全部 INTEGER(1 螺壳)，永不浮点。

-- ① 用户：螺壳余额 + 邀请码(懒生成)
ALTER TABLE users ADD COLUMN shell_balance INTEGER NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN invite_code TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS uq_users_invite_code
  ON users(invite_code) WHERE invite_code IS NOT NULL;

-- ② 螺壳账本(镜像 credit_ledger)
CREATE TABLE IF NOT EXISTS shell_ledger (
  id             INTEGER PRIMARY KEY,
  user_id        INTEGER NOT NULL REFERENCES users(id),
  delta          INTEGER NOT NULL,
  balance_after  INTEGER NOT NULL,
  reason         TEXT NOT NULL,
  ref_type       TEXT,
  ref_id         TEXT,
  remark         TEXT,
  created_at     INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_shell_ledger_user ON shell_ledger(user_id, created_at);
CREATE UNIQUE INDEX IF NOT EXISTS uq_shell_ledger_idem
  ON shell_ledger(reason, ref_type, ref_id) WHERE ref_id IS NOT NULL;

-- ③ 预测市场
--   resolve_kind: auto(调度器按 resolve_rule 自动结算，目前仅金融类) / manual(管理端录入结果)
--   resolve_rule: auto 结算规则 JSON，例
--     {"source":"index","symbol":"上证指数","op":"gte","value":3500,"yes_idx":0,"no_idx":1}
CREATE TABLE IF NOT EXISTS predict_markets (
  id                  INTEGER PRIMARY KEY,
  category            TEXT NOT NULL CHECK(category IN ('weather','finance')),
  title               TEXT NOT NULL,
  description         TEXT NOT NULL DEFAULT '',
  status              TEXT NOT NULL DEFAULT 'open'
                        CHECK(status IN ('open','closed','settled','cancelled')),
  close_at            INTEGER NOT NULL,   -- 停止下注时间(ms)
  resolve_at          INTEGER NOT NULL,   -- 预期出结果时间(ms)
  resolve_kind        TEXT NOT NULL DEFAULT 'manual' CHECK(resolve_kind IN ('auto','manual')),
  resolve_rule        TEXT NOT NULL DEFAULT '',
  resolved_option_id  INTEGER,
  rake_bps            INTEGER NOT NULL DEFAULT 0,  -- 平台抽成，万分比
  created_at          INTEGER NOT NULL,
  updated_at          INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_predict_markets_status ON predict_markets(status, close_at);

-- ④ 市场选项(每个市场 2+ 个互斥结果)
CREATE TABLE IF NOT EXISTS predict_options (
  id            INTEGER PRIMARY KEY,
  market_id     INTEGER NOT NULL REFERENCES predict_markets(id) ON DELETE CASCADE,
  idx           INTEGER NOT NULL,
  label         TEXT NOT NULL,
  pool_shells   INTEGER NOT NULL DEFAULT 0,  -- 该选项累计下注池
  bettor_count  INTEGER NOT NULL DEFAULT 0,  -- 下注人数(去重)
  UNIQUE(market_id, idx)
);

-- ⑤ 下注流水(active → won/lost/refunded)
CREATE TABLE IF NOT EXISTS predict_bets (
  id          INTEGER PRIMARY KEY,
  market_id   INTEGER NOT NULL REFERENCES predict_markets(id),
  option_id   INTEGER NOT NULL REFERENCES predict_options(id),
  user_id     INTEGER NOT NULL REFERENCES users(id),
  amount      INTEGER NOT NULL,
  payout      INTEGER NOT NULL DEFAULT 0,
  status      TEXT NOT NULL DEFAULT 'active'
                CHECK(status IN ('active','won','lost','refunded')),
  created_at  INTEGER NOT NULL,
  settled_at  INTEGER
);
CREATE INDEX IF NOT EXISTS idx_predict_bets_user ON predict_bets(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_predict_bets_market ON predict_bets(market_id);

-- ⑥ 邀请兑换：一个用户(invitee)只能被邀请一次 → UNIQUE 天然幂等
CREATE TABLE IF NOT EXISTS invite_redemptions (
  id             INTEGER PRIMARY KEY,
  inviter_id     INTEGER NOT NULL REFERENCES users(id),
  invitee_id     INTEGER NOT NULL UNIQUE REFERENCES users(id),
  reward_shells  INTEGER NOT NULL,
  created_at     INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_invite_inviter ON invite_redemptions(inviter_id, created_at DESC);
