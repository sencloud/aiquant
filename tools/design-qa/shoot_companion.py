"""设计走查：拍「只有一个 AI 伴侣」的三屏（首页 / 菜单 / 她记得的喜欢）。

用法：
    flutter build web --release --dart-define=SPLASH_MS=100
    python -m http.server 8777 --directory build/web
    python tools/design-qa/shoot_companion.py --out .impeccable/shots/companion
"""

from __future__ import annotations

import argparse
import pathlib

from playwright.sync_api import sync_playwright


def shoot(page, out: pathlib.Path, name: str, *, wait: int = 1200) -> None:
    page.wait_for_timeout(wait)
    path = out / f"{name}.png"
    page.screenshot(path=str(path))
    print(f"[ok] {path}", flush=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8777/")
    ap.add_argument("--out", default=".impeccable/shots/companion")
    ap.add_argument("--width", type=int, default=414)
    ap.add_argument("--height", type=int, default=896)
    args = ap.parse_args()

    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    w, h = args.width, args.height

    with sync_playwright() as p:
        browser = p.chromium.launch(
            channel="chrome",
            args=["--enable-unsafe-swiftshader", "--hide-scrollbars"],
        )
        page = browser.new_page(
            viewport={"width": w, "height": h},
            device_scale_factor=2,
        )
        page.goto(args.url)
        page.wait_for_selector("flutter-view", timeout=60000)
        page.evaluate("document.fonts.ready")
        shoot(page, out, "01-home", wait=2800)

        # 右上角「…」
        page.mouse.click(w - 24, 22)
        shoot(page, out, "02-menu", wait=900)

        # 菜单第一行：她记得的喜欢
        page.mouse.click(w / 2, h - 360)
        shoot(page, out, "03-interests", wait=900)

        browser.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
