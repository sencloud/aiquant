# 喜爱 · App Store 提交材料（v1.1.0）

> App ID 6770043388 · Bundle ID `com.aiquant.app` · 版本 1.1.0 · 主要语言 / 店面：简体中文 · 中国大陆  
> 依据：main @ 815061d 的代码与线上数据（2026-10-11 核对）。字数为 Python `len()` 实算，Apple 按字符计（一个汉字 = 1）。  
> 当前线上：「喜宽」1.0.5（2026-07-04 上架；主类别「财务」、次类别「工具」；17+；含「无限制网页访问」；iPhone + iPad）。

## ⚠️ 先看：提交前的阻断项

1. **ICP / App 备案名称**：中国大陆店面要求「App 信息」里的名称等元数据与工信部 App 备案一致。现有备案大概率登记的是「喜宽」，所以改名「喜爱」前要先在接入商（阿里云备案系统）做 **App 备案变更**（改 App 名称），拿到变更后的结果再在 App Store Connect 改名、核对 ICP 备案号。网站备案号是 苏ICP备2025174962号（www 页脚），App 备案号格式一般是 `苏ICP备2025174962号-xA`，请到 ASC「App 信息 → ICP 备案号」核对。
2. **生成式 AI 合规**：国内应用商店对 AI 生成类 App 越来越常要求提供所接入大模型的「算法备案 / 大模型备案」材料（接入第三方模型时提供合作方备案号 + 合作协议）。示例配置用的是 DeepSeek；请确认线上实际用的模型服务商，并准备好对方的 **网信算备** 编号，以备审核索要。App 内已有显式标识「内容由 AI 生成，注意核实」。
3. **演示账号**：已定方案 A，审核员用「使用 Apple 账号登录」（Sign in with Apple）自建账号，不提供后台演示账号；审核备注已写好（见 §9、§12）；ASC「登录信息」取消勾选「需要登录」。

## 1. App 名称（≤30）

| 方案 | 文本 | 字数 |
|---|---|---|
| 首选 | 喜爱 | 2 / 30 ✅ |
| 备选 1（「喜爱」被占用时） | 喜爱 - 钱与钓鱼的AI助手 | 14 / 30 ✅ |
| 备选 2 | 喜爱AI | 4 / 30 ✅ |

说明：App 名称全店唯一。两个字的「喜爱」很可能已被别的 App 占用，ASC 会在保存时提示。不论用哪个，都要和 App 备案里的名称一致（见阻断项 1）。App 内显示名（CFBundleDisplayName）已经是「喜爱」，商店名用备选也没问题。

## 2. 副标题（≤30）

- **AI 投研助手 · 出钓指数 · 渔获日记** — 21 / 30 ✅
- 备选：喜爱，并不是一定要得到 — 11 / 30 ✅（品牌感更强，但不带搜索词）

## 3. 推广文本（≤170，可随时改，不需要送审）

```
喜爱钱：行情、财报、资金流，开口就问；喜爱钓鱼：出钓指数、私人钓点地图、渔获日记。一句话做个小应用放到发现页，数据自动更新。新用户注册即送喜点。
```
字数：72 / 170 ✅

## 4. 描述（≤4000）

```
喜爱 —— 喜爱，并不是一定要得到。

一个 App，装着你喜爱的事。现在有两个主题：「喜爱钱」和「喜爱钓鱼」。随时在「我的 → 切换主题」里换，账号和喜点两边通用。

【喜爱钱 · AI 投研助手】
· 开口就问：A 股、美股、全球指数、外汇、期货、期权行情；估值、财报、十大股东、分红；融资融券、北向资金、行业资金流。AI 自动调取数据，给出有数据支撑的回答。
· 帮你算：收益率、夏普比率、最大回撤、相关性、Beta、均线、RSI、MACD 等常用指标直接算，还能回测 ETF 轮动。
· 资讯与事件：中文财经新闻、全球事件、行业与航运动态、经济日历，一并整理。
· 定时提醒：设好时间，让 AI 按点执行任务，结果推送给你。

【喜爱钓鱼 · 出钓好帮手】
· 出钓指数：按气压、风、气温、降水、月相五项打分，给出今天到后天的指数，以及清晨、傍晚的好时段。
· AI 钓友：哪天去、几点到、怎么钓，结合天气直接问。
· 私人钓点地图：把常去的钓点存在地图上，只有你自己能看到，一键导航过去。
· 渔获日记：记下鱼种、条数、重量、长度、钓法、饵料和照片，标记放流，自动统计。

【发现页 · 小应用】
用一句话说出想看的东西，AI 帮你做成一个小应用，放到发现页，数据自动更新。也可以从官方模板一键添加，例如：
· 品种价差监控：两个期货主力合约的价差、60 日均值与偏离
· ETF 定投计算器、棕榈油早报
· 常去水库对比：几个水库未来 3 天的出钓指数并排看
· 饵料配比计算器、本月渔获统计
小应用由 App 内置的原生组件显示，不下载、不执行任何代码。

【喜点】
AI 对话、新建和修改小应用会消耗喜点；出钓指数和钓点地图免费。小应用没做出来，喜点全额退回。新用户注册即送喜点，邀请好友双方各得喜点，也可以在 App 内购买。喜点各主题通用。

【隐私】
· 没有广告，不跨 App 追踪。
· 位置只在使用 App 时获取，用于出钓指数和钓点地图；不在后台定位，不记录行踪。
· 对话、钓点、渔获只属于你的账号。可随时在「我的 → 账号与条款 → 注销账号」删除账号和数据。

【提示】
行情数据与 AI 生成的内容仅供学习和研究参考，不构成投资建议。投资有风险，决策需谨慎。
出钓指数只根据天气打分，仅供参考。请遵守当地禁渔、禁钓规定，注意水边安全。

问题与建议：plan9@qq.com
```
字数：1004 / 4000 ✅

依据：工具清单 `backend/internal/ai/tools`（行情 / 财报 / 宏观 / 新闻事件 / 指标计算 / ETF 轮动回测）；出钓指数五项打分 `backend/internal/fishing`；小应用模板 `backend/internal/miniapp/templates`、受限表达式 `backend/internal/miniapp/xel`；喜点价格见设置页说明（AI 对话 1 喜点/轮、深度 +5；新建小应用 5、修改 2，失败退回）；隐私表述与 `backend/deploy/legal/privacy.html` 一致。没有提到已下线的功能（直播、鹦鹉螺、策略页、组合管理、我的自选、拍照识鱼、每日签到），因为每日签到在当前 UI 里已经没有入口。注册赠送和邀请奖励的具体数字由服务端配置决定，描述里只写「送喜点」，避免和线上配置对不上。

## 5. 关键词（≤100，英文逗号分隔、无空格）

```
量化,行情,股票,美股,期货,期权,外汇,ETF,财报,资金流,北向资金,定投,价差,盯盘,K线,AI助手,钓鱼,钓点,鱼情,天气,气压,路亚,台钓,野钓,水库,饵料,打窝,钓友,钓鱼天气
```
字数：94 / 100 ✅，共 29 个词。没有竞品名，也没有重复名称和副标题里的词（Apple 会自动索引名称和副标题）。没用「基金」「投资建议」「荐股」这类词，免得在国内审核时被当成证券投资咨询。

## 6. 此版本的新内容（What's New）

```
「喜宽」更名为「喜爱」：喜爱，并不是一定要得到。
· 新增「喜爱钓鱼」主题：出钓指数、AI 钓友、私人钓点地图、渔获日记
· 发现页新增小应用：一句话生成，或从官方模板一键添加，数据自动更新
· 新增邀请好友，双方各得喜点
· 注销账号时，一并删除你的小应用等全部数据
· 界面与稳定性优化
```
字数：143 / 4000

## 7. 类别

**建议：主类别「工具」（Utilities），次类别「生活」（Lifestyle）**（备选次类别：「体育」）。

- 现状是主类别「财务」。在中国大陆店面，「财务」类常被要求提供金融相关资质（证券 / 期货投资咨询、支付、借贷等许可），而 AI 讲个股、期货的内容本来就容易被往「证券投资咨询」上靠。1.1.0 已经是双主题，钓鱼和财经各占一半，继续挂「财务」会把审核注意力集中到最敏感的部分。
- 「工具」能如实覆盖 AI 助手、小应用和出钓指数；「生活」覆盖钓鱼和渔获日记。两个都不需要额外资质。
- **不要选「新闻」**：中国大陆店面的新闻类 App 需要网信办《互联网新闻信息服务许可证》。
- 代价：会退出「财务」榜单，失去那里的曝光。如果更看重财经流量，可以把「财务」放到次类别（审核风险比主类别小，但不是零）。

## 8. 年龄分级（2026 版问卷：4+ / 9+ / 13+ / 16+ / 18+）

| 问题 | 回答 | 依据 |
|---|---|---|
| App 内控制：家长控制 | 否 | 无 |
| App 内控制：年龄验证 / 年龄保障 | 否 | 无 |
| 能力：无限制网页访问 | **否**（现在线上标的是「有」，这次改掉） | App 内没有可浏览网页的 WebView（AI 直播已在编译期关闭，`ENABLE_LIVE` 默认 false，CI 也没开）；链接都用 `LaunchMode.externalApplication` 跳 Safari |
| 能力：用户生成内容（UGC） | 否 | 对话、钓点、渔获、小应用都只有本人可见；App 内看不到其他用户的内容。唯一例外是「分享」生成的单条问答网页（`/s/{id}`，不公开列出，只有拿到链接才能打开，在 App 外），已在审核备注里说明 |
| 能力：社交媒体（2026-09 起必答） | 否 | 没有信息流，也不能转发或放大其他用户的内容 |
| 能力：消息与聊天 | 否 | AI 对话不是用户之间的通讯 |
| 能力：广告 | 否 | 没有广告 SDK |
| 医疗或健康话题 | 无 |  |
| 暴力主题 / 卡通暴力 / 写实暴力 / 枪支 | 无 |  |
| 成人 / 不良主题：粗话、恐怖、酒精烟草药物 | 无 |  |
| 性内容或裸露 | 无 |  |
| 赌博 / 模拟赌博 / 竞赛 | 无 | 鹦鹉螺预测市场已下线（`kEnableNautilus`），新版里没有 |

照上面这样回答，算出来大概率是 **4+**。**建议用「调高至更高年龄分级」选 18+**，理由：隐私政策写的是「面向 17 岁以上用户」，新分级没有 17+，16+ 又低于政策要求；同时有付费虚拟币和 AI 开放问答（Apple 要求把 AI 聊天出现敏感内容的概率算进去）。如果选 18+，建议之后把隐私政策 §6 改成「18 周岁以上」，两边保持一致（这次没有改）。

## 9. 演示账号（已定：方案 A，Sign in with Apple）

审核员需要登录后才能测：AI 对话、新建小应用、渔获、私人钓点、内购、注销账号。现状：
- 登录方式只有 **邮箱验证码**（Resend 发信）和 **通过 Apple 登录**；后端 `backend/internal/auth` 没有审核账号或固定验证码。
- 审核员收不到你邮箱里的验证码，所以邮箱方式没法直接给。

**✅ 已采用方案 A**：审核备注写明「请点『使用 Apple 账号登录』（Sign in with Apple）」。登录页按钮的实际文字是「使用 Apple 账号登录」，备注里照抄这个文字。新账号首次登录自动获赠 **60 喜点**（`backend/internal/onboarding/service.go` 的 `defaultSignupCredits = 60`，即 config `credits.signup_gift` 的默认值；线上 `/server/config/config.toml` 没有覆盖这一项，2026-10-11 只读核对过）。AI 对话 1 喜点/轮（深度 +5），新建小应用 5、修改 2，60 喜点足够测完全部功能。内购走沙盒：线上 `[apple_iap] environment = "auto"`（先查 production，查不到自动回落 sandbox），审核员的沙盒购买能正常到账。ASC「App 审核信息 → 登录信息」：审核员可以自己用 Sign in with Apple 注册，所以取消勾选「需要登录」，由审核备注第 2 条说明怎么登录。如果审核仍然索要演示账号，再按方案 B 处理。
**方案 B（备用，没有实施）**：准备一个专用审核邮箱（例如 `appreview@<你的域名>`），在服务端为这一个邮箱配置固定验证码（只认这个邮箱，可随时关），并预充大约 300 喜点、预置几条渔获和钓点。需要你提供：① 这个邮箱地址；② 同意在后端加「审核账号白名单 + 固定验证码」的配置项。ASC 的「登录信息」里填：用户名 = 该邮箱，密码栏填固定验证码，并注明「这是邮箱验证码登录，验证码固定为 xxxxxx」。

## 10. 网址（2026-10-11 从 box 实测，都返回 200）

| 字段 | URL | 状态 |
|---|---|---|
| 技术支持网址（必填） | https://api.singzquant.com/legal/support.html | 200 text/html |
| 营销网址 | https://www.singzquant.com/ | 200 text/html |
| 隐私政策网址（必填） | https://api.singzquant.com/legal/privacy.html | 200 text/html |
| 用户协议（可选，填在描述 / EULA） | https://api.singzquant.com/legal/terms.html | 200 text/html |

www.singzquant.com/legal/{privacy,support,terms}.html 也都是 200，两套地址都能用。建议用 api.singzquant.com 这一套，它和 App 内「用户协议 / 隐私政策」链接是同一个源。

## 11. 版权

```
© 2026 Minglei Chen
```
（开发者名是 Minglei Chen；如果之后以公司主体运营，改成公司名。）

## 12. App 审核备注（≤4000，英文写给审核员，界面名称保留中文）

```
Thank you for reviewing 喜爱 (formerly 喜宽). Version 1.1.0 renames the app and adds a second theme.

1. THEMES
On first launch the user picks a theme: 喜爱钱 (AI market-research assistant) or 喜爱钓鱼 (fishing helper). Switch any time: 我的 → 主题 → 切换主题. One account and one 喜点 balance across themes.

2. SIGN-IN (no demo account needed)
Please use Sign in with Apple: open any feature that needs an account (e.g. send a chat message, or 我的 → 登录 / 注册) and tap 「使用 Apple 账号登录」 with your review Apple Account ("Hide My Email" is fine). A new account gets 60 free 喜点 (credits) on first sign-in, enough to test every paid feature without buying (about 60 chat turns). Browsing, the fishing index and the spot map need no account. E-mail one-time-code sign-in needs mailbox access, so please use Apple.

3. LOCATION (When In Use only)
Used only in 喜爱钓鱼: (a) 出钓 tab → locate button: fishing index for your area (sent to our server rounded to ~1 km); (b) 钓点地图: show your position and save a private spot (exact coordinates stored only for spots the user saves). No background location, no movement history. Denying location still works: type a place name (e.g. 千岛湖).

4. IN-APP PURCHASE (consumable 喜点 credits)
我的 → 喜点余额 → 充值. Four consumables: com.aiquant.app.credit60 / credit500 / credit1000 / credit5000. 喜点 pay for AI chat turns (1 per turn, deep mode +5) and creating (5) / editing (2) a mini-app; failed mini-app builds are refunded automatically. The fishing index and spot map are free. No subscriptions, no external payment links.
Sandbox: buy any package with a Sandbox Apple Account (not charged). The server verifies the transaction with the App Store Server API (sandbox accepted), and the 喜点余额 rises right away (credit60 = +60).

5. ACCOUNT DELETION
我的 → 账号与条款 → 注销账号 → confirm (3-second countdown). Deletes the account and its content (chats, mini-apps, spots, catches). Purchase/ledger records are kept anonymised where required by law.

6. MINI APPS (Guideline 2.5.2)
发现 → ＋新建 or 官方模板. A mini app is a declarative JSON configuration (schema "xiai.miniapp/1": layout components such as text, stat, table, chart and input, bound to a fixed server-side registry of data sources). It is rendered by native Flutter widgets that ship in the binary. Derived fields (e.g. a price spread or a rainfall total) use a tiny built-in expression language: literals, operators, member access, ternary and a whitelist of pure functions; no loops, assignment, user-defined functions, network or storage access, with hard limits on length, depth and steps. No executable code is downloaded or run, there is no web view, and a mini app cannot change app features or call APIs outside the registry. Mini apps are private to their creator (no sharing or public listing).

7. AI-GENERATED CONTENT
Answers come from licensed third-party large-language-model APIs in mainland China plus market/weather data (Tushare, Open-Meteo, etc.). Every chat screen shows "内容由 AI 生成，注意核实", and the Terms state that AI output is for reference only and is not investment advice. The app does not execute trades, hold funds, or give individual investment advice. There is no user-to-user messaging and no public feed. The optional share button creates an unlisted web page of a single Q&A (reachable only via its link, outside the app); nothing user-created is shown to other users inside the app.

8. OTHER
No ads, no tracking (ATT not used). Push notifications are only used for reminders the user schedules (定时提醒). Links in AI answers open in Safari (external).
Privacy: https://api.singzquant.com/legal/privacy.html  Terms: https://api.singzquant.com/legal/terms.html
Contact: plan9@qq.com
```
字数：3651 / 4000。登录按方案 A（§9）写好了，可以直接粘贴。

## 13. App 隐私（营养标签）

**是否用于追踪：否**（`NSPrivacyTracking` = false，不用 ATT，没有广告和第三方追踪）。

| 类别 | 数据类型 | 是否关联用户 | 用途 | 依据 |
|---|---|---|---|---|
| 联系信息 | 电子邮件地址 | 关联 | App 功能 | 邮箱验证码登录（加密存储） |
| 标识符 | 用户 ID | 关联 | App 功能 | 账号 ID；Sign in with Apple 的 sub |
| 标识符 | 设备 ID | 关联 | App 功能、分析 | App 生成的随机设备标识（登录 / 推送注册时上送）、推送令牌（隐私政策 §5）；Umami 匿名统计另用一个随机 ID。都不是 IDFA / IDFV。已在 PrivacyInfo.xcprivacy 声明 |
| 购买 | 购买历史 | 关联 | App 功能 | 喜点充值记录 |
| 位置 | 精确位置 | 关联 | App 功能 | 仅用户主动保存的私人钓点坐标 |
| 位置 | 粗略位置 | 不关联 | App 功能 | 出钓指数：约 1 km 精度发往服务器 |
| 用户内容 | 照片或视频 | 关联 | App 功能 | AI 对话附图、渔获照片 |
| 用户内容 | 其他用户内容 | 关联 | App 功能 | AI 对话（含主动分享的问答）、定时提醒、渔获、钓点、小应用、可选昵称 |
| 使用数据 | 产品交互 | 不关联 | 分析 | Umami 匿名页面统计（随机设备标识，不关联账号） |
| 诊断 | 崩溃数据 | 不关联 | App 功能 | 崩溃 / 错误信息 |

不勾选：姓名（昵称可选，归到「其他用户内容」）、电话号码、通讯录、健康、财务信息（不收集银行卡或资产；喜点购买走 Apple）、浏览记录、搜索记录、敏感信息、音频（没有麦克风权限）。服务器 IP 日志（≤30 天）只用于安全，不算问卷里的类别。和 `ios/Runner/PrivacyInfo.xcprivacy`（main @ 815061d）逐项对照过，一致。必需理由 API：UserDefaults（CA92.1）、文件时间戳（C617.1）已声明；没有用到系统启动时间、磁盘空间、活动键盘。

## 14. 出口合规（加密）

- Info.plist 已设置 `ITSAppUsesNonExemptEncryption = NO`，上传构建后 ASC 不会再问。
- 如果被问到：「App 是否使用加密？」→ 只使用操作系统提供的标准加密（HTTPS/TLS、钥匙串），属于豁免范围，**不需要上传出口合规文件**；不在法国分发特殊加密，不涉及法国申报。

## 15. App 内购买项目（消耗型；产品 ID 和价格已和线上 `/v1/credits/skus` 核对一致）

| 产品 ID | 后端 code | 价格 | 到账 | 显示名称（≤30） | 描述（≤45） |
|---|---|---|---|---|---|
| `com.aiquant.app.credit60` | credit_60 | ¥6 | 60 = 60 | 60 喜点（5） | 用于 AI 对话与小应用，各主题通用（18） |
| `com.aiquant.app.credit500` | credit_500 | ¥28 | 500 + 50 = 550 | 550 喜点（含赠送 50）（14） | 用于 AI 对话与小应用，各主题通用（18） |
| `com.aiquant.app.credit1000` | credit_1000 | ¥58 | 1000 + 200 = 1200 | 1200 喜点（含赠送 200）（16） | 用于 AI 对话与小应用，各主题通用（18） |
| `com.aiquant.app.credit5000` | credit_5000 | ¥298 | 5000 + 1500 = 6500 | 6500 喜点（含赠送 1500）（17） | 用于 AI 对话与小应用，各主题通用（18） |

- 类型：消耗型（Consumable）。价格请在 ASC 选择对应的人民币价格点（¥6 / ¥28 / ¥58 / ¥298）。
- 每个内购项目的「审核截图」可以都用 `iap_review/09_iap_sheet.png`（充值弹层，1320×2868）。
- 审核备注（每个 IAP 填同一段）：`喜点用于 AI 对话（1 喜点/轮）和新建/修改小应用。入口：我的 → 喜点余额 → 充值。`
- 如果 IAP 状态是「需要元数据」或「准备提交」，要和 1.1.0 一起提交（勾在版本页的「App 内购买项目和订阅」里）。

## 16. 截图

见同目录 `README.md`（截图清单、钓点地图真机截图步骤、上传说明）。iPhone 6.9" 7 张 + 钓点地图 1 张（待真机截图）；iPad 13" 7 张 + 地图 1 张（待截）。

## 17. 准备材料时发现的问题

前四条已在 PR #20（main @ 815061d，TestFlight build 202）修复并上线后端：

- ✅ **按住说话**：对话输入框占位文字改成「发消息…」。全仓库没有麦克风 / 语音识别权限文案，不用删。截图 02、07 已重拍。
- ✅ **PrivacyInfo.xcprivacy**：补声明「设备 ID」（关联、不追踪，用途 App 功能 + 分析），§13 表格已同步。必需理由 API 核对过，原有声明齐全。
- ✅ **棕榈油早报**：图表 Y 轴整条轴统一单位、按刻度步长定小数位，不会再出现两个「1万」；小应用新闻源（news.cn）剔除「或在18个月内上涨30%-40%」「目标价…」「稳赚」这类预测涨幅 / 目标价 / 收益承诺标题，规则写在 `backend/internal/miniapp/news_filter.go`。线上复核：早报要闻已没有这条。第 4 张截图仍用「品种价差监控」（早报的要闻是几个月前的旧新闻，不适合放商店）。
- ✅ **禁渔期按地点**：出钓指数按坐标判省份，只提示该省涉及的流域禁渔期。线上复核：千岛湖 `active_bans` 为空（以前返回长江 + 黄河）；武汉只返回长江十年禁渔；西宁返回长江 + 黄河上游。
- 千岛湖的地理编码（Open-Meteo）落在 28.61N 119.29E（丽水一带），真实湖区约 29.6N 119.0E。同在浙江，禁渔判断不受影响，但天气取点偏南约 110 km；之后可以给常用钓点加内置坐标。
- iPad 上是手机布局横向拉伸（1032pt 宽、没有最大宽度限制），iPad 截图如实呈现，留白多、字偏小。已上架的 App 不能取消 iPad 支持，后续可以给主要页面加最大内容宽度。
- 隐私政策写「面向 17 岁以上用户」，新年龄分级里没有 17+（见 §8）。

