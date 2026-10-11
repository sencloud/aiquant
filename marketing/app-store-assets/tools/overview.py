from PIL import Image, ImageDraw, ImageFont
import glob, os
# 截图总览 → marketing/app-store-assets/overview.png。SHOT_FONT_DIR = Noto Sans CJK SC 目录。
R=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT_DIR=os.environ.get('SHOT_FONT_DIR','/workspace/fonts')
f=ImageFont.truetype(f'{FONT_DIR}/NotoSansCJKsc-Regular.otf',26)
fb=ImageFont.truetype(f'{FONT_DIR}/NotoSansCJKsc-Bold.otf',34)
rows=[('iPhone 6.9"  1320×2868',sorted(glob.glob(f'{R}/iphone69/*.png'))+sorted(glob.glob(f'{R}/_drafts/iphone69_*.png')),330),
      ('iPad 13"  2064×2752',sorted(glob.glob(f'{R}/ipad13/*.png'))+sorted(glob.glob(f'{R}/_drafts/ipad13_*.png')),330)]
pad=24; cols=max(len(r[1]) for r in rows)
cellw=[]; 
for title,fs,w in rows:
    im=Image.open(fs[0]); cellw.append((w, round(w*im.height/im.width)))
W=pad+cols*(330+pad); H=pad+sum(60+h+50 for _,h in cellw)+pad
sheet=Image.new('RGB',(W,H),'#f4f2ef'); d=ImageDraw.Draw(sheet); y=pad
for (title,fs,w),(cw,ch) in zip(rows,cellw):
    d.text((pad,y),title,font=fb,fill='#222'); y+=60
    for i,p in enumerate(fs):
        x=pad+i*(cw+pad); sheet.paste(Image.open(p).convert('RGB').resize((cw,ch),Image.LANCZOS),(x,y))
        d.text((x,y+ch+8),os.path.basename(p).replace('.png',''),font=f,fill='#C0392B' if 'DRAFT' in p else '#444')
    y+=ch+50
sheet.save(f'{R}/overview.png'); print(sheet.size)
