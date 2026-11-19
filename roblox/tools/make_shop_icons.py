"""ショップの品のアイコン(512x512 の PNG)を作る。

使い方: python roblox/tools/make_shop_icons.py
出力: roblox/assets/shop/c1.png … c4.png(コインの袋), vip.png(VIP パス)
numpy だけで描く(画像の部品は使わない)。
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

# コインの袋(ShopConfig.lua と同じ順): 名前 → 柱ごとに積むコインの枚数(多い袋ほど山が高い)
PACKS = {"c1": [4], "c2": [4, 6], "c3": [4, 8, 5], "c4": [7, 11, 8]}
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


def coin(img, cx, cy, r):
    """斜めから見た金のコイン1枚(縁・面・刻印・光り)"""
    gold = rgb(GOLD)
    paint(img, ellipse(cx, cy + r * 0.16, r, r * 0.42), gold * 0.55)
    paint(img, ellipse(cx, cy, r, r * 0.42), gold)
    paint(img, ellipse(cx, cy, r * 0.74, r * 0.30), gold * 0.82)
    paint(img, ellipse(cx, cy, r * 0.30, r * 0.12), gold * 1.08)
    paint(img, ellipse(cx - r * 0.35, cy - r * 0.16, r * 0.30, r * 0.08), (1, 1, 1), 0.45)


def coins(img, stacks):
    """コインの山。stacks は柱ごとの枚数(左から)"""
    gold = rgb(GOLD)
    paint(img, ellipse(256, 392, 180, 18), (0, 0, 0), 0.35)
    xs = {1: [256], 2: [204, 308], 3: [150, 256, 362]}[len(stacks)]
    r = {1: 84, 2: 72, 3: 60}[len(stacks)]
    for x, k in zip(xs, stacks):
        for i in range(k):
            coin(img, x, 372 - i * 22, r)
    # きらめき
    for x, y, size in ((112, 112, 16), (404, 96, 12), (300, 54, 9)):
        star = poly([(x, y - size * 2), (x + size * 0.5, y), (x, y + size * 2), (x - size * 0.5, y)])
        star = np.maximum(star, poly([(x - size * 2, y), (x, y - size * 0.5), (x + size * 2, y), (x, y + size * 0.5)]))
        paint(img, star, gold * 1.15)


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
    for key, stacks in PACKS.items():
        img = background(navy_top, navy_bottom, rgb(GOLD) * (0.7 if sum(stacks) < 12 else 1.0))
        water(img)
        coins(img, stacks)
        save_png(os.path.join(OUT, key + ".png"), img)
    img = background((0.16, 0.12, 0.04), (0.05, 0.03, 0.0), rgb(GOLD))
    crown(img)
    save_png(os.path.join(OUT, "vip.png"), img)
    print("ok", OUT)


if __name__ == "__main__":
    main()
