"""走查用：用真实 Chrome 渲染原型并逐屏截图。

用法：python design/xiai/shoot.py [--out 目录] [--scale 2]
"""

from __future__ import annotations

import argparse
import pathlib

from playwright.sync_api import sync_playwright

ROOT = pathlib.Path(__file__).resolve().parent
URL = (ROOT / "index.html").as_uri()

# (文件名, 进入前的 JS)
SHOTS = [
    ("01-home", ""),
    ("02-home-below", "document.querySelector('#s-home').scrollTop = 999"),
    ("03-circle-ai", "go('circle')"),
    ("04-circle-feed", "go('circle'); switchSeg('feed')"),
    ("05-circle-archive", "go('circle'); switchSeg('archive')"),
    ("06-circle-shop", "go('circle'); switchSeg('shop')"),
    ("07-chat", "go('chat')"),
    ("08-chat-answer", "go('chat'); ask('帮我配一套 2000 元钓鱼装备')"),
    ("08b-chat-why", "go('chat'); ask('这条依据能展开吗？')"),
    ("09-quiz", "go('quiz')"),
    ("09b-quiz2", "go('quiz'); document.querySelector('.opt').click();"
                  " document.querySelector('#quiz-next').click()"),
    ("10-quiz-result", "go('quiz'); quizStep = 3; quizNext()"),
    ("11-circles", "go('circles')"),
    ("12-me", "go('me')"),
    ("13-empty", "go('empty')"),
    ("14-ticket", "go('circle'); sheet('ticket', true)"),
    ("15-coffee", "setCircle('coffee'); go('circle')"),
    ("16-cat", "setCircle('cat'); go('circle')"),
    ("17-cat-feed", "setCircle('cat'); go('circle'); switchSeg('feed')"),
    ("18-coffee-archive", "setCircle('coffee'); go('circle'); switchSeg('archive')"),
    ("19-money-ai", "setCircle('money'); go('circle')"),
]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(ROOT.parent.parent / ".impeccable" / "review"))
    ap.add_argument("--scale", type=float, default=1)
    args = ap.parse_args()

    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    with sync_playwright() as p:
        browser = p.chromium.launch(
            channel="chrome",
            args=["--enable-unsafe-swiftshader", "--hide-scrollbars", "--force-color-profile=srgb"],
        )
        page = browser.new_page(
            viewport={"width": 390, "height": 844},
            device_scale_factor=args.scale,
        )
        page.goto(URL)
        page.wait_for_timeout(700)

        for name, script in SHOTS:
            page.evaluate("go('home'); setCircle('fishing'); sheet(null,false)")
            if script:
                page.evaluate(script)
            page.wait_for_timeout(1500 if "ask(" in script else 480)
            page.screenshot(path=str(out / f"{name}.png"))
            print(f"[ok] {name}", flush=True)

        # 桌面：整机 + 走查台
        desk = browser.new_page(viewport={"width": 1440, "height": 900}, device_scale_factor=1)
        desk.goto(URL)
        desk.wait_for_timeout(900)
        desk.screenshot(path=str(out / "desktop.png"))
        print("[ok] desktop", flush=True)

        # 移动端宽度（真机全屏，无设备框）
        mob = browser.new_page(viewport={"width": 414, "height": 896}, device_scale_factor=1)
        mob.goto(URL)
        mob.wait_for_timeout(900)
        mob.screenshot(path=str(out / "mobile.png"))
        print("[ok] mobile", flush=True)

        browser.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
