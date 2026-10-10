"""把汉字从 Noto Sans SC Black(wght=900) 转成矢量轮廓路径。

用途：让 logo 的 SVG 不依赖本机字体，任何机器打开都是同一个形状。
（喜宽时期只转「喜」，更名「喜爱」后需要「喜」和「爱」两个字，于是把
原来的 outline_xi.py 参数化。）

用法：
    python marketing/logo/tools/outline_glyph.py            # 喜 + 爱，默认输出
    python marketing/logo/tools/outline_glyph.py 0x559C     # 只转一个字
"""

import os
import sys

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

FONT = r"C:\Windows\Fonts\NotoSansSC-VF.ttf"
WEIGHT = 900

# 字符 → 输出文件名。名字进文件名，避免调用方记编码。
GLYPHS = {
    "0x559C": ("喜", "xi-900.path"),
    "0x7231": ("爱", "ai-900.path"),
}

# 需要把字形装进哪些框（左, 上, 高）：把算好的 transform 打出来，
# 供 SVG 模板直接抄，不用手算缩放。
FRAMES = ((264, 232, 560), (240, 210, 590), (200, 300, 440), (150, 300, 380))


def outline(font, codepoint: int) -> None:
    upm = font["head"].unitsPerEm
    glyph_name = font.getBestCmap()[codepoint]
    glyph_set = font.getGlyphSet()
    pen = SVGPathPen(glyph_set, ntos=lambda v: f"{v:.1f}")
    glyph_set[glyph_name].draw(pen)

    g = font["glyf"][glyph_name]
    x_min, y_min, x_max, y_max = g.xMin, g.yMin, g.xMax, g.yMax
    out = os.path.abspath(
        os.path.join(os.path.dirname(__file__), "..", "src",
                     GLYPHS[f"0x{codepoint:04X}"][1]))
    with open(out, "w", encoding="utf-8") as fh:
        fh.write(pen.getCommands())

    print(f"U+{codepoint:04X} {GLYPHS[f'0x{codepoint:04X}'][0]}")
    print(f"  unitsPerEm = {upm}")
    print(f"  bbox       = ({x_min}, {y_min}) - ({x_max}, {y_max})")
    print(f"  written to = {out}")
    for left, top, height in FRAMES:
        s = height / (y_max - y_min)
        print(
            f"  框({left},{top}) 高{height} -> "
            f'transform="translate({left - s * x_min:.1f},{top + s * y_max:.1f}) '
            f'scale({s:.4f},-{s:.4f})"'
        )


def main() -> None:
    if not os.path.exists(FONT):
        raise SystemExit(f"找不到字体：{FONT}")
    font = TTFont(FONT)
    font = instancer.instantiateVariableFont(
        font, {"wght": WEIGHT}, updateFontNames=False)

    args = sys.argv[1:]
    if args:
        for a in args:
            outline(font, int(a, 0))
    else:
        for key in GLYPHS:
            outline(font, int(key, 0))


if __name__ == "__main__":
    main()
