"""设计走查用：把 Flutter Web 构建跑起来，按手机尺寸截几张图。

用途：改完样式后确认真实渲染效果（真实字体、真实布局），而不是靠猜。
依赖本机 Chrome 与 playwright（`pip install playwright`）。

用法：
    flutter build web --release --dart-define=INITIAL_TAB=1
    python -m http.server 8777 --directory build/web     # 另开一个终端
    python tools/design-qa/shoot_web.py --out .impeccable/shots
"""

from __future__ import annotations

import argparse
import pathlib

from playwright.sync_api import sync_playwright

# 底部页签的中心点（414 宽四等分），用于切页签截图。
TABS = {"chat": 52, "strategy": 155, "discover": 259, "me": 362}


def shoot(page, out: pathlib.Path, name: str, *, wait: int = 1600) -> None:
    page.wait_for_timeout(wait)
    path = out / f"{name}.png"
    page.screenshot(path=str(path))
    print(f"[ok] {path}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8777/")
    ap.add_argument("--out", default=".impeccable/shots")
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
        # Flutter 起来后会插入 flutter-view（不同 Flutter 版本内部元素名会变，
        # 只有 flutter-view 是稳定的）。
        page.wait_for_selector("flutter-view", timeout=60000)
        # CJK 字形在 Web 上是异步下载的，太早截图会拍到豆腐块；
        page.evaluate("document.fonts.ready")
        # 注意：入场动画（900ms）在 Web 上拍不到中间帧 —— 等 CJK 字体下载那一步
        # 就把它耗完了，而 reload 会清掉字体缓存换回一屏豆腐块。所以这里只拍
        # 稳定态；动画本身按构造核对（Interval 曲线 + 透明度/位移）。
        shoot(page, out, "00-entry", wait=400)
        shoot(page, out, "01-initial", wait=1600)

        # 顺序有讲究：「我的」未登录会弹出登录模态，模态一开后续点击全都
        # 打在模态上，所以它放最后。
        page.mouse.click(TABS["chat"], args.height - 30)
        shoot(page, out, "tab-chat")
        page.mouse.click(TABS["strategy"], args.height - 30)
        shoot(page, out, "tab-strategy")
        page.mouse.click(TABS["discover"], args.height - 30)
        shoot(page, out, "tab-discover")

        # 证伪台的档案列表在首屏之下：滚下去点开一条，核对详情页版式。
        page.mouse.click(TABS["strategy"], args.height - 30)
        # 先把指针挪到列表中间再滚 —— 停在底部页签上滚，事件落不到可滚动区域。
        page.mouse.move(args.width / 2, args.height * 0.5)
        page.mouse.wheel(0, 2400)
        shoot(page, out, "02-archive-list", wait=900)
        page.mouse.wheel(0, 2000)
        shoot(page, out, "02b-archive-list", wait=700)
        page.mouse.click(args.width / 2, args.height * 0.30)
        shoot(page, out, "03-archive-detail", wait=1500)

        # 退回证伪台，再切「我的」；否则点击会打在还开着的二级页上。
        page.go_back()
        page.wait_for_timeout(700)
        page.mouse.click(TABS["me"], args.height - 30)
        shoot(page, out, "tab-me")

        browser.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
