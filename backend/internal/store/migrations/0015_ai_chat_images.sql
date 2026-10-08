-- 多模态：user 消息可携带图片。
--
-- images_json 存一个 data URL 数组（["data:image/jpeg;base64,..."]），
-- 每次重建 LLM 上下文时按 OpenAI 多模态格式重新拼进 content 片段数组。
-- 正文仍留在 content 列，方便标题/检索/客户端展示。
ALTER TABLE ai_chat_messages ADD COLUMN images_json TEXT;
