"""一次性探针：量一下 Flutter web 实际拿到的视口尺寸，排查布局偏移。"""

from playwright.sync_api import sync_playwright

VIEW = """(() => {
  const v = document.querySelector('flutter-view');
  if (!v) return null;
  const r = v.getBoundingClientRect();
  return [r.x, r.y, r.width, r.height];
})()"""


def main() -> None:
    with sync_playwright() as p:
        b = p.chromium.launch(
            channel="chrome",
            args=["--enable-unsafe-swiftshader", "--hide-scrollbars"],
        )
        pg = b.new_page(viewport={"width": 414, "height": 896},
                        device_scale_factor=2)
        pg.goto("http://127.0.0.1:8777/")
        pg.wait_for_selector("flutter-view", timeout=60000)
        pg.wait_for_timeout(250)
        print("win  ", pg.evaluate(
            "[window.innerWidth, window.innerHeight, devicePixelRatio]"))
        print("view ", pg.evaluate(VIEW))
        pg.screenshot(path=".impeccable/shots/dbg-splash.png")
        pg.wait_for_timeout(3200)
        print("view2", pg.evaluate(VIEW))
        print("scroll", pg.evaluate(
            "[window.scrollX, window.scrollY, document.documentElement.scrollWidth, document.body.scrollWidth]"))
        pg.screenshot(path=".impeccable/shots/dbg-after.png")
        pg.evaluate("window.scrollTo(0,0)")
        pg.wait_for_timeout(200)
        pg.screenshot(path=".impeccable/shots/dbg-scroll0.png")
        b.close()


if __name__ == "__main__":
    main()
