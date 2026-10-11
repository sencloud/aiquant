"""生成原生启动屏的渐变图（无图标）。

开屏第一帧是一条纯竖向五段渐变（lib/screens/splash/splash_backdrop.dart 里的
SplashPalette.neutral），原生启动屏用同一套色值，冷启动切到 Flutter 时不跳。
竖向渐变横向拉伸不失真，所以图做得很窄，原生侧铺满（Android bitmap
gravity=fill、iOS scaleToFill）。

用法（仓库根目录）：python3 tools/gen_splash_gradient.py
改 SplashPalette.neutral 后必须重跑。
"""
from pathlib import Path

from PIL import Image

STOPS = [0.0, 0.3, 0.58, 0.82, 1.0]
COLORS = ["0B0B12", "15141F", "242130", "3E3745", "6E6068"]

ROOT = Path(__file__).resolve().parent.parent


def color_at(t: float) -> tuple:
    for i in range(len(STOPS) - 1):
        a, b = STOPS[i], STOPS[i + 1]
        if t <= b:
            u = 0.0 if b == a else (t - a) / (b - a)
            ca = bytes.fromhex(COLORS[i])
            cb = bytes.fromhex(COLORS[i + 1])
            return tuple(round(ca[k] + (cb[k] - ca[k]) * u) for k in range(3))
    return tuple(bytes.fromhex(COLORS[-1]))


def render(w: int, h: int, path: Path) -> None:
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        c = color_at((y + 0.5) / h)
        for x in range(w):
            px[x, y] = c
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, optimize=True)
    print(path.relative_to(ROOT), w, h)


def main() -> None:
    res = ROOT / "android/app/src/main/res"
    for name, d in [("mdpi", 1), ("hdpi", 1.5), ("xhdpi", 2), ("xxhdpi", 3), ("xxxhdpi", 4)]:
        render(int(16 * d), int(800 * d), res / f"drawable-{name}/splash_gradient.png")
    ios = ROOT / "ios/Runner/Assets.xcassets/LaunchImage.imageset"
    for suffix, d in [("", 1), ("@2x", 2), ("@3x", 3)]:
        render(16 * d, 932 * d, ios / f"LaunchImage{suffix}.png")


if __name__ == "__main__":
    main()
