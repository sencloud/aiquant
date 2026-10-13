"""走查用：把兴趣圈（六个圈）的关键屏用真实 Chrome 截下来。

前置：
    flutter build web --release
    python -m http.server 8779 --directory build/web
    python design/xiai/shoot_circles.py

截图落在 .impeccable/review/circles/。坐标按 414×896 视口（与
tools/design-qa/shoot_web.py 同一套底部页签坐标：四等分）。
"""

from __future__ import annotations

import argparse
import pathlib

from playwright.sync_api import sync_playwright

TAB_Y = 896 - 30
TABS = [52, 155, 259, 362]  # 今天 / 记录 / 动态圈 / 我的


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8779/")
    ap.add_argument("--out", default=".impeccable/review/circles")
    ap.add_argument("--cat-card-y", type=int, default=420)
    args = ap.parse_args()

    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    with sync_playwright() as p:
        browser = p.chromium.launch(
            channel="chrome",
            args=["--enable-unsafe-swiftshader", "--hide-scrollbars"],
        )
        page = browser.new_page(
            viewport={"width": 414, "height": 896}, device_scale_factor=1)
        page.goto(args.url)
        page.wait_for_selector("flutter-view", timeout=60000)
        page.evaluate("document.fonts.ready")
        page.wait_for_timeout(3200)  # 开屏 2s + 收尾

        def shot(name: str, wait: int = 700) -> None:
            page.wait_for_timeout(wait)
            page.screenshot(path=str(out / f"{name}.png"))
            print(f"[ok] {name}", flush=True)

        # 全新浏览器 = 全新安装：开屏之后是选主题页（现在六个圈）。
        shot("40-picker", 300)

        # 选「喜爱养猫」（第三张卡）。
        page.mouse.click(207, args.cat_card_y)
        shot("41-cat-today", 1200)
        # 「今天」页右上角的兴趣圈入口 → 兴趣圈首页。
        page.mouse.click(386, 46)
        shot("45-hub", 1200)
        # 兴趣圈首页左上角返回，回到「喜爱养猫」继续看页签。
        page.mouse.click(28, 46)
        page.wait_for_timeout(900)
        page.mouse.click(TABS[1], TAB_Y)
        shot("42-cat-log")
        page.mouse.click(TABS[2], TAB_Y)
        shot("43-cat-community")
        page.mouse.click(TABS[3], TAB_Y)
        shot("44-cat-me", 1100)

        browser.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
