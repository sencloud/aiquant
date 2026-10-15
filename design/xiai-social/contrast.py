"""新社交原型的对比度实测（WCAG 2.x，AA 门槛：正文 4.5:1）。
用法：python design/xiai-social/contrast.py
取值与 design/xiai-social/app.css 一一对应；六个圈沿用 App 的 TopicPalette。
"""

PAIRS = [
    ("正文 墨 / 纸",           "#1F1C17", "#F3F0E8", 4.5),
    ("正文 墨 / 白面",         "#1F1C17", "#FFFFFF", 4.5),
    ("次级 墨-2 / 白面",       "#5F5850", "#FFFFFF", 4.5),
    ("次级 墨-2 / 内嵌底",     "#5F5850", "#F8F5EE", 4.5),
    ("弱字 墨-3 / 纸",         "#726B61", "#F3F0E8", 4.5),
    ("弱字 墨-3 / 白面",       "#726B61", "#FFFFFF", 4.5),
    ("弱字 墨-3 / 内嵌底",     "#726B61", "#F8F5EE", 4.5),
    ("小票「依据」/ 内嵌底",    "#726B61", "#F8F5EE", 4.5),
    ("白字 / 品牌色（按钮）",   "#FFFFFF", "#9E6322", 4.5),
    ("主色深 / 纸",            "#7A4A16", "#F3F0E8", 4.5),
    ("「已实名」标 / 内嵌底",   "#5F5850", "#F8F5EE", 4.5),
]

CIRCLES = [
    ("钱 墨金",    "#9E6322", "#7A4A16", "#F1E6D3"),
    ("钓鱼 湖青",  "#1F6A7A", "#154C58", "#DCEBEE"),
    ("咖啡 深焙褐","#6F4A2A", "#553616", "#EDE3D6"),
    ("养猫 绒紫",  "#6E5A8C", "#554470", "#E7E3EE"),
    ("露营 夜营蓝","#33587A", "#26425C", "#DDE6EE"),
    ("汉服 绛红",  "#8C3A4A", "#6D2B39", "#F0DFE2"),
]


def luminance(hex_color: str) -> float:
    h = hex_color.lstrip("#")
    ch = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    lin = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in ch]
    return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2]


def ratio(a: str, b: str) -> float:
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def blend(fg: str, alpha: float, bg: str) -> str:
    f = [int(fg.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4)]
    b = [int(bg.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4)]
    return "#%02X%02X%02X" % tuple(round(alpha * fv + (1 - alpha) * bv) for fv, bv in zip(f, b))


def main() -> int:
    bad = 0
    print("共用色")
    for use, fg, bg, need in PAIRS:
        r = ratio(fg, bg)
        bad += r < need
        print(f"  {use:<22}{fg} / {bg}   {r:5.2f}  ≥{need}  {'ok' if r >= need else '低'}")

    print("\n六个圈（白字压徽记 / 主色深压标签底）")
    for name, brand, deep, soft in CIRCLES:
        a, b = ratio("#FFFFFF", brand), ratio(deep, soft)
        bad += min(a, b) < 4.5
        print(f"  {name:<12}白字/徽记 {a:5.2f}   主色深/标签底 {b:5.2f}   "
              f"{'ok' if min(a, b) >= 4.5 else '低'}")

    night = "#1E1B1A"
    print("\n开屏（夜空底 " + night + "）")
    for use, alpha, need in [("题字「喜爱」", 1.0, 4.5), ("口号", 0.78, 4.5),
                            ("不读通讯录的社交", 0.6, 4.5)]:
        fg = blend("#EFE8DA", alpha, night)
        r = ratio(fg, night)
        bad += r < need
        print(f"  {use:<18}实测色 {fg}  {r:5.2f}  ≥{need}  {'ok' if r >= need else '低'}")

    print(f"\n低于门槛的组合：{bad} 处")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
