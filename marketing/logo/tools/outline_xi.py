"""把「喜」字从 Noto Sans SC Black(wght=900) 转成矢量轮廓路径。

用途：让 logo 的 SVG 不再依赖本机字体，任何机器打开都是同一个形状。
输出：src/xi-900.path（纯路径数据），供 mark-*.svg 内联使用。

用法：
    python marketing/logo/tools/outline_xi.py
"""

import os

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

FONT = r"C:\Windows\Fonts\NotoSansSC-VF.ttf"
CODEPOINT = 0x559C  # 喜


def main() -> None:
    if not os.path.exists(FONT):
        raise SystemExit(f"找不到字体：{FONT}")

    font = TTFont(FONT)
    font = instancer.instantiateVariableFont(font, {"wght": 900}, updateFontNames=False)

    upm = font["head"].unitsPerEm
    glyph_name = font.getBestCmap()[CODEPOINT]
    glyph_set = font.getGlyphSet()
    glyph = glyph_set[glyph_name]

    pen = SVGPathPen(glyph_set, ntos=lambda v: f"{v:.1f}")
    glyph.draw(pen)
    path = pen.getCommands()

    g = font["glyf"][glyph_name]
    x_min, y_min, x_max, y_max = g.xMin, g.yMin, g.xMax, g.yMax

    out = os.path.join(os.path.dirname(__file__), "..", "src", "xi-900.path")
    out = os.path.abspath(out)
    with open(out, "w", encoding="utf-8") as fh:
        fh.write(path)

    print(f"unitsPerEm      = {upm}")
    print(f"glyph           = {glyph_name}")
    print(f"bbox            = ({x_min}, {y_min}) - ({x_max}, {y_max})")
    print(f"advanceWidth    = {glyph_set[glyph_name].width}")
    print(f"path length     = {len(path)} chars")
    print(f"written to      = {out}")

    # SVG 里把字形装进「宽 W / 高 H 的框」：s = H / bbox 高，y 轴翻转。
    print("")
    print("SVG transform（框左上角 = (left, top)）：")
    for left, top, height in ((264, 232, 560), (240, 210, 590), (262, 232, 560)):
        s = height / (y_max - y_min)
        tx = left - s * x_min
        ty = top + s * y_max
        print(
            f"  框({left},{top}) 高{height} -> "
            f'transform="translate({tx:.1f},{ty:.1f}) scale({s:.4f},-{s:.4f})"'
        )


if __name__ == "__main__":
    main()
