# 喜爱（喜 AI）

一款面向中国个人投资者的 AI 投研助理。**它的主入口之一不是找策略，而是证伪策略。**

App 有四个页签：

| 页签 | 做什么 |
|---|---|
| 对话 | 用自然语言问具体问题（某只股票、某个板块、某条信号），助理调用真实行情 / 财报 / 新闻 / 量化工具回答 |
| 策略 | **证伪台**：先过尺度闸门（往返成本 ÷ 平均振幅），再让策略过样本 / 分年 / 回撤 / 参数稳健性四道闸门；结论允许是「零条可以实盘」 |
| 发现 | 第二梯队功能的归档页（照微信）：定时提醒、组合管理、AI 直播、鹦鹉螺预测 |
| 我的 | 喜点余额与流水、自选、账号与条款 |

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

名称「喜爱」谐音「喜 AI」。视觉世界是**纸上墨金**：纸底 + 墨字 + 墨金主色，
结构学微信、材质学微信读书。完整规则见 [DESIGN.md](DESIGN.md)，
产品事实见 [PRODUCT.md](PRODUCT.md)。

图标不走设计工具，走矢量流水线，可复现：

```bash
python marketing/logo/tools/outline_glyph.py          # 汉字 → 矢量轮廓
powershell -ExecutionPolicy Bypass -File marketing/logo/build-xiai.ps1
flutter pub run flutter_launcher_icons                # 生成 iOS / Android / Web 图标
```

## 埋点

接 [Umami](https://umami.is)（开源，可自托管，也有免费云额度）。纯 HTTP 上报，
不引入任何原生依赖，因此不影响 iOS / Android 打包。`lib/services/analytics.dart`
里列了关键路径的事件名：开屏 → 页签 → 证伪台 → 成本尺 → 档案 → 登录 → 充值成功。

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

设计走查用真实渲染截图核对，不靠猜：

```bash
flutter build web --release --dart-define=INITIAL_TAB=1 --dart-define=SPLASH_MS=4200
python -m http.server 8777 --directory build/web
python tools/design-qa/shoot_web.py --out .impeccable/shots
```

`--dart-define=INITIAL_TAB=1` 让 App 直接落在证伪页签（默认 0 = 对话），
`SPLASH_MS` 拉长开屏以便截图。两者都只影响本地走查。

发版：push 到 `main` 会自动打包并在 iOS 上传 TestFlight。动手前先看
[`.agents/skills/app-release-build/SKILL.md`](.agents/skills/app-release-build/SKILL.md)
里的版本号闸门。

## 免责

证伪台是研究结论，不是投资建议。回测不含冲击成本、涨跌停无法成交、盘中流动性
枯竭等实盘约束；历史表现不代表未来收益。
