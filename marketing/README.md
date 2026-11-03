# marketing/

喜爱（原「喜宽」）在 App Store 和落地页上用的素材。**仓库里只放源码和文案，PNG / docx 是生成物、不入库**，需要时按下面跑一次就能重出。

## 目录

| 路径 | 内容 | 产出 |
|---|---|---|
| `app-store-assets/` | 1.1.0 上架材料：上架文案 `listing.md`（名称、描述、关键词、审核备注、隐私标签、内购）、截图说明 `README.md`、生成脚本 `tools/`、数据快照 `data/` | `iphone69/` 7 张、`ipad13/` 7 张、`iap_review/`、`_drafts/`、`overview.png`、`listing.docx` |
| `logo/` | Logo 方案与定稿 App 图标 | `logo/icons/*.png` 共 14 张、方案总览图、定稿对比图 |
| `logo/archive/` | 换标前的旧图标（三根柱），回退用 | 已入库，不忽略 |

## 重新生成

**App Store 截图与上架文案**：步骤和前置条件（Flutter、Python + pillow / playwright / python-docx、Noto CJK 字体）写在 `app-store-assets/README.md` 的「重新生成」。简单说：Flutter widget test 渲染真实 App 画面 → `tools/compose.py` 加标题和外框 → `tools/overview.py` 出总览；文案改 `tools/gen_listing.py` 后重新生成 `listing.md` / `listing.docx`。

**Logo**：前置是本机装了 Chrome 或 Edge——脚本用无头浏览器渲染，这样才能保证像素尺寸和中文排版精确。

```powershell
# 1) Logo 方案总览图
powershell -ExecutionPolicy Bypass -File marketing/logo/build.ps1

# 2) 定稿 App 图标（与 App 首页左上角标志同源）
powershell -ExecutionPolicy Bypass -File marketing/logo/build-xiai.ps1
dart run flutter_launcher_icons
```

第 2 步使用纯矢量源文件，不依赖字体：`logo/src/icon-xiai-market*.svg` 定义深蓝渐变、白色抽象 A 和金色行情轨迹；脚本会同时生成 iOS 方形图标源图与 Android 自适应前景 / 背景层。

> 上传 App Store 时用的是 `app-store-assets/` 里这些本地 PNG。它们不在 Git 里，换机器后要重新生成（或从原机器拷过来）。

## 改文案 / 改配色改哪里

- 截图标题 / 副标题、配色和排版：`app-store-assets/tools/compose.py`（`SHOTS`、`PALETTES`）
- 截图里的 App 画面和演示数据：`app-store-assets/tools/zz_appstore_shots_test.dart`、`app-store-assets/data/*.json`
- 上架文案、审核备注、隐私标签：`app-store-assets/tools/gen_listing.py`（`listing.md` 是它生成的，不要手改）
- Logo 图形：`logo/src/mark-*.svg`；App 图标以 `logo/src/icon-xiai-market*.svg` 为唯一源文件

## 与 App 的关系

`assets/branding/app_icon.png`（不在本目录）是 App 真正的图标源，`flutter_launcher_icons` 从它生成 iOS / Android / Web 全套。换图标时先改 `logo/src/icon-xiai-market*.svg`，运行 `build-xiai.ps1` 重出 PNG，再执行 `dart run flutter_launcher_icons`。

落地页用的 `/app-icon.svg` 是 `logo/src/icon-xiai-market.svg` 的副本，放在 `backend/deploy/www/` 下随站点部署。
