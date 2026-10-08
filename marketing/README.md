# marketing/

喜宽在 App Store 和落地页上用的视觉素材。**仓库里只放源码，PNG 是生成物、不入库**（约 30 MB），需要时按下面跑一次就能重出。

## 目录

| 路径 | 内容 | 产出 |
|---|---|---|
| `app-store-assets/` | 顶部横幅、搜索结果素材、iPhone 截屏（6.9″ + 6.5″）、iPad 截屏（12.9″ + 13″） | `喜宽_*.png` 共 24 张 |
| `logo/` | Logo 方案与定稿 App 图标 | `logo/icons/*.png` 共 14 张、方案总览图、定稿对比图 |
| `logo/archive/` | 换标前的旧图标（三根柱），回退用 | 已入库，不忽略 |

## 重新生成

前置：本机装了 Chrome 或 Edge——脚本用无头浏览器渲染，这样才能保证像素尺寸和中文排版精确。

```powershell
# 1) 商品页素材：截图 + 横幅 + 搜索素材，共 24 张
powershell -ExecutionPolicy Bypass -File marketing/app-store-assets/build.ps1

# 2) Logo 方案总览图
powershell -ExecutionPolicy Bypass -File marketing/logo/build.ps1

# 3) 定稿 App 图标（先生成字形轮廓，再出图）
python marketing/logo/tools/outline_xi.py
powershell -ExecutionPolicy Bypass -File marketing/logo/build-final.ps1
```

第 3 步的 `outline_xi.py` 需要 `fontTools`，并依赖 `C:\Windows\Fonts\NotoSansSC-VF.ttf`（Windows 自带；缺失就自行装一份 Noto Sans SC）。它把「喜」字转成路径写进 `logo/src/xi-900.path`，所以导出的 SVG 不依赖字体，换台机器打开形状一致。

> 上传 App Store 时用的是这些本地产出的 PNG。它们不在 Git 里，换机器后记得先跑一次脚本。

## 改文案 / 改配色改哪里

- 商品页截屏的文案与排版：`app-store-assets/src/screens.html`、`src/screens.css`
- 横幅与搜索素材：`app-store-assets/src/asset.html`、`src/style.css`
- Logo 图形：`logo/src/mark-*.svg`；定稿图标用 `logo/src/icon-*-template.svg`，其中 `{{XI_PATH}}` 由脚本替换成字形路径

## 与 App 的关系

`assets/branding/app_icon.png`（不在本目录）才是 App 真正的图标源，`flutter_launcher_icons` 从它生成 iOS / Android / Web 全套。换图标流程：把 `logo/icons/喜宽_appicon_*.png` 拷成 `assets/branding/app_icon.png`，然后跑 `dart run flutter_launcher_icons`。

落地页用的 `/app-icon.svg` 是 `logo/icons/喜宽_appicon_A_推荐.svg` 的副本，放在 `backend/deploy/www/` 下随站点部署。
