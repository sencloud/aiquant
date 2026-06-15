-- 邮箱验证码登录：users 增加邮箱字段（HMAC 索引 + AES 密文），并新建 email_codes 表（镜像 sms_codes）。
-- SQLite 的 ALTER TABLE ADD COLUMN 无法内联 UNIQUE，故唯一性用部分唯一索引保证。

ALTER TABLE users ADD COLUMN email_hmac TEXT;
ALTER TABLE users ADD COLUMN email_enc  BLOB;
CREATE UNIQUE INDEX IF NOT EXISTS uq_users_email_hmac ON users(email_hmac) WHERE email_hmac IS NOT NULL;

CREATE TABLE IF NOT EXISTS email_codes (
  id          INTEGER PRIMARY KEY,
  email_hmac  TEXT NOT NULL,
  code_hash   TEXT NOT NULL,
  purpose     TEXT NOT NULL CHECK(purpose IN ('login','change_email')),
  expires_at  INTEGER NOT NULL,
  consumed_at INTEGER,
  attempts    INTEGER NOT NULL DEFAULT 0,
  ip          TEXT,
  created_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_email_codes ON email_codes(email_hmac, created_at);
