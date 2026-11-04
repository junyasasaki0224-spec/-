"""render_marketing.py が描いた絵に、題字と一言を重ね、Roblox の大きさにする(Pillow)。

  python3 tools/marketing/compose.py build/marketing_raw assets/marketing

字体: tools/marketing/fonts/ の Yuji Syuku(筆の題字)・Dela Gothic One(一言)。無ければ IPA ゴシック。
どちらも SIL Open Font License(Google Fonts)。リポジトリには入れない。
"""

import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONT_DIR = os.path.join(HERE, "fonts")
FALLBACK = "/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf"

TEXTS = {
    "thumb_collection": "95種の妖怪魚を釣って、図鑑をうめよう",
    "thumb_sea": "海には、鮫・鯱・鯨の大物がいる",
    "thumb_attack": "釣った妖怪で、水の中のバトル",
    "thumb_boss": "最大4人で、ボスの大鯰に挑め",
}


def font(names, size):
    for n in names:
        p = os.path.join(FONT_DIR, n)
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.truetype(FALLBACK, size)


def with_shadow(img, layer, offset):
    shadow = layer.split()[3].filter(ImageFilter.GaussianBlur(radius=offset * 1.5))
    dark = Image.new("RGBA", img.size, (0, 0, 0, 170))
    img.paste(dark, (offset, offset), shadow)
    return Image.alpha_composite(img, layer)


def title_layer(size, square, subtitle):
    W, H = size
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    gold, ink = (255, 236, 190, 255), (70, 18, 20, 255)
    if square:
        tf = font(["YujiSyuku-Regular.ttf", "DelaGothicOne-Regular.ttf"], int(W * 0.21))
        d.text((W * 0.06, H * 0.03), "あやかし", font=tf, fill=gold, stroke_width=int(W * 0.02), stroke_fill=ink)
        w = d.textlength("釣り", font=tf)
        d.text((W - w - W * 0.07, H * 0.25), "釣り", font=tf, fill=gold, stroke_width=int(W * 0.02), stroke_fill=ink)
    else:
        tf = font(["YujiSyuku-Regular.ttf", "DelaGothicOne-Regular.ttf"], int(H * 0.17))
        sf = font(["DelaGothicOne-Regular.ttf", "YujiSyuku-Regular.ttf"], int(H * 0.06))
        d.text((W * 0.045, H * 0.04), "あやかし釣り", font=tf, fill=gold, stroke_width=int(H * 0.014), stroke_fill=ink)
        if subtitle:
            w = d.textlength(subtitle, font=sf)
            pad = H * 0.022
            x, y = W * 0.045, H * 0.85
            d.rounded_rectangle((x - pad, y - pad * 0.7, x + w + pad, y + H * 0.06 + pad * 1.1), radius=int(H * 0.03), fill=(150, 40, 34, 235))
            d.text((x, y), subtitle, font=sf, fill=(255, 250, 240, 255))
    return layer


def main():
    raw, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    icon = os.path.join(raw, "icon.png")
    if os.path.exists(icon):
        img = Image.open(icon).convert("RGBA")
        img.resize((512, 512), Image.LANCZOS).convert("RGB").save(os.path.join(out, "icon_plain.png"))
        img = with_shadow(img, title_layer(img.size, True, ""), int(img.size[0] * 0.006))
        img.resize((512, 512), Image.LANCZOS).convert("RGB").save(os.path.join(out, "icon.png"))
        print("icon.png / icon_plain.png")
    for name, sub in TEXTS.items():
        p = os.path.join(raw, name + ".png")
        if not os.path.exists(p):
            continue
        img = Image.open(p).convert("RGBA")
        img = with_shadow(img, title_layer(img.size, False, sub), int(img.size[1] * 0.005))
        img.convert("RGB").save(os.path.join(out, name + ".png"))
        print(name + ".png")


if __name__ == "__main__":
    main()
