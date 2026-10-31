# 喜AI

一个只做股票、期货 K 线的 Flutter 行情终端。打开 App 直接进入图表，
没有登录、开屏、页签或其它业务入口。

## 功能

- 搜索 A 股和国内期货合约；
- 5 分钟、15 分钟、1 小时、1 天、1 周、1 月六种周期；
- 自绘 K 线、MA5 / MA10 / MA20、成交量和右侧价格轴；
- 动态支撑区间 S1 / S2、阻力区间 R1 / R2；
- 单指平移、双指捏合缩放、长按十字光标、双击复位；
- 从十字线位置开始逐根回放，未来 K 线灰显，支撑阻力同步重算；
- 记住最后选择的品种和最近查看记录。

## 数据

行情来自 Tushare Pro：

| 周期 | 股票 | 期货 |
|---|---|---|
| 5 / 15 / 60 分钟 | `stk_mins` | `ft_mins` |
| 1 天 | `daily` | `fut_daily` |
| 1 周 / 1 月 | 日线本地聚合 | 日线本地聚合 |

分钟接口需要 Tushare 账户具备相应权限。周线和月线不依赖额外接口。

## 开发

```bash
flutter pub get
flutter analyze
flutter test
```

主要入口：

- `lib/screens/watch/watch_screen.dart`：唯一首页；
- `lib/screens/watch/widgets/trading_candle_chart.dart`：交互式 K 线；
- `lib/services/tushare_service.dart`：行情数据；
- `lib/services/market_levels.dart`：支撑阻力分析。

产品与视觉规则见 [PRODUCT.md](PRODUCT.md) 和 [DESIGN.md](DESIGN.md)。

## 发版

iOS 以 TestFlight 为主发通道。push 到 `main` 会触发 iOS / Android 构建，
动手前先看 [`app-release-build` skill](.agents/skills/app-release-build/SKILL.md)
的版本号闸门；当前版本见 `pubspec.yaml`。

## 免责

支撑阻力是基于历史价格结构的可视化辅助，不是预测，也不构成投资建议。
