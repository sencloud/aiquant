# 喜爱（喜 AI）

一款面向中国个人投资者的 AI 投研助理。界面与交互按**微信**那一套重做（1.4.0），
App 的名字不变，承诺不变：**喜爱，并不是一定要得到**。

App 有四个页签，照微信：

| 页签 | 做什么 |
|---|---|
| 消息 | 会话列表（首屏）。点一行进聊天页：助理调用真实行情 / 财报 / 新闻 / 量化工具回答 |
| 广场 | 交友那半边：六位标明的 AI 居民（林夏 / 苏予 / 安可 / 周牧 / 陈野 / 路遥）、在线状态、摇一摇；点一个人进资料页，打个招呼就开聊 |
| 发现 | 第二梯队：今天的事、信箱、见面礼 · 定时提醒、我的小应用 |
| 我 | 喜点余额与流水、邀请好友、账号与条款 |

聊天是**二级页**（左上角返回、标题是助手名 + AI 标、右上角「…」），
气泡左右分色，输入栏左边「＋」右边「发送」—— 与微信逐处对齐。

**主题与圈子已经整块拿掉** `[决定]`：不再有选主题页、切换主题、整屏换色，
也没有兴趣圈。现在只有「今晚在这儿的人」—— 广场 + 朋友圈。真人的池子还没开，
广场上全是标明的 AI 居民，真人区照实写「内测中」。

## 设计语言

「微信的骨架 + 墨金的肤色」：灰底 `#EDEDED`、白面列表、居中标题、一条发丝线收边；
主色仍是喜爱的墨金 `#9E6322`，只用在选中态 / 主动作 / 自己的气泡上。涨跌语义色独立
（涨红 `#FA5151`、跌绿 `#17864E`）。完整规则见 [DESIGN.md](DESIGN.md)，
产品事实见 [PRODUCT.md](PRODUCT.md)。

## 证伪台

定位来自本机的 [alpha-radar](../alpha-radar) 工程（策略雷达）：**它不是策略
生成器，是策略证伪器。** 量化研究里 90% 的工作量在否定，而不是在发现。

页面上的两类内容：

1. **尺度闸门（成本尺）** —— 一屏把「往返成本 ÷ 平均振幅」画成两条可比的横杠。
   换品种 / 换周期，占比与判定立刻跟着变。棕榈油 1 分钟是 57.7%，直接淘汰；
   5 分钟 22.2%，才轮到后面的闸门。
2. **证伪档案** —— 每条记录给出结论、关键数字、分年盈亏、失败机制和一条可复现
   命令。当前 8 条里 0 条可实盘，这是结论本身，不是没做完。

### 数据是怎么来的

`assets/strategy/falsification.json` 由脚本离线生成，**不做任何网络请求**：

```bash
python tools/strategy-mvp/build_falsification_data.py \
    --alpha-radar D:/GitHub/alpha-radar
```

它读 alpha-radar 的 `data_cache`（Tushare 缓存的期货主力连续 5 分钟线 / 日线、
A 股日线），用 alpha-radar 自己的成本模型算出每个「品种 × 周期」的成本占比；
15 / 30 / 60 分钟由 5 分钟重采样。证伪档案里的数字取自 alpha-radar 的
`docs/findings.md`。

App 优先读内置资产（离线可用、首屏不等网络）；如果后端提供了
`GET /v1/strategy/falsification`（同一份 schema），会用远端覆盖本地，
这样补一条结论不用发版。

## 品牌

名称「喜爱」谐音「喜 AI」。视觉世界就是**微信**那一套（见上「设计语言」）；
图标不在本次重做范围内，仍是纸底 + 墨字「喜」+ 墨金四角星。

图标不走设计工具，走矢量流水线，可复现：

```bash
python marketing/logo/tools/outline_glyph.py          # 汉字 → 矢量轮廓
powershell -ExecutionPolicy Bypass -File marketing/logo/build-xiai.ps1
flutter pub run flutter_launcher_icons                # 生成 iOS / Android / Web 图标
```

## 埋点

接 [Umami](https://umami.is)（开源，可自托管，也有免费云额度）。纯 HTTP 上报，
不引入任何原生依赖，因此不影响 iOS / Android 打包。`lib/services/analytics.dart`
里列了关键路径的事件名：开屏 → 页签 → 对话 → 发现入口 → 登录 → 充值成功。

未配置就是 no-op：

```
UMAMI_HOST=https://cloud.umami.is
UMAMI_WEBSITE_ID=<在 Umami 新建网站后拿到>
```

`distinct_id` 是本地生成的随机 UUID，不带手机号 / 邮箱。

## 开发

```bash
flutter pub get
flutter analyze
flutter run                 # 真机 / 模拟器
flutter run -d chrome       # 网页预览（按手机尺寸看得更准）
```

### 天亮以前（二次元试用，默认关闭）

《喜爱 · 天亮以前》是「广场」那一半的二次元试用版：六位居民全部换成像素立绘，
七夜、三条路线、十个结局；当前这一刀先把林夏线跑通，聊天回复是本地脚本，
`/v1/story/chat` 的 AI 接口还没接。

```bash
# 直接把试用版当首页（走查 / 截图用）
flutter run -d chrome --dart-define=STORY_TRIAL_HOME=true

# 或在主 App「发现」里多一行入口，主 App 其它页面不动
flutter run --dart-define=ENABLE_STORY_TRIAL=true
```

试用版文案的中文字体是 Noto Sans SC 子集（`assets/fonts/`）。改完 `lib/story/`
文案后重跑一次，避免 Web 端漏字：

```bash
python tools/gen_story_font.py
```

设计稿与需求：[design/xiai-night/requirements.md](design/xiai-night/requirements.md)。

后端已接：

- `GET /v1/story/state`：当前故事线 + 消息 + 已解锁结局。
- `PUT /v1/story/runs/{id}`：保存进度（夜 / beat / 心级 / flags / 结局）。
- `POST /v1/story/runs/{id}/chat`：SSE 自由聊天，场景 prompt 在服务端拼。
- `GET /v1/story/config`：试用版远程开关（总开关 / 开放角色 / 分享 / 聊天上限 / 公告），公开读。
- `PUT /v1/admin/story/config`：用 `X-Admin-Key` 更新开关；不重启即生效（key 沿用 `[nautilus].admin_key`）。
- `0027_story.sql`：`story_runs` / `story_messages` / `story_endings`，随 api 启动迁移。
- `0028_story_config.sql`：`story_config` 单行配置；默认三条路线全开。

立绘终稿：把 6 × 6 张 PNG 按 [`assets/night/portraits/README.md`](assets/night/portraits/README.md)
的命名放进去，再给角色加 `artAsset` 前缀即可；缺图自动回落到代码绘制的试作。

设计走查用真实渲染截图核对，不靠猜：

```bash
flutter build web --release --dart-define=SPLASH_MS=100
python -m http.server 8777 --directory build/web
python tools/design-qa/shoot_wx.py --out .impeccable/shots/wx   # 消息 / 聊天 / 广场 / 朋友圈 / 发现 / 我
```

`--dart-define=INITIAL_TAB=0..3` 让 App 直接落在某个页签（0 消息 / 1 广场 /
2 发现 / 3 我），`SPLASH_MS` 拉长开屏以便截图。两者都只影响本地走查。
金图（`test/goldens/`）生成时给 `STRATEGY_FONT_DIR` 指一个装了中文字体的目录，
否则中文会渲染成方框：

```bash
STRATEGY_FONT_DIR=/path/to/fonts flutter test --update-goldens
```

广场的六张写真头像与朋友圈配图由阿里云百炼生成（虚构人物 / 场景，不是真人照片）：

```bash
python .tools/gen_portraits.py            # 头像 → assets/portraits/
python .tools/gen_portraits.py --scenes   # 朋友圈配图 → assets/moments/
```

脚本从 `DASHSCOPE_API_KEY` 或 `%TEMP%\dashscope.key` 读 key，产物入库；
key 本身不进仓库、也不打进 App 包。

发版：push 到 `main` 会自动打包并在 iOS 上传 TestFlight。动手前先看
[`.agents/skills/app-release-build/SKILL.md`](.agents/skills/app-release-build/SKILL.md)
里的版本号闸门。

## 免责

证伪台是研究结论，不是投资建议。回测不含冲击成本、涨跌停无法成交、盘中流动性
枯竭等实盘约束；历史表现不代表未来收益。
