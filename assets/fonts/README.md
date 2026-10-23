# NightSans

《喜爱 · 天亮以前》试用版的中文字体子集，由 **Noto Sans SC** 裁剪而来。

- 源字体：Noto Sans SC（`NotoSansSC-VF.ttf`，Google / Adobe）
- 授权：SIL Open Font License 1.1
  <https://openfontlicense.org/open-font-license-official-text/>
- 原因：Flutter Web 的系统字体回退会漏掉少量汉字（如「煮」「遥」「炖」）；
  把现有文案的字符集裁成子集，三端一致，体积约 400KB。
- 重新生成：

  ```bash
  pip install fonttools
  python tools/gen_story_font.py
  # 或 STORY_FONT_SRC=/path/to/NotoSansSC-VF.ttf python tools/gen_story_font.py
  ```

改 `lib/story/` 里的文案后，记得重跑一次；字体文件入库，运行时不联网。
