# 喜爱 1.1.0 · App Store 上架材料与截图

本目录是 1.1.0 上架用的全部材料。**文本（文案、说明、生成脚本、数据快照）入库；PNG 和 .docx 是生成物，不入库**（见 `../.gitignore`），本机这一份就是要上传的成品。

```
app-store-assets/
├── listing.md / listing.docx   上架文案：名称、副标题、描述、关键词、审核备注、隐私标签、内购…（docx 由 md 生成）
├── README.md                   本文件：截图清单、钓点地图真机截图步骤、上传说明、重新生成
├── overview.png                全部截图的总览（只供查看，不上传）
├── iphone69/*.png              iPhone 6.9" 1320×2868，7 张
├── ipad13/*.png                iPad 13" 2064×2752，7 张
├── iap_review/*.png            内购项目审核截图
├── _drafts/*.png               钓点地图 OSM 草稿（带「不要上传」标记）
├── data/*.json                 截图用的线上数据快照（2026-10-11 抓取）
└── tools/                      生成脚本（见文末「重新生成」）
```

## 交付文件（全部 RGB PNG、无 alpha、尺寸精确）

| # | iPhone 6.9"（1320×2868） | iPad 13"（2064×2752） | 标题 / 副标题 | 画面 |
|---|---|---|---|---|
| 1 | iphone69/01_theme.png | ipad13/01_theme.png | 喜爱，并不是一定要得到 / 一个 App，两种喜爱：喜爱钱 · 喜爱钓鱼 | 选主题页 |
| 2 | iphone69/02_money_chat.png | ipad13/02_money_chat.png | 行情数据，开口就问 / 期货、A 股、财报、资金流，AI 帮你查数、算指标 | 喜爱钱 · 对话（豆油 / 棕榈油价差） |
| 3 | iphone69/03_money_discover.png | ipad13/03_money_discover.png | 常看的，放到发现页 / 一句话做个小应用，数据自动更新 | 喜爱钱 · 发现页小应用 |
| 4 | iphone69/04_money_miniapp.png | ipad13/04_money_miniapp.png | 想看什么，一句话搭好 / 例：豆油与棕榈油价差、60 日均值与偏离 | 小应用「品种价差监控」 |
| 5 | iphone69/05_fishing_forecast.png | ipad13/05_fishing_forecast.png | 出钓前，先看指数 / 气压、风、气温、降水、月相打分，附好时段 | 喜爱钓鱼 · 出钓（千岛湖） |
| 6 | **待真机截图** | **待真机截图** | 私人钓点，只有你能看到 / 地图上存钓点，一键导航过去 | 钓点地图（见下文） |
| 7 | iphone69/07_fishing_chat.png | ipad13/07_fishing_chat.png | AI 钓友，帮你挑日子 / 结合天气和出钓指数，说清哪天去、几点到 | 喜爱钓鱼 · 对话 |
| 8 | iphone69/08_fishing_catches.png | ipad13/08_fishing_catches.png | 每一竿，都记得 / 渔获日记：鱼种、重量、钓法、放流 | 渔获日记 |

- 内购审核截图：`iap_review/09_iap_sheet.png`（充值弹层，喜点档位来自线上 `/v1/credits/skus`）。
- 总览：`overview.png`。草稿：`_drafts/*_06_fishing_map_DRAFT.png`（OSM 底图，带红色「不要上传」标记，**不要上传**）。

## 数据来源
- 出钓指数：线上 `GET /v1/fishing/forecast?place=千岛湖`（2026-10-11 抓取，Open-Meteo），原样渲染。
- 小应用：线上官方模板试运行 `POST /v1/miniapps/templates/{id}/run` 的真实返回（大商所 Y2701 / P2701，2026-10-09 收盘）。
- 喜爱钱对话里的数字都是从上面这份真实数据算出来的（−629、均值 −1096、σ≈184、+2.5σ），没有投资建议措辞。
- 喜爱钓鱼对话按千岛湖的真实预报写（12 日 90 分、13 日 96 分，时段和风速都对得上）。
- 渔获、钓点：虚构但真实感的示例（老河湾、大坝下等通用地名），不含任何真实用户数据。
- 渲染方式：Flutter widget test（main@7c8aae2；02、07 在 815061d 重拍，对话框占位文字已改成「发消息…」），Noto Sans/Serif CJK SC 只在测试里通过 FontLoader 加载，App 本身没加字体。数字字体用 Noto Sans；iOS 上没指定字体的文本走系统字体，Noto 和苹方的字形接近。

## 钓点地图：需要真机截图
iOS 上的钓点地图是 **Apple 地图（MapKit 原生视图）**，widget test 渲染不出来；草稿用的 OSM 底图和 iOS 实际界面不一样，所以不能当正式图用。截图步骤：
1. 用 iPhone 16/17 Pro Max（原生就是 1320×2868）。其他 iPhone 也行，脚本会等比缩放后居中裁切。装 TestFlight build 202 或更新的版本。
2. 用测试用的 Apple 账号点「使用 Apple 账号登录」（不要用个人账号，免得昵称等个人信息入镜），切到「喜爱钓鱼」。
3. 定位权限选「使用 App 期间」。**不要让蓝点（你的真实位置）出现在画面里**：把地图拖到千岛湖一带。
4. 在湖边长按，或者点「在地图中心添加钓点」，加 3–4 个钓点，名字用通用的（老河湾、大坝下、东南湾、西岛），填上鱼种。
5. 回到地图全览（顶部显示「N 个钓点 · 只有你能看到」），用电源键 + 音量上键截屏。iPad 13"（2064×2752，12.9" 的 2048×2732 也可以）同样截一张。
6. 合成：`python tools/compose.py --only 06 --phone-screen <iPhone截图> --ipad-screen <iPad截图>`，再跑 `python tools/overview.py`（环境见下文「重新生成」）。脚本会盖掉真机状态栏，统一画成 9:41，输出到 `iphone69/06_fishing_map.png`、`ipad13/06_fishing_map.png`。
- 如果来不及：先只上传 7 张也可以（Apple 要求 1–10 张），地图那张等下个版本或者改元数据时再补。

## 上传到 App Store Connect
- 版本 1.1.0 → 「App 预览和截屏」→ iPhone 选 **6.9 英寸显示屏**，iPad 选 **13 英寸显示屏**。按 01→08 的顺序拖进去；前 3 张在搜索结果里最显眼。
- 把旧的「喜宽」截图全部删掉，里面有已下线的功能。
- 更小尺寸的设备会自动用 6.9" 和 13" 的截图缩放，不用另外上传。

## 重新生成

在仓库根目录执行。需要：Flutter（与 App 同版本）、Python 3 + `pillow` + `playwright`（合成）+ `python-docx`（转 Word）、Noto Sans CJK SC / Noto Serif CJK SC 字体文件、DejaVu Sans Mono。

```bash
# 字体位置（默认是 box 上的路径；本机按实际位置改）
export SHOT_FONT_DIR=/path/to/NotoSansCJKsc      # NotoSansCJKsc-Regular.otf / -Bold.otf
export SHOT_SERIF_DIR=/path/to/NotoSerifCJKsc    # NotoSerifCJKsc-Regular.otf / -Medium.otf
export SHOT_MONO_DIR=/path/to/dejavu             # DejaVuSansMono.ttf / -Bold.ttf
# export SHOT_OSM_TILES=/path/to/osm_tiles       # 可选：钓点地图草稿的 OSM 瓦片（z_x_y.png）；不给就跳过 06 草稿

# 1) App 画面原图 → marketing/app-store-assets/raw/{phone,ipad}/（不入库）
#    截图脚本和字体补丁只在本地临时用，跑完一定还原，不要提交。
cp marketing/app-store-assets/tools/zz_appstore_shots_test.dart test/
git apply marketing/app-store-assets/tools/shot_only_wk_kit.patch
SHOT_DEVICE=phone flutter test --update-goldens test/zz_appstore_shots_test.dart
SHOT_DEVICE=ipad  flutter test --update-goldens test/zz_appstore_shots_test.dart
git checkout -- lib/widgets/wk_kit.dart && rm test/zz_appstore_shots_test.dart

# 2) 加标题、渐变背景、设备外框 → iphone69/、ipad13/、_drafts/；再出总览
python marketing/app-store-assets/tools/compose.py            # --only 02 只重出一张；CHROME=<浏览器路径> 可选
python marketing/app-store-assets/tools/overview.py
#    内购审核截图直接用原图：cp raw/phone/09_iap_sheet.png iap_review/

# 3) 上架文案（改 tools/gen_listing.py 里的文字，不要直接改 listing.md）
python marketing/app-store-assets/tools/gen_listing.py
python marketing/app-store-assets/tools/md2docx.py marketing/app-store-assets/listing.md marketing/app-store-assets/listing.docx
```

- 为什么要字体补丁：flutter_tester 里没指定字体的文字永远用测试字体（方块），`shot_only_wk_kit.patch` 只给两个组件临时指定 `ShotSans`（= Noto Sans CJK），App 本身不带也不需要这些字体。
- 数据：`data/*.json` 是线上接口的原样返回（出钓指数、官方模板试运行、喜点档位）。想换新数据就重新抓：`GET /v1/fishing/forecast?place=千岛湖&days=3`、`POST /v1/miniapps/templates/{id}/run`（body `{}`）、`GET /v1/credits/skus`。
