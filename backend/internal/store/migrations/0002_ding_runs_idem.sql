-- B4 ReportRun 幂等：弱网客户端可能多次重试同一次执行结果的上报，
-- 为同一 task_id + started_at 联合唯一兜底。
-- (task_id, started_at) 已经有非唯一 idx_runs_task；这里加唯一索引；
-- 如果历史数据里已存在重复行，唯一索引建表会失败 — 因此先用 GROUP BY 去重。

-- 1) 找出每个 (task_id, started_at) 的第一行（最小 id），删除其它重复行
DELETE FROM ding_runs
WHERE id NOT IN (
  SELECT MIN(id) FROM ding_runs GROUP BY task_id, started_at
);

-- 2) 建立联合唯一索引
CREATE UNIQUE INDEX IF NOT EXISTS uq_ding_runs_task_started
  ON ding_runs(task_id, started_at);
