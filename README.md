# 嘻，AI

用成交记录截图复盘你的交易。上传一张券商 App 的成交记录截图，核对买卖、
数量、价格和手续费后，应用会按先进先出还原已平仓交易，告诉你实际呈现出的
交易逻辑、问题和改进措施。

一级页面只有两个：**嘻，AI** 和 **我的**。

## 手机端

- 从相册多选成交记录截图（可一次选多张，自动合并相邻页重叠成交）；
- 识别成交行并逐行核对，可修改、删除或撤销删除；
- 输出已实现盈亏、胜率、盈亏比、持有时间、连续盈亏、手续费与集中度；
- 报告固定包含交易逻辑、问题、改进措施和样本限制；
- 复盘结果同步到登录账号，原截图不保存，默认最多保留 20 份；
- “我的”按微信式白面分组组织最近复盘、交易记录、看盘与设置；
- “看盘”保留为“我的”里的二级工具，不占用一级页签。

## 电脑端

电脑端项目位于 `D:\workspaces\games\adb-desktop`。打开左侧“交易”分组里的
“交易复盘”后，可以：

1. 使用邮箱验证码登录，选择已连接 ADB 的手机；
2. 启动手机上的大智慧，并打开“我的 → 历史成交 / 成交查询”；
3. 只截取当前可见页面并提取成交行，翻页后重新识别；
4. 修改或删除识别错误的行；
5. 生成并保存复盘，手机登录同一账号后即可查看。

电脑端不会读取或保存券商账户密码，不执行下单、撤单或转账。手机端不需要
开启电脑连接、局域网服务，也不需要输入配对码。

## 报告口径

- 卖出与买入按先进先出配对；
- 无法与截图内买入配对的卖出不计入已实现盈亏；
- 少于 3 笔已平仓卖出时，胜率和盈亏比只作初步观察；
- 截图没有账户总资金、仓位比例、入场理由或风险预算时，不推断这些信息；
- 不提供交易指令、收益预测或收益承诺。

## 开发

```powershell
flutter pub get
flutter analyze
flutter test --no-pub test/trade_review_engine_test.dart test/trade_review_report_test.dart test/xiai_shell_test.dart
```

主要入口：

- `lib/screens/shell/xiai_shell.dart`：双页签外壳；
- `lib/screens/trade_review/trade_review_home.dart`：截图上传与最近复盘；
- `lib/screens/trade_review/trade_confirm_screen.dart`：成交行核对；
- `lib/screens/trade_review/trade_report_screen.dart`：复盘报告；
- `lib/screens/my/my_screen.dart`：微信式“我的”；
- `lib/screens/settings/settings_screen.dart`：隐私、协议与关于；
- `lib/services/trade_review_engine.dart`：配对、指标与结论；
- `lib/services/trade_screenshot_parser.dart`：手机识图接口；

产品和视觉规则见 [PRODUCT.md](PRODUCT.md) 与 [DESIGN.md](DESIGN.md)。

## 发版

iOS 以 TestFlight 为主发通道。push 到 `main` 会触发 iOS / Android 构建，
发版前先按 [`app-release-build` skill](.agents/skills/app-release-build/SKILL.md)
检查版本号与构建闸门；当前版本见 `pubspec.yaml`。

## 免责

复盘基于用户提供并核对后的成交记录，只用于整理交易行为和改进执行纪律，
不构成投资建议。
