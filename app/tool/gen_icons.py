"""Generates placeholder launcher icons (white "S" on the brand colour).
Replace store_assets/icon_1024.png with a designed logo and re-run."""
import os, sys
from PIL import Image, ImageDraw, ImageFont

BRAND = (214, 51, 108)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, 'android/app/src/main/res')
FONT = '/usr/share/fonts/opentype/inter/InterDisplay-Bold.otf'

def letter(size, scale, bg):
    img = Image.new('RGBA', (size, size), BRAND + (255,) if bg else (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    f = ImageFont.truetype(FONT, int(size * scale))
    box = d.textbbox((0, 0), 'S', font=f)
    w, h = box[2] - box[0], box[3] - box[1]
    d.text(((size - w) / 2 - box[0], (size - h) / 2 - box[1]), 'S', font=f, fill='white')
    return img

src = os.path.join(ROOT, 'store_assets/icon_1024.png')
if not os.path.exists(src) or '--force' in sys.argv:
    letter(1024, 0.62, True).save(src)
base = Image.open(src).convert('RGBA')
base.resize((512, 512), Image.LANCZOS).save(os.path.join(ROOT, 'store_assets/play_store_icon_512.png'))

dens = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
for name, m in dens.items():
    d = os.path.join(RES, f'mipmap-{name}')
    os.makedirs(d, exist_ok=True)
    s = int(48 * m)
    sq = base.resize((s, s), Image.LANCZOS)
    mask = Image.new('L', (s, s), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, s - 1, s - 1), fill=255)
    round_ = Image.new('RGBA', (s, s)); round_.paste(sq, (0, 0), mask)
    round_.save(os.path.join(d, 'ic_launcher.png'))
    letter(int(108 * m), 0.36, False).save(os.path.join(d, 'ic_launcher_foreground.png'))

any_ = os.path.join(RES, 'mipmap-anydpi-v26'); os.makedirs(any_, exist_ok=True)
open(os.path.join(any_, 'ic_launcher.xml'), 'w').write('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
    <monochrome android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
''')
vals = os.path.join(RES, 'values'); os.makedirs(vals, exist_ok=True)
open(os.path.join(vals, 'ic_launcher_background.xml'), 'w').write(
    '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">#%02X%02X%02X</color>\n</resources>\n' % BRAND)
print('icons written')
