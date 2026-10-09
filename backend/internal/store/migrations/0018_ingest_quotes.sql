-- 本机采集端推上来的行情缓存（RPA 中转）。
--
-- 为什么要落库而不是只放内存：服务的 api 进程与 scheduler 进程是分开的，
-- 采集端只推给 api；DING / 直播这类在 scheduler 里跑的 AI 任务同样需要实时价。
-- 落库后两个进程都能读到同一份最新行情。
CREATE TABLE IF NOT EXISTS ingest_quotes (
  symbol      TEXT PRIMARY KEY,
  payload_json TEXT NOT NULL,
  received_at INTEGER NOT NULL
);
