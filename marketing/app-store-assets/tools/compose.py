#!/usr/bin/env python3
"""喜爱 App Store 营销截图合成。

用法：
  python3 compose.py                      # 按 SHOTS 合成全部（iPhone 6.9" + iPad 13"）
环境变量：SHOT_FONT_DIR（Noto Sans CJK SC 目录）、SHOT_RAW_DIR（原始截图，默认 ../raw）、CHROME（浏览器路径，可空）。
输出写到 marketing/app-store-assets/{iphone69,ipad13,_drafts}/。
  python3 compose.py --only 06 --phone-screen /path/real_iphone_capture.png [--ipad-screen ...]
真机截图：iPhone 16/17 Pro Max（1320×2868）直接用；其他尺寸会按比例缩放后居中裁切。
输出：RGB PNG（无 alpha），1320×2868 / 2064×2752。
"""
import argparse, base64, io, json, os, sys
from PIL import Image
from playwright.sync_api import sync_playwright

ASSETS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # marketing/app-store-assets
# Noto Sans CJK SC 字体目录（NotoSansCJKsc-Regular.otf / -Bold.otf），默认 box 上的位置
FONT_DIR = os.environ.get('SHOT_FONT_DIR', '/workspace/fonts')
ROOT = ASSETS
RAW = os.environ.get('SHOT_RAW_DIR', f'{ASSETS}/raw')  # zz_appstore_shots_test.dart 的输出（不入库）
OUT = ASSETS
# 留空用 Playwright 自带的 Chromium；box 上是 /usr/bin/google-chrome
CHROME = os.environ.get('CHROME') or None

PALETTES = {  # 与 lib/screens/splash/splash_backdrop.dart 一致
    'neutral': dict(stops=['#0B0B12', '#15141F', '#242130', '#3E3745', '#6E6068'], glow='#CDB4B4',
                    line='#E6DFE8', top='#F7F4F6', bottom='#DCD2D8', slogan='#E2DCE2'),
    'money': dict(stops=['#120B06', '#24160C', '#452B16', '#7E5530', '#C99668'], glow='#F4C48C',
                  line='#F2DCB3', top='#FFF7E8', bottom='#E6C48A', slogan='#EBDCC2'),
    'fishing': dict(stops=['#03141A', '#07262E', '#104550', '#3C7880', '#C7A895'], glow='#FFCFA8',
                    line='#CDEBEA', top='#F6FBFA', bottom='#C9E3DF', slogan='#D8EAE7'),
}

# (编号, 文件名, 主题, 原始截图, 标题, 副标题)
SHOTS = [
    ('01', 'theme', 'neutral', '01_picker', '喜爱，并不是一定要得到', '一个 App，两种喜爱：喜爱钱 · 喜爱钓鱼'),
    ('02', 'money_chat', 'money', '02_money_chat', '行情数据，开口就问', '期货、A 股、财报、资金流，AI 帮你查数、算指标'),
    ('03', 'money_discover', 'money', '03_money_discover', '常看的，放到发现页', '一句话做个小应用，数据自动更新'),
    ('04', 'money_miniapp', 'money', '04b_miniapp_spread', '想看什么，一句话搭好', '例：豆油与棕榈油价差、60 日均值与偏离'),
    ('05', 'fishing_forecast', 'fishing', '05_forecast', '出钓前，先看指数', '气压、风、气温、降水、月相打分，附好时段'),
    ('06', 'fishing_map', 'fishing', None, '私人钓点，只有你能看到', '地图上存钓点，一键导航过去'),
    ('07', 'fishing_chat', 'fishing', '07_fishing_chat', 'AI 钓友，帮你挑日子', '结合天气和出钓指数，说清哪天去、几点到'),
    ('08', 'fishing_catches', 'fishing', '08_catches', '每一竿，都记得', '渔获日记：鱼种、重量、钓法、放流'),
]

DEVICES = {
    'iphone69': dict(w=1320, h=2868, raw='phone', sw=1320, sh=2868, pt=3),
    'ipad13': dict(w=2064, h=2752, raw='ipad', sw=2064, sh=2752, pt=2),
}


def data_url(img: Image.Image) -> str:
    b = io.BytesIO(); img.save(b, 'PNG')
    return 'data:image/png;base64,' + base64.b64encode(b.getvalue()).decode()


def fit_screen(path, sw, sh, real_capture=False, pt=3, phone=True):
    im = Image.open(path).convert('RGB')
    if im.size != (sw, sh):  # 真机截图尺寸不同：等比缩放后居中裁切
        s = max(sw / im.width, sh / im.height)
        im = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
        l, t = (im.width - sw) // 2, (im.height - sh) // 2
        im = im.crop((l, t, l + sw, t + sh))
    if real_capture:
        # 真机截图自带状态栏（真实时间/电量）：用其下方一行的颜色盖掉，再统一画 9:41 状态栏。
        from PIL import ImageDraw
        bar = (54 if phone else 24) * pt
        row = im.crop((0, bar + 4, sw, bar + 5)).resize((1, 1), Image.BOX).getpixel((0, 0))
        ImageDraw.Draw(im).rectangle((0, 0, sw, bar), fill=row)
    return im


def html(dev, pal, title, sub, screen_url, status_bar):
    W, H = dev['w'], dev['h']
    p = PALETTES[pal]
    phone = dev['raw'] == 'phone'
    # 版式
    head_top = 0.085 * H if phone else 0.07 * H
    title_px = 104 if phone else 132
    sub_px = 40 if phone else 50
    dev_top = 0.255 * H if phone else 0.225 * H
    dev_h = H - dev_top - (0.035 * H)
    ratio = dev['sw'] / dev['sh']
    bezel = 22 if phone else 34
    scr_h = dev_h - 2 * bezel
    scr_w = scr_h * ratio
    dev_w = scr_w + 2 * bezel
    k = scr_w / (dev['sw'] / dev['pt'])  # 每 pt 多少像素
    scr_r = (55 if phone else 18) * k
    stops = ','.join(f'{c} {i * 25}%' for i, c in enumerate(p['stops']))
    island = (f'<div class="island" style="width:{125*k}px;height:{37*k}px;top:{11*k}px;'
              f'border-radius:{20*k}px"></div>') if phone else \
             f'<div class="cam" style="top:{bezel/2-6}px"></div>'
    sb = ''
    if status_bar:
        fs = 17 * k
        if phone:
            sb = f'''<div class="sb" style="height:{54*k}px;padding:0 {34*k}px 0 {50*k}px;font-size:{fs}px;padding-top:{8*k}px">
              <span>9:41</span><span class="ic">{icons(k)}</span></div>'''
        else:
            sb = f'''<div class="sb" style="height:{24*k}px;padding:0 {22*k}px;font-size:{13*k}px">
              <span>9:41 &nbsp;10月11日 周日</span><span class="ic">{icons(k*0.8)}</span></div>'''
    stars = ''.join(
        f'<i style="left:{x}%;top:{y}%;width:{s}px;height:{s}px;opacity:{o}"></i>'
        for x, y, s, o in [(8, 4, 5, .7), (22, 9, 3, .5), (84, 3, 6, .8), (70, 12, 3, .4), (93, 15, 4, .6),
                           (4, 17, 3, .4), (47, 2, 3, .5), (60, 7, 4, .6), (32, 19, 2, .4), (15, 23, 3, .3)])
    return f'''<!doctype html><html><head><meta charset="utf-8"><style>
*{{margin:0;padding:0;box-sizing:border-box}}
html,body{{width:{W}px;height:{H}px;overflow:hidden}}
body{{background:linear-gradient(180deg,{stops});position:relative;font-family:"Noto Sans CJK SC","Noto Sans SC",sans-serif}}
.glow{{position:absolute;left:50%;top:{head_top + title_px*0.6}px;width:{W*1.1}px;height:{W*0.55}px;transform:translate(-50%,-50%);
  background:radial-gradient(closest-side,{p['glow']}33,transparent 70%)}}
.orbit{{position:absolute;left:50%;top:{head_top + title_px*0.7}px;width:{W*1.5}px;height:{W*0.42}px;transform:translate(-50%,-50%) rotate(-6deg);
  border:1.5px solid {p['line']}22;border-radius:50%}}
.orbit.b{{width:{W*1.25}px;height:{W*0.3}px;transform:translate(-50%,-50%) rotate(-3deg);border-color:{p['line']}18}}
i{{position:absolute;border-radius:50%;background:#fff;box-shadow:0 0 10px 2px {p['glow']}88}}
.head{{position:absolute;left:0;right:0;top:{head_top}px;text-align:center}}
h1{{font-family:"Noto Serif CJK SC","Noto Serif SC",serif;font-weight:600;font-size:{title_px}px;letter-spacing:{title_px*0.06}px;
  background:linear-gradient(180deg,{p['top']},{p['bottom']});-webkit-background-clip:text;color:transparent;line-height:1.2}}
.orn{{display:flex;align-items:center;justify-content:center;gap:14px;margin:{sub_px*0.7}px 0 {sub_px*0.6}px}}
.orn b{{display:block;width:{title_px*0.9}px;height:2px;background:linear-gradient(90deg,transparent,{p['line']}aa)}}
.orn b+b{{transform:scaleX(-1)}}
.orn s{{display:block;width:10px;height:10px;background:{p['line']};transform:rotate(45deg);opacity:.85}}
p.sub{{font-size:{sub_px}px;color:{p['slogan']};letter-spacing:{sub_px*0.08}px;font-weight:400}}
.dev{{position:absolute;left:50%;top:{dev_top}px;width:{dev_w}px;height:{dev_h}px;transform:translateX(-50%);
  background:#0c0c0e;border-radius:{scr_r+bezel}px;padding:{bezel}px;
  box-shadow:0 0 0 3px #3a3a40,0 0 0 5px #1a1a1d,0 40px 90px rgba(0,0,0,.55),0 10px 30px rgba(0,0,0,.35)}}
.scr{{position:relative;width:{scr_w}px;height:{scr_h}px;border-radius:{scr_r}px;overflow:hidden;background:#fff}}
.scr img{{display:block;width:100%;height:100%}}
.island{{position:absolute;left:50%;transform:translateX(-50%);background:#000;z-index:3}}
.cam{{position:absolute;left:50%;width:12px;height:12px;margin-left:-6px;border-radius:50%;background:#1d2633}}
.sb{{position:absolute;left:0;right:0;top:0;display:flex;align-items:center;justify-content:space-between;
  font-family:"Noto Sans","Noto Sans CJK SC",sans-serif;font-weight:600;color:#111;z-index:2}}
.ic{{display:flex;align-items:center}}
</style></head><body>
<div class="glow"></div><div class="orbit"></div><div class="orbit b"></div>{stars}
<div class="head"><h1>{title}</h1><div class="orn"><b></b><s></s><b></b></div><p class="sub">{sub}</p></div>
<div class="dev">{island}<div class="scr"><img src="{screen_url}">{sb}</div></div>
</body></html>'''


def icons(k):
    c = '#111'
    sig = ''.join(f'<rect x="{i*6}" y="{12-3*(i+1)}" width="4" height="{3*(i+1)}" rx="1" fill="{c}"/>' for i in range(4))
    wifi = (f'<path d="M1 5 Q9 -1 17 5" stroke="{c}" stroke-width="2.2" fill="none" stroke-linecap="round"/>'
            f'<path d="M4.5 8.2 Q9 4.6 13.5 8.2" stroke="{c}" stroke-width="2.2" fill="none" stroke-linecap="round"/>'
            f'<circle cx="9" cy="11.3" r="1.7" fill="{c}"/>')
    bat = (f'<rect x="0.8" y="0.8" width="23" height="11.4" rx="3.4" stroke="{c}" stroke-opacity=".4" fill="none" stroke-width="1.2"/>'
           f'<rect x="2.6" y="2.6" width="17" height="7.8" rx="1.8" fill="{c}"/>'
           f'<rect x="25.2" y="4.3" width="1.6" height="4.4" rx=".8" fill="{c}" fill-opacity=".45"/>')
    s = k * 1.05
    return (f'<svg width="{22*s}" height="{13*s}" viewBox="0 0 22 13" style="margin-right:{6*s}px">{sig}</svg>'
            f'<svg width="{18*s}" height="{13*s}" viewBox="0 0 18 13" style="margin-right:{6*s}px">{wifi}</svg>'
            f'<svg width="{27*s}" height="{13*s}" viewBox="0 0 27 13">{bat}</svg>')


def render(page, dev_key, shot, screen_path, out_path, draft_mark=None, real_capture=False):
    dev = DEVICES[dev_key]
    no, name, pal, raw, title, sub = shot
    scr = fit_screen(screen_path, dev['sw'], dev['sh'], real_capture, dev['pt'], dev['raw'] == 'phone')
    page.set_viewport_size({'width': dev['w'], 'height': dev['h']})
    page.set_content(html(dev, pal, title, sub, data_url(scr), status_bar=True), wait_until='load')
    page.evaluate('document.fonts.ready')
    png = page.screenshot(full_page=False)
    im = Image.open(io.BytesIO(png)).convert('RGB')
    if draft_mark:
        from PIL import ImageDraw, ImageFont
        d = ImageDraw.Draw(im)
        f = ImageFont.truetype(f'{FONT_DIR}/NotoSansCJKsc-Bold.otf', 56)
        d.rectangle((0, dev['h'] // 2 - 110, dev['w'], dev['h'] // 2 + 110), fill='#C0392B')
        for i, line in enumerate(draft_mark.split('\n')):
            d.text((dev['w'] // 2, dev['h'] // 2 + (i - 0.5) * 80), line, font=f, fill='white', anchor='mm')
    assert im.size == (dev['w'], dev['h']), im.size
    im.save(out_path, 'PNG', optimize=True)
    return out_path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--only')
    ap.add_argument('--phone-screen')
    ap.add_argument('--ipad-screen')
    a = ap.parse_args()
    with sync_playwright() as pw:
        b = pw.chromium.launch(executable_path=CHROME)
        page = b.new_page(device_scale_factor=1)
        for dev_key in DEVICES:
            os.makedirs(f'{OUT}/{dev_key}', exist_ok=True)
            os.makedirs(f'{OUT}/_drafts', exist_ok=True)
            for shot in SHOTS:
                no, name, pal, raw, *_ = shot
                if a.only and no != a.only:
                    continue
                custom = a.phone_screen if dev_key == 'iphone69' else a.ipad_screen
                if a.only and custom:
                    print(render(page, dev_key, shot, custom, f'{OUT}/{dev_key}/{no}_{name}.png', real_capture=True))
                elif raw:
                    print(render(page, dev_key, shot, f'{RAW}/{DEVICES[dev_key]["raw"]}/{raw}.png',
                                 f'{OUT}/{dev_key}/{no}_{name}.png'))
                elif no == '06':  # 钓点地图：iOS 上是 Apple 地图，需真机截图；这里只出带标记的 OSM 草稿
                    print(render(page, dev_key, shot, f'{RAW}/{DEVICES[dev_key]["raw"]}/06_map_osm_draft.png',
                                 f'{OUT}/_drafts/{dev_key}_06_fishing_map_DRAFT.png',
                                 draft_mark='草稿 · 不要上传\niOS 实际是 Apple 地图，需真机截图'))
        b.close()


if __name__ == '__main__':
    main()
