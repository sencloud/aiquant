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
    ap.add_argument("--coffee-row-y", type=int, default=632)
    ap.add_argument("--camping-row-y", type=int, default=250)
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

        # 选「喜爱养猫」（第三张卡）→ 现在是 App 首屏：兴趣圈首页。
        page.mouse.click(207, args.cat_card_y)
        shot("41-first-screen", 1400)

        # 首屏三个页签：首页 / 圈子 / 我的（三等分）。
        page.mouse.click(207, TAB_Y)
        shot("42-circles")
        page.mouse.click(69, TAB_Y)
        page.wait_for_timeout(700)

        # 进「喜爱咖啡」（第四行）→ 圈内的「今天」。
        page.mouse.click(207, args.coffee_row_y)
        shot("44-coffee-today", 1300)

        # 记录 → 记一条（把烘焙日标成起算日）→ 回首页看这一行长出真数字。
        page.mouse.click(TABS[1], TAB_Y)
        shot("45-coffee-log")
        page.mouse.click(386, 46)
        page.wait_for_timeout(900)
        page.mouse.click(207, 700)
        page.keyboard.type("茉香日晒 200g")
        page.wait_for_timeout(400)
        page.mouse.click(207, 838)
        page.wait_for_timeout(400)
        shot("46-log-editor", 300)
        page.mouse.click(207, 872)
        page.wait_for_timeout(900)
        page.mouse.click(TABS[0], TAB_Y)
        shot("47-coffee-today-real", 1300)

        # 回首页：这一行现在应该有真数字与轨道。
        page.mouse.click(386, 46)
        shot("48-first-screen-real", 1300)

        # 「我的」要登录，会全屏弹出登录页 —— 放最后，否则后面的点击都打在它上面。
        page.mouse.click(345, TAB_Y)
        shot("43-me", 1100)

        browser.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
