"""ショップの品のアイコン(512x512 の PNG)を作る。

使い方: python roblox/tools/make_shop_icons.py
出力: roblox/assets/shop/x1.png … x5.png, vip.png
色は src/Meta.lua の品と同じ。numpy だけで描く(画像の部品は使わない)。
"""
import os
import struct
import zlib

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "shop")
S = 512
SS = 3  # なめらかにするため、3倍の大きさで描いて縮める
N = S * SS

# 品の色(Meta.lua と同じ数)
ITEMS = {
    "x1": {"kind": "skin", "hull": 16245222, "trim": 14707340, "deck": 15979483, "cowl": 14707340},
    "x2": {"kind": "skin", "hull": 1316394, "trim": 2748671, "deck": 921632, "cowl": 16728008},
    "x3": {"kind": "skin", "hull": 11741982, "trim": 15253850, "deck": 8001044, "cowl": 1315860},
    "x4": {"kind": "helmet", "base": 16242399, "stripe": 14239866},
    "x5": {"kind": "helmet", "base": 1053734, "stripe": 2748671},
}
GOLD = 15911244


def rgb(n):
    """数の色を 0〜1 の3つの値にする"""
    return np.array([(n >> 16) & 255, (n >> 8) & 255, n & 255], dtype=float) / 255


YY, XX = np.mgrid[0:N, 0:N].astype(float) / SS


def paint(img, mask, color, alpha=1.0):
    """形の所だけ色を塗る"""
    a = mask[..., None] * alpha
    img[:] = img * (1 - a) + np.asarray(color, dtype=float) * a


def poly(points):
    """多角形の内側(偶奇の決まり)"""
    inside = np.zeros((N, N), dtype=bool)
    n = len(points)
    for i in range(n):
        x1, y1 = points[i]
        x2, y2 = points[(i + 1) % n]
        if y1 == y2:
            continue
        cond = (YY >= min(y1, y2)) & (YY < max(y1, y2))
        xs = x1 + (YY - y1) * (x2 - x1) / (y2 - y1)
        inside ^= cond & (XX < xs)
    return inside.astype(float)


def circle(cx, cy, r):
    return (((XX - cx) ** 2 + (YY - cy) ** 2) <= r * r).astype(float)


def ellipse(cx, cy, rx, ry):
    return ((((XX - cx) / rx) ** 2 + ((YY - cy) / ry) ** 2) <= 1).astype(float)


def rect(x0, y0, x1, y1):
    return ((XX >= x0) & (XX < x1) & (YY >= y0) & (YY < y1)).astype(float)


def background(top, bottom, frame):
    """縦のグラデーションの地と、角の丸い枠"""
    t = (YY / S)[..., None]
    img = np.asarray(top) * (1 - t) + np.asarray(bottom) * t
    # 中央を少し明るく
    glow = np.clip(1 - np.sqrt((XX - S / 2) ** 2 + (YY - S * 0.45) ** 2) / (S * 0.55), 0, 1)
    img = img + (glow ** 2)[..., None] * 0.18
    # 枠(角の丸い四角の帯)
    def rounded(m, r):
        x = np.clip(np.maximum(np.maximum(m + r - XX, XX - (S - m - r)), 0), 0, None)
        y = np.clip(np.maximum(np.maximum(m + r - YY, YY - (S - m - r)), 0), 0, None)
        return (x ** 2 + y ** 2) <= r * r
    outer, inner = rounded(10, 46), rounded(26, 30)
    band = (outer & ~inner).astype(float)
    paint(img, band, frame)
    return img


def water(img):
    """下の方に水面の線を数本"""
    for i, y in enumerate((392, 418, 444)):
        wave = y + 5 * np.sin(XX / 26 + i)
        m = ((YY > wave) & (YY < wave + 5) & (XX > 60) & (XX < 452)).astype(float)
        paint(img, m, (1, 1, 1), 0.22 - i * 0.05)


def boat(img, c):
    """横から見た競艇の艇(左が前)"""
    hull, trim, deck, cowl = rgb(c["hull"]), rgb(c["trim"]), rgb(c["deck"]), rgb(c["cowl"])
    # 影
    paint(img, ellipse(262, 380, 190, 16), (0, 0, 0), 0.35)
    # 船体
    paint(img, poly([(70, 300), (120, 262), (430, 262), (452, 300), (440, 360), (110, 360)]), hull)
    # 船体の下の暗い面
    paint(img, poly([(78, 322), (446, 322), (440, 360), (110, 360)]), hull * 0.62)
    # 縁取りの帯
    paint(img, poly([(92, 300), (448, 300), (446, 314), (84, 314)]), trim)
    # 甲板
    paint(img, poly([(130, 262), (150, 236), (380, 236), (420, 262)]), deck)
    # 選手の座る所(風よけ)
    paint(img, poly([(250, 236), (280, 196), (318, 196), (330, 236)]), (0.75, 0.9, 1.0), 0.75)
    # エンジンのカバー
    paint(img, poly([(408, 250), (420, 190), (470, 190), (476, 260)]), cowl)
    paint(img, rect(420, 196, 468, 206), (1, 1, 1), 0.35)
    # エンジンの軸とプロペラ
    paint(img, rect(440, 260, 452, 352), (0.25, 0.27, 0.3))
    # 光り
    paint(img, poly([(130, 270), (420, 270), (424, 280), (124, 280)]), (1, 1, 1), 0.28)


def helmet(img, c):
    """横から見たヘルメット(左が前)"""
    base, stripe = rgb(c["base"]), rgb(c["stripe"])
    paint(img, ellipse(256, 410, 140, 16), (0, 0, 0), 0.35)
    # 頭の丸い所と下の切り口
    shell = circle(256, 250, 150) * (YY < 330)
    shell = np.maximum(shell, rect(110, 300, 402, 372) * circle(256, 250, 168))
    # 暗い色でも地から見分けられるよう、外側に細い明るい縁
    edge = circle(256, 250, 158) * (YY < 372) * (1 - shell)
    paint(img, edge, (0.75, 0.85, 1.0), 0.5)
    paint(img, shell, base)
    # 影(右下を暗く)
    shade = shell * np.clip((XX - 256) / 200 + (YY - 250) / 260, 0, 1)
    paint(img, shade, (0, 0, 0), 0.28)
    # まん中の線
    band = shell * (np.abs((XX - 256) * 0.35 + (YY - 250) * 1.0 + 40) < 24)
    paint(img, band, stripe)
    # 顔の窓(バイザー)
    visor = poly([(106, 230), (210, 222), (238, 300), (114, 320)]) * circle(256, 250, 156)
    paint(img, visor, (0.08, 0.1, 0.14))
    paint(img, poly([(118, 238), (196, 232), (204, 252), (122, 258)]) * visor, (1, 1, 1), 0.35)
    # 下の縁
    paint(img, rect(108, 358, 404, 374) * circle(256, 250, 170), (0.12, 0.12, 0.14))
    # 光り
    paint(img, ellipse(300, 160, 70, 26), (1, 1, 1), 0.3)


def crown(img):
    """VIP パスの金の冠"""
    gold = rgb(GOLD)
    paint(img, ellipse(256, 400, 150, 16), (0, 0, 0), 0.35)
    body = poly([(120, 360), (106, 190), (186, 270), (256, 150), (326, 270), (406, 190), (392, 360)])
    paint(img, body, gold)
    paint(img, body * np.clip((XX - 200) / 260, 0, 1), (0.55, 0.32, 0.0), 0.35)
    paint(img, rect(120, 330, 392, 368), gold * 0.8)
    for x, y, r in ((106, 186, 18), (256, 146, 20), (406, 186, 18)):
        paint(img, circle(x, y, r), gold)
        paint(img, circle(x - 5, y - 5, r * 0.35), (1, 1, 1), 0.6)
    for x, col in ((180, (0.86, 0.12, 0.2)), (256, (0.1, 0.45, 0.9)), (332, (0.86, 0.12, 0.2))):
        paint(img, circle(x, 300, 16), col)


def save_png(path, img):
    """縮めて PNG に書く(画像の部品なし)"""
    small = img.reshape(S, SS, S, SS, 3).mean(axis=(1, 3))
    data = (np.clip(small, 0, 1) * 255 + 0.5).astype(np.uint8)
    raw = b"".join(b"\x00" + data[y].tobytes() for y in range(S))

    def chunk(tag, body):
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", S, S, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def main():
    os.makedirs(OUT, exist_ok=True)
    navy_top, navy_bottom = (0.06, 0.13, 0.27), (0.02, 0.05, 0.12)
    for key, c in ITEMS.items():
        img = background(navy_top, navy_bottom, (0.86, 0.33, 0.95))  # SR の紫の枠
        water(img)
        (boat if c["kind"] == "skin" else helmet)(img, c)
        save_png(os.path.join(OUT, key + ".png"), img)
    img = background((0.16, 0.12, 0.04), (0.05, 0.03, 0.0), rgb(GOLD))
    crown(img)
    save_png(os.path.join(OUT, "vip.png"), img)
    print("ok", OUT)


if __name__ == "__main__":
    main()
