"""兴趣圈配色的对比度实测（WCAG 2.x，AA 门槛：正文 4.5:1）。
用法：python design/xiai/contrast.py
取值与 design/xiai/app.css 里的 TopicPalette 一一对应。
"""

ROWS = [
    ("钱 墨金", "#9E6322", "#7A4A16", "#F3F0E8", "#726B61"),
    ("钓鱼 湖青", "#1F6A7A", "#154C58", "#EEF2F0", "#646A67"),
    ("咖啡 深焙褐", "#6F4A2A", "#553616", "#F2EFE9", "#6E665D"),
    ("养猫 绒紫", "#6E5A8C", "#554470", "#EFEBF2", "#6C6770"),
    ("健身 铁蓝灰", "#45536B", "#333E51", "#EDEFF2", "#686D75"),
]


def luminance(hex_color: str) -> float:
    h = hex_color.lstrip("#")
    channels = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    linear = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in channels]
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


def ratio(a: str, b: str) -> float:
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def main() -> int:
    print(f"{'圈':<12}{'白字/品牌':>10}{'品牌深/纸':>11}{'品牌/纸':>9}{'弱字/纸':>9}")
    for name, brand, deep, paper, weak in ROWS:
        cells = [ratio("#FFFFFF", brand), ratio(deep, paper),
                 ratio(brand, paper), ratio(weak, paper)]
        flag = "" if min(cells[0], cells[2], cells[3]) >= 4.5 else "  ← 有值低于 4.5"
        print(f"{name:<12}" + "".join(f"{c:>9.2f}  " for c in cells) + flag)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
