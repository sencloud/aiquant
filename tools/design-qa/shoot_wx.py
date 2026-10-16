"""设计走查：把 Flutter Web 构建跑起来，拍微信式外壳（消息 / 圈子 / 发现 / 我）。

用法：
    flutter build web --release --dart-define=SPLASH_MS=100
    python -m http.server 8777 --directory build/web     # 另开一个终端
    python tools/design-qa/shoot_wx.py --out .impeccable/shots/wx
"""

from __future__ import annotations

import argparse
import pathlib

from playwright.sync_api import sync_playwright

# 底部页签的中心点（414 宽四等分）：消息 / 圈子 / 发现 / 我。
TABS = {"chats": 52, "circles": 155, "discover": 259, "me": 362}


def shoot(page, out: pathlib.Path, name: str, *, wait: int = 1400) -> None:
    page.wait_for_timeout(wait)
    path = out / f"{name}.png"
    page.screenshot(path=str(path))
    print(f"[ok] {path}", flush=True)


def tap_tab(page, key: str, y: int) -> None:
    page.mouse.click(TABS[key], y)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8777/")
    ap.add_argument("--out", default=".impeccable/shots/wx")
    ap.add_argument("--width", type=int, default=414)
    ap.add_argument("--height", type=int, default=896)
    args = ap.parse_args()

    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    tab_y = args.height - 28

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
        shoot(page, out, "01-chats", wait=2600)

        # 没对话时先给一个入口（点它同样进聊天页）。
        page.mouse.click(args.width / 2, args.height * 0.63)
        page.wait_for_timeout(1200)
        # 右上角 ＋ → 再新开一段（聊天页）。顶栏高 44，图标在 y≈22。
        page.mouse.click(args.width - 22, 22)
        shoot(page, out, "02-chat", wait=1800)

        # 聊天页右上角「…」：换助手 / 新的对话 / 删除。
        page.mouse.click(args.width - 22, 22)
        shoot(page, out, "03-chat-menu", wait=900)
        page.keyboard.press("Escape")
        page.wait_for_timeout(600)

        # 聊天页是二级页：先按左上角返回，回到「消息」列表，再切页签。
        page.mouse.click(28, 22)
        page.wait_for_timeout(800)

        # 圈子：六个兴趣圈。
        tap_tab(page, "circles", tab_y)
        shoot(page, out, "04-circles", wait=1200)
        page.mouse.click(args.width / 2, 214)
        shoot(page, out, "04b-circle", wait=1200)
        page.mouse.click(28, 22)
        page.wait_for_timeout(800)

        # 发现：记录 + 工具。
        tap_tab(page, "discover", tab_y)
        shoot(page, out, "05-discover")

        # 我：微信式个人页。未登录会先弹登录，关掉它才看得到底下的「我」。
        tap_tab(page, "me", tab_y)
        page.wait_for_timeout(1400)
        shoot(page, out, "06-me-login", wait=400)
        # 关掉登录页（左上角的 ×，顶栏高 44、图标在 y≈22）。
        page.mouse.click(28, 22)
        shoot(page, out, "07-me", wait=1200)

        browser.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
