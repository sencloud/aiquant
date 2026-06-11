#!/usr/bin/env python3
# 生成「鹦鹉螺」预测市场图标：对数螺旋切面 + 腔室隔板。
# 输出 assets/branding/nautilus.png(透明底白色线稿，UI 里可任意着色)。
# 用法：python .tools/gen_nautilus.py
import math
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = 512          # 输出尺寸
SS = 4           # 超采样倍数(抗锯齿)
W = S * SS

WHITE = (255, 255, 255, 255)

# 每转一圈半径放大的倍数。鹦鹉螺真实值约 3.2，太大会像车轮、太小会像蚊香。
GROWTH_PER_TURN = 3.2
B = math.log(GROWTH_PER_TURN) / (2 * math.pi)


def spiral_point(cx, cy, a, theta):
    """对数螺旋 r = a * e^(B*theta)，theta 增大沿逆时针向外。"""
    r = a * math.exp(B * theta)
    return (cx + r * math.cos(theta), cy - r * math.sin(theta))


def stamp(d, p, width):
    d.ellipse([p[0] - width / 2, p[1] - width / 2,
               p[0] + width / 2, p[1] + width / 2], fill=WHITE)


def stroke_path(d, pts, widths):
    """沿路径密集铺圆，规避 PIL line joint 的毛刺。"""
    for i in range(len(pts) - 1):
        x0, y0 = pts[i]
        x1, y1 = pts[i + 1]
        seg = math.hypot(x1 - x0, y1 - y0)
        n = max(1, int(seg / max(1.0, widths[i] * 0.22)))
        for j in range(n + 1):
            t = j / n
            w = widths[i] + (widths[i + 1] - widths[i]) * t
            stamp(d, (x0 + (x1 - x0) * t, y0 + (y1 - y0) * t), w)


def main():
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    cx, cy = W * 0.50, W * 0.50
    theta_end = 2 * math.pi * 1.62          # 外端点位置(开口朝左下)
    turns = 2.35
    theta_start = theta_end - 2 * math.pi * turns
    a = (W * 0.44) / math.exp(B * theta_end)     # 最外圈半径 ~0.44W

    stroke_max = W * 0.036
    stroke_min = W * 0.014

    # 1) 主螺旋线(线宽由内向外渐粗)
    steps = 700
    pts, widths = [], []
    for i in range(steps + 1):
        t = theta_start + (theta_end - theta_start) * i / steps
        pts.append(spiral_point(cx, cy, a, t))
        k = i / steps
        widths.append(stroke_min + (stroke_max - stroke_min) * (k ** 0.8))
    stroke_path(d, pts, widths)

    # 2) 腔室隔板：仅最外一圈，连接 spiral(t) 与内一圈 spiral(t-2pi)。
    n_sep = 6
    t_hi = theta_end - 0.62          # 不顶到开口
    t_lo = theta_end - 2 * math.pi + 1.05  # 不挤进内圈
    for i in range(n_sep):
        t = t_hi - (t_hi - t_lo) * i / (n_sep - 1)
        p_out = spiral_point(cx, cy, a, t)
        p_in = spiral_point(cx, cy, a, t - 2 * math.pi)
        # 隔板两端略缩进，避免与螺旋线交叠出疙瘩
        dx, dy = p_out[0] - p_in[0], p_out[1] - p_in[1]
        norm = math.hypot(dx, dy) or 1.0
        inset_in, inset_out = stroke_max * 0.30, stroke_max * 0.42
        q_in = (p_in[0] + dx / norm * inset_in, p_in[1] + dy / norm * inset_in)
        q_out = (p_out[0] - dx / norm * inset_out, p_out[1] - dy / norm * inset_out)
        w_in, w_out = stroke_max * 0.42, stroke_max * 0.60
        stroke_path(d, [q_in, q_out], [w_in, w_out])

    out = img.resize((S, S), Image.LANCZOS)
    dst = os.path.join(ROOT, "assets", "branding", "nautilus.png")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    out.save(dst)
    print("NAUTILUS_DONE:", dst)


if __name__ == "__main__":
    main()
