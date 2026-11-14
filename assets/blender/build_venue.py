"""みなと競艇場の固定構造物を生成して GLB に書き出す。
  python build_venue.py <出力.glb> [プレビュー画像の出力先ディレクトリ]
ここではゲームと同じ座標 (x=ホーム方向, y=上, z=スタンド側) で書き、P() で Blender 座標へ直す。
AO は頂点カラーに焼く。Glass / Lamp マテリアルはゲーム側で差し替える(UV 付き)。"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh
from mathutils import Vector, Matrix, Euler
from bl_util import *

OUT = sys.argv[1] if len(sys.argv) > 1 else 'venue.glb'
PREV = sys.argv[2] if len(sys.argv) > 2 else None
reset()

QUAY = 1.6
MINX, MAXX, MINZ, MAXZ = -262, 252, -78, 58
def P(x, y, z): return Vector((x, -z, y))

mat('Concrete', (0.62, 0.61, 0.57), 0.9)
mat('ConcreteDark', (0.4, 0.4, 0.38), 0.92)
mat('ConcreteLight', (0.76, 0.75, 0.71), 0.88)
mat('Asphalt', (0.2, 0.21, 0.22), 0.95)
mat('Grass', (0.2, 0.36, 0.14), 1.0)
mat('Algae', (0.1, 0.13, 0.09), 0.6)
mat('Steel', (0.42, 0.45, 0.48), 0.55, 0.6)
mat('White', (0.88, 0.88, 0.86), 0.6)
mat('Dark', (0.05, 0.055, 0.065), 0.7)
mat('Red', (0.62, 0.05, 0.06), 0.5)
mat('Blue', (0.06, 0.2, 0.6), 0.5)
mat('Yellow', (0.85, 0.6, 0.04), 0.5)
mat('Orange', (0.85, 0.3, 0.03), 0.5)
mat('Roof', (0.78, 0.8, 0.82), 0.5, 0.3)
mat('SeatBlue', (0.08, 0.25, 0.62), 0.6)
mat('SeatOrange', (0.86, 0.38, 0.06), 0.6)
mat('BarrierA', (0.56, 0.62, 0.66), 0.7)
mat('BarrierB', (0.4, 0.46, 0.5), 0.7)
mat('BarrierY', (0.82, 0.62, 0.06), 0.7)
mat('Wood', (0.36, 0.25, 0.14), 0.8)
mat('Glass', (0.25, 0.4, 0.52), 0.1, 0.8)
mat('Lamp', (0.9, 0.9, 0.86), 0.4)

def ry_(v, a): c, s = math.cos(a), math.sin(a); return Vector((v.x * c + v.z * s, v.y, -v.x * s + v.z * c))
def rx_(v, a): c, s = math.cos(a), math.sin(a); return Vector((v.x, v.y * c - v.z * s, v.y * s + v.z * c))

class VB(Builder):
    def bx(self, m, cx, cy, cz, w, h, d, ry=0.0, rx=0.0, bevel=0.0):
        return self.box(m, (w, d, h), tuple(P(cx, cy, cz)), (rx, 0, ry), bevel=bevel)
    def cy(self, m, cx, cy, cz, r, h, r2=None, seg=12):
        return self.cyl(m, r, h, tuple(P(cx, cy, cz)), r2=r2, seg=seg)
    def quad(self, m, c, w, h, ry=0.0, rx=0.0, uv=(1, 1), off=0.0):
        """ローカル XY 平面の四角(法線 +z)を rx→ry の順に回して置く"""
        pts = []
        for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            v = Vector((sx * w / 2, sy * h / 2, off))
            pts.append(P(*(ry_(rx_(v, rx), ry) + Vector(c))))
        return self.face([self.vert(p) for p in pts], m, [(0, 0), (uv[0], 0), (uv[0], uv[1]), (0, uv[1])])
    def grid(self, m, x0, x1, z0, z1, y, cell):
        nx, nz = max(1, round((x1 - x0) / cell)), max(1, round((z1 - z0) / cell))
        vs = [[self.vert(P(x0 + (x1 - x0) * i / nx, y, z0 + (z1 - z0) * j / nz)) for j in range(nz + 1)] for i in range(nx + 1)]
        for i in range(nx):
            for j in range(nz):
                self.face([vs[i][j], vs[i][j + 1], vs[i + 1][j + 1], vs[i + 1][j]], m, smooth=False)
    def wall(self, m, x0, z0, x1, z1, y0, y1, cell=6.0):
        """鉛直な壁を水平方向に分割して張る(AO 用)"""
        L = math.hypot(x1 - x0, z1 - z0); n = max(1, round(L / cell))
        a = [(self.vert(P(x0 + (x1 - x0) * i / n, y0, z0 + (z1 - z0) * i / n)), self.vert(P(x0 + (x1 - x0) * i / n, y1, z0 + (z1 - z0) * i / n))) for i in range(n + 1)]
        for i in range(n): self.face([a[i][0], a[i + 1][0], a[i + 1][1], a[i][1]], m, smooth=False)

def done(b, name): return b.build(name, sharp_angle=30, merge=1e-4)

# ================= 陸地と護岸 =================
B = VB()
ZF = MAXZ + 0.8          # スタンド側護岸の水際
# スタンド前: 階段護岸 → エプロン
for k in range(3):
    B.grid('Concrete', -440, 440, ZF + k * 0.9, ZF + (k + 1) * 0.9, 0.25 + k * 0.45, 8)
    B.wall('Concrete' if k else 'Algae', -440, ZF + k * 0.9, 440, ZF + k * 0.9, -2.5 if k == 0 else 0.25 + (k - 1) * 0.45, 0.25 + k * 0.45, 8)
B.wall('Concrete', -440, ZF + 2.7, 440, ZF + 2.7, 1.15, QUAY, 8)
B.grid('ConcreteLight', -440, 440, ZF + 2.7, 72, QUAY, 4)
B.grid('Asphalt', -440, 440, 119, 330, QUAY, 30)
B.grid('Asphalt', -440, -150, 72, 119, QUAY, 10)
B.grid('Asphalt', 190, 440, 72, 119, QUAY, 10)
# 対岸の堤
ZB = MINZ - 0.8
B.wall('Algae', 300, ZB, -300, ZB, -2.5, 0.35, 8); B.wall('Concrete', 300, ZB, -300, ZB, 0.35, QUAY, 8)
B.grid('Concrete', -300, 300, ZB - 7, ZB, QUAY, 4)
B.grid('Grass', -300, 300, ZB - 19, ZB - 7, QUAY + 0.05, 6)
B.grid('Asphalt', -300, 300, ZB - 40, ZB - 19, QUAY, 20)
# 1マーク奥
XR = MAXX + 0.8
B.wall('Algae', XR, ZF, XR, ZB, -2.5, 0.35, 8); B.wall('Concrete', XR, ZF, XR, ZB, 0.35, QUAY, 8)
B.grid('Concrete', XR, XR + 9, ZB - 19, ZF, QUAY, 4)
B.grid('Grass', XR + 9, XR + 24, ZB - 19, ZF, QUAY + 0.05, 6)
B.grid('Asphalt', XR + 24, 440, ZB - 40, ZF + 14, QUAY, 30)
# ピット側
XL = MINX - 29
B.wall('Algae', XL, ZB, XL, ZF, -2.5, 0.35, 8); B.wall('Concrete', XL, ZB, XL, ZF, 0.35, QUAY, 8)
B.wall('Algae', -300, ZB, XL, ZB, -2.5, 0.35, 8); B.wall('Concrete', -300, ZB, XL, ZB, 0.35, QUAY, 8)
B.grid('Concrete', -440, XL, ZB - 19, ZF, QUAY, 6)
land = done(B, 'Land')

# ================= 消波装置 =================
B = VB()
k = 0
def barrier(x, z, ry):
    global k
    m = 'BarrierY' if k % 7 == 3 else ('BarrierA' if k % 2 else 'BarrierB'); k += 1
    B.bx(m, x, 0.18, z, 6.0, 0.8, 1.1, ry)
    B.bx('Dark', x, 0.62, z, 6.02, 0.1, 0.9, ry)
x = MINX + 3
while x < MAXX: barrier(x, MAXZ + 0.1, 0); barrier(x, MINZ - 0.1, 0); x += 6.4
z = MINZ + 3
while z < MAXZ:
    if not (-21 < z < 44): barrier(MINX - 0.1, z, math.pi / 2)     # ピットの前はあけておく(艇の出入口)
    barrier(MAXX + 0.1, z, math.pi / 2); z += 6.4
barriers = done(B, 'Barriers')

# ================= スタンド =================
B = VB()
SX0, SX1, BAY = -150, 190, 8.5
NB = round((SX1 - SX0) / BAY)
ROWS, TZ0, TD, TR = 12, 72.0, 1.5, 0.62
for bi in range(NB):
    x0, x1 = SX0 + bi * BAY, SX0 + (bi + 1) * BAY
    aisle = (bi % 4 == 0)
    seat = 'SeatBlue' if (bi // 4) % 2 == 0 else 'SeatOrange'
    for i in range(ROWS):
        y0, y1, z0 = QUAY + TR * i, QUAY + TR * (i + 1), TZ0 + TD * i
        v = [B.vert(P(x0, y0, z0)), B.vert(P(x1, y0, z0)), B.vert(P(x1, y1, z0)), B.vert(P(x0, y1, z0)), B.vert(P(x0, y1, z0 + TD)), B.vert(P(x1, y1, z0 + TD))]
        B.face([v[0], v[1], v[2], v[3]], 'Concrete', smooth=False)
        B.face([v[3], v[2], v[5], v[4]], 'ConcreteLight', smooth=False)
        sx0 = x0 + (1.5 if aisle else 0.15)
        B.bx(seat, (sx0 + x1 - 0.15) / 2, y1 + 0.4, z0 + 0.95, x1 - 0.15 - sx0, 0.07, 0.42)
        B.bx(seat, (sx0 + x1 - 0.15) / 2, y1 + 0.62, z0 + 1.2, x1 - 0.15 - sx0, 0.4, 0.05, 0, -0.2)
        B.bx('Steel', (sx0 + x1 - 0.15) / 2, y1 + 0.2, z0 + 0.95, x1 - 0.6 - sx0, 0.4, 0.06)
    if aisle:   # 通路の手すり
        for i in (0, ROWS):
            B.cy('Steel', x0 + 0.1, QUAY + TR * i + 0.55, TZ0 + TD * i, 0.035, 1.1, seg=6)
        a, b_ = P(x0 + 0.1, QUAY + 1.1, TZ0), P(x0 + 0.1, QUAY + TR * ROWS + 1.1, TZ0 + TD * ROWS)
        B.tube('Steel', [a, b_], 0.035, 6)
TOPY, TOPZ = QUAY + TR * ROWS, TZ0 + TD * ROWS        # 最上段 (y=9.04, z=90)
B.grid('ConcreteLight', SX0, SX1, TOPZ, TOPZ + 4, TOPY, BAY)
B.wall('ConcreteDark', SX1, TOPZ + 4, SX0, TOPZ + 4, QUAY, TOPY + 0.6, BAY)       # コンコース入口の奥壁
# 妻側の壁
for x in (SX0, SX1):
    v = [B.vert(P(x, QUAY, TZ0)), B.vert(P(x, TOPY, TOPZ)), B.vert(P(x, TOPY, TOPZ + 4)), B.vert(P(x, QUAY, TOPZ + 4))]
    B.face(v, 'Concrete', smooth=False)
# 最前列の柵
B.tube('White', [P(SX0, QUAY + 1.05, TZ0 - 0.4), P(SX1, QUAY + 1.05, TZ0 - 0.4)], 0.04, 6)
B.tube('White', [P(SX0, QUAY + 0.55, TZ0 - 0.4), P(SX1, QUAY + 0.55, TZ0 - 0.4)], 0.03, 6)
x = SX0
while x <= SX1: B.cy('White', x, QUAY + 0.52, TZ0 - 0.4, 0.04, 1.05, seg=6); x += BAY / 4
# 上層階: 床スラブ・柱・ガラス
FZ, BZ = 84.2, 116.0                 # ガラス面と背面
F0, FH, NF = TOPY + 0.6, 5.8, 3
for kf in range(NF + 1):
    y = F0 + kf * FH
    B.bx('ConcreteLight', (SX0 + SX1) / 2, y, (FZ - 0.9 + BZ) / 2, SX1 - SX0 + 1.2, 0.55, BZ - FZ + 0.9)
    if kf < NF:
        B.bx('White', (SX0 + SX1) / 2, y + 0.75, FZ - 0.75, SX1 - SX0, 0.06, 0.06)     # 手すり
for bi in range(NB + 1):
    x = SX0 + bi * BAY
    B.bx('ConcreteLight', x, (QUAY + F0 + NF * FH) / 2 + 0.3, FZ + 0.25, 0.75, F0 + NF * FH - QUAY, 0.75)
    if bi % 2 == 0: B.bx('Concrete', x, (QUAY + TOPY) / 2 + 4, TOPZ + 3.6, 0.8, 8.6 + TOPY - QUAY, 0.8)
for kf in range(NF):
    y = F0 + kf * FH + 0.28
    for bi in range(NB):
        x0 = SX0 + bi * BAY
        B.quad('Glass', (x0 + BAY / 2, y + (FH - 0.55) / 2, FZ + 0.4), BAY - 0.75, FH - 0.55, math.pi, 0, uv=(4, 1))
        for q in range(1, 4): B.bx('White', x0 + BAY * q / 4, y + (FH - 0.55) / 2, FZ + 0.36, 0.09, FH - 0.55, 0.12)
        B.bx('White', x0 + BAY / 2, y + 1.1, FZ + 0.36, BAY - 0.75, 0.08, 0.12)
RY = F0 + NF * FH                    # 屋根下面
B.wall('Concrete', SX0, FZ, SX0, BZ, TOPY, RY, 8); B.wall('Concrete', SX1, BZ, SX1, FZ, TOPY, RY, 8)
B.wall('Concrete', SX1, BZ, SX0, BZ, QUAY, RY, 17)
# 大屋根(前へせり出す片持ち)とトラス
RZ0 = 70.5
for bi in range(NB):
    x0 = SX0 + bi * BAY
    v = [B.vert(P(x0, RY + 2.6, RZ0)), B.vert(P(x0 + BAY, RY + 2.6, RZ0)), B.vert(P(x0 + BAY, RY + 0.9, BZ + 2)), B.vert(P(x0, RY + 0.9, BZ + 2))]
    B.face(v, 'Roof', smooth=False)
    w = [B.vert(P(x0, RY + 2.2, RZ0)), B.vert(P(x0 + BAY, RY + 2.2, RZ0)), B.vert(P(x0 + BAY, RY + 0.5, BZ + 2)), B.vert(P(x0, RY + 0.5, BZ + 2))]
    B.face(w[::-1], 'ConcreteLight', smooth=False)
B.bx('Blue', (SX0 + SX1) / 2, RY + 2.4, RZ0 - 0.15, SX1 - SX0 + 2, 1.5, 0.3)
for x in (SX0 - 0.5, SX1 + 0.5): B.bx('Roof', x, RY + 1.55, (RZ0 + BZ + 2) / 2, 1.0, 2.2, BZ + 2 - RZ0)
for bi in range(0, NB + 1, 2):
    x = SX0 + bi * BAY
    B.tube('Steel', [P(x, RY + 2.0, RZ0 + 0.6), P(x, RY + 0.7, FZ + 0.3)], 0.16, 6)       # 下弦材
    B.tube('Steel', [P(x, RY + 5.5, FZ + 0.3), P(x, RY + 2.5, RZ0 + 0.6)], 0.11, 6)       # 吊り材
    B.tube('Steel', [P(x, RY + 0.5, FZ + 0.3), P(x, RY + 5.5, FZ + 0.3)], 0.2, 6)          # マスト
    B.tube('Steel', [P(x, RY + 5.5, FZ + 0.3), P(x, RY + 1.2, BZ - 2)], 0.11, 6)
# 屋根先端の照明
for bi in range(NB):
    B.quad('Lamp', (SX0 + bi * BAY + BAY / 2, RY + 1.75, RZ0 + 1.2), 5.2, 0.9, math.pi, 0.75, uv=(0.6, 0.25))
    B.bx('Dark', SX0 + bi * BAY + BAY / 2, RY + 1.8, RZ0 + 1.45, 5.6, 0.5, 1.1, 0, 0.75)
# 屋上看板の枠(文字面はゲーム側)
B.bx('Dark', 20, RY + 8.4, BZ - 36.0, 97, 9.6, 0.5)
for x in range(-24, 65, 11):
    B.tube('Steel', [P(x, RY + 2.4, BZ - 34.5), P(x, RY + 12.6, BZ - 35.6)], 0.14, 6)
    B.tube('Steel', [P(x, RY + 2.0, BZ - 30), P(x, RY + 10, BZ - 35.6)], 0.1, 6)
# 両端の階段棟
for x in (SX0 - 9, SX1 + 9):
    B.bx('Concrete', x, QUAY + 13, 100, 16, 26, 30, bevel=0.0)
    B.bx('ConcreteDark', x, QUAY + 26.3, 100, 17, 0.6, 31)
    for kf in range(4): B.quad('Glass', (x, QUAY + 4 + kf * 6, 84.98), 9, 3.2, math.pi, 0, uv=(4, 0.6))
stand = done(B, 'Stand')

# ================= 審判塔・大時計の台・センターポール・距離標 =================
B = VB()
B.bx('ConcreteLight', 10, QUAY + 6.5, 66, 5, 13, 5)
for y in (QUAY + 13.2, QUAY + 17.7): B.bx('Roof', 10, y, 66, 9.6, 0.5, 9.6)
for a in range(4):
    c = ry_(Vector((0, 0, 4.0)), a * math.pi / 2) + Vector((10, QUAY + 15.45, 66))
    B.quad('Glass', tuple(c), 8, 3.9, a * math.pi / 2, 0, uv=(4, 0.7))
for sx in (-1, 1):
    for sz in (-1, 1): B.bx('White', 10 + sx * 4, QUAY + 15.45, 66 + sz * 4, 0.3, 4, 0.3)
B.cy('Steel', 10, QUAY + 21, 66, 0.08, 6, seg=6)
B.bx('Steel', 9, QUAY + 19, 65, 1.2, 1.6, 0.2)
for k in range(8):   # 外階段
    B.bx('Steel', 13.2, QUAY + 0.8 + k * 1.5, 64 + (k % 2) * 2.6, 1.2, 0.12, 2.6)
# 大時計の支柱
B.bx('Steel', 0.6, QUAY + 2.2, 62.2, 0.9, 6, 0.9)
B.bx('ConcreteDark', 0.6, QUAY + 0.2, 62.2, 2.4, 0.4, 2.4)
# センターポール
PX, PZ = 0, 4
B.cy('White', PX, 0.2, PZ, 1.0, 0.55, seg=18)
B.cy('White', PX, 6.8, PZ, 0.14, 13, r2=0.2, seg=10)
for i in range(3): B.cy('Yellow' if i % 2 else 'Red', PX, 2.2 + i * 1.6, PZ, 0.24, 0.8, seg=10)
B.cy('Red', PX, 13.5, PZ, 0.35, 0.35, seg=10)
B.tube('Dark', [P(0, 12.6, 4), P(0, 12.6, 61)], 0.03, 5)
for d in (50, 100, 150, 200): B.bx('Steel', -d, QUAY + 1.0, 59.4, 0.15, 2.0, 0.15)
# 対岸の大型映像装置の筐体
SCX, SCZ = 38, MINZ - 10.3
B.bx('Dark', SCX, QUAY + 13, SCZ, 44.6, 18, 1.8)
B.bx('Steel', SCX, QUAY + 22.3, SCZ, 45.4, 0.6, 2.6)
for x in (SCX - 15, SCX + 15):
    B.bx('Steel', x, QUAY + 2.2, SCZ - 0.4, 1.4, 4.4, 1.4)
    B.tube('Steel', [P(x, QUAY + 0.2, SCZ - 5), P(x, QUAY + 12, SCZ - 1)], 0.25, 6)
B.bx('Steel', SCX, QUAY + 4.2, SCZ - 1.6, 44, 0.12, 1.2)
B.tube('Steel', [P(SCX - 22, QUAY + 5.3, SCZ - 2.2), P(SCX + 22, QUAY + 5.3, SCZ - 2.2)], 0.04, 5)
# 広告看板の枠
x = MINX + 8
while x < MAXX - 4:
    B.bx('Dark', x, QUAY + 1.3, MINZ - 1.68, 12.3, 2.5, 0.22)
    for dx in (-5, 5): B.bx('Steel', x + dx, QUAY + 0.6, MINZ - 2.0, 0.12, 1.2, 0.5)
    x += 13
z = MINZ + 10
while z < MAXZ - 6:
    B.bx('Dark', MAXX + 1.78, QUAY + 1.3, z, 0.22, 2.5, 12.3)
    z += 13
# スタンド前の水際の柵
B.tube('White', [P(-262, QUAY + 1.1, 61.7), P(252, QUAY + 1.1, 61.7)], 0.04, 5)
B.tube('White', [P(-262, QUAY + 0.6, 61.7), P(252, QUAY + 0.6, 61.7)], 0.03, 5)
x = -262
while x <= 252: B.cy('White', x, QUAY + 0.55, 61.7, 0.045, 1.1, seg=6); x += 4
struct = done(B, 'Structures')

# ================= ナイター照明塔 =================
B = VB()
def tower(x, z, ry):
    B.cy('Steel', x, QUAY + 18, z, 0.42, 36, r2=0.75, seg=10)
    B.cy('ConcreteDark', x, QUAY + 0.4, z, 1.3, 0.8, seg=10)
    B.cy('Steel', x, QUAY + 33, z, 1.5, 0.15, seg=10)
    for a in range(8):
        d = ry_(Vector((1.5, 0, 0)), a * math.pi / 4)
        B.cy('Steel', x + d.x, QUAY + 33.6, z + d.z, 0.03, 1.1, seg=4)
    c = Vector((x, QUAY + 38, z))
    B.bx('Dark', c.x, c.y, c.z, 11, 6.4, 0.6, ry, 0.35)
    B.quad('Lamp', tuple(c), 10.2, 5.6, ry, 0.35, uv=(1, 1), off=0.32)
    for sx in (-3.4, 3.4):
        p0 = ry_(rx_(Vector((sx, -2, -0.4)), 0.35), ry) + c
        B.tube('Steel', [P(x, QUAY + 35, z), P(*p0)], 0.09, 5)
for x in (-215, -75, 95, 215): tower(x, MINZ - 14, 0)
tower(MAXX + 18, -40, -math.pi / 2); tower(MAXX + 18, 25, -math.pi / 2); tower(-300, -55, math.pi / 2)
towers = done(B, 'Towers')

# ================= ピット =================
B = VB()
B.bx('ConcreteDark', -277.5, 0.15, 12, 27, 0.8, 66)
B.bx('Wood', -277.5, 0.57, 12, 26.6, 0.05, 65.6)
B.bx('Roof', -279, 5.7, 13, 26, 0.3, 60, 0, 0, 0)
B.bx('Blue', -265.9, 5.5, 13, 0.25, 0.9, 60)
for i in range(7):
    for x in (-267, -290): B.bx('Steel', x, 3.1, -17 + i * 10, 0.28, 5.2, 0.28)
    B.bx('Steel', -278.5, 5.45, -17 + i * 10, 23.5, 0.3, 0.2)
for i in range(6):
    B.bx('White', -271.5, 0.72, -17 + i * 10, 0.25, 0.5, 9)
    B.bx('Dark', -266.0, 4.2, -12 + i * 10, 0.2, 2.5, 2.5)          # 艇番表示の枠
B.bx('ConcreteLight', -316, QUAY + 5, 10, 40, 10, 84)
B.bx('Roof', -316, QUAY + 10.3, 10, 41.5, 0.6, 85.5)
for kf in range(2):
    for i in range(10): B.quad('Glass', (-295.92, QUAY + 2.8 + kf * 4.6, -27 + i * 8.2), 6, 2.2, math.pi / 2, 0, uv=(3, 0.5))
B.bx('Concrete', -300, QUAY + 0.5, -40, 20, 1.0, 10)                 # 揚降機の台
B.bx('Yellow', -296, QUAY + 4, -40, 0.6, 8, 0.6); B.bx('Yellow', -287, QUAY + 7.8, -40, 18, 0.6, 0.6)
# 救助艇
for x, z, ry in ((205, -66, 0.2), (-236, -68, 2.9)):
    B.bx('Orange', x, 0.3, z, 5.4, 0.9, 2.1, ry, 0, bevel=0.15)
    c = ry_(Vector((-0.5, 0, 0)), ry)
    B.bx('White', x + c.x, 1.25, z + c.z, 1.9, 1.1, 1.6, ry)
    B.cy('Steel', x, 2.5, z, 0.04, 1.6, seg=5)
pit = done(B, 'Pit')

# ================= 会場の外: スタンド背面・正面入口・広場・駐車場・道路 =================
B = VB()
ZBK = BZ + 0.07
YG = QUAY + 0.06                       # 地面に描く線や舗装の高さ
def strip(m, x0, x1, z0, z1, y=YG): B.grid(m, x0, x1, z0, z1, y, 999)
# スタンド背面: 各階の窓、柱型、軒の青帯、1階のガラス
for kf in range(NF):
    y = F0 + kf * FH + 0.28
    for bi in range(NB):
        B.quad('Glass', (SX0 + bi * BAY + BAY / 2, y + 2.4, ZBK), BAY - 2.0, 2.8, 0, 0, uv=(3, 0.6))
    B.bx('White', (SX0 + SX1) / 2, y + 0.75, BZ + 0.15, SX1 - SX0, 0.18, 0.3)
for bi in range(NB + 1): B.bx('ConcreteLight', SX0 + bi * BAY, (QUAY + RY) / 2, BZ + 0.22, 0.8, RY - QUAY, 0.5)
B.bx('Blue', (SX0 + SX1) / 2, RY - 0.5, BZ + 0.3, SX1 - SX0 + 1, 1.3, 0.35)
for bi in range(NB):
    if bi % 4 != 3: B.quad('Glass', (SX0 + bi * BAY + BAY / 2, QUAY + 2.3, ZBK), BAY - 1.6, 3.4, 0, 0, uv=(3, 1))
    else: B.bx('Steel', SX0 + bi * BAY + BAY / 2, QUAY + 1.9, BZ + 0.12, BAY - 2.2, 3.8, 0.2)      # 搬入口のシャッター
# 正面入口: 大きな庇、柱、入場ゲート、階段
EX = 20
B.bx('Roof', EX, QUAY + 7.4, BZ + 9.5, 66, 0.45, 19)
B.bx('ConcreteLight', EX, QUAY + 7.0, BZ + 9.5, 65, 0.35, 18.4)
B.bx('Blue', EX, QUAY + 8.5, BZ + 19.0, 66, 1.9, 0.5)
for x in range(EX - 30, EX + 31, 12):
    B.cy('White', x, QUAY + 3.6, BZ + 17.6, 0.4, 7.2, seg=12)
    B.bx('Steel', x, QUAY + 7.0, BZ + 9.5, 0.3, 0.5, 18)
for i in range(9):
    x = EX - 20 + i * 5
    B.bx('ConcreteDark', x, QUAY + 0.55, BZ + 5.5, 1.0, 1.1, 2.6); B.bx('Steel', x, QUAY + 1.15, BZ + 5.5, 1.05, 0.08, 2.7)
    B.bx('Yellow', x, QUAY + 0.95, BZ + 6.9, 1.02, 0.25, 0.1)
for side in (-1, 1):                    # 入口わきの案内板
    B.bx('Dark', EX + side * 37, QUAY + 2.2, BZ + 12, 0.3, 3.2, 5); B.bx('Steel', EX + side * 37, QUAY + 0.3, BZ + 12, 0.5, 0.6, 5.4)
# 広場: 明るい舗装と目地、植えます、ベンチ、旗ざお
B.grid('ConcreteLight', SX0 - 14, SX1 + 14, 119.2, 147, QUAY + 0.05, 9)
for z in (126, 133, 140): strip('Concrete', SX0 - 14, SX1 + 14, z - 0.12, z + 0.12, QUAY + 0.07)
x = SX0 - 5
while x < SX1 + 6:
    strip('Concrete', x - 0.12, x + 0.12, 119.2, 147, QUAY + 0.07)
    x += 17
for x in range(-140, 181, 32):
    if abs(x - EX) < 40: continue
    B.bx('Concrete', x, QUAY + 0.4, 134, 9, 0.8, 3.2, bevel=0.06); B.bx('Grass', x, QUAY + 0.82, 134, 8.4, 0.06, 2.6)
    for dx in (-2.6, 2.6):
        B.bx('Wood', x + dx, QUAY + 0.5, 137.3, 2.6, 0.1, 0.6); B.bx('Steel', x + dx - 1.1, QUAY + 0.25, 137.3, 0.08, 0.45, 0.5); B.bx('Steel', x + dx + 1.1, QUAY + 0.25, 137.3, 0.08, 0.45, 0.5)
for i, m in enumerate(('Red', 'White', 'Blue', 'Yellow', 'Orange', 'White')):
    x = EX - 20 + i * 8
    B.cy('Steel', x, QUAY + 6.5, 144.5, 0.1, 13, seg=8); B.cy('Yellow', x, QUAY + 13.1, 144.5, 0.18, 0.25, seg=8)
    B.bx(m, x + 1.25, QUAY + 11.7, 144.5, 2.3, 1.5, 0.05)
# 駐車場(西・東): 区画線、車止めの生け垣、照明
LOTS = ((-206, -14), (56, 204))
for x0, x1 in LOTS:
    strip('White', x0, x1, 149.3, 149.5); strip('White', x0, x1, 194.5, 194.7)
    for zr in (152, 169, 186):
        strip('White', x0, x1, zr + 5.0, zr + 5.14)
        x = x0
        while x <= x1 + 0.01:
            strip('White', x - 0.06, x + 0.06, zr, zr + 10.14)
            x += 2.9
    B.bx('Grass', (x0 + x1) / 2, QUAY + 0.45, 197.2, x1 - x0, 0.9, 1.1, bevel=0.1)
    for x in (x0 + 30, (x0 + x1) / 2, x1 - 30):
        for zr in (163.6, 180.6):
            B.cy('Steel', x, QUAY + 5, zr, 0.14, 10, seg=8); B.bx('Steel', x, QUAY + 10, zr, 2.6, 0.12, 0.3)
            for dx in (-1.2, 1.2): B.bx('Lamp', x + dx, QUAY + 9.9, zr, 0.9, 0.16, 0.5)
# 道路: 歩道、車線、横断歩道、街灯、バス停
for z0, z1 in ((199, 204), (223, 228)):
    B.grid('ConcreteLight', -440, 440, z0, z1, QUAY + 0.14, 20)
    B.wall('Concrete', -440, z1 if z0 < 210 else z0, 440, z1 if z0 < 210 else z0, QUAY, QUAY + 0.14, 40)
strip('White', -440, 440, 204.7, 204.85); strip('White', -440, 440, 222.15, 222.3)
x = -436
while x < 436:
    if abs(x + 2 - EX) > 7: strip('White', x, x + 4, 213.4, 213.6)
    x += 9
for k in range(9): strip('White', EX - 4, EX + 4, 205.6 + k * 1.9, 206.5 + k * 1.9)
x = -420
while x <= 420:
    for z, s_ in ((201.5, 1), (225.5, -1)):
        B.cy('Steel', x, QUAY + 4.3, z, 0.12, 8.4, seg=8); B.bx('Steel', x, QUAY + 8.4, z + s_ * 1.2, 0.12, 0.12, 2.6)
        B.bx('Lamp', x, QUAY + 8.3, z + s_ * 2.3, 0.5, 0.14, 1.0)
    x += 56
for bx_ in (EX + 26, EX - 60):          # バス停
    B.bx('Roof', bx_, QUAY + 2.9, 201.2, 9, 0.14, 2.4)
    for dx in (-4.2, 4.2): B.bx('Steel', bx_ + dx, QUAY + 1.5, 200.2, 0.12, 2.8, 0.12)
    B.quad('Glass', (bx_, QUAY + 1.6, 200.15), 8.4, 2.0, 0, 0, uv=(3, 0.6))
    B.bx('Wood', bx_, QUAY + 0.6, 200.8, 6, 0.1, 0.6); B.cy('Blue', bx_ + 5.6, QUAY + 2.9, 202.6, 0.5, 0.08, seg=14); B.cy('Steel', bx_ + 5.6, QUAY + 1.5, 202.6, 0.06, 2.8, seg=6)
# ピット棟の外まわり: 窓とシャッター
for kf in range(2):
    for i in range(10):
        B.quad('Glass', (-336.08, QUAY + 2.8 + kf * 4.6, -27 + i * 8.2), 6, 2.2, -math.pi / 2, 0, uv=(3, 0.5))
    for i in range(4):
        B.quad('Glass', (-331 + i * 10, QUAY + 2.8 + kf * 4.6, 52.08), 7, 2.2, 0, 0, uv=(3, 0.5))
        B.quad('Glass', (-331 + i * 10, QUAY + 7.4, -32.08), 7, 2.2, math.pi, 0, uv=(3, 0.5))
for i in range(4): B.bx('Steel', -331 + i * 10, QUAY + 2.4, -32.1, 7, 4.6, 0.2)
B.bx('Blue', -316, QUAY + 9.6, 10, 40.4, 0.8, 84.4)
# 1マーク奥: 艇庫
B.bx('ConcreteLight', 372, QUAY + 5.5, -6, 70, 11, 54); B.bx('Roof', 372, QUAY + 11.3, -6, 72, 0.6, 56); B.bx('Blue', 372, QUAY + 10.2, -6, 70.4, 0.8, 54.4)
for i in range(6):
    B.bx('Steel', 345 + i * 11, QUAY + 2.6, 21.1, 8, 5.2, 0.2)
    B.quad('Glass', (336.92, QUAY + 7.4, -28 + i * 9), 6, 2.2, -math.pi / 2, 0, uv=(3, 0.5))
outside = done(B, 'Outside')

# ================= 遠景: 大橋・クレーン・煙突・タンク・埋立地 =================
B = VB()
BZ_ = -520
B.bx('White', 0, 46, BZ_, 1900, 2.6, 16)
B.bx('ConcreteLight', 0, 48.2, BZ_ - 8, 1900, 1.2, 0.4); B.bx('ConcreteLight', 0, 48.2, BZ_ + 8, 1900, 1.2, 0.4)
x = -900
while x <= 900:
    if abs(abs(x) - 240) > 30: B.bx('Concrete', x, 22, BZ_, 6, 46, 10)
    x += 120
for tx in (-240, 240):
    for dz in (-1, 1):
        B.tube('White', [P(tx, 0, BZ_ + dz * 14), P(tx, 150, BZ_ + dz * 3)], 2.6, 8)
    B.bx('White', tx, 120, BZ_, 7, 5, 12); B.bx('White', tx, 62, BZ_, 7, 5, 21); B.bx('White', tx, 152, BZ_, 6, 8, 8)
for i in range(4):
    x, z = 560 + i * 70, -250
    for dx in (-12, 12):
        for dz in (-9, 9): B.bx('Red', x + dx, 32, z + dz, 2.2, 62, 2.2)
    B.bx('Red', x, 62, z, 28, 3, 22); B.bx('White', x, 66, z - 30, 4, 3, 96); B.bx('Red', x, 80, z + 4, 3, 26, 3)
    B.tube('Red', [P(x, 92, z + 4), P(x, 67, z - 76)], 0.5, 5); B.tube('Red', [P(x, 92, z + 4), P(x, 67, z + 16)], 0.5, 5)
    B.bx('White', x, 60, z - 20, 6, 5, 8)
for x, z, h in ((-640, -700, 150), (-560, -730, 120), (-720, -760, 135)):
    n = 8
    for i in range(n): B.cy('Red' if i % 2 == 0 else 'White', x, h * (i + 0.5) / n, z, 4 + 2 * (1 - (i + 0.5) / n), h / n, r2=4 + 2 * (1 - (i + 1.5) / n), seg=12)
for i in range(6):
    B.cy('White', -520 + i * 40, 11, -780, 16, 20, seg=20)
    B.cy('ConcreteLight', -520 + i * 40, 21.5, -780, 12, 1.5, r2=2, seg=20)
B.bx('ConcreteDark', 0, 0, -910, 2400, 3, 320); B.bx('ConcreteDark', 780, 0, 100, 560, 3, 700)
far = done(B, 'Far')

objs = [land, barriers, stand, struct, towers, pit, outside, far]
tris = sum(len(p.vertices) - 2 for o in objs for p in o.data.polygons)
print('TRIANGLES', tris)
bake_ao([land, barriers, stand, struct, towers, pit, outside], samples=24, lo=0.22, gamma=0.9, dist=14)
bake_ao([far], samples=8, lo=0.5, gamma=1.0, dist=30)
export_glb(OUT, objs)

if PREV:
    os.makedirs(PREV, exist_ok=True)
    preview(os.path.join(PREV, 'venue_stand.png'), tuple(P(-40, 9, 10)), tuple(P(40, 12, 90)), lens=28, samples=32, sun=(0.75, 0.0, 2.6), ground=False)
    preview(os.path.join(PREV, 'venue_far.png'), tuple(P(120, 14, 40)), tuple(P(40, 6, -80)), lens=30, samples=32, sun=(0.75, 0.0, 2.6), ground=False)
