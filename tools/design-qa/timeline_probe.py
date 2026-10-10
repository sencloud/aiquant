"""按时间轴连拍 + 像素测带，用来查「启动过程里到底闪过了几屏」。

存在的理由：冷启动那几百毫秒里可能夹着一个不该出现的占位屏（比如开屏之后
又闪一屏空标题），而它一闪而过 —— 肉眼截图很难抓。这个脚本从首帧开始每
[--step] 毫秒拍一张，对每张做「有墨的横向带」统计：

  · 开屏页：中间两个字块 + 底部两行（立场 + 状态），底部四分之一有墨
  · 空标题页：只有中间一坨，底部四分之一是空的
  · 主界面：底部有输入框和页签，墨带明显更多

所以「底部四分之一有没有墨」就是区分『开屏/主界面』与『空标题页』的判据。

用法：
    flutter build web --release            # 用默认的 2 秒开屏
    python -m http.server 8778 --directory build/web
    python tools/design-qa/timeline_probe.py --url http://127.0.0.1:8778/
"""

from __future__ import annotations

import argparse
import pathlib

import numpy as np
from PIL import Image
from playwright.sync_api import sync_playwright

PAPER = np.array([243, 240, 232])


def bands(img: Image.Image) -> list[tuple[int, int]]:
    """返回「有墨」的行区间列表（像素坐标）。"""
    a = np.asarray(img.convert("RGB")).astype(int)
    ink = np.abs(a - PAPER).sum(axis=2) > 40
    rows = np.where(ink.any(axis=1))[0]
    if len(rows) == 0:
        return []
    out, start, prev = [], rows[0], rows[0]
    for r in rows[1:]:
        if r - prev > 14:
            out.append((int(start), int(prev)))
            start = r
        prev = r
    out.append((int(start), int(prev)))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8778/")
    ap.add_argument("--out", default=".impeccable/shots/timeline")
    ap.add_argument("--step", type=int, default=250)
    ap.add_argument("--until", type=int, default=3500)
    ap.add_argument("--width", type=int, default=414)
    ap.add_argument("--height", type=int, default=896)
    args = ap.parse_args()

    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    with sync_playwright() as p:
        browser = p.chromium.launch(
            channel="chrome",
            args=["--enable-unsafe-swiftshader", "--hide-scrollbars"],
        )
        page = browser.new_page(
            viewport={"width": args.width, "height": args.height},
            device_scale_factor=2,
        )
        page.goto(args.url)
        page.wait_for_selector("flutter-view", timeout=60000)

        elapsed = 0
        while elapsed <= args.until:
            page.wait_for_timeout(args.step)
            elapsed += args.step
            path = out / f"t{elapsed:05d}.png"
            page.screenshot(path=str(path))
            b = bands(Image.open(path))
            h = args.height * 2
            bottom = [x for x in b if x[0] > h * 0.75]
            mid = [x for x in b if h * 0.3 < x[0] < h * 0.75]
            verdict = ("主界面/开屏" if bottom else "只有中部内容 —— 疑似空标题页")
            print(f"t={elapsed:>5}ms 墨带={len(b):>2} 中部={len(mid)} "
                  f"底部1/4={len(bottom)}  {verdict}")

        browser.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
