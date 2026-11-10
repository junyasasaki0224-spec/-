"""競艇ボート(ハイドロプレーン)・船外機・レーサーを生成して GLB に書き出す。
  python build_boat.py <出力.glb> [プレビュー画像の出力先ディレクトリ]
ノード構成(ゲーム側が名前で参照する):
  Hull / Cowl / Glass / Plates / Flag / Wheel / Motor / RacerLower / RacerUpper
マテリアル名 BoatColor / Suit / Helmet / HelmetStripe / NumberPlate はゲーム側で艇ごとに差し替える。"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh
from mathutils import Vector, Matrix, Euler
from bl_util import *

OUT = sys.argv[1] if len(sys.argv) > 1 else 'boat.glb'
PREV = sys.argv[2] if len(sys.argv) > 2 else None
reset()

# ---------------- マテリアル ----------------
mat('HullWhite', (0.93, 0.93, 0.9), 0.22)
mat('HullBottom', (0.05, 0.07, 0.1), 0.35)
mat('Trim', (0.03, 0.03, 0.035), 0.55)
mat('Deck', (0.9, 0.9, 0.87), 0.3)
mat('BoatColor', (0.8, 0.05, 0.08), 0.28)
mat('Cockpit', (0.04, 0.04, 0.045), 0.7)
mat('Plywood', (0.42, 0.27, 0.13), 0.6)
mat('NumberPlate', (1, 1, 1), 0.45)
mat('Flag', (1, 1, 1), 0.8)
mat('Glass', (0.6, 0.75, 0.85), 0.05, alpha=0.35)
mat('Metal', (0.72, 0.74, 0.77), 0.3, 1.0)
mat('MetalDark', (0.2, 0.21, 0.23), 0.45, 0.9)
mat('MotorBlack', (0.025, 0.025, 0.03), 0.4)
mat('MotorRed', (0.7, 0.04, 0.03), 0.35)
mat('Rubber', (0.02, 0.02, 0.02), 0.85)
mat('Suit', (0.8, 0.05, 0.08), 0.75)
mat('Pants', (0.06, 0.07, 0.1), 0.8)
mat('Helmet', (0.9, 0.9, 0.9), 0.15)
mat('HelmetStripe', (0.8, 0.05, 0.08), 0.15)
mat('Visor', (0.02, 0.025, 0.03), 0.05, 0.6)
mat('Glove', (0.9, 0.9, 0.88), 0.7)
mat('Boot', (0.03, 0.03, 0.035), 0.6)

# ---------------- 艇体 ----------------
L0, L1 = -1.45, 1.45
XC0, XC1 = -1.30, 0.02       # コックピットの前後
CW = 0.40                    # コックピットの半幅
FLOOR = 0.085

def tt(x): return (x - L0) / (L1 - L0)
def beam(x):
    t = tt(x)
    if t < 0.5: return 0.67 - 0.035 * (1 - t / 0.5) ** 2
    u = (t - 0.5) / 0.5
    return 0.67 * max(0.0, 1 - u ** 3.4) ** (1 / 2.4)
def keel(x):
    u = max(0.0, (tt(x) - 0.48) / 0.52)
    return 0.26 * u ** 2.3
def sheer(x): return 0.33 + 0.035 * tt(x)
def deck_z(x, y):
    b = max(beam(x) * 0.965, 1e-3)
    return sheer(x) + 0.004 + 0.03 * (1 - min(1.0, abs(y) / b) ** 2)
def yc(x): return min(CW, beam(x) * 0.72)

def section(x):
    b, k, s = beam(x), keel(x), sheer(x)
    c = yc(x)
    return [(0, k), (0.45 * b, k), (0.8 * b, k + 0.003), (0.93 * b, k + 0.018),
            (0.985 * b, k + 0.06), (b, k + (s - k) * 0.5), (b, s - 0.03), (0.992 * b, s - 0.006),
            (0.965 * b, s + 0.004), (max(0.895 * b, c + 0.01), deck_z(x, 0.895 * b)), (c, deck_z(x, c)), (0, deck_z(x, 0))]
STRIP_MAT = ['HullBottom', 'HullBottom', 'HullBottom', 'HullWhite', 'HullWhite', 'HullWhite', 'Trim', 'Trim', 'BoatColor', 'Deck', 'Deck']

# ステーション(船首側を細かく)
xs = []
N = 46
for i in range(N + 1):
    t = i / N
    xs.append(L0 + (L1 - L0) * (1 - (1 - t) ** 1.7) * 0.9985)
xs = sorted(set([round(x, 5) for x in xs] + [XC0, XC1]))
ic0, ic1 = xs.index(XC0), xs.index(XC1)

B = Builder()
grid = []   # grid[i][side][j]
well = []   # well[i][side] = [w0, w1, w2, w3] (コックピット内)
for i, x in enumerate(xs):
    sec = section(x)
    row = []
    for sgn in (1, -1):
        row.append([B.vert((x, sgn * y, z)) for y, z in sec])
    grid.append(row)
    if ic0 <= i <= ic1:
        c, zd = yc(x), deck_z(x, yc(x))
        w = []
        for sgn in (1, -1):
            w.append([B.vert((x, sgn * c, zd + 0.035)), B.vert((x, sgn * (c - 0.025), zd + 0.035)),
                      B.vert((x, sgn * (c - 0.04), FLOOR)), B.vert((x, 0, FLOOR))])
        well.append(w)
    else: well.append(None)

for i in range(len(xs) - 1):
    for s in (0, 1):
        a, b = grid[i][s], grid[i + 1][s]
        for j in range(11):
            if j == 10 and ic0 <= i < ic1: continue
            B.face([a[j], b[j], b[j + 1], a[j + 1]], STRIP_MAT[j])
        if ic0 <= i < ic1:
            wa, wb = well[i][s], well[i + 1][s]
            B.face([a[10], b[10], wb[0], wa[0]], 'Deck')
            B.face([wa[0], wb[0], wb[1], wa[1]], 'Trim')
            B.face([wa[1], wb[1], wb[2], wa[2]], 'Cockpit')
            B.face([wa[2], wb[2], wb[3], wa[3]], 'Plywood')
# コックピットの前後の壁
for i in (ic0, ic1):
    gp, gm, wp, wm = grid[i][0], grid[i][1], well[i][0], well[i][1]
    B.face([gp[10], gp[11], gm[10], wm[0], wp[0]], 'Deck')
    B.face([wp[0], wm[0], wm[1], wp[1]], 'Trim')
    B.face([wp[1], wm[1], wm[2], wm[3], wp[2]], 'Cockpit')
# トランサム(船尾板)と船首の蓋
for i, m in ((0, 'HullWhite'), (len(xs) - 1, 'HullWhite')):
    loop = grid[i][0][:] + grid[i][1][::-1]
    B.face(loop, m)
hull = B.build('Hull', sharp_angle=38)

# トランサムのモーター取付板
B = Builder()
B.box('Plywood', (0.03, 0.34, 0.2), (L0 - 0.012, 0, 0.26), bevel=0.004)
B.box('Metal', (0.012, 0.3, 0.03), (L0 - 0.03, 0, 0.345))
# 船首のバンパーと牽引リング
B.torus('Metal', 0.03, 0.007, (L1 - 0.06, 0, sheer(L1) + 0.04), (math.pi / 2, 0, 0), 14, 6)
# スロットルレバー(左舷)
B.box('MetalDark', (0.12, 0.03, 0.05), (-0.16, CW + 0.0, 0.42), bevel=0.004)
B.tube('Metal', [(-0.16, CW - 0.015, 0.43), (-0.1, CW - 0.03, 0.535)], 0.009, 8)
B.sphere('Rubber', (0.035, 0.035, 0.035), (-0.097, CW - 0.031, 0.54), seg=10, rings=6)
# ハンドル軸
WHEEL_C = Vector((-0.1, 0.0, 0.565)); WHEEL_TILT = math.radians(64)
ax = Vector((math.sin(WHEEL_TILT), 0, -math.cos(WHEEL_TILT)))     # 前下がりの軸
B.tube('MetalDark', [tuple(WHEEL_C), tuple(WHEEL_C + ax * 0.22)], 0.016, 10)
fit = B.build('Fittings', sharp_angle=45)

# ---------------- カウリング ----------------
CX0, CX1 = -0.01, 0.86
def cowl_h(u): return 0.265 * (1 - u ** 1.65)
def cowl_w(u): return 0.445 * (1 - 0.42 * u ** 2.0)
def cowl_pt(u, a, off=0.0):
    x = CX0 + (CX1 - CX0) * u
    w, h = cowl_w(u), cowl_h(u)
    e = 0.62
    cy, sz = math.cos(a), math.sin(a)
    y = w * (abs(cy) ** e) * (1 if cy >= 0 else -1)
    z = sheer(x) - 0.004 + h * (sz ** e)
    p = Vector((x, y, z))
    if off:
        n = Vector((0, cy, sz)).normalized()
        p += n * off
    return p
B = Builder()
NU, NA = 18, 22
rows = []
for iu in range(NU + 1):
    u = (iu / NU) ** 1.15
    rows.append([B.vert(cowl_pt(u, math.pi * ia / NA)) for ia in range(NA + 1)])
for iu in range(NU):
    for ia in range(NA):
        B.face([rows[iu][ia], rows[iu + 1][ia], rows[iu + 1][ia + 1], rows[iu][ia + 1]], 'BoatColor')
# 後端: 内側へ折り返した縁と奥の計器盤
inner = [B.vert(cowl_pt(0, math.pi * ia / NA) * 1.0 + Vector((0.0, 0, 0))) for ia in range(NA + 1)]
for ia in range(NA + 1):
    p = cowl_pt(0, math.pi * ia / NA)
    c = Vector((CX0, 0, sheer(CX0)))
    inner[ia].co = c + (p - c) * 0.9 + Vector((0.035, 0, 0))
for ia in range(NA):
    B.face([rows[0][ia + 1], rows[0][ia], inner[ia], inner[ia + 1]], 'Trim')
B.face(inner[::-1], 'Cockpit')
cowl = B.build('Cowl', sharp_angle=50)

# 風防
B = Builder()
a0, a1, n = 0.14 * math.pi, 0.86 * math.pi, 14
lo, hi = [], []
for i in range(n + 1):
    a = a0 + (a1 - a0) * i / n
    p = cowl_pt(0.015, a)
    k = math.sin(a) ** 2
    lo.append(B.vert(p)); hi.append(B.vert(p + Vector((-0.07 * k, 0, 0.1 * k + 0.012))))
for i in range(n):
    B.face([lo[i], lo[i + 1], hi[i + 1], hi[i]], 'Glass')
glass = B.build('Glass', sharp_angle=None, recalc=False)

# 艇番プレート(カウル左右・船首デッキ) UV は 0..1
B = Builder()
for sgn in (1, -1):
    nu, na = 4, 3
    u0, u1, aa0, aa1 = 0.1, 0.5, math.radians(7), math.radians(40)
    vs = [[None] * (na + 1) for _ in range(nu + 1)]
    for i in range(nu + 1):
        for j in range(na + 1):
            u = u0 + (u1 - u0) * i / nu; a = aa0 + (aa1 - aa0) * j / na
            p = cowl_pt(u, a if sgn > 0 else math.pi - a, 0.004)
            vs[i][j] = (B.vert(p), ((1 - i / nu) if sgn > 0 else i / nu, j / na))
    for i in range(nu):
        for j in range(na):
            q = [vs[i][j], vs[i + 1][j], vs[i + 1][j + 1], vs[i][j + 1]]
            if sgn < 0: q = q[::-1]
            B.face([v for v, _ in q], 'NumberPlate', [uv for _, uv in q])
# 船首デッキ: 後ろから見て読める向き
px0, px1, pw = 0.93, 1.27, 0.19
q = [((px0, pw), (0, 0)), ((px0, -pw), (1, 0)), ((px1, -pw), (1, 1)), ((px1, pw), (0, 1))]
B.face([B.vert((x, y, deck_z(x, y) + 0.004)) for (x, y), _ in q], 'NumberPlate', [uv for _, uv in q])
plates = B.build('Plates', sharp_angle=None, recalc=False, merge=0)

# 艇旗
B = Builder()
FX = 1.33
B.tube('Metal', [(FX, 0, sheer(FX)), (FX, 0, sheer(FX) + 0.52)], 0.007, 6)
pole = B.build('FlagPole')
B = Builder()
fw, fh, nx, nz = 0.27, 0.19, 6, 3
fv = [[(B.vert((-fw * i / nx, 0, -fh * j / nz)), (i / nx, 1 - j / nz)) for j in range(nz + 1)] for i in range(nx + 1)]
for i in range(nx):
    for j in range(nz):
        q = [fv[i][j], fv[i + 1][j], fv[i + 1][j + 1], fv[i][j + 1]]
        B.face([v for v, _ in q], 'Flag', [uv for _, uv in q])
flag = B.build('Flag', origin=(0, 0, 0), sharp_angle=None, recalc=False, merge=0)
flag.location = (FX, 0, sheer(FX) + 0.51)

# ---------------- ハンドル ----------------
B = Builder()
B.torus('Rubber', 0.15, 0.014, (0, 0, 0), (0, 0, 0), 28, 8)
for k in range(3):
    a = math.radians(90 + 120 * k)
    B.tube('Metal', [(0, 0, 0.0), (0.15 * math.cos(a), 0.15 * math.sin(a), 0)], 0.008, 6)
B.cyl('MetalDark', 0.03, 0.03, (0, 0, 0.0), seg=12)
wheel = B.build('Wheel')
# ローカル Z 軸 = ハンドル軸。軸を前下がりに倒す(ゲーム側はこの軸まわりに回す)
wheel.location = WHEEL_C
wheel.rotation_euler = Vector((0, 0, 1)).rotation_difference(ax).to_euler()

# ---------------- 船外機 ----------------
PIV = Vector((L0 - 0.075, 0, 0.3))          # 操舵軸
B = Builder()
mx = L0 - 0.19                               # 機関の中心 x
# クランプブラケットとスイベル
B.box('MetalDark', (0.07, 0.2, 0.2), (L0 - 0.055, 0, 0.3), bevel=0.006)
for s in (1, -1): B.cyl('Metal', 0.014, 0.05, (L0 + 0.02, s * 0.07, 0.2), (0, math.pi / 2, 0), seg=10)
B.cyl('Metal', 0.022, 0.3, tuple(PIV), seg=12)
# ドライブシャフトハウジング(排気筒)
B.cyl('Metal', 0.05, 0.62, (mx, 0, 0.16), r2=0.062, seg=16)
B.box('Metal', (0.11, 0.035, 0.5), (mx - 0.035, 0, 0.1), bevel=0.01)
# アンチキャビテーションプレート
B.box('Metal', (0.3, 0.17, 0.012), (mx - 0.05, 0, -0.07), bevel=0.004)
B.box('Metal', (0.1, 0.03, 0.14), (mx, 0, -0.15), bevel=0.008)
# ギアケースとスケグ
B.sphere('Metal', (0.3, 0.085, 0.085), (mx, 0, -0.23), (0, 0, 0), seg=16, rings=10)
v = [B.vert(p) for p in [(mx + 0.07, 0, -0.26), (mx - 0.1, 0, -0.26), (mx - 0.07, 0, -0.38), (mx + 0.0, 0, -0.37)]]
B.face(v, 'Metal'); B.face(v[::-1], 'Metal')
# プロペラ
B.cyl('MetalDark', 0.028, 0.08, (mx - 0.17, 0, -0.23), (0, math.pi / 2, 0), r2=0.012, seg=12)
for k in range(2):
    a = math.pi * k + 0.4
    B.sphere('Metal', (0.012, 0.085, 0.15), (mx - 0.165, 0.065 * math.cos(a), -0.23 + 0.065 * math.sin(a)), (a + math.pi / 2, 0.0, 0.35), seg=10, rings=6)
# パワーヘッド(2気筒)
B.box('MotorBlack', (0.26, 0.24, 0.27), (mx - 0.01, 0, 0.61), bevel=0.02)
B.box('MetalDark', (0.2, 0.2, 0.06), (mx, 0, 0.47), bevel=0.01)
for k in range(9):   # シリンダーの冷却フィン
    B.box('MetalDark', (0.075, 0.215, 0.01), (mx - 0.165, 0, 0.5 + k * 0.027), bevel=0.0)
B.box('MotorBlack', (0.05, 0.2, 0.25), (mx - 0.15, 0, 0.61), bevel=0.008)
for k in range(2):   # 点火プラグ
    B.cyl('Glove', 0.012, 0.06, (mx - 0.215, 0, 0.55 + k * 0.12), (0, math.pi / 2, 0), seg=8)
    B.tube('Rubber', [(mx - 0.245, 0, 0.55 + k * 0.12), (mx - 0.25, 0.06, 0.6 + k * 0.1), (mx - 0.1, 0.125, 0.7)], 0.006, 6)
# フライホイールとスターター
B.cyl('Metal', 0.125, 0.04, (mx, 0, 0.775), seg=28)
B.cyl('MetalDark', 0.07, 0.035, (mx, 0, 0.81), seg=20)
B.cyl('Metal', 0.02, 0.02, (mx, 0, 0.835), seg=10)
# キャブレターと吸気
B.box('Metal', (0.07, 0.09, 0.08), (mx + 0.16, 0, 0.58), bevel=0.008)
B.cyl('MetalDark', 0.036, 0.07, (mx + 0.215, 0, 0.58), (0, math.pi / 2, 0), r2=0.05, seg=14)
# 燃料タンク
B.sphere('MotorRed', (0.2, 0.2, 0.13), (mx + 0.03, 0, 0.9), seg=18, rings=10)
B.cyl('Metal', 0.025, 0.02, (mx + 0.03, 0, 0.97), seg=10)
for s in (1, -1): B.tube('Metal', [(mx + 0.03, s * 0.09, 0.86), (mx + 0.03, s * 0.11, 0.76)], 0.006, 6)
# 色帯と番号板
B.box('BoatColor', (0.265, 0.245, 0.06), (mx - 0.01, 0, 0.69), bevel=0.01)
# 操舵バーとワイヤ
B.tube('Metal', [(mx + 0.1, -0.3, 0.42), (mx + 0.1, 0.3, 0.42)], 0.011, 8)
B.tube('Metal', [(mx + 0.02, 0, 0.44), (mx + 0.1, 0, 0.42)], 0.012, 8)
# キャリングハンドル
B.tube('Metal', [(mx + 0.13, -0.09, 0.72), (mx + 0.19, -0.09, 0.76), (mx + 0.19, 0.09, 0.76), (mx + 0.13, 0.09, 0.72)], 0.008, 6)
motor = B.build('Motor', origin=tuple(PIV), sharp_angle=42)

# ---------------- レーサー ----------------
HIP = Vector((-0.74, 0, 0.41))
# 下半身(膝をついて踵に腰を落とす乗艇姿勢)
legs = []
for s in (1, -1):
    j = [((-0.73, s * 0.1, 0.4), 0.088), ((-0.4, s * 0.17, 0.17), 0.066), ((-1.0, s * 0.14, 0.15), 0.046), ((-1.13, s * 0.14, 0.125), 0.04)]
    legs.append(skin_object('leg', j, [(0, 1), (1, 2), (2, 3)], mat('Pants'), 2))
B = Builder()
for s in (1, -1):
    B.sphere('Boot', (0.19, 0.095, 0.09), (-1.1, s * 0.14, 0.13), seg=12, rings=8)
    B.box('Rubber', (0.13, 0.13, 0.03), (-0.39, s * 0.17, 0.105), bevel=0.012)                   # 膝当て
boots = B.build('boots', sharp_angle=None)
lower = join(legs + [boots], 'RacerLower')

# 上半身(前傾して伏せ込む)
hand_r = Vector(WHEEL_C) + Vector((-0.03, -0.12, 0.085))
hand_l = Vector((-0.1, CW - 0.03, 0.56))
jo = [((-0.74, 0, 0.41), (0.135, 0.105)), ((-0.6, 0, 0.53), (0.12, 0.09)), ((-0.41, 0, 0.675), (0.15, 0.1)),
      ((-0.31, 0, 0.75), 0.06), ((-0.25, 0, 0.8), 0.05)]
ed = [(0, 1), (1, 2), (2, 3), (3, 4)]
for s, hand in ((1, hand_l), (-1, hand_r)):
    sh = Vector((-0.37, s * 0.2, 0.725))
    el = (sh + hand) / 2 + Vector((-0.03, s * 0.07, -0.07))
    n = len(jo)
    jo += [(tuple(sh), 0.068), (tuple(el), 0.05), (tuple(hand), 0.038)]
    ed += [(2, n), (n, n + 1), (n + 1, n + 2)]
torso = skin_object('torso', jo, ed, mat('Suit'), 2)
B = Builder()
B.sphere('Glove', (0.095, 0.08, 0.08), tuple(hand_l), seg=12, rings=8)
B.sphere('Glove', (0.095, 0.08, 0.08), tuple(hand_r), seg=12, rings=8)
gl = B.build('gloves', sharp_angle=None)

# 救命胴衣(艇番色) と背番号
ang = math.atan2(0.675 - 0.41, -0.41 + 0.74)
vc = Vector((-0.535, 0, 0.6))
tq = Euler((0, math.pi / 2 - ang, 0), 'XYZ')      # ローカル Z = 胴体方向, ローカル -X = 背中
B = Builder()
B.box('Suit', (0.235, 0.375, 0.37), tuple(vc), tuple(tq), bevel=0.055)
B.box('Suit', (0.1, 0.2, 0.09), tuple(vc + Vector((0.16, 0, 0.165))), tuple(tq), bevel=0.03)   # 襟
vest = B.build('vest', sharp_angle=None)
B = Builder()
Mv = Matrix.Translation(vc) @ tq.to_matrix().to_4x4()
bx = -0.1215
bq = [((bx, 0.125, -0.12), (0, 0)), ((bx, -0.125, -0.12), (1, 0)), ((bx, -0.125, 0.125), (1, 1)), ((bx, 0.125, 0.125), (0, 1))]
B.face([B.vert(Mv @ Vector(p)) for p, _ in bq], 'NumberPlate', [uv for _, uv in bq])
backnum = B.build('backnum', sharp_angle=None, recalc=False, merge=0)

# ヘルメット(極を左右に向けて、ストライプとバイザーを面の並びに沿わせる)
HC = Vector((-0.155, 0, 0.895))
B = Builder()
hrot = Euler((math.pi / 2, 0, 0), 'XYZ')
hf = B.sphere('Helmet', (0.3, 0.29, 0.265), tuple(HC), tuple(hrot), seg=32, rings=20)
for f in hf:
    c = f.calc_center_median() - HC
    el = math.degrees(math.atan2(c.z, c.x))          # 前方を 0 とした仰角
    if abs(c.y) < 0.098 and -16 < el < 30 and c.x > 0: f.material_index = B.mi('Visor')
    elif abs(c.y) < 0.03 and (el > 30 or c.x < 0) and c.z > -0.06: f.material_index = B.mi('HelmetStripe')
B.sphere('Helmet', (0.2, 0.235, 0.15), tuple(HC + Vector((0.07, 0, -0.085))), seg=18, rings=10)   # チンガード
B.cyl('Rubber', 0.095, 0.05, tuple(HC + Vector((-0.05, 0, -0.13))), (0, math.radians(-30), 0), seg=18)
helmet = B.build('helmet', sharp_angle=None)

upper = join([torso, vest, backnum, helmet, gl], 'RacerUpper')
bpy.context.scene.cursor.location = HIP
bpy.ops.object.select_all(action='DESELECT'); upper.select_set(True); bpy.context.view_layer.objects.active = upper
bpy.ops.object.origin_set(type='ORIGIN_CURSOR')

objs = [hull, fit, cowl, glass, plates, pole, flag, wheel, motor, lower, upper]
for o in objs:
    if o.name not in ('Glass', 'Plates', 'Flag'):
        pass
bake_ao([o for o in objs if o.name not in ('Glass', 'Flag')], samples=40, lo=0.3)

tris = sum(len(p.vertices) - 2 for o in objs for p in o.data.polygons)
print('TRIANGLES', tris)
export_glb(OUT, objs)

if PREV:
    os.makedirs(PREV, exist_ok=True)
    preview(os.path.join(PREV, 'boat_rear.png'), (-4.2, 1.6, 1.9), (0, 0, 0.45), lens=60)
    preview(os.path.join(PREV, 'boat_side.png'), (-0.6, -3.6, 1.2), (-0.5, 0, 0.5), lens=70)
