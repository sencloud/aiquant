-- 证伪档案快照去重：只有内容变化才新增一行，未变化只刷新 checked_at。
-- 全部为新增列，不改动已有数据；旧行的 content_hash 为空，下次同步时回填。
ALTER TABLE falsification_snapshots ADD COLUMN content_hash  TEXT NOT NULL DEFAULT '';
ALTER TABLE falsification_snapshots ADD COLUMN etag          TEXT NOT NULL DEFAULT '';
ALTER TABLE falsification_snapshots ADD COLUMN last_modified TEXT NOT NULL DEFAULT '';
ALTER TABLE falsification_snapshots ADD COLUMN checked_at    INTEGER NOT NULL DEFAULT 0;
