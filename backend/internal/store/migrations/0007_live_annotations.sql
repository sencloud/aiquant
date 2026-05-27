-- AI 直播 v2 增量：嘉宾发言「与 K 线共振」—— 结构化标注。
--
-- 需求：
--   嘉宾说「支撑 128 / 目标 145 / 止损 120」时，主图自动画出对应水平线
--   + label（如「林园·止损 120」），把人话和图形对齐，让观众一眼看到。
--
-- 实现：
--   * guest_speaker LLM 输出契约改为 JSON：{content, annotations: [...]}
--   * 每条 annotation = {type, price, label}
--       type: support / resistance / stop / target / note
--       price: 浮点价位
--       label: ≤ 8 字短标签（前端会拼 persona 名）
--   * 后端持久化在 live_messages.annotations 字段（TEXT，JSON 字符串）；
--     为空时表示该条发言只有文字、无价位标注（如纯宏观/纯方法论）。
--   * 前端拉到 message 后，把当前焦点的所有 annotations 累计推给 webview
--     的 JS hook（window.__setAnnotations）— 增量、无重载、无闪烁。

ALTER TABLE live_messages ADD COLUMN annotations TEXT;
