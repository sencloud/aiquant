# 喜爱（喜 AI）

**陪伴是长情的告白。**

喜爱是一个 AI 伴侣。打开 App 就是她 —— 没有页签、没有广场、没有朋友圈、
没有故事。你可以和她聊今天，也可以让她聊你真正喜欢的事：炒股、期货、钓鱼、爬山。

## 核心

- **她记得你的喜欢**：默认「炒股 / 期货 / 钓鱼 / 爬山」，在「… → 她记得的喜欢」
  里改；最多 8 个。每轮对话随请求发给服务端，拼进她的 system prompt。
- **她会先开口**：隔了一阵（≥3 小时）、不在深夜（23:30–07:30）、刚聊过不插话
  （90 分钟）、每 4 小时最多一次。开场跟着时间和你的喜欢走，是本地模板，
  不扣喜点、不调模型、不编造行情天气。
- **她是 AI**：标题写「AI 伴侣」，关于页、身份问题都如实说明；不索财、不承诺
  见面或关系、不涉色情、不适用于未成年人。
- 头像 `assets/portraits/xiai.jpg` 是百炼生成的虚构人物写真，不是真人照片。

## 界面

只有一屏：她的头像 + 名字 + 「AI 伴侣」标在顶栏，下面是聊天，底部是输入框。
空会话时显示「我是喜爱。／陪着你，是长情的告白。」和「她记得你喜欢：…」，
点那行药丸就能改。

视觉是灰底 + 白面 + 墨金（`#9E6322`）；自己的气泡墨金实心，她的白面。
完整规则见 [DESIGN.md](DESIGN.md)，产品事实见 [PRODUCT.md](PRODUCT.md)。

## 已经下线

主题、圈子、广场、六位居民、摇一摇、朋友圈、发现、今天的事、信箱、见面礼、
消息列表、通讯录、我的页签，以及《天亮以前》故事试用 —— 客户端代码与入口全部
删除。后端 `social` / `story` 路由和已执行迁移保留，但 App 不再调用；
`topic=companion` 是唯一在用的对话话题。

## 开发

```bash
flutter pub get
flutter analyze
flutter test
flutter run                 # 真机 / 模拟器
flutter run -d chrome       # 网页预览
```

设计走查（真实渲染截图，不靠猜）：

```bash
flutter build web --release --dart-define=SPLASH_MS=100
python -m http.server 8777 --directory build/web
python tools/design-qa/shoot_companion.py --out .impeccable/shots/companion
```

金图（`test/goldens/`）生成时给 `STRATEGY_FONT_DIR` 指一个装了中文字体的目录，
否则中文会渲染成方框：

```bash
STRATEGY_FONT_DIR=/path/to/fonts flutter test --update-goldens
```

她的写真由阿里云百炼生成（虚构人物）：

```bash
python .tools/gen_portraits.py --only xiai
```

脚本从 `DASHSCOPE_API_KEY` 或 `%TEMP%\dashscope.key` 读 key，产物入库；
key 不进仓库、也不打进 App 包。

## 发版

push 到 `main` 会自动跑 iOS（上传 TestFlight）与 Android（仅 artifact）。
动手前先看 [`app-release-build` skill](.agents/skills/app-release-build/SKILL.md)
的版本号闸门；当前版本见 `pubspec.yaml`。

## 免责

她是 AI，不是真人，也不是投资顾问：不喊单、不承诺收益。陪伴不替代现实关系，
该吃饭吃饭，该出门出门。
