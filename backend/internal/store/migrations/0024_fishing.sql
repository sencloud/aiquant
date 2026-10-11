-- 喜爱钓鱼 P0：渔获日记、私人钓点、拍照识鱼。
--
-- 全部按用户私有（不做公开钓点）。CREATE ... IF NOT EXISTS：api / scheduler /
-- pusher 启动时都会跑迁移，并发执行也不会失败。

-- 私人钓点：只存坐标和备注；导航交给系统地图（客户端拼 geo / 高德 / Apple Maps 链接）。
CREATE TABLE IF NOT EXISTS fishing_spots (
  id          INTEGER PRIMARY KEY,
  uuid        TEXT NOT NULL UNIQUE,
  user_id     INTEGER NOT NULL REFERENCES users(id),
  name        TEXT NOT NULL,
  lat         REAL,
  lon         REAL,
  water_type  TEXT,            -- 水库 / 野河 / 湖泊 / 黑坑 / 其他（自由文本）
  note        TEXT,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_fishing_spots_user
  ON fishing_spots(user_id, updated_at DESC);

-- 渔获日记：一次出钓一条（或一条鱼一条，由用户自己决定）。照片可选，
-- 客户端压缩后以 JPEG 字节存库（单张上限见 fishing.MaxPhotoBytes）。
CREATE TABLE IF NOT EXISTS fishing_catches (
  id          INTEGER PRIMARY KEY,
  uuid        TEXT NOT NULL UNIQUE,
  user_id     INTEGER NOT NULL REFERENCES users(id),
  caught_at   INTEGER NOT NULL,          -- 毫秒
  species     TEXT NOT NULL,
  count       INTEGER NOT NULL DEFAULT 1,
  weight_g    INTEGER,                   -- 总重（克），可空
  length_cm   REAL,                      -- 最大一条体长，可空
  spot_uuid   TEXT,                      -- 关联私人钓点（可空）
  spot_name   TEXT,
  lat         REAL,
  lon         REAL,
  method      TEXT,                      -- 台钓 / 路亚 / 海竿 / 其他
  bait        TEXT,
  weather     TEXT,                      -- 当时天气摘要（客户端带上出钓指数）
  note        TEXT,
  released    INTEGER NOT NULL DEFAULT 0,
  photo       BLOB,
  photo_mime  TEXT,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_fishing_catches_user
  ON fishing_catches(user_id, caught_at DESC);

-- 拍照识鱼：request_id 由客户端生成，(user_id, request_id) 唯一 → 重试不重复扣费。
-- status: pending（已扣费、识别中）/ done / failed（已退款）。
CREATE TABLE IF NOT EXISTS fishing_identifications (
  id          INTEGER PRIMARY KEY,
  user_id     INTEGER NOT NULL REFERENCES users(id),
  request_id  TEXT NOT NULL,
  status      TEXT NOT NULL,
  credits     INTEGER NOT NULL,
  refunded    INTEGER NOT NULL DEFAULT 0,
  result_json TEXT,
  error       TEXT,
  created_at  INTEGER NOT NULL,
  updated_at  INTEGER NOT NULL,
  UNIQUE (user_id, request_id)
);
