CREATE TABLE IF NOT EXISTS trade_reviews (
  user_id      INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  id           TEXT NOT NULL,
  report_json  TEXT NOT NULL,
  created_at   INTEGER NOT NULL,
  updated_at   INTEGER NOT NULL,
  PRIMARY KEY(user_id, id)
);

CREATE INDEX IF NOT EXISTS idx_trade_reviews_user_updated
  ON trade_reviews(user_id, updated_at DESC);
