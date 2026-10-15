"""走查用：用真实 Chrome 渲染原型并逐屏截图。

用法：python design/xiai-friend/shoot.py --view --sheets
说明：
  --view   额外在 <out>/view/ 里出一份长边 1500px 的压缩图，方便逐张看图走查。
  --sheets 用 1x 截图拼三张接触印相（每张四屏），一次看一屏的版式；
           拼图总宽压到 1500px 以内，正文仍然读得清。
"""

from __future__ import annotations

import argparse
import pathlib

from playwright.sync_api import sync_playwright

ROOT = pathlib.Path(__file__).resolve().parent
URL = (ROOT / "index.html").as_uri()

# (文件名, 进入前的 JS)
SHOTS = [
    ("01-splash",      "go('splash')"),
    ("02-onboard",     "go('onboard')"),
    ("03-home",        "go('home')"),
    ("03b-home-below", "go('home'); document.querySelector('#s-home').scrollTop = 999"),
    ("04-profile-real","renderProfile('che'); go('profile')"),
    ("05-profile-ai",  "renderProfile('man'); go('profile')"),
    ("06-chat-real",   "openChat('che')"),
    ("07-chat-ai",     "openChat('man')"),
    ("08-chat-fresh",  "openChat('du')"),
    ("08b-chat-sent",  "openChat('du'); send(PEOPLE['du'].ice[0][0])"),
    ("09-ice-sheet",   "renderProfile('man'); go('profile'); sheet('ice', true)"),
    ("10-who-sheet",   "go('home'); sheet('who', true)"),
    ("11-done",        "go('done')"),
    ("12-inbox",       "go('inbox')"),
    ("13-me",          "go('me')"),
    ("14-mark-detail", "setMark('detail'); go('home')"),
    ("15-mark-profile","setMark('profile'); go('home')"),
]

VANILLA = """
go('splash'); setMark('all'); sheet(null, false);
"""

SHEETS = {
    "comp-a": ["01-splash", "02-onboard", "03-home", "11-done"],
    "comp-b": ["04-profile-real", "05-profile-ai", "08-chat-fresh", "09-ice-sheet"],
    "comp-c": ["12-inbox", "13-me", "10-who-sheet", "14-mark-detail"],
}


def shoot(browser, out: pathlib.Path, scale: float) -> None:
    out.mkdir(parents=True, exist_ok=True)
    page = browser.new_page(viewport={"width": 390, "height": 844}, device_scale_factor=scale)
    page.goto(URL)
    page.wait_for_timeout(700)

    for name, script in SHOTS:
        page.evaluate(VANILLA)
        page.evaluate(script)
        page.wait_for_timeout(1800 if "send(" in script else 500)
        visible = page.evaluate("document.querySelectorAll('.screen:not([hidden])').length")
        if visible != 1:
            raise RuntimeError(f"{name}: 同时有 {visible} 屏可见，截图不可信")
        page.screenshot(path=str(out / f"{name}.png"))
        print(f"[ok] {name}", flush=True)

    desk = browser.new_page(viewport={"width": 1440, "height": 960}, device_scale_factor=1)
    desk.goto(URL)
    desk.wait_for_timeout(900)
    desk.screenshot(path=str(out / "desktop.png"))
    print("[ok] desktop", flush=True)

    mob = browser.new_page(viewport={"width": 414, "height": 896}, device_scale_factor=1)
    mob.goto(URL)
    mob.wait_for_timeout(900)
    mob.screenshot(path=str(out / "mobile.png"))
    print("[ok] mobile", flush=True)
    page.close(); desk.close(); mob.close()


def contact_sheets(x1: pathlib.Path) -> None:
    from PIL import Image

    pw, gap = 352, 10
    for name, shots in SHEETS.items():
        ims = [Image.open(x1 / f"{s}.png").resize((pw, round(pw * 844 / 390)), Image.LANCZOS)
               for s in shots]
        canvas = Image.new("RGB", (4 * pw + 5 * gap, ims[0].height + 2 * gap), (38, 35, 32))
        for i, im in enumerate(ims):
            canvas.paste(im, (gap + i * (pw + gap), gap))
        canvas.save(x1 / f"{name}.png")
        print(f"[ok] {name} {canvas.size}", flush=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(pathlib.Path(__file__).resolve().parents[2]
                                        / ".impeccable" / "review" / "xiai-friend"))
    ap.add_argument("--scale", type=float, default=2)
    ap.add_argument("--view", action="store_true", help="额外输出长边 1500px 的看图副本")
    ap.add_argument("--sheets", action="store_true", help="额外输出 1x 截图与三张接触印相")
    args = ap.parse_args()

    out = pathlib.Path(args.out)
    x1 = out / "x1"

    with sync_playwright() as p:
        browser = p.chromium.launch(
            channel="chrome",
            args=["--enable-unsafe-swiftshader", "--hide-scrollbars", "--force-color-profile=srgb"],
        )
        shoot(browser, out, args.scale)
        if args.sheets:
            shoot(browser, x1, 1)
        browser.close()

    if args.sheets:
        contact_sheets(x1)

    if args.view:
        from PIL import Image
        vd = out / "view"
        vd.mkdir(exist_ok=True)
        for f in sorted(out.glob("*.png")):
            im = Image.open(f)
            long_side = max(im.size)
            if long_side > 1500:
                k = 1500 / long_side
                im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
            im.save(vd / f.name)
        print(f"[ok] view/ {len(list(vd.glob('*.png')))} 张", flush=True)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
