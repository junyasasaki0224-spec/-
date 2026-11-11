# ============================================================
#  Blender (bpy) による競走馬・騎手モデルの生成
#    1. 解剖学的な塊(胴・筋肉・関節・腱)を距離場として滑らかに融合し、表面を抽出
#    2. Blenderでスムージング・リダクション・法線・マテリアル
#    3. 骨格(アーマチュア)を組み、各パーツの所属からスキンウェイトを算出
#    4. glTF(.glb) に書き出し。確認用にCyclesでレンダリング
#  実行:  python tools/blender/build_models.py <出力glb> [プレビュー出力ディレクトリ]
#  必要:  pip install bpy scikit-image
#  座標:  +X 前方, +Y 左, +Z 上 [m]  (glTFでは +X 前, +Y 上, +Z 右)
# ============================================================
import sys, math
import numpy as np
import bpy
from mathutils import Vector
from skimage import measure

OUT = sys.argv[1] if len(sys.argv) > 1 else 'assets/horse.glb'
PREVIEW = sys.argv[2] if len(sys.argv) > 2 else None
VOX = 0.011


# ---------------- 距離場 ----------------
def smin(a, b, k):
    if k <= 0:
        return np.minimum(a, b)
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b + (a - b) * h - k * h * (1 - h)


def d_ell(P, c, r, pitch=0.0):
    q = P - np.asarray(c, np.float32)
    if pitch:
        cs, sn = math.cos(pitch), math.sin(pitch)
        x = q[:, 0] * cs + q[:, 2] * sn
        z = -q[:, 0] * sn + q[:, 2] * cs
        q = np.stack([x, q[:, 1], z], 1)
    r = np.asarray(r, np.float32)
    k0 = np.linalg.norm(q / r, axis=1)
    k1 = np.linalg.norm(q / (r * r), axis=1)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-6)


def d_cap(P, a, b, ra, rb, sy=1.0):
    a = np.asarray(a, np.float32).copy(); b = np.asarray(b, np.float32).copy()
    Q = P
    if sy != 1.0:
        Q = P.copy(); Q[:, 1] /= sy; a[1] /= sy; b[1] /= sy
    ab = b - a
    t = np.clip(((Q - a) @ ab) / float(ab @ ab), 0, 1)
    d = np.linalg.norm(Q - (a + t[:, None] * ab), axis=1) - (ra + (rb - ra) * t)
    return d * min(1.0, sy)


class Shape:
    """プリミティブの集合。各プリミティブは骨と部位(マテリアル)を持つ"""
    def __init__(self):
        self.prims = []

    def ell(self, c, r, bone, part='coat', k=0.05, pitch=0.0, sub=False):
        self.prims.append(('e', (c, r, math.radians(pitch)), bone, part, k, sub))

    def cap(self, a, b, ra, rb, bone, part='coat', k=0.04, sy=1.0, sub=False):
        self.prims.append(('c', (a, b, ra, rb, sy), bone, part, k, sub))

    def sph(self, c, r, bone, part='coat', k=0.04, sub=False):
        self.ell(c, (r, r, r), bone, part, k, sub=sub)

    def both(self, fn, *a, **kw):
        """左右対称に追加 (座標タプルの y を反転)。骨名の末尾に .L/.R"""
        npts = 2 if fn == self.cap else 1
        for s, suf in ((1, '.L'), (-1, '.R')):
            aa = list(a)
            for i in range(npts):
                aa[i] = (a[i][0], a[i][1] * s, a[i][2])
            kk = dict(kw); bone = kk.pop('bone')
            fn(*aa, bone=bone + suf, **kk)

    def fn(self, func, lo, hi, bone, part, k=0.0):
        """任意の距離関数 (馬体表面に沿う布・革など)"""
        self.prims.append(('f', (func, lo, hi), bone, part, k, False))

    def subset(self, parts):
        S = Shape(); S.prims = [p for p in self.prims if p[3] in parts]
        return S

    def bounds(self, pad=0.05):
        lo = np.full(3, 1e9); hi = np.full(3, -1e9)
        for kind, pr, *_ in self.prims:
            if kind == 'e':
                r = max(pr[1]); a = np.asarray(pr[0]) - r; b = np.asarray(pr[0]) + r
            elif kind == 'c':
                r = max(pr[2], pr[3]) * max(1.0, pr[4])
                a = np.minimum(pr[0], pr[1]) - r; b = np.maximum(pr[0], pr[1]) + r
            else:
                a, b = np.asarray(pr[1]), np.asarray(pr[2])
            lo = np.minimum(lo, a); hi = np.maximum(hi, b)
        lo -= pad; hi += pad; lo[2] = max(lo[2], 0.0)
        return lo, hi

    def dist(self, P, prim):
        kind, pr = prim[0], prim[1]
        if kind == 'f':
            return pr[0](P)
        return d_ell(P, *pr) if kind == 'e' else d_cap(P, *pr)

    def field(self, P):
        d = np.full(len(P), 1e3, np.float32)
        for pr in self.prims:
            if pr[5]:
                continue
            d = smin(d, self.dist(P, pr).astype(np.float32), pr[4])
        for pr in self.prims:
            if pr[5]:
                dd = self.dist(P, pr).astype(np.float32)
                d = -smin(-d, dd, pr[4])
        return d

    def mesh(self, vox=VOX, floor=None):
        lo, hi = self.bounds()
        lo = np.asarray(lo, np.float32); hi = np.asarray(hi, np.float32)
        n = np.ceil((hi - lo) / vox).astype(int) + 1
        ax = [lo[i] + np.arange(n[i], dtype=np.float32) * vox for i in range(3)]
        G = np.stack(np.meshgrid(*ax, indexing='ij'), -1).reshape(-1, 3)
        d = np.empty(len(G), np.float32)
        step = 400000
        for i in range(0, len(G), step):
            d[i:i + step] = self.field(G[i:i + step])
        if floor is not None:
            d = np.maximum(d, floor - G[:, 2])
        v, f, _, _ = measure.marching_cubes(d.reshape(n), 0.0, spacing=(vox, vox, vox))
        return v + lo, f

    def attribs(self, V, sigma=0.022):
        """頂点ごとの 骨ウェイト と 部位"""
        bones = sorted({p[2] for p in self.prims if not p[5]})
        parts = sorted({p[3] for p in self.prims if not p[5]})
        db = np.full((len(V), len(bones)), 1e3, np.float32)
        dp = np.full((len(V), len(parts)), 1e3, np.float32)
        for pr in self.prims:
            if pr[5]:
                continue
            dd = self.dist(V, pr)
            bi, pi = bones.index(pr[2]), parts.index(pr[3])
            db[:, bi] = np.minimum(db[:, bi], dd)
            dp[:, pi] = np.minimum(dp[:, pi], dd)
        w = np.exp(-(db - db.min(1, keepdims=True)) / sigma)
        w[w < 0.02] = 0
        w /= w.sum(1, keepdims=True)
        return bones, w, parts, dp.argmin(1)


# ---------------- 馬体 ----------------
def horse_body():
    S = Shape()
    # 胴
    S.ell((0.10, 0, 1.25), (0.56, 0.272, 0.315), 'spine', k=0.08)
    S.ell((0.48, 0, 1.22), (0.30, 0.24, 0.35), 'chest', k=0.08)
    S.ell((0.63, 0, 1.08), (0.15, 0.165, 0.19), 'chest', k=0.07)          # 胸前
    S.ell((0.40, 0, 1.53), (0.25, 0.068, 0.125), 'chest', k=0.08, pitch=8)   # き甲
    S.cap((0.22, 0, 1.495), (-0.30, 0, 1.505), 0.08, 0.095, 'spine', k=0.09, sy=1.5)  # 背
    S.ell((-0.22, 0, 1.335), (0.36, 0.242, 0.238), 'spine', k=0.09)       # 腰・ひばら
    S.ell((-0.55, 0, 1.315), (0.35, 0.265, 0.315), 'hips', k=0.09)          # 後躯
    S.ell((-0.47, 0, 1.51), (0.30, 0.17, 0.108), 'hips', k=0.08, pitch=-6)   # 尻(十字部)
    S.cap((-0.80, 0, 1.47), (-0.93, 0, 1.40), 0.085, 0.06, 'hips', k=0.06)   # 尾根
    # 肩〜前肢
    S.both(S.ell, (0.57, 0.150, 1.23), (0.185, 0.115, 0.31), bone='scapula', k=0.06, pitch=-24)
    S.both(S.sph, (0.715, 0.135, 1.185), 0.085, bone='scapula', k=0.06)   # 肩端
    S.both(S.ell, (0.52, 0.165, 1.03), (0.135, 0.085, 0.165), bone='humerus', k=0.06, pitch=20)
    S.both(S.cap, (0.435, 0.16, 0.95), (0.47, 0.16, 0.54), 0.080, 0.046, bone='radius', k=0.05)
    S.both(S.ell, (0.468, 0.168, 0.84), (0.066, 0.058, 0.125), bone='radius', k=0.04)
    S.both(S.ell, (0.476, 0.16, 0.515), (0.052, 0.047, 0.062), bone='radius', k=0.025)   # 前膝
    S.both(S.cap, (0.474, 0.16, 0.50), (0.474, 0.16, 0.235), 0.033, 0.030, bone='cannonF', k=0.02, sy=0.85)
    S.both(S.cap, (0.452, 0.16, 0.47), (0.452, 0.16, 0.24), 0.017, 0.017, bone='cannonF', k=0.012)  # 屈腱
    S.both(S.sph, (0.472, 0.16, 0.218), 0.046, bone='cannonF', k=0.02)   # 球節
    S.both(S.cap, (0.478, 0.16, 0.205), (0.528, 0.16, 0.098), 0.036, 0.040, bone='pasternF', k=0.02)
    S.both(S.cap, (0.535, 0.16, 0.088), (0.558, 0.16, 0.012), 0.050, 0.066, bone='pasternF', part='hoof', k=0.012)
    # 後肢
    S.both(S.ell, (-0.64, 0.140, 1.12), (0.205, 0.145, 0.30), bone='femur', k=0.06, pitch=16)
    S.both(S.ell, (-0.74, 0.115, 1.16), (0.16, 0.12, 0.25), bone='femur', k=0.07, pitch=10)   # 半腱様筋(尻の丸み)
    S.both(S.sph, (-0.385, 0.175, 0.99), 0.082, bone='femur', k=0.04)   # 膝(後膝)
    S.both(S.cap, (-0.56, 0.16, 1.25), (-0.40, 0.175, 1.0), 0.13, 0.085, bone='femur', k=0.05)   # 大腿
    S.both(S.cap, (-0.40, 0.17, 0.975), (-0.775, 0.17, 0.62), 0.092, 0.046, bone='tibia', k=0.05)
    S.both(S.ell, (-0.535, 0.172, 0.855), (0.115, 0.068, 0.125), bone='tibia', k=0.04, pitch=-42)
    S.both(S.ell, (-0.783, 0.17, 0.605), (0.058, 0.044, 0.07), bone='tibia', k=0.025)   # 飛節
    S.both(S.sph, (-0.832, 0.17, 0.648), 0.034, bone='tibia', k=0.03)     # 飛端
    S.both(S.cap, (-0.83, 0.17, 0.64), (-0.60, 0.17, 0.80), 0.022, 0.03, bone='tibia', k=0.02)   # アキレス腱
    S.both(S.cap, (-0.783, 0.17, 0.59), (-0.745, 0.17, 0.24), 0.037, 0.032, bone='cannonH', k=0.02, sy=0.85)
    S.both(S.cap, (-0.812, 0.17, 0.57), (-0.77, 0.17, 0.25), 0.018, 0.017, bone='cannonH', k=0.012)
    S.both(S.sph, (-0.745, 0.17, 0.222), 0.047, bone='cannonH', k=0.02)
    S.both(S.cap, (-0.74, 0.17, 0.208), (-0.695, 0.17, 0.098), 0.036, 0.040, bone='pasternH', k=0.02)
    S.both(S.cap, (-0.688, 0.17, 0.088), (-0.665, 0.17, 0.012), 0.050, 0.066, bone='pasternH', part='hoof', k=0.012)
    # 頸: 上下に深く左右に薄い
    S.cap((0.50, 0, 1.40), (0.80, 0, 1.63), 0.235, 0.175, 'neck1', k=0.09, sy=0.52)
    S.cap((0.80, 0, 1.63), (1.135, 0, 1.862), 0.172, 0.132, 'neck2', k=0.06, sy=0.6)
    S.cap((0.46, 0, 1.56), (1.16, 0, 1.955), 0.05, 0.045, 'neck2', k=0.05)   # 頸の峰
    # 頭
    S.ell((1.225, 0, 1.90), (0.115, 0.094, 0.105), 'head', k=0.05)        # 頭蓋
    S.both(S.ell, (1.25, 0.04, 1.775), (0.085, 0.05, 0.115), bone='head', k=0.04, pitch=-25)  # 頬(下顎)
    S.cap((1.27, 0, 1.865), (1.57, 0, 1.575), 0.088, 0.052, 'head', k=0.04, sy=0.8)    # 顔
    S.cap((1.30, 0, 1.925), (1.59, 0, 1.635), 0.040, 0.034, 'head', k=0.04, sy=1.1)   # 鼻梁
    S.cap((1.27, 0, 1.72), (1.54, 0, 1.50), 0.045, 0.034, 'head', k=0.03, sy=0.9)     # 下顎
    S.ell((1.60, 0, 1.535), (0.058, 0.052, 0.06), 'head', k=0.03)         # 鼻口部
    S.sph((1.555, 0, 1.487), 0.036, 'head', k=0.03)                       # おとがい
    S.both(S.sph, (1.335, 0.078, 1.842), 0.036, bone='head', k=0.025)     # 眼窩
    S.both(S.cap, (1.19, 0.060, 1.975), (1.178, 0.082, 2.085), 0.040, 0.016, bone='head', k=0.015, sy=1.0)  # 耳
    for s in (1, -1):
        S.sph((1.640, 0.032 * s, 1.552), 0.015, 'head', k=0.012, sub=True)   # 鼻孔
        S.cap((1.208, 0.060 * s, 2.01), (1.20, 0.078 * s, 2.07), 0.016, 0.006, 'head', k=0.01, sub=True)  # 耳の内側
    return S


def horse_hair():
    S = Shape()
    # たてがみ(右側へ流す)
    n = 10
    for i in range(n):
        t = i / (n - 1)
        x = 0.50 + t * 0.66; z = 1.60 + t * 0.365
        S.ell((x - 0.02, -0.04, z - 0.005), (0.085, 0.024, 0.085 - 0.03 * t), 'neck1' if t < 0.5 else 'neck2', 'mane', k=0.03, pitch=-32)
    S.ell((1.285, 0.0, 1.955), (0.055, 0.04, 0.08), 'head', 'mane', k=0.02, pitch=-50)  # 前髪
    # 尾
    S.cap((-0.90, 0, 1.455), (-1.03, 0, 1.30), 0.055, 0.078, 'tail1', 'mane', k=0.03)
    S.cap((-1.03, 0, 1.30), (-1.10, 0, 0.95), 0.078, 0.085, 'tail2', 'mane', k=0.03)
    S.cap((-1.10, 0, 0.95), (-1.115, 0, 0.52), 0.085, 0.022, 'tail3', 'mane', k=0.03)
    return S


def jockey(body):
    S = Shape()
    S.ell((-0.09, 0, 1.895), (0.135, 0.15, 0.11), 'jhip', 'breeches', k=0.04)
    S.cap((-0.05, 0, 1.915), (0.38, 0, 1.985), 0.12, 0.135, 'jtorso', 'silk', k=0.04, sy=1.22)
    S.ell((0.33, 0, 1.955), (0.14, 0.17, 0.105), 'jtorso', 'silk', k=0.04, pitch=10)
    S.cap((0.44, 0, 2.00), (0.50, 0, 2.03), 0.05, 0.048, 'jhead', 'skin', k=0.02)    # 首
    S.sph((0.565, 0, 2.065), 0.09, 'jhead', 'skin', k=0.01)
    S.ell((0.585, 0, 2.03), (0.055, 0.06, 0.05), 'jhead', 'skin', k=0.02)            # あご
    S.ell((0.555, 0, 2.095), (0.122, 0.108, 0.09), 'jhead', 'helmet', k=0.008, pitch=14)
    S.ell((0.665, 0, 2.085), (0.045, 0.07, 0.013), 'jhead', 'helmet', k=0.008, pitch=14)   # つば
    S.ell((0.64, 0, 2.058), (0.034, 0.08, 0.027), 'jhead', 'goggles', k=0.006, pitch=14)
    for s, suf in ((1, '.L'), (-1, '.R')):
        S.sph((0.40, 0.165 * s, 1.965), 0.068, 'jarmU' + suf, 'sleeve', k=0.03)
        S.cap((0.40, 0.175 * s, 1.955), (0.52, 0.21 * s, 1.765), 0.054, 0.046, 'jarmU' + suf, 'sleeve', k=0.025)
        S.cap((0.52, 0.21 * s, 1.765), (0.75, 0.078 * s, 1.80), 0.045, 0.035, 'jarmL' + suf, 'sleeve', k=0.02)
        S.sph((0.785, 0.07 * s, 1.80), 0.042, 'jarmL' + suf, 'glove', k=0.012)
        S.cap((-0.08, 0.10 * s, 1.875), (0.30, 0.215 * s, 1.705), 0.082, 0.06, 'jthigh' + suf, 'breeches', k=0.03)
        S.cap((0.30, 0.215 * s, 1.705), (0.03, 0.265 * s, 1.43), 0.056, 0.042, 'jshin' + suf, 'boot', k=0.02)
        S.cap((0.025, 0.265 * s, 1.415), (0.17, 0.27 * s, 1.375), 0.043, 0.034, 'jshin' + suf, 'boot', k=0.015)
    # 競走鞍
    S.ell((0.12, 0, 1.60), (0.215, 0.135, 0.03), 'spine', 'saddle', k=0.01, pitch=4)
    S.ell((0.30, 0, 1.615), (0.05, 0.08, 0.035), 'spine', 'saddle', k=0.01)

    # ゼッケン: 馬体表面から少し浮かせた薄い布
    def cloth(P):
        d = np.abs(body.field(P) - 0.013) - 0.006
        bx = np.maximum(np.abs(P[:, 0] - 0.09) - 0.27, np.abs(P[:, 2] - 1.47) - 0.24)
        return np.maximum(d, bx)
    S.fn(cloth, (-0.20, -0.33, 1.21), (0.38, 0.33, 1.66), 'spine', 'cloth')

    # 頭絡(馬体表面に沿う革帯) と手綱
    def bridle(P):
        sh = np.abs(body.field(P) - 0.007) - 0.005
        x, y, z = P[:, 0], P[:, 1], P[:, 2]
        ax = (x - 1.30) * 0.70 - (z - 1.915) * 0.714
        nose = np.abs(ax - 0.265) - 0.011                         # 鼻革
        brow = np.maximum(np.abs(ax + 0.035) - 0.010, -(z - 1.86))  # 額革
        ln = ((x - 1.195) * 0.76 + (z - 1.94) * 0.65)             # 頬革: うなじ〜口角を結ぶ線からの距離
        cheek = np.maximum(np.abs(ln) - 0.010, 0.035 - np.abs(y))
        cheek = np.maximum(cheek, np.maximum(1.50 - z, z - 1.99))
        return np.maximum(sh, np.minimum(np.minimum(nose, brow), cheek))
    S.fn(bridle, (1.10, -0.14, 1.44), (1.68, 0.14, 2.02), 'head', 'tack')
    for s, suf in ((1, '.L'), (-1, '.R')):
        S.sph((1.575, 0.058 * s, 1.515), 0.02, 'head', 'tack', k=0.004)       # ハミ環
        S.cap((1.575, 0.062 * s, 1.515), (1.30, 0.105 * s, 1.70), 0.011, 0.011, 'head', 'tack', k=0.004)
        S.cap((1.30, 0.105 * s, 1.70), (1.02, 0.10 * s, 1.80), 0.011, 0.011, 'neck2', 'tack', k=0.004)
        S.cap((1.02, 0.10 * s, 1.80), (0.80, 0.075 * s, 1.80), 0.011, 0.011, 'jarmL' + suf, 'tack', k=0.004)
    return S



# ---------------- 骨格 ----------------
def bone_table():
    B = [  # name, head, tail, parent
        ('hips', (-0.62, 0, 1.33), (-0.25, 0, 1.36), None),
        ('spine', (-0.25, 0, 1.36), (0.15, 0, 1.36), 'hips'),
        ('chest', (0.15, 0, 1.36), (0.52, 0, 1.40), 'spine'),
        ('neck1', (0.52, 0, 1.40), (0.82, 0, 1.64), 'chest'),
        ('neck2', (0.82, 0, 1.64), (1.17, 0, 1.92), 'neck1'),
        ('head', (1.17, 0, 1.92), (1.60, 0, 1.53), 'neck2'),
        ('tail1', (-0.90, 0, 1.46), (-1.03, 0, 1.30), 'hips'),
        ('tail2', (-1.03, 0, 1.30), (-1.10, 0, 0.98), 'tail1'),
        ('tail3', (-1.10, 0, 0.98), (-1.115, 0, 0.62), 'tail2'),
        ('jhip', (-0.09, 0, 1.80), (-0.05, 0, 1.915), 'spine'),
        ('jtorso', (-0.05, 0, 1.915), (0.44, 0, 2.00), 'jhip'),
        ('jhead', (0.44, 0, 2.00), (0.60, 0, 2.12), 'jtorso'),
    ]
    for s, suf in ((1, '.L'), (-1, '.R')):
        B += [
            ('scapula' + suf, (0.44, 0.10 * s, 1.52), (0.71, 0.15 * s, 1.19), 'chest'),
            ('humerus' + suf, (0.71, 0.15 * s, 1.19), (0.435, 0.16 * s, 0.95), 'scapula' + suf),
            ('radius' + suf, (0.435, 0.16 * s, 0.95), (0.474, 0.16 * s, 0.515), 'humerus' + suf),
            ('cannonF' + suf, (0.474, 0.16 * s, 0.515), (0.472, 0.16 * s, 0.218), 'radius' + suf),
            ('pasternF' + suf, (0.472, 0.16 * s, 0.218), (0.545, 0.16 * s, 0.03), 'cannonF' + suf),
            ('femur' + suf, (-0.56, 0.14 * s, 1.29), (-0.385, 0.17 * s, 0.98), 'hips'),
            ('tibia' + suf, (-0.385, 0.17 * s, 0.98), (-0.783, 0.17 * s, 0.605), 'femur' + suf),
            ('cannonH' + suf, (-0.783, 0.17 * s, 0.605), (-0.745, 0.17 * s, 0.222), 'tibia' + suf),
            ('pasternH' + suf, (-0.745, 0.17 * s, 0.222), (-0.68, 0.17 * s, 0.03), 'cannonH' + suf),
            ('jarmU' + suf, (0.40, 0.175 * s, 1.955), (0.52, 0.21 * s, 1.765), 'jtorso'),
            ('jarmL' + suf, (0.52, 0.21 * s, 1.765), (0.78, 0.07 * s, 1.80), 'jarmU' + suf),
            ('jthigh' + suf, (-0.08, 0.10 * s, 1.875), (0.30, 0.215 * s, 1.705), 'jhip'),
            ('jshin' + suf, (0.30, 0.215 * s, 1.705), (0.03, 0.265 * s, 1.43), 'jthigh' + suf),
        ]
    return B


# ---------------- Blender ----------------
def make_object(name, V, F, shape, mats, target_tris, uv_fn=None, smooth_iter=6, force_part=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(map(float, v)) for v in V], [], [tuple(map(int, f[::-1])) for f in F])
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    bones, w, parts, pid = shape.attribs(V)
    for bi, b in enumerate(bones):
        vg = ob.vertex_groups.new(name=b)
        idx = np.nonzero(w[:, bi] > 0)[0]
        for i in idx:
            vg.add([int(i)], float(w[i, bi]), 'REPLACE')
    # マテリアル
    if force_part:
        parts = [force_part]; pid = np.zeros(len(V), int)
    for p in parts:
        me.materials.append(mats[p])
    fp = pid[F]
    for poly, tri in zip(me.polygons, fp):
        poly.material_index = int(np.bincount(tri).argmax())
        poly.use_smooth = True
    # マスクをUVに格納 (JS側で毛色・白徴・陰影に使う)
    if uv_fn:
        u0, u1 = uv_fn(V)
        for nm, data in (('UVMap', u0), ('UVMask', u1)):
            layer = me.uv_layers.new(name=nm)
            for li, loop in enumerate(me.loops):
                layer.data[li].uv = (float(data[loop.vertex_index, 0]), float(data[loop.vertex_index, 1]))
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    m = ob.modifiers.new('smooth', 'SMOOTH'); m.factor = 0.6; m.iterations = smooth_iter
    bpy.ops.object.modifier_apply(modifier=m.name)
    m = ob.modifiers.new('dec', 'DECIMATE'); m.ratio = min(1.0, target_tris / len(F))
    bpy.ops.object.modifier_apply(modifier=m.name)
    m = ob.modifiers.new('smooth2', 'SMOOTH'); m.factor = 0.3; m.iterations = 2
    bpy.ops.object.modifier_apply(modifier=m.name)
    for poly in ob.data.polygons:
        poly.use_smooth = True
    ob.select_set(False)
    print(name, 'verts', len(ob.data.vertices), 'tris', len(ob.data.polygons))
    return ob


def horse_masks(V):
    x, y, z = V[:, 0], V[:, 1], V[:, 2]
    sm = lambda a, b, t: np.clip((t - a) / (b - a), 0, 1) ** 2 * (3 - 2 * np.clip((t - a) / (b - a), 0, 1))
    # 四肢下部と鼻先の黒み (鹿毛系の「黒い長靴」)
    points = 1 - sm(0.50, 0.92, z)
    muzzle = 1 - sm(0.07, 0.19, np.sqrt((x - 1.60) ** 2 + (z - 1.52) ** 2 + y ** 2))
    points = np.maximum(points, muzzle * 0.8)
    # 白徴の候補領域: 0.2=流星(顔の正面)  0.4/0.5=前肢左右  0.6/0.7=後肢左右 の白
    mark = np.zeros(len(V), np.float32)
    ax = (x - 1.30) * 0.7 + (z - 1.915) * -0.714   # 鼻梁に沿った位置
    off = (x - 1.30) * 0.714 + (z - 1.915) * 0.7   # 顔の前面側ほど大
    blaze = (ax > 0.02) & (ax < 0.36) & (off > 0.02) & (np.abs(y) < 0.028) & (x > 1.2)
    mark[blaze] = 0.2
    leg = z < 0.30
    mark[leg & (x > 0) & (y > 0)] = 0.4; mark[leg & (x > 0) & (y < 0)] = 0.5
    mark[leg & (x < 0) & (y > 0)] = 0.6; mark[leg & (x < 0) & (y < 0)] = 0.7
    sock_h = np.clip(z / 0.30, 0, 1)  # 白の高さ判定用
    # 簡易な陰影: 腹下・股・顎下を暗く
    under = sm(1.05, 0.86, z) * (np.abs(x) < 0.75) * (z > 0.8)
    inner = (1 - sm(0.02, 0.14, np.abs(y))) * (z < 1.0) * (z > 0.3)
    ao = 1 - 0.35 * np.maximum(under, inner * 0.8)
    return np.stack([points, mark], 1), np.stack([ao, sock_h], 1)


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mats = {}
    cols = {'coat': (0.30, 0.15, 0.07), 'hoof': (0.05, 0.045, 0.04), 'mane': (0.03, 0.025, 0.02), 'eye': (0.01, 0.01, 0.01),
            'silk': (0.75, 0.1, 0.1), 'sleeve': (0.9, 0.8, 0.1), 'breeches': (0.92, 0.92, 0.9), 'boot': (0.03, 0.03, 0.03),
            'skin': (0.78, 0.56, 0.44), 'helmet': (0.1, 0.25, 0.8), 'goggles': (0.05, 0.05, 0.06), 'glove': (0.9, 0.9, 0.9), 'saddle': (0.12, 0.07, 0.04), 'cloth': (0.93, 0.93, 0.9), 'tack': (0.07, 0.04, 0.025)}
    rough = {'coat': 0.42, 'hoof': 0.5, 'mane': 0.6, 'eye': 0.1, 'silk': 0.38, 'sleeve': 0.38, 'breeches': 0.7, 'boot': 0.3, 'skin': 0.6, 'helmet': 0.45, 'goggles': 0.15, 'glove': 0.7, 'saddle': 0.5, 'cloth': 0.8, 'tack': 0.45}
    for k, c in cols.items():
        m = bpy.data.materials.new(k)
        m.use_nodes = True
        bsdf = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
        bsdf.inputs['Base Color'].default_value = (*c, 1)
        bsdf.inputs['Roughness'].default_value = rough[k]
        mats[k] = m

    body = horse_body()
    objs_h, objs_j = [], []
    # 馬体(毛)と蹄は別メッシュにして境界をきれいに出す
    for parts, tris, vox, it in ((['coat'], 10500, VOX, 6), (['hoof'], 700, 0.006, 2)):
        sh = body.subset(parts) if parts != ['coat'] else body
        V, F = sh.mesh(vox=vox, floor=0.004)
        objs_h.append(make_object('H_' + parts[0], V, F, sh, mats, tris, uv_fn=horse_masks, smooth_iter=it, force_part=parts[0]))
    hair = horse_hair()
    V, F = hair.mesh()
    objs_h.append(make_object('H_hair', V, F, hair, mats, 1500, uv_fn=horse_masks, smooth_iter=4))
    jk = jockey(body)
    for parts, tris, vox, it in ((['silk'], 700, 0.009, 3), (['sleeve'], 600, 0.008, 3), (['breeches'], 600, 0.009, 3), (['boot'], 500, 0.008, 3),
                                 (['skin'], 300, 0.007, 2), (['helmet'], 350, 0.007, 2), (['goggles'], 80, 0.006, 1), (['glove'], 120, 0.007, 2),
                                 (['saddle'], 160, 0.007, 2), (['cloth'], 500, 0.007, 2), (['tack'], 1500, 0.0055, 1)):
        sh = jk.subset(parts)
        V, F = sh.mesh(vox=vox)
        objs_j.append(make_object('J_' + parts[0], V, F, sh, mats, tris, smooth_iter=it))
    # 目
    eyes = []
    for s in (1, -1):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=10, ring_count=6, radius=0.021, location=(1.343, 0.099 * s, 1.842))
        e = bpy.context.active_object; e.data.materials.append(mats['eye'])
        for p in e.data.polygons: p.use_smooth = True
        vg = e.vertex_groups.new(name='head'); vg.add(list(range(len(e.data.vertices))), 1.0, 'REPLACE')
        eyes.append(e)
    # 統合: 馬 / 騎手+馬具
    def join(objs, name):
        bpy.ops.object.select_all(action='DESELECT')
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        bpy.ops.object.join()
        objs[0].name = name
        return objs[0]
    ob_body = join(objs_h + eyes, 'Horse')
    ob_j = join(objs_j, 'Jockey')
    print('TOTAL tris horse', len(ob_body.data.polygons), 'jockey', len(ob_j.data.polygons))

    # アーマチュア
    arm = bpy.data.armatures.new('Rig')
    rig = bpy.data.objects.new('Rig', arm)
    bpy.context.scene.collection.objects.link(rig)
    bpy.ops.object.select_all(action='DESELECT')
    bpy.context.view_layer.objects.active = rig; rig.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    for name, h, t, par in bone_table():
        b = arm.edit_bones.new(name); b.head = h; b.tail = t
        if par:
            b.parent = arm.edit_bones[par]
    bpy.ops.object.mode_set(mode='OBJECT')
    for ob in (ob_body, ob_j):
        ob.parent = rig
        md = ob.modifiers.new('Armature', 'ARMATURE'); md.object = rig

    if PREVIEW:
        render_preview(PREVIEW)
    import os
    os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_yup=True, export_apply=False, export_skins=True,
                              export_animations=False, export_texcoords=True, export_normals=True, export_materials='EXPORT',
                              export_def_bones=False)
    print('exported', OUT, os.path.getsize(OUT) // 1024, 'KB')


def render_preview(outdir):
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.samples = 24
    sc.view_settings.view_transform = 'Standard'
    sc.cycles.device = 'CPU'
    sc.render.resolution_x = 1100; sc.render.resolution_y = 700
    w = bpy.data.worlds.new('W'); sc.world = w; w.use_nodes = True
    w.node_tree.nodes['Background'].inputs[0].default_value = (0.6, 0.75, 1.0, 1); w.node_tree.nodes['Background'].inputs[1].default_value = 0.6
    sun = bpy.data.objects.new('Sun', bpy.data.lights.new('Sun', 'SUN')); sun.data.energy = 2.6
    sun.rotation_euler = (math.radians(50), 0, math.radians(35)); sc.collection.objects.link(sun)
    bpy.ops.mesh.primitive_plane_add(size=30); g = bpy.context.active_object
    gm = bpy.data.materials.new('g'); gm.diffuse_color = (0.2, 0.4, 0.15, 1); g.data.materials.append(gm)
    cam = bpy.data.objects.new('Cam', bpy.data.cameras.new('Cam')); sc.collection.objects.link(cam); sc.camera = cam
    cam.data.lens = 60
    for nm, pos, tgt in (('side', (0.3, -6.2, 1.25), (0.3, 0, 1.12)), ('q', (4.6, -3.6, 1.9), (0.3, 0, 1.15)), ('front', (5.6, 0.9, 1.6), (0.4, 0, 1.3)), ('rear', (-4.4, -2.6, 2.2), (0.2, 0, 1.2))):
        cam.location = pos
        d = Vector(tgt) - Vector(pos)
        cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = f'{outdir}/horse_{nm}.png'
        bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(g); bpy.data.objects.remove(sun); bpy.data.objects.remove(cam)


build()
