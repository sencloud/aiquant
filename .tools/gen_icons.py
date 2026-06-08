#!/usr/bin/env python3
# 生成喜宽 App 图标(iOS + Android)：暗底 + 琥珀微光 + 三根圆角 K 线柱。
# 用法：python .tools/gen_icons.py
import os
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = 1024

AMBER = (217, 118, 6)   # #D97706
LIGHT = (229, 229, 229)  # #E5E5E5
BG_TOP = (22, 18, 13)    # 暖调深色
BG_BOT = (10, 10, 11)    # 近黑


def make_master() -> Image.Image:
    # 垂直渐变背景(顶部暖 → 底部近黑)
    base_bot = Image.new("RGB", (S, S), BG_BOT)
    base_top = Image.new("RGB", (S, S), BG_TOP)
    grad = Image.new("L", (1, S))
    for y in range(S):
        grad.putpixel((0, y), int(255 * (y / (S - 1))))
    grad = grad.resize((S, S))
    bg = Image.composite(base_bot, base_top, grad)

    # 琥珀色柔光(柱体后方)
    glow = Image.new("L", (S, S), 0)
    gd = ImageDraw.Draw(glow)
    cx, cy, rr = 512, 452, 300
    gd.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=255)
    glow = glow.filter(ImageFilter.GaussianBlur(150))
    glow = glow.point(lambda v: int(v * 0.24))
    amber_layer = Image.new("RGB", (S, S), AMBER)
    bg = Image.composite(amber_layer, bg, glow)

    # 三根 K 线柱(比例对齐落地页 favicon，32→1024 ×32)
    draw = ImageDraw.Draw(bg)

    def bar(x, y, w, h, color):
        draw.rounded_rectangle([x, y, x + w, y + h], radius=30, fill=color)

    bar(256, 320, 96, 384, AMBER)   # 左·琥珀
    bar(464, 192, 96, 640, LIGHT)   # 中·浅(最高)
    bar(672, 416, 96, 288, AMBER)   # 右·琥珀
    return bg


def save(master, size, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    master.resize((size, size), Image.LANCZOS).save(path)


def main():
    master = make_master()

    ios_dir = os.path.join(ROOT, "ios", "Runner", "Assets.xcassets", "AppIcon.appiconset")
    ios = {
        "Icon-App-20x20@1x.png": 20, "Icon-App-20x20@2x.png": 40, "Icon-App-20x20@3x.png": 60,
        "Icon-App-29x29@1x.png": 29, "Icon-App-29x29@2x.png": 58, "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40, "Icon-App-40x40@2x.png": 80, "Icon-App-40x40@3x.png": 120,
        "Icon-App-50x50@1x.png": 50, "Icon-App-50x50@2x.png": 100,
        "Icon-App-57x57@1x.png": 57, "Icon-App-57x57@2x.png": 114,
        "Icon-App-60x60@2x.png": 120, "Icon-App-60x60@3x.png": 180,
        "Icon-App-72x72@1x.png": 72, "Icon-App-72x72@2x.png": 144,
        "Icon-App-76x76@1x.png": 76, "Icon-App-76x76@2x.png": 152,
        "Icon-App-83.5x83.5@2x.png": 167,
        "Icon-App-1024x1024@1x.png": 1024,
    }
    for fn, sz in ios.items():
        save(master, sz, os.path.join(ios_dir, fn))

    android = {"mipmap-mdpi": 48, "mipmap-hdpi": 72, "mipmap-xhdpi": 96,
               "mipmap-xxhdpi": 144, "mipmap-xxxhdpi": 192}
    for d, sz in android.items():
        save(master, sz, os.path.join(ROOT, "android", "app", "src", "main", "res", d, "ic_launcher.png"))

    # 源图：登录页 Image.asset + flutter_launcher_icons 都用这一张，必须同步更新。
    save(master, 1024, os.path.join(ROOT, "assets", "branding", "app_icon.png"))

    # 预览图(给落地页 / 自查)
    save(master, 512, os.path.join(ROOT, ".tools", "_icon_preview.png"))
    print("ICONS_DONE: iOS", len(ios), "Android", len(android), "+ branding source")


if __name__ == "__main__":
    main()
