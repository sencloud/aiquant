"""设计走查：把 Flutter Web 构建跑起来，拍新社交骨架（今天 / 圈子 / 信箱 / 我的）。

用法：
    flutter build web --release --dart-define=SPLASH_MS=100
    python -m http.server 8777 --directory build/web     # 另开一个终端
    python tools/design-qa/shoot_social.py --out .impeccable/shots/social
"""

from __future__ import annotations

import argparse
import pathlib

from playwright.sync_api import sync_playwright

# 底部页签的中心点（414 宽四等分）：今天 / 圈子 / 信箱 / 我的。
TABS = {"today": 52, "circles": 155, "mail": 259, "me": 362}


def shoot(page, out: pathlib.Path, name: str, *, wait: int = 1400) -> None:
    page.wait_for_timeout(wait)
    path = out / f"{name}.png"
    page.screenshot(path=str(path))
    print(f"[ok] {path}", flush=True)


def tap_tab(page, key: str) -> None:
    page.mouse.click(TABS[key], 868)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8777/")
    ap.add_argument("--out", default=".impeccable/shots/social")
    ap.add_argument("--width", type=int, default=414)
    ap.add_argument("--height", type=int, default=896)
    ap.add_argument("--pick-y", type=int, default=315,
                    help="首启选择页里「喜爱钓鱼」那张卡的中心 y（默认 315），0 表示不点")
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
        page.evaluate("document.fonts.ready")
        if args.pick_y:
            # 全新安装 + 多主题：首启先落在选择页，点一个圈才进壳。
            page.mouse.click(args.width // 2, args.pick_y)
            page.wait_for_timeout(1200)
        shoot(page, out, "01-today", wait=2600)
        for key in ("circles", "mail", "me"):
            tap_tab(page, key)
            shoot(page, out, f"02-{key}")
        tap_tab(page, "today")
        shoot(page, out, "03-back-today", wait=900)
        browser.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
