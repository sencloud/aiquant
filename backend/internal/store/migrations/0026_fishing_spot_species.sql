-- 私人钓点地图：钓点加「主要鱼种」（可选，自由文本，如「鲫鱼、翘嘴」）。
--
-- 坐标一律存 WGS-84（GPS 原始坐标系）；Apple 地图在中国大陆显示用的 GCJ-02
-- 由客户端在显示 / 取点时换算，库里不存第二套坐标。
-- 迁移只由 api 进程执行（scheduler / pusher 只等待），ALTER 不会被并发重复执行。
ALTER TABLE fishing_spots ADD COLUMN species TEXT;
