# 天亮以前 · 立绘终稿目录

当前六位角色由 `lib/story/pixel_portrait.dart` 代码绘制（试作）。美术终稿按下面的约定放进来，再把
`lib/story/story_content.dart` 里对应角色的 `artAsset` 设为目录前缀即可，页面不用改。

## 文件命名

```
assets/night/portraits/<character_id>_<expression>.png
```

- `character_id`：`linxia` / `suyu` / `chenye` / `anke` / `zhoumu` / `luyao`
- `expression`：`calm` / `soft` / `hurt` / `smile` / `smirk` / `away`

例如：

```
assets/night/portraits/linxia_calm.png
assets/night/portraits/linxia_soft.png
assets/night/portraits/suyu_smirk.png
```

代码里的前缀写 `assets/night/portraits/linxia`，运行时自动拼表情名。

## 规格

- 画布 512 × 704（64 × 88 的 8 倍），透明背景，人物在画布内居中偏上。
- 像素块对齐 8px 网格，不抗锯齿；导出 PNG-24，不要 WebP / 带 alpha 的 JPG。
- 同一角色的六张表情必须同构图、同光位，只换眉眼、嘴、腮红、泪光。
- 发色 / 服装 / 配饰以 `story_content.dart` 里的 `hair / jacket / accent / accessory` 为准；
  终稿允许加细节，但不要换人。
- 角色都是成年人；不要画校服、幼态比例、真实明星脸。

## 替换步骤

1. 把 6 × 6 张 PNG 放进本目录。
2. 在 `story_content.dart` 的角色构造里加 `artAsset: 'assets/night/portraits/linxia'`。
3. `flutter pub get` 后跑 `flutter test test/story_widget_test.dart`；缺图时 `Image.asset` 会自动回落到
   代码绘制的试作，不会白屏。
4. 截一张通讯录 / 档案页，确认裁切没有切到头顶。
