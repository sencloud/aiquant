# 嘻，AI

用成交记录截图复盘你的交易。上传一张券商 App 的成交记录截图，核对买卖、
数量、价格和手续费后，应用会按先进先出还原已平仓交易，告诉你实际呈现出的
交易逻辑、问题和改进措施。

一级页面只有两个：**嘻，AI** 和 **我的**。

## 手机端

- 从相册选择或拍摄成交记录截图；
- 识别成交行并逐行核对，可修改、删除或撤销删除；
- 输出已实现盈亏、胜率、盈亏比、持有时间、连续盈亏、手续费与集中度；
- 报告固定包含交易逻辑、问题、改进措施和样本限制；
- 复盘结果保存在本机，原截图不保存，默认最多保留 20 份；
- “我的”按微信式白面分组组织最近复盘、交易记录、看盘、电脑连接与隐私设置；
- “看盘”保留为“我的”里的二级工具，不占用一级页签。

## 电脑端接入

电脑端项目位于 `D:\workspaces\games\adb-desktop`。打开左侧“交易”分组里的
“交易复盘”后，可以：

1. 选择 PNG/JPEG 成交截图；
2. 在电脑端调用已配置的识图模型提取成交行；
3. 修改或删除识别错误的行；
4. 填写手机“我的 → 电脑连接”显示的地址和六位配对码；
5. 发送后，手机保存报告并自动打开。

电脑与手机需要处于同一 Wi-Fi，或连接同一个手机热点。手机接收服务只在
“电脑连接”页面打开期间运行。电脑端截图的识别请求会发往电脑上配置的识图
模型；手机只接收核对后的日期、方向、数量、价格与手续费。

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
- `lib/screens/trade_review/trade_desktop_connect_screen.dart`：局域网配对；
- `lib/screens/my/my_screen.dart`：微信式“我的”；
- `lib/services/trade_review_engine.dart`：配对、指标与结论；
- `lib/services/trade_screenshot_parser.dart`：手机识图接口；
- `lib/services/trade_desktop_server.dart`：手机接收电脑成交行。

产品和视觉规则见 [PRODUCT.md](PRODUCT.md) 与 [DESIGN.md](DESIGN.md)。

## 发版

iOS 以 TestFlight 为主发通道。push 到 `main` 会触发 iOS / Android 构建，
发版前先按 [`app-release-build` skill](.agents/skills/app-release-build/SKILL.md)
检查版本号与构建闸门；当前版本见 `pubspec.yaml`。

## 免责

复盘基于用户提供并核对后的成交记录，只用于整理交易行为和改进执行纪律，
不构成投资建议。
