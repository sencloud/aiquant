# Fincept App (Flutter)

`flutter-app/` 是 [FINCEPT 终端](../fincept-qt) 的移动 / Web (H5) 简化版，
保留了原桌面应用里**最常用**的两块功能：

| Tab | 对应 Qt 模块 | 内置数据源 |
|:--|:--|:--|
| **助理** | `src/ai_chat/AiChatScreen` | DeepSeek（默认 `deepseek-reasoner` 深度模式） |
| **组合** | `src/screens/portfolio/PortfolioScreen` | Tushare Pro |

构建产物可同时分发到 **Android、iOS、Web (H5)**。

---

## 快速开始

> 仓库里没有打包 Flutter SDK 本身。请先安装 Flutter ≥ 3.22 + Dart ≥ 3.4
> 再执行下面的命令。

```bash
cd flutter-app

# 1) 一次性补齐 Flutter 自动生成的平台文件（Gradle wrapper、Xcode workspace、Web bootstrap 等）。
flutter create -t app --org io.fincept --project-name fincept_app .

# 2) 拉依赖
flutter pub get

# 3) 跑起来
flutter run                 # 自动选择已连接的设备
flutter run -d chrome       # Web (H5)
flutter run -d <android-id> # 真机 / 模拟器
flutter run -d <ios-id>     # iPhone / iPad

# 4) 发版构建
flutter build apk --release       # Android
flutter build appbundle --release # Android App Bundle
flutter build ios --release       # iOS（需在 macOS 上）
flutter build web --release       # Web 静态站点 → build/web/
```

> `flutter create` 会**保留**仓库里已写好的 `lib/`、`pubspec.yaml`、
> `android/app/src/main/AndroidManifest.xml` 等文件，仅补齐缺失的脚本和图标。

---

## 内置 token / API key

打开应用后，**首页就是 AI 助理**，并且默认走 DeepSeek 的深度模式
(`deepseek-reasoner`)。两组凭证均**编译期内置**，运行期可在“设置”覆盖：

| 用途 | 配置项 | 默认值 (源码) |
|:--|:--|:--|
| 行情 / 品种列表 | Tushare Pro Token | `lib/core/config/app_config.dart::BuiltInSecrets.tushareToken` |
| AI 助理 | DeepSeek API Key | `lib/core/config/app_config.dart::BuiltInSecrets.deepseekApiKey` |

源码里写的是 `PUT_YOUR_…_HERE` 占位串，请在打包前替换为真实凭证；
或在应用内 **设置 → DeepSeek / Tushare** 中粘贴，会优先用本地保存的值。

---

## 功能概要

### 助理 Tab（首页）
* DeepSeek SSE 流式回复，自动展示 `reasoning_content`（深度模式独有）。
* 多会话管理：左侧抽屉新建 / 重命名 / 删除，本地 Hive 持久化。
* 模式切换：`deepseek-reasoner`（深度）↔ `deepseek-chat`（普通）。
* 内置示例提问、Token 缺失提示、流式中断。

### 组合 Tab
* 顶部命令栏：新建 / 切换 / 删除组合，刷新行情。
* 统计带：组合市值、未实现盈亏、今日变化、持仓分布。
* **加入品种对话框**（关键功能）：
  * 4 个一级 Tab：`A 股 / ETF / 期货 / 指数`；
  * 高级筛选：交易所、行业 / 类别、关键字搜索；
  * 多选 → 弹出数量 + 均价确认对话框 → 批量入库。
* 10 个分析 Tab，结构对齐桌面版：
  1. **总览** — 走势图 + 行业环形图 + 持仓表格（多列排序、涨跌色）
  2. **行业** — 市值占比、盈亏贡献、资产类别分布
  3. **绩效 / 风险** — 累计收益、年化波动率、Sharpe、最大回撤、Top winners / losers
  4. **优化** — 等权 vs 反向波动 vs 当前权重对比
  5. **量化统计** — 收益率分布直方图、HHI、Top 3 集中度
  6. **报告** — Markdown / JSON 一键复制
  7. **交易** — 滑动删除的交易流水
  8. **风控** — 集中度告警 + 单标的风险热度图
  9. **规划** — 复利模拟（年化收益 / 期限 / 月供 滑块）
  10. **经济** — 沪深 300 等基准指数行情

### 平台
| 平台 | 状态 |
|:--|:--|
| Android | ✅ `min SDK 23` (Android 6+) |
| iOS | ✅ `min iOS 12` |
| Web (H5) | ✅ Chrome / Edge / Safari，支持 PWA 安装 |

> Tushare 接口走 `http://api.tushare.pro`，移动端 ATS / Cleartext 已放开；
> Web 部署若使用 HTTPS 反代，建议把 Tushare 端点改成 HTTPS（自建网关或私有代理）。

---

## 目录结构

```
flutter-app/
├── lib/
│   ├── main.dart                       # 入口（Hive + Provider 初始化）
│   ├── app.dart                        # MaterialApp + 主题
│   ├── theme/app_theme.dart            # Bloomberg 风格深色主题
│   ├── core/
│   │   ├── config/app_config.dart      # 内置 token + 设置覆盖
│   │   ├── storage/hive_setup.dart
│   │   └── utils/china_market.dart     # 移植自 Qt::ChinaMarket
│   ├── models/                         # Hive POCO（组合 / 交易 / 聊天）
│   ├── services/
│   │   ├── tushare_service.dart        # stock_basic / fund_basic / fut_basic / *daily
│   │   ├── deepseek_service.dart       # SSE 流式
│   │   └── portfolio_repository.dart   # 持仓聚合
│   ├── state/                          # Provider notifier 三件套
│   └── screens/
│       ├── home/                       # 底部导航：助理 / 组合
│       ├── assistant/                  # 聊天 UI
│       ├── portfolio/                  # 命令栏 + 10 个 tab + 各种弹窗
│       └── settings/
├── android/                            # 已写好 manifest / Gradle / Kotlin 入口
├── ios/                                # AppDelegate + Info.plist + Podfile
├── web/                                # H5 入口
└── pubspec.yaml
```

---

## 与 Qt 桌面版的差异 / 取舍

| 模块 | 桌面版 | Flutter 版 |
|:--|:--|:--|
| AI 工具调用 | MCP 全套（含 Tushare 工具） | 仅文本/Markdown 回复，工具调用留待 v2 |
| 组合分析 | Python 量化 (FFN/QuantStats) | 纯 Dart 客户端轻量化，无 Python 依赖 |
| 行情来源 | Tushare + yfinance + 券商行情 | 只走 Tushare（与移动端定位一致） |
| 多窗口 / Dock 屏幕 | F1–F12 多面板 | 仅 2 个一级 Tab |

更复杂的分析（Markowitz、VaR/CVaR、压力测试、PME 报告）建议结合
桌面端使用，移动端聚焦于查看 + 简单决策。
