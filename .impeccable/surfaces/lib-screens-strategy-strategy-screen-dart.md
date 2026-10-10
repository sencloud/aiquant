---
version: 1
slug: "lib-screens-strategy-strategy-screen-dart"
primary_target: "lib/screens/strategy/strategy_screen.dart"
related_targets: []
---

# 证伪台（策略页签）

- **模式**：Operate。访客来做一个判断 —— 这套策略能不能实盘。
- **范围**：`lib/screens/strategy/` 三个文件（证伪台主屏、证伪详情、实盘策略），
  以及它依赖的设计系统（`lib/theme/app_theme.dart`、`lib/widgets/wk_kit.dart`）。
- **受众**：中国 A 股 / 期货的个人投资者。他们每天被「胜率 80%」「稳赚」这类
  文案轰炸，缺的不是又一个策略，而是一个敢说「不行」的地方。
- **任务**：先过尺度闸门（往返成本 ÷ 平均振幅），再让策略过样本 / 分年 / 回撤 /
  参数稳健性四道闸门；任何一条不过，结论写「不行」并写清为什么不行。
- **内容与证据**：本机 alpha-radar 工程的真实产出 —— 15 行按品种 × 周期算出的
  成本占比、8 条带分年与失败机制的证伪记录、每条附可复现命令。
- **约束**：不要求登录（证伪结论是获客内容）；不得虚构任何数字；涨跌色沿用国内
  惯例（红涨绿跌），所以品牌主色刻意不取绿；数据离线可用。
- **未决**：真订阅商品（App Store Connect 建品 + 后端 SKU）尚未落地，
  当前转化路径指向已有的喜点充值。

## Direction contract

**THESIS**：这个页面只做一件事 —— 证明什么不行。它拒绝的是「先给一条漂亮曲线、
再补一段免责声明」的行业默认排版；结论句排在最前，且允许结论是零。

**OWN-WORLD**：纸上墨金。纸底 `#F3F0E8`、白面分组卡 14 圆角、发丝线
`#E7E2D6`、墨 `#1F1C17`、品牌墨金 `#9E6322`。构件是 `WkPage / WkGroup / WkRow /
WkTag / WkStat / WkNote`：页面是纸，内容是卡，卡内是行，行靠发丝线分。
条目与数字用等宽字形，标题与结论句用平台衬线。

**STORY**：访客先读到一句判断（八条记录，零条可以实盘），再用成本尺亲手把
1 分钟周期判死，然后顺着档案理解每一条「为什么不行」。离开时他知道这个产品
敢说不行 —— 这正是他愿意付费的理由。

**FIRST VIEWPORT**：导航栏居中「证伪台」→ 结论卡（衬线大字一句判断 + 一行计数
+ 一句立场）→ 尺度闸门卡（品种 chip、周期 chip、成本与振幅两条横杠、占比大数
与判定）。主动作是选品种 / 换周期，签名的成本尺就在闸门卡中央。

**FORM**：用户 brief 直接钉死了世界（「参考微信、微信读书」），因此没有跑
concept-seed，方向由 brief 决定（seed: n/a，brief-pinned）。结构取自微信的
分组列表，材质取自微信读书的纸面。

**FINISH**：`flutter analyze` 不新增任何问题；关键屏以浏览器真实渲染截图核对
（`tools/design-qa/shoot_web.py`）；收尾产出 DESIGN.md 与 PRODUCT.md 更新。
