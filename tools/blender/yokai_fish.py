# 妖怪魚をアニメキャラクター風の3Dモデルにする(Blender 4.2 / bpy)。
#
# 使い方(Blender の Python で実行):
#   1) lune run tools/export_fish.luau build/fish.json            (ゲームのデザインデータを書き出す)
#   2) blender -b -P tools/blender/yokai_fish.py -- --defs build/fish.json --out build/fish --export --luau src/shared/Config/FishMeshes.luau
#      (Blender が無い環境では pip の bpy==4.2.0 で `python tools/blender/yokai_fish.py ...` でも動く)
#   その他: --ids hasu_koi,bake_fugu(一部だけ) / --render(確認用の画像) / --verify GLB 出力先(書き出し結果の確認)
#
# つくりの方針:
#   * 体: 頭・胴・尾の付け根などの楕円体を「ボクセルで溶かして一体化」し、なめらかな一つの体にする(粘土をこねたような形)
#   * 目: 縦長の白目 + グラデーションの虹彩 + 瞳 + 大小2つの光 + 太いまつげの線(アニメの目)
#   * 顔: ほっぺの赤み、小さな口(にっこり・への字・ω・舌・牙…)
#   * 色: 平らな色(アニメの塗り)。お腹は明るく、背中は少し濃く
#   * 輪郭線: 少し大きい裏返しの殻(インバーテッドハル)。Roblox でも同じ方法で線が出る
#   * レア度: 大きさ、ひれの縁取り(伝説以上は金)、額の金の紋、後光の輪、鬼火 を自動で付ける
#
# 座標: Blender は Z が上。魚は +Y が頭(glTF 書き出しで Roblox の -Z が頭になる)。

import argparse
import json
import math
import os
import random
import sys

import bpy  # noqa: I001  (bpy を先に読み込むと bmesh / mathutils が使えるようになる)
import bmesh
from mathutils import Matrix, Vector
from mathutils import noise as mnoise

# ---------------------------------------------------------------------------
# 基本

RARITY_SCALE = {"common": 0.75, "uncommon": 0.88, "rare": 1.05, "epic": 1.3, "legendary": 1.7, "mythic": 2.15, "secret": 2.6}  # FishBuilder と同じ
RARITY_ORDER = {"common": 1, "uncommon": 2, "rare": 3, "epic": 4, "legendary": 5, "mythic": 6, "secret": 7}
INK = (0.07, 0.05, 0.09)
WHITE = (0.98, 0.97, 0.95)
GOLD = (0.95, 0.76, 0.31)
PINK = (1.0, 0.56, 0.66)
RED = (0.84, 0.15, 0.24)
LIGHT = Vector((0.35, 0.45, 0.82)).normalized()  # 塗りの影の向き
OUTLINE = 0.011  # 輪郭線(裏返しの殻)の厚み。細めにして、描いた線より立体の縁に見せる


def hexc(h):
    """#RRGGBB → 0..1(sRGB)。色の計算は sRGB のまま行い、書き込む時に linear へ直す"""
    h = h.lstrip("#")
    return tuple(int(h[i : i + 2], 16) / 255 for i in (0, 2, 4))


def to_linear(c):
    return tuple((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c)


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def lighten(c, t):
    return mix(c, (1, 1, 1), t)


def darken(c, t):
    return mix(c, (0, 0, 0), t)


def smoothstep(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def frame(forward, up_hint=Vector((0, 0, 1))):
    """forward を Y 軸にした回転行列(パーツの長い向きを forward へ)"""
    f = Vector(forward).normalized()
    up = Vector(up_hint)
    if abs(f.dot(up.normalized())) > 0.97:
        up = Vector((1, 0, 0))
    x = f.cross(up).normalized()
    z = x.cross(f).normalized()
    return Matrix((x, f, z)).transposed()


QUALITY = float(os.environ.get("FISH_QUALITY", "2.0"))  # 体の細かさ(1 = 軽い試作、2 = 本番)。試し描きは FISH_QUALITY=1
# 部品(目・ひれ・飾り)の作り方。ゲーム用の軽い版は LOD["parts"] を下げ、目の上に重ねる薄い模様
# (虹彩・瞳・光)を省く。その色は細かい版からテクスチャに焼き込まれるので見た目は同じ
LOD = {"parts": QUALITY, "decals": True}


def q(n):
    return max(6, int(round(n * LOD["parts"])))


def catmull(points, per=4):
    """点の列をなめらかな曲線にする(ひげ・まつげ・口の線)"""
    pts = [Vector(p) for p in points]
    if len(pts) < 3:
        return pts
    out = []
    ext = [pts[0] * 2 - pts[1]] + pts + [pts[-1] * 2 - pts[-2]]
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        for j in range(per):
            t = j / per
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3))
    out.append(pts[-1])
    return out


class Geo:
    """色つきの形を1つの bmesh に足していく入れ物"""

    def __init__(self):
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.float_color.new("Col")

    def add_sphere(self, center, radii, color, rot=None, seg=16, rings=10, taper=None, color_fn=None, shape_fn=None):
        """楕円体を足す。taper=(強さ, べき) で +Y 側を細くして涙型にする。
        color_fn(x, y, z) は単位球の上の位置から色を返す(ひれの筋・虹彩の模様など)。
        shape_fn(x, y, z) は単位球の点を変形して返す(ひれの縁のぎざぎざなど)"""
        tmp = bmesh.new()
        bmesh.ops.create_uvsphere(tmp, u_segments=q(seg), v_segments=q(rings), radius=1.0)
        tmp.verts.index_update()
        tmp.verts.ensure_lookup_table()
        unit = {}
        for v in tmp.verts:
            x, y, z = v.co
            unit[v.index] = (x, y, z)
            if shape_fn:
                x, y, z = shape_fn(x, y, z)
            if taper:
                k, p = taper
                t = min(1.0, max(0.0, (y + 1) / 2))  # 0(根元)..1(先)
                s = max(0.02, 1 - k * t**p)
                x *= s
                z *= s
            v.co = Vector((x * radii[0], y * radii[1], z * radii[2]))
        m = rot if rot is not None else Matrix.Identity(3)
        for v in tmp.verts:
            v.co = m @ v.co + Vector(center)
        if m.determinant() < 0:
            # 鏡に映す向きの回転だと面が裏返るので、表(外向き)に戻す(法線マップの焼き込みに必要)
            bmesh.ops.reverse_faces(tmp, faces=tmp.faces[:])
        self._merge(tmp, color, (lambda v: color_fn(*unit[v.index])) if color_fn else None)

    def add_torus(self, center, normal, major, minor, color, seg=64, sides=14, arc=1.0, start=0.0):
        # 軽い版では輪の分割も減らす(細かい版はそのまま)
        f = LOD["parts"] / QUALITY
        seg, sides = max(16, int(seg * f)), max(6, int(sides * f))
        tmp = bmesh.new()
        n = Vector(normal).normalized()
        a = Vector((1, 0, 0)) if abs(n.x) < 0.9 else Vector((0, 1, 0))
        u = n.cross(a).normalized()
        w = n.cross(u).normalized()
        rings = []
        closed = arc >= 0.999
        count = seg if closed else seg + 1
        for i in range(count):
            th = (start + arc * i / seg) * 2 * math.pi
            c = u * math.cos(th) * major + w * math.sin(th) * major
            radial = c.normalized()
            ring = []
            for j in range(sides):
                ph = j / sides * 2 * math.pi
                p = Vector(center) + c + (radial * math.cos(ph) + n * math.sin(ph)) * minor
                ring.append(tmp.verts.new(p))
            rings.append(ring)
        for i in range(len(rings) - (0 if closed else 1)):
            r1, r2 = rings[i], rings[(i + 1) % len(rings)]
            for j in range(sides):
                tmp.faces.new((r1[j], r1[(j + 1) % sides], r2[(j + 1) % sides], r2[j]))
        self._merge(tmp, color)

    def add_tube(self, points, radius, color, sides=6, radius_end=None, smooth=True):
        """点の列に沿った管(まつげ・ひげ・口の線など)。点の間はなめらかに補間する"""
        if smooth:
            points = catmull(points, 4)
        sides = q(sides)
        tmp = bmesh.new()
        rings = []
        n = len(points)
        for i, p in enumerate(points):
            p = Vector(p)
            d = (Vector(points[min(i + 1, n - 1)]) - Vector(points[max(i - 1, 0)])).normalized()
            r = radius if radius_end is None else radius + (radius_end - radius) * i / max(1, n - 1)
            a = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
            u = d.cross(a).normalized()
            w = d.cross(u).normalized()
            ring = [tmp.verts.new(p + (u * math.cos(j / sides * 2 * math.pi) + w * math.sin(j / sides * 2 * math.pi)) * r) for j in range(sides)]
            rings.append(ring)
        for i in range(n - 1):
            for j in range(sides):
                tmp.faces.new((rings[i][j], rings[i][(j + 1) % sides], rings[i + 1][(j + 1) % sides], rings[i + 1][j]))
        tmp.faces.new(list(reversed(rings[0])))
        tmp.faces.new(rings[-1])
        self._merge(tmp, color)
        # 端を丸く
        self.add_sphere(points[0], (radius,) * 3, color, seg=8, rings=5)
        self.add_sphere(points[-1], ((radius_end or radius),) * 3, color, seg=8, rings=5)

    def add_disc(self, center, normal, rx, ry, color, up=Vector((0, 0, 1)), thick=0.012, seg=18, color_fn=None, curve=0.0):
        """表面に貼る平たい円(目・ほっぺ・紋など)。rx は横、ry は縦。
        color_fn(u, v) は円の中の位置(-1..1、u 横・v 縦)から色を返す。
        curve(=1/半径)を渡すと、丸い頭に沿うように縁を沈めて曲げる(横から見て飛び出さない)"""
        n = Vector(normal).normalized()
        upv = Vector(up) - n * Vector(up).dot(n)
        if upv.length < 1e-4:
            upv = Vector((0, 1, 0)) - n * n.y
        upv.normalize()
        side = upv.cross(n).normalized()
        rot = Matrix((side, n, upv)).transposed()  # Y 軸 = 法線(薄い方向)
        fn = (lambda x, y, z: color_fn(x, z)) if color_fn else None
        bend = None
        if curve:
            bend = lambda x, y, z: (x, y - curve * ((x * rx) ** 2 + (z * ry) ** 2) * 0.5 / thick, z)
        self.add_sphere(center, (rx, thick, ry), color, rot=rot, seg=seg, rings=6, color_fn=fn, shape_fn=bend)

    def _merge(self, tmp, color, vert_color=None):
        lc = to_linear(color)
        rgba = (lc[0], lc[1], lc[2], 1.0)
        layer = tmp.loops.layers.float_color.new("Col")
        cache = {}
        for f in tmp.faces:
            for l in f.loops:
                if vert_color:
                    vi = l.vert.index
                    if vi not in cache:
                        c = to_linear(vert_color(l.vert))
                        cache[vi] = (c[0], c[1], c[2], 1.0)
                    l[layer] = cache[vi]
                else:
                    l[layer] = rgba
        mesh = bpy.data.meshes.new("tmp")
        tmp.to_mesh(mesh)
        tmp.free()
        self.bm.from_mesh(mesh)
        bpy.data.meshes.remove(mesh)
        self.col = self.bm.loops.layers.float_color.get("Col")

    def to_object(self, name):
        mesh = bpy.data.meshes.new(name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        for p in mesh.polygons:
            p.use_smooth = True
        return obj


def evaluated_copy(obj, name):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = obj.evaluated_get(dg)
    mesh = bpy.data.meshes.new_from_object(ev)
    new = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(new)
    return new


# ---------------------------------------------------------------------------
# 体の形(Blender 座標: +Y が頭、Z が上)

SHAPES = {
    "koi": dict(
        parts=[((0, 0.42, 0.04), (0.47, 0.52, 0.5)), ((0, 0.05, 0.02), (0.42, 0.45, 0.46)), ((0, -0.3, 0), (0.36, 0.62, 0.41)), ((0, -0.86, 0.0), (0.15, 0.36, 0.2))],
        head=((0, 0.42, 0.04), (0.47, 0.52, 0.5)), tail="forked", tailY=-1.12, length=2.3, dorsal="sail",
    ),
    "catfish": dict(
        parts=[((0, 0.45, -0.04), (0.6, 0.5, 0.36)), ((0, -0.2, 0), (0.44, 0.8, 0.34)), ((0, -0.95, 0), (0.15, 0.36, 0.17))],
        head=((0, 0.45, -0.04), (0.6, 0.5, 0.36)), tail="fan", tailY=-1.22, length=2.5, dorsal="small",
    ),
    "puffer": dict(
        parts=[((0, 0.05, 0), (0.72, 0.7, 0.68)), ((0, -0.72, 0), (0.14, 0.24, 0.17))],
        head=((0, 0.05, 0), (0.72, 0.7, 0.68)), tail="fan", tailY=-0.9, length=1.8, dorsal="small",
    ),
    "eel": dict(parts=None, head=((0, 1.25, 0.02), (0.3, 0.42, 0.32)), tail="ribbon", tailY=-1.75, length=3.4, dorsal="ribbon"),
    "angler": dict(
        parts=[((0, 0.22, 0.06), (0.68, 0.62, 0.6)), ((0, -0.42, 0), (0.42, 0.5, 0.4)), ((0, -0.92, 0), (0.14, 0.3, 0.17))],
        head=((0, 0.22, 0.06), (0.68, 0.62, 0.6)), tail="fan", tailY=-1.15, length=2.2, dorsal="spines",
    ),
    "ray": dict(
        parts=[
            ((0, 0.0, 0.0), (0.52, 0.6, 0.26)),
            ((0, 0.42, 0.1), (0.44, 0.36, 0.32)),
            ((0.6, -0.08, -0.06), (0.72, 0.46, 0.09)),
            ((-0.6, -0.08, -0.06), (0.72, 0.46, 0.09)),
            ((1.05, -0.2, -0.14), (0.38, 0.26, 0.06)),
            ((-1.05, -0.2, -0.14), (0.38, 0.26, 0.06)),
        ],
        head=((0, 0.42, 0.1), (0.44, 0.36, 0.32)), tail="whip", tailY=-0.6, length=2.0, dorsal="none",
    ),
    # 鮫(伝説以上の大物): 先へ細くなる鼻先、高い三角の背びれ、上の葉が長い三日月の尾、えらの切れ目
    # 部品の3つ目は taper(先 = +Y 側を細くする強さ, べき)
    "shark": dict(
        parts=[
            ((0, 0.55, 0.03), (0.4, 0.5, 0.37)),
            ((0, 0.92, -0.02), (0.31, 0.42, 0.25), (0.45, 1.3)),
            ((0, 0.3, 0.01), (0.47, 0.42, 0.44)),  # 頭と胴のつなぎ(くびれを埋める)
            ((0, 0.02, 0.0), (0.5, 0.8, 0.49)),
            ((0, -0.38, 0.0), (0.4, 0.45, 0.39)),  # 胴と尾のつなぎ
            ((0, -0.62, 0.01), (0.3, 0.62, 0.3)),
            ((0, -1.12, 0.02), (0.12, 0.4, 0.15)),
        ],
        head=((0, 0.55, 0.03), (0.4, 0.5, 0.37)), tail="crescent", tailY=-1.42, length=2.9, dorsal="shark",
    ),
    # 鯱: 丸く太い頭と体、まっすぐ高い背びれ、横に広がる尾びれ(白黒の模様は pattern="orca")
    "orca": dict(
        parts=[
            ((0, 0.7, 0.02), (0.44, 0.5, 0.42)),
            ((0, 1.08, -0.1), (0.25, 0.18, 0.17)),
            ((0, 0.45, 0.01), (0.52, 0.42, 0.5)),  # 頭と胴のつなぎ
            ((0, 0.1, 0.0), (0.56, 0.82, 0.55)),
            ((0, -0.4, 0.0), (0.46, 0.45, 0.45)),  # 胴と尾のつなぎ
            ((0, -0.62, 0.0), (0.34, 0.66, 0.36)),
            ((0, -1.12, 0.0), (0.12, 0.38, 0.2)),
        ],
        head=((0, 0.7, 0.02), (0.44, 0.5, 0.42)), tail="flukes", tailY=-1.42, length=2.9, dorsal="orca",
    ),
    # 鮭(川の大物): 鉤のように曲がった下あご、背中のこぶ、脂びれ、大きな二又の尾
    "salmon": dict(
        parts=[
            ((0, 0.62, 0.03), (0.38, 0.5, 0.42)),
            ((0, 0.98, -0.03), (0.27, 0.36, 0.27), (0.5, 1.2)),
            ((0, 0.3, 0.06), (0.43, 0.42, 0.5)),
            ((0, 0.08, 0.14), (0.42, 0.62, 0.54)),  # 背中のこぶ
            ((0, -0.12, 0.0), (0.44, 0.7, 0.46)),
            ((0, -0.62, 0.0), (0.3, 0.58, 0.36)),
            ((0, -1.1, 0.0), (0.12, 0.38, 0.19)),
        ],
        head=((0, 0.62, 0.04), (0.38, 0.5, 0.42)), tail="forked", tailY=-1.4, length=2.9, dorsal="salmon",
    ),
    # 大山椒魚(川の主): 平たく広い頭、太く平たい体、4本の短い足、尾の上下のひれ、いぼいぼの肌
    "salamander": dict(
        parts=[
            ((0, 0.8, 0.0), (0.64, 0.46, 0.25)),
            ((0, 0.42, 0.0), (0.58, 0.4, 0.28)),
            ((0, 0.0, 0.0), (0.52, 0.7, 0.3)),
            ((0, -0.62, 0.0), (0.38, 0.55, 0.26)),
            ((0, -1.02, 0.02), (0.22, 0.45, 0.25)),
            ((0, -1.45, 0.03), (0.12, 0.4, 0.21)),
        ],
        head=((0, 0.8, 0.02), (0.64, 0.46, 0.26)), tail="paddle", tailY=-1.75, length=3.4, dorsal="ridge",
    ),
    # 鯨(海の主): 大きく丸い頭、長い胸びれ、小さな背のこぶ、横に広い尾びれ、のどの畝
    "whale": dict(
        parts=[
            ((0, 0.78, 0.02), (0.55, 0.62, 0.5)),
            ((0, 0.4, 0.0), (0.6, 0.45, 0.54)),
            ((0, 0.02, 0.0), (0.62, 0.9, 0.56)),
            ((0, -0.45, 0.0), (0.5, 0.5, 0.46)),
            ((0, -0.75, 0.0), (0.36, 0.66, 0.36)),
            ((0, -1.22, 0.0), (0.13, 0.42, 0.2)),
        ],
        head=((0, 0.78, 0.02), (0.55, 0.62, 0.5)), tail="flukes", tailY=-1.52, length=3.2, dorsal="hump",
    ),
    # 蝶鮫(チョウザメ。湖の古代魚): 平たく長い鼻先、背と横の骨の板(3列)、後ろの小さな背びれ、上の葉が長い尾
    "sturgeon": dict(
        parts=[
            ((0, 0.58, 0.02), (0.36, 0.42, 0.3)),
            ((0, 1.0, -0.02), (0.24, 0.5, 0.12), (0.45, 1.3)),
            ((0, 0.25, 0.0), (0.42, 0.4, 0.36)),
            ((0, -0.05, 0.0), (0.42, 0.75, 0.37)),
            ((0, -0.62, 0.0), (0.27, 0.58, 0.26)),
            ((0, -1.08, 0.03), (0.11, 0.38, 0.13)),
        ],
        head=((0, 0.58, 0.04), (0.36, 0.42, 0.3)), tail="crescent", tailY=-1.4, length=3.0, dorsal="sturgeon",
    ),
}
# --- 百鬼の祠の限定の魚だけの形(釣れる魚には無い、ひとめで違うシルエット) ---
SHAPES.update({
    # 翻車魚(マンボウ): 縦に高い円盤の体、上下に高い背びれ・しりびれ、尾の代わりのひだ(舵びれ)。天照では体のまわりに日の光の棘
    "mola": dict(
        parts=[((0, 0.0, 0.0), (0.3, 0.86, 0.98)), ((0, 0.52, 0.04), (0.33, 0.44, 0.6))],
        head=((0, 0.52, 0.04), (0.33, 0.44, 0.6)), tail="none", tailY=-0.86, length=1.9, dorsal="none",
    ),
    # 撞木鮫(シュモクザメ): 鮫の体に、横へ長い金づちの頭。目は金づちの両端
    "hammer": dict(
        parts=[
            ((0, 0.55, 0.03), (0.36, 0.45, 0.33)),
            ((0, 0.3, 0.01), (0.45, 0.42, 0.42)),
            ((0, 0.02, 0.0), (0.48, 0.8, 0.47)),
            ((0, -0.38, 0.0), (0.38, 0.45, 0.37)),
            ((0, -0.88, 0.01), (0.25, 0.42, 0.26)),  # 胴と尾のつなぎ
            ((0, -1.35, 0.03), (0.15, 0.4, 0.2)),
            ((0, 0.92, 0.06), (1.25, 0.28, 0.17)),
            ((0, 0.75, 0.03), (0.4, 0.3, 0.26)),
        ],
        head=((0, 0.92, 0.06), (1.25, 0.28, 0.17)), tail="crescent", tailY=-1.75, length=3.4, dorsal="shark",
    ),
    # 龍: うねる長い体、4本の足と爪、長い鼻先、背中の棘、尾の先の炎のような房
    "dragon": dict(parts=None, head=((0, 1.42, 0.22), (0.33, 0.42, 0.3)), tail="none", tailY=-1.95, length=3.9, dorsal="none"),
    # 八岐大蛇: がっしりした胴から8本の首が扇に伸び、それぞれに頭。尾は8本
    "hydra": dict(
        parts=[((0, 0.1, 0.0), (0.62, 0.8, 0.5)), ((0, -0.62, 0.0), (0.42, 0.55, 0.36)), ((0, -1.1, 0.0), (0.18, 0.4, 0.2))],
        head=((0, 1.45, 1.25), (0.3, 0.36, 0.26)), tail="fan", tailY=-1.35, length=3.0, dorsal="none",
    ),
    # 海月(クラゲ): 丸い傘、ふちのひだ、垂れ下がる口腕と細い触手
    "jelly": dict(
        parts=[((0, 0.0, 0.32), (0.74, 0.74, 0.5)), ((0, 0.0, 0.04), (0.8, 0.8, 0.16))],
        head=((0, 0.0, 0.32), (0.74, 0.74, 0.5)), tail="none", tailY=-0.8, length=1.6, dorsal="none",
    ),
    # 竜の落とし子(タツノオトシゴ): 立った体、長い口先、前にふくらむお腹、くるりと巻いた尾
    "seahorse": dict(parts=None, head=((0, 0.24, 1.0), (0.23, 0.29, 0.23)), tail="none", tailY=-0.2, length=1.5, dorsal="none"),
    # 鳳凰魚: 細い体に、鳥のつばさのように広がる胸びれ(3枚重ね)と、長い尾羽
    "phoenix": dict(
        parts=[((0, 0.55, 0.05), (0.34, 0.44, 0.38)), ((0, 0.1, 0.02), (0.36, 0.56, 0.38)), ((0, -0.45, 0.0), (0.24, 0.6, 0.28)), ((0, -0.95, 0.0), (0.1, 0.34, 0.12))],
        head=((0, 0.55, 0.05), (0.34, 0.44, 0.38)), tail="none", tailY=-1.2, length=2.4, dorsal="none",
    ),
    # 羽衣魚(ベタのような): 短く高い体に、体より大きく流れる尾・背びれ・しりびれ、袖のような長い胸びれ
    "veil": dict(
        parts=[((0, 0.35, 0.02), (0.31, 0.4, 0.4)), ((0, -0.05, 0.0), (0.33, 0.5, 0.44)), ((0, -0.45, 0.0), (0.2, 0.34, 0.27))],
        head=((0, 0.35, 0.02), (0.31, 0.4, 0.4)), tail="none", tailY=-0.72, length=2.0, dorsal="none",
    ),
})
NEW_SHAPES = ("mola", "hammer", "dragon", "hydra", "jelly", "seahorse", "phoenix", "veil")

# 龍の背骨(x, y, z, 太さ)。上下にうねる
DRAGON_SPINE = [(0.0, 1.2, 0.2, 0.26), (0.0, 0.85, 0.05, 0.27), (0.0, 0.5, -0.12, 0.27), (0.0, 0.15, -0.08, 0.26), (0.0, -0.2, 0.12, 0.24), (0.0, -0.55, 0.22, 0.21), (0.0, -0.9, 0.08, 0.18), (0.0, -1.25, -0.1, 0.14), (0.0, -1.6, -0.06, 0.1), (0.0, -1.9, 0.06, 0.06)]
# 竜の落とし子の背骨(頭の下から、お腹、巻いた尾の先まで)
SEAHORSE_SPINE = [(0.0, 0.12, 0.8, 0.17), (0.0, 0.12, 0.55, 0.24), (0.0, 0.16, 0.25, 0.3), (0.0, 0.08, -0.05, 0.27), (0.0, -0.04, -0.33, 0.2), (0.0, -0.06, -0.58, 0.15), (0.0, 0.06, -0.8, 0.11), (0.0, 0.24, -0.86, 0.09), (0.0, 0.36, -0.72, 0.075), (0.0, 0.3, -0.56, 0.06), (0.0, 0.18, -0.6, 0.05)]

# 八岐大蛇の首の先の頭の位置(真ん中が主の頭。ほかの7つは左右に扇)
def hydra_heads():
    """8つの頭: 真ん中の主の頭は高く前へ、ほかの7つは左右に大きく広げて高さを変える(冠のように見える)"""
    heads = [((0, 1.45, 1.25), 1.0)]
    for k in range(7):
        a = math.radians(-81 + k * 27)
        heads.append(((math.sin(a) * 1.35, 0.75 + 0.45 * math.cos(a), 0.75 + 0.55 * math.cos(a) + 0.12 * (k % 2)), 0.78))
    return heads


def spine_body(body, spine, sp, S, c1):
    for k in range(len(spine) - 1):
        a0, a1 = spine[k], spine[k + 1]
        for j in range(5):
            t = j / 5
            x, y, z, r = (a0[i] + (a1[i] - a0[i]) * t for i in range(4))
            body.add_sphere(sp((x, y, z)), tuple(S @ Vector((r, r * 1.1, r * 1.08))), c1, seg=20, rings=12)
    x, y, z, r = spine[-1]
    body.add_sphere(sp((x, y, z)), tuple(S @ Vector((r, r * 1.1, r * 1.08))), c1, seg=20, rings=12)


def special_body(d, body, sp, S, c1):
    """限定の形の体(溶かして一体にする部分)"""
    shape = d["shape"]
    if shape == "dragon":
        spine_body(body, DRAGON_SPINE, sp, S, c1)
        body.add_sphere(sp((0, 1.42, 0.22)), (0.33, 0.42, 0.3), c1)
        body.add_sphere(sp((0, 1.82, 0.12)), (0.2, 0.32, 0.15), c1, taper=(0.35, 1.2))  # 長い鼻先
        body.add_sphere(sp((0, 1.7, 0.0)), (0.17, 0.3, 0.08), c1, taper=(0.4, 1.2))  # 下あご
        for (y, z) in ((0.78, 0.0), (-0.75, 0.1)):  # 4本の足
            for sgn in (1, -1):
                dirv = Vector((sgn * 0.8, 0.25 if y > 0 else -0.2, -0.6)).normalized()
                root = sp((sgn * 0.18, y, z - 0.08))
                body.add_sphere(tuple(root + dirv * 0.22), (0.1, 0.3, 0.1), c1, rot=frame(dirv))
    elif shape == "seahorse":
        spine_body(body, SEAHORSE_SPINE, sp, S, c1)
        body.add_sphere(sp((0, 0.24, 1.0)), (0.23, 0.29, 0.23), c1)
        body.add_sphere(sp((0, 0.62, 0.97)), (0.075, 0.32, 0.085), c1, rot=frame(Vector((0, 1, -0.08))), taper=(0.3, 1.0))  # 管のような口
    elif shape == "hydra":
        for (hp_, k) in hydra_heads():
            hp = Vector(hp_)
            base = Vector((hp.x * 0.35, 0.45, 0.3))
            mid = (base + hp) / 2 + Vector((hp.x * 0.1, -0.15, 0.3))
            pts = catmull([tuple(base), tuple(mid), tuple(hp)], 7)
            for i, pt in enumerate(pts):
                r = (0.17 - 0.06 * i / len(pts)) * (1.0 if k == 1.0 else 0.85)
                body.add_sphere(pt, (r, r, r), c1, seg=16, rings=10)
            fwd = (hp - mid).normalized()
            body.add_sphere(tuple(hp), (0.3 * k, 0.36 * k, 0.26 * k), c1, rot=frame(fwd) if k != 1.0 else None)
            body.add_sphere(tuple(hp + fwd * 0.3 * k), (0.17 * k, 0.26 * k, 0.12 * k), c1, rot=frame(fwd), taper=(0.35, 1.1))


def special_details(d, g, fin, sp, S, head, c1, c2, c3, fin_col, order, deco):
    """限定の形のひれ・尾・飾り(体とは別の部品)"""
    shape = d["shape"]
    hc, hr = head
    if shape == "mola":
        # 高い背びれとしりびれ(鎌のよう)
        for zs in (1, -1):
            dirv = Vector((0, -0.25, zs)).normalized()
            fin(tuple(Vector((0, -0.3, zs * 0.78)) + dirv * 0.45), (0.05, 0.55, 0.26), frame(dirv), c3, taper=(0.75, 1.3), rays=5)
        # 舵びれ(尾の代わりの、ふちのひだ)
        for i in range(7):
            a = math.radians(-60 + i * 20)
            dirv = Vector((0, -math.cos(a), math.sin(a)))
            p = Vector((0, -0.8 * math.cos(a) - 0.02, 0.92 * math.sin(a)))
            fin(tuple(p + dirv * 0.12), (0.035, 0.16, 0.12), frame(dirv, Vector((1, 0, 0))), lighten(c2, 0.1), taper=(0.1, 1.0), rays=3)
        # 日の光: 体のまわりに金と朱の棘(天照)
        if "sun_disc" in deco:
            for i in range(20):
                a = i / 20 * 2 * math.pi
                out = Vector((0, math.cos(a), math.sin(a)))
                if out.y > 0.55:
                    continue  # 顔の前はあける
                rim = Vector((0, 0.92 * math.cos(a), 1.04 * math.sin(a)))
                L = 0.42 if i % 2 == 0 else 0.28
                col = GOLD if i % 2 == 0 else (1.0, 0.5, 0.2)
                g.add_sphere(tuple(rim + out * L * 0.5), (0.03, L * 0.5, 0.07), col, rot=frame(out, Vector((1, 0, 0))), taper=(0.95, 1.3), seg=10, rings=6)
            g.add_torus(Vector((0, 0, 0)), Vector((1, 0, 0)), 1.0, 0.03, GOLD, seg=48, sides=8)
        for s in (1, -1):  # 小さな胸びれ
            fin((s * 0.3, 0.12, -0.05), (0.03, 0.18, 0.12), frame(Vector((s * 0.7, -0.6, 0.1)), Vector((0, 0, 1))))
    elif shape == "hammer":
        for s in (1, -1):  # 金づちの両端の丸いふくらみ(目がここに付く)
            g.add_sphere((s * 1.2, 0.93, 0.07), (0.14, 0.2, 0.17), darken(c1, 0.04), seg=14, rings=8)
            g.add_disc(Vector((s * 1.33, 0.95, 0.08)), Vector((s, 0.25, 0.1)), 0.08, 0.09, WHITE, thick=0.02)
            g.add_disc(Vector((s * 1.345, 0.955, 0.08)), Vector((s, 0.25, 0.1)), 0.045, 0.06, INK, thick=0.02)
    elif shape == "dragon":
        # 背中の棘(先へいくほど小さい)と、尾の先の炎のような房
        for i, (x, y, z, r) in enumerate(DRAGON_SPINE[:-1]):
            p = sp((x, y, z + r * 0.95))
            dirv = Vector((0, -0.45, 1)).normalized()
            g.add_sphere(tuple(p + dirv * 0.09), (0.03, 0.06, 0.16 - i * 0.01), c3, rot=frame(dirv), taper=(0.95, 1.2), seg=10, rings=6)
        tip = Vector(sp(DRAGON_SPINE[-1][:3]))
        for k in range(5):
            dirv = Vector(((k - 2) * 0.22, -1, 0.3 + (k % 2) * 0.25)).normalized()
            fin(tuple(tip + dirv * 0.22), (0.035, 0.28, 0.12), frame(dirv), c3 if k % 2 else lighten(c3, 0.25), taper=(0.9, 1.2), rays=0)
        # 足の爪(3本ずつ)
        for (y, z) in ((0.78, 0.0), (-0.75, 0.1)):
            for sgn in (1, -1):
                dirv = Vector((sgn * 0.8, 0.25 if y > 0 else -0.2, -0.6)).normalized()
                foot = sp((sgn * 0.18, y, z - 0.08)) + dirv * 0.5
                for kk in range(3):
                    a = (kk - 1) * 0.5
                    toe = Vector((sgn * 0.5, math.cos(a) * 0.7, -0.5 + math.sin(a) * 0.2)).normalized()
                    g.add_sphere(tuple(foot + toe * 0.07), (0.025, 0.08, 0.025), GOLD, rot=frame(toe), taper=(0.9, 1.2), seg=8, rings=5)
        # 長い龍のひげ
        for sgn in (1, -1):
            p0 = Vector((sgn * 0.1, 1.98, 0.1))
            pts = [p0, p0 + Vector((sgn * 0.3, 0.1, 0.05)), p0 + Vector((sgn * 0.6, -0.15, -0.1)), p0 + Vector((sgn * 0.75, -0.55, -0.05))]
            g.add_tube([tuple(x) for x in pts], 0.018, GOLD, radius_end=0.008)
        # たてがみ(首のまわり)
        if "mane" in deco:
            for i in range(9):
                a = (i - 4) * 0.33
                p = Vector((math.sin(a) * 0.26, 1.15 - abs(i - 4) * 0.02, 0.32 + math.cos(a) * 0.18))
                dirv = Vector((math.sin(a) * 0.8, -0.7, math.cos(a) * 0.6)).normalized()
                g.add_sphere(tuple(p + dirv * 0.12), (0.04, 0.17, 0.08), c2, rot=frame(dirv), taper=(0.9, 1.2), seg=10, rings=6)
    elif shape == "hydra":
        # 主ではない7つの頭の目(光る)と小さな角
        for (hp_, k) in hydra_heads()[1:]:
            hp = Vector(hp_)
            base = Vector((hp.x * 0.35, 0.45, 0.3))
            mid = (base + hp) / 2 + Vector((hp.x * 0.1, -0.15, 0.3))
            fwd = (hp - mid).normalized()
            side = fwd.cross(Vector((0, 0, 1))).normalized()
            up = side.cross(fwd).normalized()
            for s in (1, -1):
                e = hp + fwd * 0.1 + side * s * 0.15 + up * 0.08
                g.add_sphere(tuple(e), (0.05, 0.05, 0.05), c3, seg=10, rings=6)
                g.add_sphere(tuple(e + (e - hp).normalized() * 0.03), (0.022, 0.022, 0.022), INK, seg=8, rings=5)
                hdir = (up * 0.9 - fwd * 0.4 + side * s * 0.3).normalized()
                g.add_sphere(tuple(hp + up * 0.15 + side * s * 0.1 + hdir * 0.08), (0.03, 0.12, 0.03), (0.96, 0.92, 0.82), rot=frame(hdir), taper=(0.95, 1.3), seg=8, rings=5)
        # 背中の棘
        for i in range(6):
            y = 0.3 - i * 0.28
            g.add_sphere((0, y, 0.48 - i * 0.03 + 0.08), (0.035, 0.08, 0.16 - i * 0.012), c3, rot=frame(Vector((0, -0.4, 1))), taper=(0.95, 1.2), seg=10, rings=6)
        for s in (1, -1):
            fin((s * 0.55, 0.0, -0.3), (0.035, 0.3, 0.16), frame(Vector((s * 0.8, -0.5, -0.4)), Vector((0, 1, 0))), darken(c1, 0.05), taper=(0.4, 1.1), rays=0)
    elif shape == "jelly":
        # 傘のふちのひだ
        for i in range(16):
            a = i / 16 * 2 * math.pi
            out = Vector((math.cos(a), math.sin(a), -0.35)).normalized()
            p = Vector((math.cos(a) * 0.78, math.sin(a) * 0.78, -0.02))
            g.add_sphere(tuple(p + out * 0.05), (0.13, 0.1, 0.04), lighten(c2, 0.2), rot=frame(out, Vector((0, 0, 1))), seg=10, rings=6)
        # 口腕(ひらひらの4本)
        for k in range(4):
            a = k / 4 * 2 * math.pi + 0.4
            for i in range(9):
                z = -0.05 - i * 0.14
                wob = math.sin(i * 0.8 + k) * 0.08
                p = (math.cos(a) * (0.15 + wob), math.sin(a) * (0.15 + wob), z)
                g.add_sphere(p, (0.14 - i * 0.008, 0.06, 0.08), mix(c2, WHITE, 0.25 + 0.05 * (i % 2)), rot=frame(Vector((math.cos(a), math.sin(a), 0)), Vector((0, 0, 1))), seg=10, rings=6)
        # 細い触手と、そこに咲く桜
        for k in range(12):
            a = k / 12 * 2 * math.pi
            r0 = 0.66
            pts = [(math.cos(a) * r0, math.sin(a) * r0, -0.05)]
            for i in range(1, 6):
                pts.append((math.cos(a) * (r0 + 0.05 * math.sin(i + k)), math.sin(a) * (r0 + 0.05 * math.cos(i + k)), -0.05 - i * 0.24))
            g.add_tube(pts, 0.022, lighten(c2, 0.35), radius_end=0.008)
            if k % 3 == 0:
                tip = Vector(pts[3])
                for pi_ in range(5):
                    pa = pi_ / 5 * 2 * math.pi
                    pd = Vector((math.cos(pa), math.sin(pa), 0))
                    g.add_sphere(tuple(tip + pd * 0.06), (0.05, 0.035, 0.012), PINK, rot=frame(pd, Vector((0, 0, 1))), seg=8, rings=5)
                g.add_sphere(tuple(tip), (0.025, 0.025, 0.025), GOLD, seg=8, rings=5)
        # 傘の上の桜の花
        for k in range(6):
            a = k / 6 * 2 * math.pi + 0.3
            c = Vector((math.cos(a) * 0.45, math.sin(a) * 0.45, 0.7))
            nrm = Vector((c.x / 0.74**2, c.y / 0.74**2, (c.z - 0.32) / 0.5**2)).normalized()
            cc = Vector((math.cos(a) * 0.45, math.sin(a) * 0.45, 0.32 + 0.5 * math.sqrt(max(0.0, 1 - (0.45 / 0.74) ** 2))))
            for pi_ in range(5):
                pa = pi_ / 5 * 2 * math.pi
                u = nrm.cross(Vector((0, 0, 1)) if abs(nrm.z) < 0.9 else Vector((1, 0, 0))).normalized()
                v = nrm.cross(u)
                pd = u * math.cos(pa) + v * math.sin(pa)
                g.add_sphere(tuple(cc + pd * 0.07 + nrm * 0.01), (0.06, 0.04, 0.012), PINK, rot=frame(pd, nrm), seg=8, rings=5)
    elif shape == "seahorse":
        # 頭の冠(とげ)、背びれ、胸びれ、狐の尾(3本のふさ)
        for i in range(5):
            a = (i - 2) * 0.35
            dirv = Vector((math.sin(a) * 0.5, -0.3, 1)).normalized()
            g.add_sphere((math.sin(a) * 0.1, 0.18, 1.22), (0.03, 0.05, 0.12), c3, rot=frame(dirv), taper=(0.95, 1.2), seg=8, rings=5)
        fin((0, -0.16, 0.05), (0.03, 0.2, 0.16), frame(Vector((0, -1, 0.1))), lighten(c2, 0.2), taper=(0.1, 1.0), rays=7)
        for s in (1, -1):
            fin((s * 0.2, 0.18, 0.82), (0.025, 0.12, 0.08), frame(Vector((s * 0.7, -0.6, 0)), Vector((0, 0, 1))), lighten(c2, 0.2))
        for k in range(max(1, d.get("tails") or 3)):
            a = (k - 1) * 0.45
            dirv = Vector((math.sin(a) * 0.6, -1, 0.55 + 0.15 * math.cos(a))).normalized()
            base = Vector((0, -0.08, 0.35))
            g.add_sphere(tuple(base + dirv * 0.42), (0.13, 0.48, 0.15), WHITE if k % 2 == 0 else lighten(c2, 0.3), rot=frame(dirv), taper=(0.7, 1.6))
            g.add_sphere(tuple(base + dirv * 0.82), (0.07, 0.16, 0.08), lighten(c3, 0.3), rot=frame(dirv), taper=(0.9, 1.4), seg=10, rings=6)
    elif shape == "phoenix":
        # 鳥のつばさのような胸びれ(3枚重ね、根元は体の色 → 先は金)
        for s in (1, -1):
            for k, (dy, dz, L) in enumerate(((-0.15, 0.55, 1.15), (-0.45, 0.25, 0.95), (-0.75, 0.0, 0.75))):
                dirv = Vector((s * 1.0, dy, dz)).normalized()
                base = Vector((s * 0.28, 0.35 - k * 0.12, 0.12))
                col = (c1, c3, c2)[k]
                fin(tuple(base + dirv * L * 0.5), (0.03, L * 0.55, 0.2 - k * 0.03), frame(dirv, Vector((0, 0, 1)) if abs(dirv.z) < 0.9 else Vector((0, 1, 0))), col, taper=(0.7, 1.4), rays=9)
        # 長い尾羽(真ん中の3本はとても長く、先に目玉の模様)
        base = Vector((0, -1.05, 0.02))
        for i in range(7):
            t = (i - 3) / 3
            dirv = Vector((t * 0.55, -1, 0.15 + 0.3 * (1 - abs(t)))).normalized()
            L = 1.5 - abs(t) * 0.7
            fin(tuple(base + dirv * L * 0.5), (0.03, L * 0.52, 0.09), frame(dirv), c2 if i % 2 else c3, taper=(0.4, 1.2), rays=0)
            tip = base + dirv * L * 0.98
            g.add_disc(tip, Vector((1, 0, 0)), 0.09, 0.11, GOLD, thick=0.03)
            g.add_disc(tip + Vector((0.016, 0, 0)), Vector((1, 0, 0)), 0.05, 0.06, (0.2, 0.35, 0.9), thick=0.02)
        # 背中の炎のようなひれ
        for i in range(3):
            dirv = Vector((0, -0.5, 1)).normalized()
            g.add_sphere((0, 0.1 - i * 0.3, 0.42 - i * 0.05), (0.035, 0.12, 0.22 - i * 0.04), lighten(c3, 0.15), rot=frame(dirv), taper=(0.95, 1.3))
    elif shape == "veil":
        veil = lighten(c2, 0.25)
        tipc = WHITE

        def wavy(x, y, z):
            k = 1 + 0.06 * math.sin(math.atan2(z, y + 1) * 9) * max(0.0, (y + 1) / 2)
            return x, -1 + (y + 1) * k, z * k

        # 体より大きく流れる尾(扇)
        base = Vector((0, -0.62, 0.0))
        for i in range(7):
            a = math.radians(-66 + i * 22)
            dirv = Vector((0, -math.cos(a), math.sin(a)))
            L = 1.15 - abs(a) * 0.15
            g.add_sphere(tuple(base + dirv * L * 0.55), (0.025, L * 0.58, 0.3), mix(veil, c3, 0.15 * (i % 2)), rot=frame(dirv, Vector((1, 0, 0))), taper=(0.1, 1.0), shape_fn=wavy, seg=20, rings=12)
            g.add_sphere(tuple(base + dirv * L * 1.05), (0.02, 0.06, 0.2), tipc, rot=frame(dirv, Vector((1, 0, 0))), seg=10, rings=6)
        # 背びれ・しりびれ(後ろへ長く流れる)
        for zs, L in ((1, 0.95), (-1, 1.05)):
            dirv = Vector((0, -0.7, zs * 0.7)).normalized()
            g.add_sphere(tuple(Vector((0, -0.1, zs * 0.36)) + dirv * L * 0.5), (0.025, L * 0.55, 0.28), veil, rot=frame(dirv, Vector((1, 0, 0))), taper=(0.1, 1.0), shape_fn=wavy, seg=20, rings=12)
        # 袖のような長い胸びれ
        for s in (1, -1):
            dirv = Vector((s * 0.55, -0.6, -0.6)).normalized()
            fin(tuple(Vector((s * 0.28, 0.2, -0.12)) + dirv * 0.4), (0.025, 0.46, 0.13), frame(dirv, Vector((0, 0, 1))), veil, taper=(0.3, 1.1), rays=5)
BIG = ("shark", "orca", "whale", "salamander", "sturgeon", "hammer")  # 大物の形(ひれは体の色、筋なし)

EEL_SPINE = [(0.0, 1.25, 0.02, 0.3), (0.05, 0.9, 0.0, 0.28), (0.08, 0.5, 0.0, 0.27), (0.04, 0.1, 0.0, 0.25), (-0.04, -0.3, 0.0, 0.22), (-0.08, -0.7, 0.0, 0.19), (-0.04, -1.1, 0.0, 0.15), (0.03, -1.45, 0.0, 0.11)]


def head_point(head, yaw_deg, pitch_deg):
    """頭の楕円体の表面の点と法線。yaw: 正面(+Y)から横への角度、pitch: 上向きの角度"""
    (cx, cy, cz), (rx, ry, rz) = head
    yaw, pitch = math.radians(yaw_deg), math.radians(pitch_deg)
    d = Vector((math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch)))
    p = Vector((d.x * rx, d.y * ry, d.z * rz))
    n = Vector((p.x / rx**2, p.y / ry**2, p.z / rz**2)).normalized()
    return Vector((cx, cy, cz)) + p, n


# ---------------------------------------------------------------------------
# 1匹を組み立てる


def build_fish(d, parts_only=False):
    """(体, 部品) を作る。parts_only なら体は作らず (None, 部品) を返す(軽い版の部品だけ作り直す時)"""
    rng = random.Random(d["id"])
    shape = SHAPES.get(d["shape"], SHAPES["koi"])
    deco = set(d.get("deco") or [])
    order = RARITY_ORDER[d["rarity"]]
    c1, c2 = hexc(d["c1"]), hexc(d["c2"])
    c3 = hexc(d["c3"]) if d.get("c3") else c2
    prop = d.get("body") or [1, 1, 1]
    S = Matrix.Diagonal((prop[0], prop[2], prop[1]))  # 幅=X, 長さ=Y, 高さ=Z

    def sp(v):
        return S @ Vector(v)

    head = (tuple(sp(shape["head"][0])), tuple(S @ Vector(shape["head"][1])))

    body_mesh = None
    if not parts_only:
        # --- 体(溶かして一体化) ---
        body = Geo()
        if d["shape"] in ("dragon", "seahorse"):
            special_body(d, body, sp, S, c1)
        elif d["shape"] == "eel":
            # 背骨の点を細かく補間して、つなぎ目の無い一本の体にする
            for k in range(len(EEL_SPINE) - 1):
                a0, a1 = EEL_SPINE[k], EEL_SPINE[k + 1]
                for j in range(5):
                    t = j / 5
                    x, y, z, r = (a0[i] + (a1[i] - a0[i]) * t for i in range(4))
                    body.add_sphere(sp((x, y, z)), tuple(S @ Vector((r, r * 1.1, r * 1.08))), c1, seg=20, rings=12)
            x, y, z, r = EEL_SPINE[-1]
            body.add_sphere(sp((x, y, z)), tuple(S @ Vector((r, r * 1.1, r * 1.08))), c1, seg=20, rings=12)
        else:
            for part in shape["parts"]:
                c, r = part[0], part[1]
                body.add_sphere(sp(c), tuple(S @ Vector(r)), c1, taper=part[2] if len(part) > 2 else None)
        if d["shape"] == "hydra":
            special_body(d, body, sp, S, c1)
        if "bighead" in deco:
            (hc, hr) = head
            body.add_sphere(Vector(hc) + Vector((0, -hr[1] * 0.25, hr[2] * 0.7)), (hr[0] * 0.95, hr[1] * 0.9, hr[2] * 0.85), c1)
        if d["shape"] == "angler":
            body.add_sphere(sp((0, 0.62, -0.26)), tuple(S @ Vector((0.56, 0.32, 0.24))), c1)  # 大きなあご
        if d["shape"] == "catfish":
            body.add_sphere(sp((0, 0.82, -0.12)), tuple(S @ Vector((0.42, 0.2, 0.2))), c1)  # 平たい口先
        if d["shape"] == "salmon":
            # 鉤のように上へ曲がった下あご(繁殖期の雄の鮭)
            body.add_sphere(sp((0, 1.18, -0.2)), tuple(S @ Vector((0.13, 0.2, 0.1))), c1, rot=frame(Vector((0, 0.7, 0.7))), taper=(0.6, 1.2))
        if d["shape"] == "salamander":
            # 4本の短い足(体と溶かして一体に)
            for s in (1, -1):
                for (y, z0, out) in ((0.42, -0.12, 0.62), (-0.48, -0.1, 0.5)):
                    dirv = Vector((s * 0.85, 0.15 if y > 0 else -0.25, -0.5)).normalized()
                    root = sp((s * out * 0.75, y, z0))
                    body.add_sphere(tuple(root + dirv * 0.16), (0.13, 0.22, 0.12), c1, rot=frame(dirv))

        body_obj = body.to_object(d["id"] + "_raw")
        size = max(prop) * 2.3
        rm = body_obj.modifiers.new("remesh", "REMESH")
        rm.mode = "VOXEL"
        rm.voxel_size = 0.028 * size / 2.3 / (1.1 * QUALITY)
        rm.use_smooth_shade = True
        sm = body_obj.modifiers.new("smooth", "SMOOTH")
        sm.factor = 1.0
        sm.iterations = int(14 * (1.1 * QUALITY) ** 2)
        body_mesh = evaluated_copy(body_obj, d["id"] + "_body")
        bpy.data.objects.remove(body_obj)

        # 表面の細部(鱗・えら・側線・いぼ・毛穴)を彫り、色の手がかりを作る
        feats = sculpt_body(body_mesh, d, head)
        # 体の色: 明るいお腹・少し濃い背中・模様・細部
        paint_body(body_mesh, d, head, c1, c2, c3, rng, S, feats)

    # --- 細かい部品(目・ひれ・飾り) ---
    g = Geo()
    fin_col = lighten(c3, 0.18)
    rim = GOLD if order >= 5 else darken(c3, 0.28)
    fin_scale = 1 + (order - 1) * 0.07
    big = d["shape"] in BIG
    big_fin = darken(c1, 0.05)  # 鮫・鯱のひれは体と同じ色(縁取りはレア度で付く)

    def fin(center, radii, rot, color=None, taper=(0.75, 1.4), rays=7):
        """ひれ: 根元から放射状に伸びる筋、根元→先のグラデーション、縁の色(レアほど太く、伝説以上は金)、
        先の筋の間のぎざぎざ。単位球の座標で、根元は y=-1"""
        r = tuple(x * fin_scale if i != 0 else x for i, x in enumerate(radii))
        base_col = color or fin_col
        root_col, tip_col, ray_col = darken(base_col, 0.14), lighten(base_col, 0.2), darken(base_col, 0.28)
        edge_w = 0.06 + 0.025 * order

        def cfn(x, y, z):
            t = (y + 1) / 2
            c = mix(root_col, tip_col, smoothstep(0.0, 0.9, t))
            phi = math.atan2(z, y + 1.0)
            if rays and abs(math.sin(phi * rays)) < 0.16 and t > 0.1:
                c = mix(c, ray_col, 0.3)  # 筋はうっすら(形の凹凸でも見える)
            rr = math.sqrt(y * y + z * z)
            if rr > 1 - edge_w and t > 0.22:
                c = rim if order >= 5 else mix(c, rim, 0.6 if order >= 3 else 0.35)
            return c

        def sfn(x, y, z):
            rr = math.sqrt(y * y + z * z)
            t = (y + 1) / 2
            if rays and rr > 0.55 and t > 0.3:
                phi = math.atan2(z, y + 1.0)
                k = 1 - 0.07 * (0.5 + 0.5 * math.cos(phi * rays * 2)) * min(1.0, (rr - 0.55) / 0.45)
                return x, -1 + (y + 1) * k, z * k
            return x, y, z

        g.add_sphere(center, r, base_col, rot=rot, taper=taper, seg=24, rings=16, color_fn=cfn, shape_fn=sfn)

    tailY = sp((0, shape["tailY"], 0)).y
    tails = d.get("tails") or 0
    tail_kind = shape["tail"]
    if tails >= 2 and tail_kind != "whip" and (d["shape"] not in NEW_SHAPES or d["shape"] == "hydra"):
        # 何本もの尾: ふわっと扇に広げる(九尾は9本)
        L = 0.62 if tails <= 4 else 0.7
        for i in range(tails):
            t = (i / (tails - 1)) * 2 - 1
            dirv = Vector((t * 0.5, -1, t * 0.85 + 0.15))
            col = c3 if i % 2 else fin_col
            base = Vector((0, tailY + 0.05, 0.02))
            fin(tuple(base + dirv.normalized() * L * 0.55), (0.05, L * 0.6, 0.2 if tails <= 4 else 0.16), frame(dirv, Vector((1, 0, 0))), col, taper=(0.6, 1.6))
    elif tail_kind == "forked":
        for s in (1, -1):
            fin((0, tailY - 0.2, s * 0.14), (0.05, 0.5, 0.24), frame(Vector((0, -1, s * 0.75))))
    elif tail_kind == "fan":
        fin((0, tailY - 0.12, 0), (0.05, 0.36, 0.34), frame(Vector((0, -1, 0))), taper=(0.0, 1))
    elif tail_kind == "crescent":
        # 鮫の尾: 上の葉が長く、下の葉が短い三日月
        base = Vector((0, tailY + 0.08, 0.02))
        upv, lov = Vector((0, -0.62, 0.78)).normalized(), Vector((0, -0.55, -0.72)).normalized()
        fin(tuple(base + upv * 0.3), (0.045, 0.36, 0.12), frame(upv), big_fin, taper=(0.85, 1.1), rays=0)
        fin(tuple(base + lov * 0.2), (0.045, 0.23, 0.1), frame(lov), big_fin, taper=(0.8, 1.1), rays=0)
    elif tail_kind == "flukes":
        # 鯱の尾: 横に広がる2枚(水平)
        base = Vector((0, tailY + 0.06, 0.0))
        k = 1.3 if d["shape"] == "whale" else 1.0  # 鯨の尾は大きい
        for s in (1, -1):
            dirv = Vector((s * 0.95, -0.5, 0.0)).normalized()
            fin(tuple(base + dirv * 0.27 * k), (0.04, 0.31 * k, 0.17 * k), frame(dirv, Vector((0, 1, 0))), big_fin, taper=(0.55, 1.3), rays=0)
    elif tail_kind == "paddle":
        # 山椒魚の尾の先: 縦に平たいひれ
        fin((0, tailY + 0.1, 0.04), (0.035, 0.3, 0.2), frame(Vector((0, -1, 0.1))), big_fin, taper=(0.3, 1.0), rays=0)
    elif tail_kind == "ribbon":
        fin((0, tailY - 0.05, 0), (0.04, 0.42, 0.2), frame(Vector((0, -1, 0))), taper=(0.6, 1))
    elif tail_kind == "whip":
        if "cloth" in deco:
            pts = [(math.sin(i * 0.9) * 0.12, tailY - i * 0.32, math.sin(i * 0.7) * 0.06) for i in range(9)]
            for i, p in enumerate(pts):
                g.add_sphere(p, (0.34 - i * 0.025, 0.2, 0.035), mix(c1, c2, i / 9), seg=16, rings=8)
        else:
            pts = [(0, tailY - i * 0.16, 0.02 + math.sin(i * 0.5) * 0.03) for i in range(9)]
            g.add_tube(pts, 0.05, c1, radius_end=0.015)
            g.add_sphere(pts[-1], (0.04, 0.14, 0.04), c3, taper=(0.9, 1))
    if "plumes" in deco:
        for i in range(5):
            t = (i - 2) / 2
            dirv = Vector((t * 0.6, -1, 0.25 + t * 0.2))
            L = 0.95 - abs(t) * 0.2
            base = Vector((0, tailY, 0.05))
            c = base + dirv.normalized() * L * 0.55
            fin(tuple(c), (0.04, L * 0.55, 0.11), frame(dirv), c2 if i % 2 == 0 else c3)
            tip = base + dirv.normalized() * L * 1.02
            g.add_disc(tip, Vector((1, 0, 0)), 0.08, 0.1, GOLD, thick=0.03)

    # 背びれ
    top_z = head[0][2] + head[1][2]
    if d["shape"] in NEW_SHAPES:
        pass  # 限定の形の背びれ・たてがみは special_details で付ける
    elif "mane" in deco:
        if d["shape"] == "eel":
            for i, (x, y, z, r) in enumerate(EEL_SPINE[:-1]):
                p = sp((x, y, z + r * 1.0))
                g.add_sphere(p + Vector((0, 0, 0.1)), (0.035, 0.12, 0.2 - i * 0.012), c3, rot=frame(Vector((0, -0.4, 1))), taper=(0.95, 1.2))
        else:
            for i in range(6):
                y = 0.6 - i * 0.28
                g.add_sphere(sp((0, y, top_z * 0.95 - i * 0.03)), (0.035, 0.12, 0.2), c3, rot=frame(Vector((0, -0.4, 1))), taper=(0.95, 1.2))
    elif shape["dorsal"] == "sail":
        fin(sp((0, -0.15, 0.4)), (0.04, 0.42, 0.2), frame(Vector((0, -0.55, 0.85))))
    elif shape["dorsal"] == "small":
        z = 0.32 if d["shape"] == "catfish" else 0.62
        fin(sp((0, -0.25 if d["shape"] == "catfish" else -0.1, z)), (0.04, 0.24, 0.16), frame(Vector((0, -0.6, 0.8))))
    elif shape["dorsal"] == "ribbon":
        for i, (x, y, z, r) in enumerate(EEL_SPINE[1:]):
            g.add_sphere(sp((x, y, z + r * 0.95)), (0.025, 0.22, 0.09), fin_col, seg=16, rings=8)
    elif shape["dorsal"] == "shark":
        dirv = Vector((0, -0.42, 0.9)).normalized()
        fin(tuple(sp((0, 0.02, 0.36)) + dirv * 0.32), (0.05, 0.36, 0.22), frame(dirv), big_fin, taper=(0.9, 1.0), rays=0)
        # 尾の近くの小さな第2背びれと、しりびれ
        fin(sp((0, -0.98, 0.21)), (0.03, 0.1, 0.07), frame(Vector((0, -0.6, 1))), big_fin, taper=(0.9, 1.0), rays=0)
        fin(sp((0, -0.95, -0.2)), (0.03, 0.09, 0.06), frame(Vector((0, -0.6, -1))), big_fin, taper=(0.9, 1.0), rays=0)
    elif shape["dorsal"] == "orca":
        dirv = Vector((0, -0.16, 1)).normalized()
        fin(tuple(sp((0, -0.05, 0.42)) + dirv * 0.4), (0.06, 0.44, 0.2), frame(dirv), big_fin, taper=(0.88, 1.25), rays=0)
    elif shape["dorsal"] == "salmon":
        fin(sp((0, -0.1, 0.62)), (0.04, 0.3, 0.2), frame(Vector((0, -0.5, 0.85))))
        # 脂びれ(尾の近くの小さな丸いひれ)
        fin(sp((0, -0.92, 0.3)), (0.03, 0.08, 0.06), frame(Vector((0, -0.4, 1))), taper=(0.2, 1.0), rays=0)
    elif shape["dorsal"] == "sturgeon":
        # 後ろの小さな背びれと、しりびれ
        fin(sp((0, -0.8, 0.26)), (0.03, 0.15, 0.09), frame(Vector((0, -0.55, 0.85))), big_fin, taper=(0.8, 1.0), rays=0)
        fin(sp((0, -0.82, -0.22)), (0.03, 0.12, 0.07), frame(Vector((0, -0.55, -0.85))), big_fin, taper=(0.8, 1.0), rays=0)
        # 骨の板(背に1列、横に2列)。体の太さに合わせて少し埋める
        keys = [(0.6, 0.34, 0.28), (0.25, 0.4, 0.34), (-0.05, 0.42, 0.36), (-0.6, 0.26, 0.25), (-0.95, 0.15, 0.15)]

        def wh(y):
            for (y0, w0, h0), (y1, w1, h1) in zip(keys, keys[1:]):
                if y1 <= y <= y0:
                    t = (y0 - y) / (y0 - y1)
                    return w0 + (w1 - w0) * t, h0 + (h1 - h0) * t
            return keys[-1][1], keys[-1][2]

        plate = lighten(c2, 0.1)
        for k in range(12):
            y = 0.5 - k * 0.12
            w, h = wh(y)
            for pos, out in ((Vector((0, y, h * 0.94)), Vector((0, 0, 1))), (Vector((w * 0.94, y, 0)), Vector((1, 0, 0.15))), (Vector((-w * 0.94, y, 0)), Vector((-1, 0, 0.15)))):
                g.add_sphere(tuple(S @ pos), (0.035, 0.055, 0.035), plate, rot=frame(out), taper=(0.9, 1.0), seg=8, rings=5)
    elif shape["dorsal"] == "hump":
        # 鯨: 背の小さなこぶのようなひれ
        fin(sp((0, -0.62, 0.42)), (0.05, 0.14, 0.12), frame(Vector((0, -0.6, 0.8))), big_fin, taper=(0.7, 1.2), rays=0)
    elif shape["dorsal"] == "ridge":
        # 山椒魚: 尾の上と下に、低く長いひれ
        for zs in (1, -1):
            for i in range(5):
                y = -0.85 - i * 0.18
                fin(sp((0, y, zs * (0.2 - i * 0.02))), (0.025, 0.12, 0.06 - i * 0.004), frame(Vector((0, -1, zs * 0.25))), big_fin, taper=(0.1, 1.0), rays=0)
    elif shape["dorsal"] == "spines":
        for i in range(3):
            g.add_sphere(sp((0, -0.05 - i * 0.22, 0.6 - i * 0.05)), (0.035, 0.1, 0.2 - i * 0.03), c3, rot=frame(Vector((0, -0.3, 1))), taper=(0.95, 1.2))
    if order >= 4 and shape["dorsal"] not in ("none", "orca", "hump", "ridge", "sturgeon") and "mane" not in deco and d["shape"] not in NEW_SHAPES:
        fin(sp((0, -0.55, 0.3)), (0.03, 0.34, 0.12), frame(Vector((0, -0.85, 0.45))), c3)

    # 胸びれ
    if big:
        hc, hr = head
        frills = "frills" in deco
        for s in (1, -1):
            if d["shape"] in ("shark", "sturgeon", "hammer"):
                # 鮫: 長く、横へ翼のように張り出す(蝶鮫も)
                base = Vector((s * hr[0] * 0.75, hc[1] - hr[1] * 0.75, hc[2] - hr[2] * 0.55))
                dirv = Vector((s * 0.85, -0.55, -0.32)).normalized()
                L = 0.66 if frills else 0.52
                fin(tuple(base + dirv * L * 0.5), (0.035, L * 0.55, 0.17), frame(dirv, Vector((0, 1, 0))), c3 if frills else big_fin, taper=(0.85, 1.1), rays=0)
                # 腹びれ
                fin(sp((s * 0.17, -0.5, -0.3)), (0.025, 0.12, 0.07), frame(Vector((s * 0.4, -0.8, -0.5)), Vector((0, 1, 0))), big_fin, taper=(0.85, 1.1), rays=0)
            elif d["shape"] == "whale":
                # 鯨: とても長い胸びれ(ざとう鯨のように)
                base = Vector((s * hr[0] * 0.85, hc[1] - hr[1] * 0.9, hc[2] - hr[2] * 0.55))
                dirv = Vector((s * 0.8, -0.5, -0.4)).normalized()
                L = 0.95 if frills else 0.8
                fin(tuple(base + dirv * L * 0.5), (0.04, L * 0.55, 0.14), frame(dirv, Vector((0, 1, 0))), c3 if frills else big_fin, taper=(0.55, 1.2), rays=0)
            elif d["shape"] == "salamander":
                # 足の先の指(4本)
                for (y, z0, out) in ((0.42, -0.12, 0.62), (-0.48, -0.1, 0.5)):
                    dirv = Vector((s * 0.85, 0.15 if y > 0 else -0.25, -0.5)).normalized()
                    foot = sp((s * out * 0.75, y, z0)) + dirv * 0.34
                    for k in range(4):
                        a = (k - 1.5) * 0.35
                        toe = Vector((s * math.cos(a) * 0.6, math.sin(a) * 0.8 + (0.1 if y > 0 else -0.1), -0.2)).normalized()
                        g.add_sphere(tuple(foot + toe * 0.06), (0.03, 0.06, 0.025), darken(c1, 0.08), rot=frame(toe), taper=(0.5, 1.0))
            else:
                # 鯱: 丸いうちわ形
                base = Vector((s * hr[0] * 0.8, hc[1] - hr[1] * 0.7, hc[2] - hr[2] * 0.6))
                dirv = Vector((s * 0.7, -0.45, -0.6)).normalized()
                L = 0.62 if frills else 0.46
                fin(tuple(base + dirv * L * 0.5), (0.035, L * 0.55, 0.18), frame(dirv, Vector((0, 1, 0))), c3 if frills else big_fin, taper=(0.3, 1.0), rays=0)
    elif d["shape"] not in ("ray",) + NEW_SHAPES:
        frills = "frills" in deco
        for s in (1, -1):
            if d["shape"] == "eel":
                base = sp((s * 0.3, 0.95, -0.08))
            else:
                hc, hr = head
                base = Vector((s * hr[0] * 0.8, hc[1] - hr[1] * 0.35, hc[2] - hr[2] * 0.35))
            L = 0.55 if frills else 0.28
            dirv = Vector((s * 0.8, -0.7, -0.35))
            fin(tuple(base + dirv.normalized() * L * 0.5), (0.03, L * 0.55, 0.16 if frills else 0.13), frame(dirv, Vector((0, 0, 1))), c3 if frills else None)

    # 河豚のトゲ
    if d["shape"] == "puffer" and "smooth" not in deco:
        (hc, hr) = head
        for i in range(18):
            yaw = (i % 9) * 40 - 160
            pitch = 25 if i < 9 else -15
            p, n = head_point(head, yaw + 180 if False else yaw, pitch)
            if p.y > hc[1] + hr[1] * 0.75:
                continue
            g.add_sphere(tuple(p + n * 0.05), (0.035, 0.13, 0.035), lighten(c2, 0.25), rot=frame(n), taper=(0.95, 1.1))

    if d["shape"] in NEW_SHAPES:
        special_details(d, g, fin, sp, S, head, c1, c2, c3, fin_col, order, deco)
    add_face(g, d, head, deco, c1, c2, c3, order)
    add_decos(g, d, head, deco, c1, c2, c3, order, S, tailY)

    # レア度の飾り
    hc, hr = head
    if order >= 5 and not ({"coin", "okappa"} & deco):
        p, n = head_point(head, 0, 38)
        g.add_disc(p + n * 0.01, n, 0.1, 0.1, GOLD, up=Vector((0, 0, 1)) - n * n.z if abs(n.z) < 0.95 else Vector((0, 1, 0)), thick=0.02)
    if order >= 6 and d["shape"] not in NEW_SHAPES:  # 限定の形は形そのものが特別(後光はゲームの中で付く)
        ring_c = Vector((0, hc[1] - hr[1] * 0.6, hc[2] + hr[2] * 1.05))
        R = max(hr[0], hr[2]) * 1.35
        g.add_torus(ring_c, Vector((0, 1, 0)), R, 0.035, lighten(c3, 0.5))
        if order >= 7:
            g.add_torus(ring_c, Vector((0, 1, 0)), R * 0.75, 0.025, GOLD)
            for i in range(3):
                a = i / 3 * 2 * math.pi + 0.4
                g.add_sphere((math.cos(a) * 1.1, math.sin(a) * 0.8 - 0.1, 0.55 + 0.25 * math.sin(a * 2)), (0.11, 0.11, 0.15), lighten(c3, 0.35), taper=(0.7, 1.5), rot=frame(Vector((0, 0.001, 1))))

    detail = g.to_object(d["id"] + "_detail")
    return body_mesh, detail


# ---------------------------------------------------------------------------
# 体の表面の細部


def sculpt_body(obj, d, head):
    """細かい体に、鱗・えらの線・側線・いぼ・毛穴を彫る。
    凹凸は軽いモデルの法線マップに焼き込まれ、色の手がかり(戻り値)は塗りに使う"""
    mesh = obj.data
    shape = d["shape"]
    (hcx, hcy, hcz), (hrx, hry, hrz) = head
    zs = [v.co.z for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zmin, zmax, ymin, ymax = min(zs), max(zs), min(ys), max(ys)
    seed = Vector((sum(map(ord, d["id"])) * 0.37, 1.3, 2.9))
    feats = {}
    sy, ss = 0.11, 0.115  # 鱗の大きさ(長さ方向・周方向)
    for v in mesh.vertices:
        p = v.co
        nrm = v.normal.copy()
        h = (p.z - zmin) / max(1e-4, zmax - zmin)
        t = (p.y - ymin) / max(1e-4, ymax - ymin)
        disp = 0.0
        scale_edge = gill = lateral = spot = speck = 0.0
        # えらの線: 頭と胴の境目。横から見て「)」の形の細い弧(えらぶた)で、真ん中ほど尾の側へふくらむ
        zz = (p.z - hcz) / (hrz * 0.72)
        gy = hcy - hry * (0.62 if shape != "puffer" else 0.75) + hry * 0.32 * min(1.0, zz * zz)
        if shape in ("koi", "catfish", "angler", "puffer", "salmon"):
            if abs(zz) < 1.0 and abs(p.x) > hrx * 0.35:
                gill = (1 - smoothstep(0.006, 0.02, abs(p.y - gy))) * (1 - smoothstep(0.75, 1.0, abs(zz)))
                disp -= 0.01 * gill
        # 鮫のえら: 頭の後ろに5本の切れ目(少し斜め)
        if shape == "shark" and abs(p.x) > hrx * 0.45 and abs(zz) < 0.85:
            for i in range(5):
                gyi = hcy - hry * 0.55 - i * 0.07 + 0.04 * zz
                gill = max(gill, (1 - smoothstep(0.005, 0.014, abs(p.y - gyi))) * (1 - smoothstep(0.6, 0.85, abs(zz))))
            disp -= 0.012 * gill
        # 鱗(鯉型)。えらぶたより後ろだけ
        if shape in ("koi", "salmon"):
            fade = smoothstep(0.28, 0.42, h) * smoothstep(0.1, 0.22, t) * (1 - smoothstep(gy - 0.09, gy - 0.04, p.y))
            if fade > 0:
                theta = math.atan2(p.z, p.x)
                a, b = p.y / sy, theta * 0.42 / ss
                row = math.floor(a)
                best, bdy = 9.0, 0.0
                for rr in (row - 1, row, row + 1):
                    off = 0.5 * (rr % 2)
                    cb = math.floor(b - off)
                    for cc in (cb - 1, cb, cb + 1):
                        dy, db = a - (rr + 0.5), b - (cc + 0.5 + off)
                        dist = math.sqrt(dy * dy + db * db)
                        if dist < best:
                            best, bdy = dist, dy
                # 尾の側の縁だけを弧として描く(重なった鱗に見える)
                scale_edge = smoothstep(0.36, 0.48, best) * (1.0 if bdy < 0.08 else 0.0) * fade
                disp += 0.006 * fade * smoothstep(0.0, 0.5, best) - 0.005 * scale_edge
        # 側線(点線)
        if shape in ("koi", "catfish", "eel", "salmon") and 0.15 < t < 0.78:
            mid = 0.52 if shape != "eel" else 0.6
            if abs(h - mid) < 0.022 and (p.y / 0.07) % 1.0 < 0.45:
                lateral = 1.0
                disp -= 0.003
        n3 = mnoise.noise(p * 7.0 + seed)
        if shape == "whale" and h < 0.3 and t > 0.55:
            # のどの畝(縦の溝)
            groove = 1 - smoothstep(0.0, 0.35, abs(math.sin(p.x * 34)))
            gill = max(gill, groove * 0.6 * smoothstep(0.55, 0.7, t))
            disp -= 0.006 * groove
        if shape == "salamander":
            # 横腹のしわと、体じゅうのいぼ
            fold = (1 - smoothstep(0.0, 0.25, abs(math.sin(p.y * 22)))) * smoothstep(0.3, 0.45, h) * (1 - smoothstep(0.55, 0.7, h))
            disp -= 0.006 * fold
            if n3 > 0.3:
                spot = smoothstep(0.3, 0.55, n3) * 0.8
                disp += 0.01 * spot
        if shape == "angler" and n3 > 0.38:
            spot = smoothstep(0.38, 0.6, n3)  # いぼ
            disp += 0.012 * spot
        elif shape == "puffer" and mnoise.noise(p * 16.0 + seed) > 0.45 and h > 0.3:
            spot = 1.0  # 毛穴
            disp -= 0.004
        elif shape == "ray" and nrm.z > 0.4 and mnoise.noise(p * 11.0 + seed) > 0.42:
            speck = 1.0  # 背中の点々
        elif shape in ("catfish", "eel"):
            spot = smoothstep(0.25, 0.55, n3) * 0.6  # ぬめった肌のまだら
        # 細かい凹凸(質感)。鮫はざらざらの肌、鯱はつるつる
        if shape in ("shark", "sturgeon"):
            disp += 0.0012 * mnoise.noise(p * 90.0 + seed)
        if shape not in ("orca", "whale"):
            disp += 0.0015 * mnoise.noise(p * 40.0 + seed)
        v.co = p + nrm * disp
        if scale_edge or gill or lateral or spot or speck:
            feats[v.index] = (scale_edge, gill, lateral, spot, speck)
    mesh.update()
    return feats


# ---------------------------------------------------------------------------
# 体の塗り


def paint_body(obj, d, head, c1, c2, c3, rng, S, feats=None):
    mesh = obj.data
    if "Col" in mesh.color_attributes:
        mesh.color_attributes.remove(mesh.color_attributes["Col"])
    mesh.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    col = mesh.color_attributes["Col"]
    pat = d.get("pattern")
    zs = [v.co.z for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zmin, zmax = min(zs), max(zs)
    ymin, ymax = min(ys), max(ys)
    spots = []
    if pat in ("spots", "patches"):
        n = 4 if pat == "patches" else 9
        verts = [v.co.copy() for v in mesh.vertices if v.co.z > (zmin + zmax) / 2 - 0.05]
        for _ in range(n):
            spots.append(rng.choice(verts))
    belly_c = c2 if pat in ("belly", "orca") else lighten(c1, 0.45)
    (hcx, hcy, hcz), (hrx, hry, hrz) = head
    for poly in mesh.polygons:
        for li in poly.loop_indices:
            v = mesh.vertices[mesh.loops[li].vertex_index].co
            h = (v.z - zmin) / max(1e-4, zmax - zmin)
            t = (v.y - ymin) / max(1e-4, ymax - ymin)  # 0 尾 .. 1 頭
            c = c1
            # 模様
            if pat == "stripes":
                band = math.sin(t * 7 * math.pi)
                if band > 0.55 and t < 0.8 and h > 0.15:
                    c = c2
            elif pat == "ribs":
                band = math.sin(t * 11 * math.pi)
                if (band > 0.75 and t < 0.75 and h > 0.2) or (h > 0.9 and t < 0.85):
                    c = c2
            elif pat in ("spots", "patches"):
                r = 0.32 if pat == "patches" else 0.11
                for s in spots:
                    if (v - s).length < r:
                        c = c2
                        break
            elif pat == "saddle":
                if h > 0.55 and 0.3 < t < 0.7:
                    c = c2
            elif pat == "gradient":
                c = mix(c1, c2, smoothstep(0.65, 0.25, t))
            elif pat == "dango":
                k = int(t * 3.0)
                c = [c3, lighten(c1, 0.3), c2][min(2, k)]
            elif pat == "orca":
                # 鯱: 白いお腹とあご、横腹へ跳ね上がる白、目の後ろの白い楕円、背びれの後ろの灰色の鞍
                flank = 0.36 + 0.26 * smoothstep(0.26, 0.36, t) * (1 - smoothstep(0.42, 0.52, t))
                if (h < flank and t > 0.12) or (h < 0.46 and t > 0.86):
                    c = c2
                ey, ez = hcy - hry * 0.3, hcz + hrz * 0.4
                if abs(v.x) > hrx * 0.35 and ((v.y - ey) / 0.21) ** 2 + ((v.z - ez) / 0.1) ** 2 < 1:
                    c = c2
                if h > 0.84 and 0.36 < t < 0.5:
                    c = mix(c1, c2, 0.4)
            # 細部の色(鱗の弧・えらの線・側線・いぼ・点々)
            f = feats.get(mesh.loops[li].vertex_index) if feats else None
            if f:
                scale_edge, gill, lateral, spot, speck = f
                # 色はひかえめに(形の凹凸は法線マップと光で見せる)
                if scale_edge:
                    c = mix(c, darken(c, 0.16), scale_edge * 0.6)
                if spot:
                    c = mix(c, darken(c, 0.15), spot * 0.6)
                if speck:
                    c = mix(c, lighten(c, 0.45), 0.7)
                if lateral:
                    c = mix(c, darken(c, 0.2), 0.6)
            # お腹は明るく、背中は少し濃く(アニメの塗り)
            if pat not in ("dango",):
                c = mix(c, belly_c, smoothstep(0.42, 0.22, h))
            c = mix(c, darken(c, 0.1), smoothstep(0.8, 0.98, h))
            # 影は描き込まない(ゲームの光で立体に見せる)。光の当たらない下側だけ、ほんのり暗くする
            nrm = mesh.loops[li].normal if hasattr(mesh.loops[li], "normal") else poly.normal
            k = smoothstep(-0.8, 0.2, nrm.dot(LIGHT))
            c = mix((c[0] * 0.92, c[1] * 0.92, c[2] * 0.95), c, k)
            if f and f[1]:
                c = mix(c, darken(c, 0.3), f[1] * 0.8)  # えらの線
            lc = to_linear(c)
            col.data[li].color = (lc[0], lc[1], lc[2], 1.0)


# ---------------------------------------------------------------------------
# 顔


def eye_frame(n):
    up = Vector((0, 0, 1))
    up = (up - n * up.dot(n)).normalized()
    return up


def add_eye(g, center, n, w, h, style, iris, order, glow=False, curve=0.0):
    """立体のフィギュアのような目。w, h は白目の幅と高さ。
    白目(上にわずかな影) → 虹彩(なめらかなグラデーションと淡い縁) → 瞳 → 光1つ → 細い上まぶたの線"""
    up = eye_frame(n)
    side = up.cross(n).normalized()
    # 目尻(後ろ側)の向き: 頭の前(+Y)と反対の横方向
    outer = 1.0 if side.dot(Vector((0, -1, 0))) > 0 else -1.0
    lw = 0.022 * (h / 0.2)  # 線の太さの基準

    def at(du, dv, dn):
        # 頭の丸みに沿って、目の中心から離れるほど沈める。
        # 全体を少し頭に埋める(横から見て目が飛び出しにくい)。重ねる間隔は変えない(輪郭線がきれいに出る間隔)
        dn = dn - 0.008
        return center + side * du + up * dv + n * (dn - curve * (du * du + dv * dv) * 0.5)

    def disc(c, rx, ry, color, **kw):
        g.add_disc(c, n, rx, ry, color, curve=curve, **kw)

    def decal(c, rx, ry, color, **kw):
        # 白目の上に重ねる薄い模様。軽い版では省く(色は焼き込まれる)
        if LOD["decals"]:
            disc(c, rx, ry, color, **kw)

    # まぶたの線の色: 真っ黒ではなく、肌の色を濃くした色(描いた線より、立体の縁に見える)
    lid = mix(INK, darken(g_skin[0] or INK, 0.55), 0.35)

    if style == "dot":
        disc(at(0, 0, 0.01), w * 0.42, h * 0.5, INK, up=up, thick=0.02, seg=24)
        decal(at(-w * 0.1, h * 0.18, 0.025), w * 0.11, w * 0.11, WHITE, up=up, thick=0.01)
        return

    # 白目: 上に向かってわずかに影。光る目(神話・秘伝)は白目を暗くして、虹彩が光って見えるようにする
    sclera = (1.0, 0.86, 0.32) if style == "cat" else WHITE
    shade = mix(sclera, (0.78, 0.8, 0.9), 0.4)
    if glow:
        sclera = mix(INK, darken(g_skin[0] or INK, 0.5), 0.45)
        shade = darken(sclera, 0.3)
        if sum(iris) / 3 > 0.8:  # 白っぽい虹彩は光って見えないので金色に寄せる
            iris = mix(iris, (1.0, 0.8, 0.3), 0.6)
    disc(at(0, 0, 0.0), w, h, sclera, up=up, thick=0.02, seg=32, color_fn=lambda u, v: mix(sclera, shade, smoothstep(0.35, 1.0, v)))

    if style == "cat":
        decal(at(0, 0, 0.016), w * 0.78, h * 0.86, sclera, up=up, thick=0.012, seg=32, color_fn=lambda u, v: mix((1.0, 0.92, 0.45), (0.95, 0.62, 0.12), smoothstep(-0.8, 0.8, v)))
        decal(at(0, 0, 0.024), w * 0.16, h * 0.8, INK, up=up, thick=0.012, seg=24)
    else:
        dark, light = darken(iris, 0.4), lighten(iris, 0.22)

        def iris_fn(u, v):
            # 上が少し濃く下が少し明るい、なめらかな虹彩と、細く淡い縁(筋や模様は入れない)
            r = math.sqrt(u * u + v * v)
            c = mix(light, iris, smoothstep(-0.9, 0.1, v))
            c = mix(c, dark, smoothstep(0.2, 1.0, v) * 0.55)
            if r > 0.9:
                c = mix(c, darken(iris, 0.45), 0.5)
            return c

        decal(at(0, -h * 0.04, 0.012), w * 0.76, h * 0.82, iris, up=up, thick=0.014, seg=40, color_fn=iris_fn)
        pupil = mix(INK, darken(iris, 0.7), 0.25) if not glow else lighten(iris, 0.65)
        decal(at(0, -h * 0.02, 0.022), w * 0.36, h * 0.44, pupil, up=up, thick=0.012, seg=28)
    if not glow:
        # 光は1つだけ(ひかえめな楕円)
        decal(at(-w * 0.22 * outer, h * 0.26, 0.034), w * 0.14, w * 0.18, WHITE, up=up, thick=0.012, seg=24)
    # 上まぶたの線: 細めで、目尻に向かって少し細くなる(跳ね・下まつげ・二重の線は描かない)
    # 白目は縁が頭に埋まるので、見えている白目の縁(半径の約 92%)に沿わせる
    pts = [at(math.cos(math.radians(a)) * w * 0.93 * outer * -1, math.sin(math.radians(a)) * h * 0.92, 0.016) for a in range(168, 8, -16)]
    g.add_tube(pts, lw * 0.6, lid, radius_end=lw * 0.4)
    if style == "sleepy":
        disc(at(0, h * 0.42, 0.04), w * 1.12, h * 0.6, g_skin[0], up=up, thick=0.03, seg=28)
        g.add_tube([at(-w, h * 0.0, 0.05), at(0, -h * 0.08, 0.055), at(w, h * 0.0, 0.05)], lw * 0.6, lid)
    if style == "angry":
        g.add_tube([at(-w * 0.9 * outer, h * 1.5, 0.03), at(0, h * 1.38, 0.03), at(w * 0.9 * outer, h * 1.15, 0.03)], lw * 0.9, lid, radius_end=lw * 0.5)


g_skin = [None]


def add_face(g, d, head, deco, c1, c2, c3, order):
    eyes = d.get("eyes") or ("none" if "noface" in deco else ("big" if "big_eye" in deco else "normal"))
    mouth = d.get("mouth") or {"koi": "small", "catfish": "wide", "puffer": "o", "eel": "small", "angler": "grin", "ray": "none", "shark": "jaws", "orca": "smile", "salmon": "fangs", "salamander": "wide", "whale": "smile", "sturgeon": "wide"}.get(d["shape"], "small")
    g_skin[0] = c1
    if d["shape"] == "hammer":
        eyes = "none"  # 撞木鮫の目は金づちの両端(special_details)
    iris = c3 if d.get("c3") else c2
    # 虹彩の色が体と近すぎるときは補色寄りに
    if sum(abs(iris[i] - c1[i]) for i in range(3)) < 0.35:
        iris = mix(iris, (0.25, 0.45, 0.9), 0.6)
    glow = eyes == "glow" or order >= 6
    hc, hr = head
    scale_eye = min(hr[0], hr[2])
    curve = 0.95 / ((hr[0] + hr[1] + hr[2]) / 3)  # 目を頭の丸みに沿わせる
    if d["shape"] == "ray":
        yaw_side, pitch = 30, 32
    elif d["shape"] == "eel":
        yaw_side, pitch = 40, 18
    elif d["shape"] == "puffer":
        yaw_side, pitch = 34, 12
    elif d["shape"] == "shark":
        yaw_side, pitch = 50, 14
    elif d["shape"] == "orca":
        yaw_side, pitch = 52, 6
    elif d["shape"] == "salmon":
        yaw_side, pitch = 44, 12
    elif d["shape"] == "salamander":
        yaw_side, pitch = 36, 48  # 小さな目が頭の上に
    elif d["shape"] == "whale":
        yaw_side, pitch = 64, -10  # 口の端の近く、低いところ
    elif d["shape"] == "sturgeon":
        yaw_side, pitch = 40, 22
    elif d["shape"] == "hammer":
        yaw_side, pitch = 30, 20  # 金づちの前の上(両端の目は special_details で付ける)
    elif d["shape"] == "mola":
        yaw_side, pitch = 46, 18
    elif d["shape"] == "jelly":
        yaw_side, pitch = 22, 4  # 傘の前
    elif d["shape"] == "dragon":
        yaw_side, pitch = 40, 26
    else:
        yaw_side, pitch = 33, 14
    if eyes == "big":
        p, n = head_point(head, 0, 22 if d["shape"] != "ray" else 35)
        add_eye(g, p, n, scale_eye * 0.55, scale_eye * 0.62, "normal", iris, order, glow, curve)
    elif eyes != "none":
        w = scale_eye * (0.33 if eyes == "cute" else 0.27)
        h = w * 1.25
        for s in (1, -1):
            p, n = head_point(head, s * yaw_side, pitch)
            add_eye(g, p, n, w, h, eyes, iris, order, glow, curve)
    if "third_eye" in deco:
        p, n = head_point(head, 0, 52)
        add_eye(g, p, n, scale_eye * 0.16, scale_eye * 0.22, "normal", iris, order, glow, curve)
    if "blush" in deco or eyes == "cute":
        for s in (1, -1):
            p, n = head_point(head, s * (yaw_side + 6), pitch - 22)
            g.add_disc(p + n * 0.005, n, scale_eye * 0.16, scale_eye * 0.09, PINK, thick=0.012, curve=curve)
    # 口
    p, n = head_point(head, 0, {"ray": 10, "shark": -20, "orca": -14, "salamander": -12, "whale": -26, "sturgeon": -34}.get(d["shape"], -12))
    side = Vector((1, 0, 0))
    up = eye_frame(n)
    w = scale_eye * 0.22
    lip = darken(c1, 0.75)

    def m(du, dv, dn=0.015):
        return p + side * du + up * dv + n * dn

    if mouth in ("small", "smile", "frown", "wide", "fangs", "geta"):
        width = w * {"orca": 1.9, "whale": 3.0, "salamander": 4.0}.get(d["shape"], 2.2 if mouth == "wide" else 1.0)
        if mouth == "wide" and d["shape"] != "salamander":
            width = w * 2.2
        bend = {"smile": 1, "frown": -1}.get(mouth, 0.35)
        pts = [m(width * (i / 6 * 2 - 1), -bend * w * 0.35 * (1 - (i / 6 * 2 - 1) ** 2)) for i in range(7)]
        g.add_tube(pts, 0.018 * (scale_eye / 0.45), lip)
        if mouth == "fangs":
            for s in (1, -1):
                g.add_sphere(tuple(m(s * width * 0.45, -w * 0.12, 0.02)), (0.025, 0.025, 0.06), WHITE, rot=frame(Vector((0, 0, -1))), taper=(0.95, 1))
        if mouth == "geta":
            for s in (1, -1):
                g.add_disc(m(s * w * 0.18, -w * 0.25, 0.02), n, w * 0.16, w * 0.2, WHITE, thick=0.02)
    elif mouth in ("o", "open", "tongue"):
        g.add_disc(m(0, -w * 0.1, 0.005), n, w * 0.45, w * 0.5 if mouth != "o" else w * 0.42, lip, thick=0.02)
        g.add_disc(m(0, -w * 0.3, 0.02), n, w * 0.3, w * 0.18, (0.95, 0.42, 0.45), thick=0.012)
        if mouth == "tongue":
            base = m(0, -w * 0.4, 0.04)
            g.add_sphere(tuple(base + n * 0.12 + Vector((0, 0, -0.12))), (0.09, 0.22, 0.035), RED, rot=frame(n * 0.6 + Vector((0, 0, -1))), taper=(0.3, 1))
    elif mouth == "grin":
        g.add_disc(m(0, -w * 0.1, 0.005), n, w * 1.6, w * 0.55, lip, thick=0.02)
        for i in range(6):
            x = (i / 5 * 2 - 1) * w * 1.25
            g.add_sphere(tuple(m(x, w * 0.25, 0.025)), (0.03, 0.03, 0.07), WHITE, rot=frame(Vector((0, 0, -1))), taper=(0.95, 1))
    elif mouth == "jaws":
        # 鮫の口: 横に広い、にやりとした口と、とがった歯の列
        width = w * 3.0
        lw = 0.022 * (scale_eye / 0.45)

        def jaw(u):
            return m(width * u, w * 0.45 * u * u - w * 0.1)

        g.add_tube([jaw(i / 8 * 2 - 1) for i in range(9)], lw, lip)
        for i in range(7):
            u = (i / 6 * 2 - 1) * 0.78
            g.add_sphere(tuple(jaw(u) - up * w * 0.14 + n * 0.012), (0.026, 0.065, 0.026), WHITE, rot=frame(-up), taper=(0.95, 1))
    elif mouth == "beak":
        g.add_sphere(tuple(m(0, 0, 0.08)), (0.09, 0.22, 0.07), GOLD, rot=frame(n), taper=(0.95, 1))


# ---------------------------------------------------------------------------
# 飾り(元の妖怪が一目で分かる記号)


def add_decos(g, d, head, deco, c1, c2, c3, order, S, tailY):
    hc, hr = head
    hc = Vector(hc)
    top = hc + Vector((0, -hr[1] * 0.1, hr[2] * 0.96))

    def hp(yaw, pitch):
        return head_point(head, yaw, pitch)

    if "horns" in deco:
        for s in (1, -1):
            p, n = hp(s * 28, 55)
            dirv = (n + Vector((s * 0.3, -0.2, 0.6))).normalized()
            g.add_sphere(tuple(p + dirv * 0.16), (0.07, 0.24, 0.07), (0.96, 0.92, 0.82), rot=frame(dirv), taper=(0.95, 1.3))
    if "antlers" in deco:
        for s in (1, -1):
            p, n = hp(s * 22, 60)
            pts = [p, p + Vector((s * 0.12, -0.05, 0.25)), p + Vector((s * 0.25, -0.15, 0.48))]
            g.add_tube(pts, 0.035, (0.98, 0.9, 0.7), radius_end=0.02)
            g.add_tube([pts[1], pts[1] + Vector((s * 0.02, 0.15, 0.18))], 0.025, (0.98, 0.9, 0.7), radius_end=0.015)
    if "ears" in deco:
        for s in (1, -1):
            p, n = hp(s * 32, 52)
            dirv = (n + Vector((0, 0, 0.9))).normalized()
            g.add_sphere(tuple(p + dirv * 0.13), (0.15, 0.2, 0.06), c1, rot=frame(dirv, Vector((0, 1, 0))), taper=(0.95, 1.1))
            g.add_sphere(tuple(p + dirv * 0.13 + Vector((0, 0.035, 0))), (0.09, 0.14, 0.04), PINK, rot=frame(dirv, Vector((0, 1, 0))), taper=(0.95, 1.1))
    if "crown" in deco:
        g.add_disc(top + Vector((0, 0, 0.02)), Vector((0, 0, 1)), hr[0] * 0.55, hr[0] * 0.55, (0.86, 0.94, 0.97), up=Vector((0, 1, 0)), thick=0.04)
        g.add_torus(top + Vector((0, 0, 0.02)), Vector((0, 0, 1)), hr[0] * 0.56, 0.035, darken(c3, 0.1))
    if "leaf" in deco:
        g.add_sphere(tuple(top + Vector((0.02, -0.05, 0.2))), (0.03, 0.26, 0.13), (0.36, 0.64, 0.27), rot=frame(Vector((0.3, -0.4, 1)), Vector((1, 0, 0))), taper=(0.9, 1.4))
        g.add_tube([top, top + Vector((0, 0.0, 0.08))], 0.018, (0.24, 0.42, 0.18))
    if "umbrella" in deco:
        base = top + Vector((0, -0.05, 0.12))
        # 広い傘の屋根(ドーム)と、骨の模様、てっぺんの石突き
        R = hr[0] * 1.35
        g.add_sphere(tuple(base + Vector((0, 0, 0.1))), (R, R, 0.26), c3)
        g.add_sphere(tuple(base + Vector((0, 0, 0.06))), (R * 1.02, R * 1.02, 0.12), c2)
        for i in range(8):
            a = i / 8 * 2 * math.pi
            g.add_tube([base + Vector((0, 0, 0.36)), base + Vector((math.cos(a) * R * 0.98, math.sin(a) * R * 0.98, 0.1))], 0.014, c2)
        g.add_sphere(tuple(base + Vector((0, 0, 0.4))), (0.06, 0.06, 0.08), (0.17, 0.1, 0.06))
    if "hat" in deco:
        base = top + Vector((0, -0.03, 0.05))
        g.add_sphere(tuple(base + Vector((0, 0, 0.04))), (hr[0] * 1.45, hr[0] * 1.45, 0.06), (0.79, 0.64, 0.36))
        g.add_sphere(tuple(base + Vector((0, 0, 0.12))), (hr[0] * 0.75, hr[0] * 0.75, 0.24), (0.72, 0.57, 0.3), rot=frame(Vector((0, 0.001, 1)), Vector((0, 1, 0))), taper=(0.85, 1.3))
    if "okappa" in deco:
        hair = (0.11, 0.09, 0.13)
        g.add_sphere(tuple(hc + Vector((0, -hr[1] * 0.12, hr[2] * 0.18))), (hr[0] * 1.08, hr[1] * 0.95, hr[2] * 0.92), hair)
        # 前髪(ぱっつん)
        for i in range(7):
            x = (i / 6 * 2 - 1) * hr[0] * 0.7
            p = hc + Vector((x, hr[1] * 0.78, hr[2] * 0.55))
            g.add_sphere(tuple(p), (0.09, 0.07, 0.12), hair)
    if "hair" in deco:
        hair = c3 if d.get("c3") else (0.11, 0.09, 0.13)
        for i in range(5):
            x = (i / 4 * 2 - 1) * hr[0] * 0.5
            pts = [hc + Vector((x, hr[1] * 0.2, hr[2] * 0.9)), hc + Vector((x * 1.2, -hr[1] * 0.8, hr[2] * 0.75)), hc + Vector((x * 1.4, -hr[1] * 2.0, hr[2] * 0.3 + math.sin(i) * 0.05)), hc + Vector((x * 1.5, -hr[1] * 3.0, hr[2] * 0.1))]
            g.add_tube(pts, 0.06, hair, radius_end=0.02)
    if "nose" in deco:
        p, n = hp(0, 8)
        g.add_sphere(tuple(p + Vector((0, 0.25, 0.02))), (0.07, 0.3, 0.07), mix(c1, RED, 0.5), rot=frame(Vector((0, 1, 0.1))), taper=(0.4, 1))
    if "crest" in deco:
        for i in range(5):
            p, n = hp((i - 2) * 9, 70 - abs(i - 2) * 6)
            dirv = (n + Vector((0, -0.6, 0.4))).normalized()
            g.add_sphere(tuple(p + dirv * 0.12), (0.045, 0.2 - abs(i - 2) * 0.03, 0.045), c3, rot=frame(dirv), taper=(0.95, 1.2))
    if "whiskers" in deco:
        col = WHITE if "beard" in deco else (0.15, 0.12, 0.12)
        for s in (1, -1):
            for k in range(2):
                p, n = hp(s * 22, -8 - k * 8)
                pts = [p, p + Vector((s * 0.25, 0.2 - k * 0.1, -0.05 - k * 0.08)), p + Vector((s * 0.55, 0.1 - k * 0.15, -0.15 - k * 0.12)), p + Vector((s * 0.75, -0.08, -0.12 - k * 0.15))]
                g.add_tube(pts, 0.016, col, radius_end=0.008)
    if "beard" in deco:
        p, n = hp(0, -40)
        g.add_sphere(tuple(p + Vector((0, 0.02, -0.12))), (0.14, 0.12, 0.25), WHITE, rot=frame(Vector((0, 0.2, -1))), taper=(0.85, 1.2))
    if "bell" in deco:
        ring_c = hc + Vector((0, -hr[1] * 0.55, -hr[2] * 0.1))
        g.add_torus(ring_c, Vector((0, 1, 0)), max(hr[0], hr[2]) * 0.92, 0.045, RED)
        g.add_sphere(tuple(ring_c + Vector((0, 0.05, -max(hr[0], hr[2]) * 0.98))), (0.1, 0.1, 0.1), GOLD)
    if "shimenawa" in deco:
        ring_c = hc + Vector((0, -hr[1] * 1.2, 0))
        R = max(hr[0], hr[2]) * 1.0
        g.add_torus(ring_c, Vector((0, 1, 0)), R, 0.07, (0.85, 0.76, 0.54))
        for x in (-0.3, 0, 0.3):
            p = ring_c + Vector((x * R * 1.6, 0.02, -R * 0.95))
            g.add_sphere(tuple(p + Vector((0, 0, -0.1))), (0.06, 0.02, 0.12), WHITE)
    if "lotus" in deco:
        base = top + Vector((0, 0, 0.03))
        for i in range(8):
            a = i / 8 * 2 * math.pi
            dirv = Vector((math.cos(a) * 0.6, math.sin(a) * 0.6, 1)).normalized()
            g.add_sphere(tuple(base + dirv * 0.1), (0.06, 0.15, 0.03), lighten(PINK, 0.2), rot=frame(dirv, Vector((math.cos(a), math.sin(a), 0))), taper=(0.8, 1.4))
        g.add_sphere(tuple(base + Vector((0, 0, 0.05))), (0.05, 0.05, 0.05), GOLD)
    if "kanzashi" in deco:
        base = top + Vector((hr[0] * 0.45, -0.05, -0.02))
        g.add_tube([base, base + Vector((0.18, -0.12, 0.25))], 0.018, GOLD)
        g.add_sphere(tuple(base + Vector((0.2, -0.13, 0.28))), (0.08, 0.08, 0.08), c3 if d.get("c3") else PINK)
        for k in range(3):
            g.add_sphere(tuple(base + Vector((0.22, -0.13, 0.18 - k * 0.07))), (0.025, 0.025, 0.025), GOLD)
    if "coin" in deco:
        p, n = hp(0, 35)
        g.add_disc(p + n * 0.01, n, 0.12, 0.08, GOLD, thick=0.02)
    if "wind_bag" in deco:
        g.add_torus(hc + Vector((0, -hr[1] * 0.9, hr[2] * 0.6)), Vector((0, 1, 0)), max(hr[0] * 1.8, 0.6), 0.09, c3, arc=0.5, start=0.0)
    if "drums" in deco:
        center = Vector((0, -0.3, 0.35)) if d["shape"] != "hammer" else Vector((0, -0.25, 0.55))
        R = 1.0 if d["shape"] != "hammer" else 0.62
        g.add_torus(center, Vector((1, 0, 0)), R, 0.03, GOLD)
        for i in range(6):
            a = i / 6 * 2 * math.pi
            p = center + Vector((0, math.cos(a) * R, math.sin(a) * R))
            g.add_sphere(tuple(p), (0.1, 0.16, 0.16), (0.71, 0.2, 0.16))
            g.add_disc(p + Vector((0.1, 0, 0)), Vector((1, 0, 0)), 0.11, 0.11, (0.97, 0.9, 0.75), thick=0.01)
    if "fire_wheel" in deco:
        center = Vector((0, -0.2, 0.05))
        R = 0.95
        g.add_torus(center, Vector((1, 0, 0)), R, 0.05, (1.0, 0.48, 0.18))
        for i in range(12):
            a = i / 12 * 2 * math.pi
            p = center + Vector((0, math.cos(a) * R, math.sin(a) * R))
            out = Vector((0, math.cos(a), math.sin(a)))
            g.add_sphere(tuple(p + out * 0.1), (0.06, 0.14, 0.06), (1.0, 0.71, 0.28), rot=frame(out), taper=(0.95, 1.2))
    if "sun_disc" in deco and d["shape"] != "mola":  # 翻車魚は体そのものが日輪(special_details)
        if d["shape"] != "ray":
            # 鱏以外: 頭の後ろに小さめの日輪(金の縁)
            at = hc + Vector((0, -hr[1] * 1.1, hr[2] + 0.26))
            g.add_disc(at, Vector((0, 1, 0)), 0.36, 0.36, (1.0, 0.62, 0.24), thick=0.03)
            g.add_torus(at, Vector((0, 1, 0)), 0.38, 0.03, GOLD)
        else:
            g.add_disc(hc + Vector((0, -0.55, 0.65)), Vector((0, 1, 0)), 0.55, 0.55, (1.0, 0.62, 0.24), thick=0.03)
    if "moon" in deco:
        # 三日月: 太さが中央で太く端で細い弧(管を重ねて作る)
        pts = []
        for i in range(21):
            a = math.radians(-80 + i * 160 / 20)
            pts.append((i, Vector((0, math.sin(a) * 0.95 - 0.25, 0.5 + math.cos(a) * 0.95))))
        for i, p in pts:
            r = 0.025 + 0.1 * math.sin(i / 20 * math.pi) ** 1.5
            g.add_sphere(tuple(p + Vector((0, 0, -r * 0.4))), (r * 0.8, r * 1.2, r), (0.97, 0.95, 0.78), seg=14, rings=8)
    if "orb" in deco:
        p, n = hp(0, -45)
        g.add_sphere(tuple(p + Vector((0, 0.15, -0.15))), (0.13, 0.13, 0.13), (0.81, 0.96, 1.0))
    if "lantern" in deco:
        base = hc + Vector((0, hr[1] * 0.2, hr[2] * 0.95))
        tip = base + Vector((0, 0.45, 0.35))
        g.add_tube([base, base + Vector((0, 0.15, 0.3)), tip], 0.025, darken(c1, 0.3))
        g.add_sphere(tuple(tip + Vector((0, 0.05, -0.08))), (0.13, 0.13, 0.16), (1.0, 0.71, 0.28))
        g.add_disc(tip + Vector((0, 0.05, 0.06)), Vector((0, 0, 1)), 0.09, 0.09, INK, thick=0.02)
    if "flame" in deco:
        base = Vector((0, tailY - 0.1, 0.25))
        for i in range(3):
            g.add_sphere(tuple(base + Vector(((i - 1) * 0.08, -0.05 * abs(i - 1), 0.12))), (0.08, 0.08, 0.2 - abs(i - 1) * 0.05), lighten(c3, 0.2), rot=frame(Vector((0, -0.3, 1))), taper=(0.9, 1.3))


# ---------------------------------------------------------------------------
# 仕上げ: 結合・輪郭線・材質


def finish(body, detail, d, scale, keep_body=False):
    """体と部品を一つのメッシュにまとめる(keep_body なら体は消さずに残す)"""
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.from_mesh(detail.data)
    # 部品ごとに面を外向きにそろえる(管・輪など手で面を張った部品も含めて)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    mesh = bpy.data.meshes.new(d["id"])
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(d["id"], mesh)
    bpy.context.scene.collection.objects.link(obj)
    for p in mesh.polygons:
        p.use_smooth = True
    obj.scale = (scale, scale, scale)
    if not keep_body:
        bpy.data.objects.remove(body)
    bpy.data.objects.remove(detail)
    return obj


def make_outline(obj, thickness):
    ol = obj.copy()
    ol.data = obj.data.copy()
    dm = ol.modifiers.new("lighter", "DECIMATE")
    dm.ratio = 0.5
    ol.name = obj.name + "_Outline"
    bpy.context.scene.collection.objects.link(ol)
    mod = ol.modifiers.new("solid", "SOLIDIFY")
    mod.thickness = thickness
    mod.offset = 1.0
    mod.use_flip_normals = True
    mod.use_rim = False
    mod.use_rim_only = False
    baked = evaluated_copy(ol, obj.name + "_Outline")
    bpy.data.objects.remove(ol)
    # 元の面は消して、裏返しの殻だけ残す(殻は後半に作られる)
    bm = bmesh.new()
    bm.from_mesh(baked.data)
    n_orig = len(bm.faces) // 2
    bm.faces.ensure_lookup_table()
    bmesh.ops.delete(bm, geom=[bm.faces[i] for i in range(n_orig)], context="FACES")
    # 間引きでつぶれた(面積ほぼ0の)三角形を消す(glTF で「壊れたメッシュ」にならないように)
    bmesh.ops.dissolve_degenerate(bm, dist=1e-5, edges=bm.edges[:])
    flat = [f for f in bm.faces if f.calc_area() < 1e-10]
    if flat:
        bmesh.ops.delete(bm, geom=flat, context="FACES")
    # 向きをそろえる: 部品ごとに外向きへ計算し直してから、全部を内向きに裏返す
    # (Roblox は内向きの面を正面から描かないので、外周だけが線として見える)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    bm.to_mesh(baked.data)
    bm.free()
    baked.scale = obj.scale
    return baked


def ink_material(name, color):
    """輪郭線(裏返しの殻)。カメラに近い側の面は透明にして、外周だけ線として見せる"""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    ink = nt.nodes.new("ShaderNodeEmission")
    ink.inputs["Color"].default_value = (*color, 1)
    ink.inputs["Strength"].default_value = 1.0
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mixs = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(geo.outputs["Backfacing"], mixs.inputs["Fac"])
    nt.links.new(ink.outputs[0], mixs.inputs[1])
    nt.links.new(tr.outputs[0], mixs.inputs[2])
    nt.links.new(mixs.outputs[0], out.inputs["Surface"])
    return mat


def toon_material(name, use_vertex=True, color=(0, 0, 0)):
    """確認用の材質: ゲーム(SurfaceAppearance)に近い、少しつやのある立体の塗り"""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    if use_vertex:
        attr = nt.nodes.new("ShaderNodeVertexColor")
        attr.layer_name = "Col"
        nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = 0.45
    return mat


# ---------------------------------------------------------------------------
# Roblox 用の書き出し: 軽いメッシュ + 色を焼き込んだテクスチャ + 輪郭線


def facing_check(obj, expect_front, rays=200):
    """外から中心へ光線を飛ばし、最初に当たる面の向きを数える。
    体は表(外向き)、輪郭線は裏(内向き)でなければ Roblox で正しく描けない"""
    from mathutils.bvhtree import BVHTree

    dg = bpy.context.evaluated_depsgraph_get()
    bvh = BVHTree.FromObject(obj, dg)
    c = sum((v.co for v in obj.data.vertices), Vector()) / len(obj.data.vertices)
    R = max(obj.dimensions) * 2 + 1
    rng = random.Random(7)
    good = total = 0
    for _ in range(rays):
        dvec = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()
        hit, nrm, _, _ = bvh.ray_cast(obj.matrix_world.inverted() @ (obj.matrix_world @ c + dvec * R), -dvec)
        if hit is None:
            continue
        total += 1
        is_front = nrm.dot(-dvec) < 0
        good += 1 if is_front == expect_front else 0
    ratio = good / max(1, total)
    if ratio < 0.97:
        raise RuntimeError(f"{obj.name}: 面の向きが正しくない ({ratio:.0%})")
    return ratio


def tri_count(obj):
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def select_only(objs, active):
    for o in bpy.data.objects:
        if o is not None and o.name in bpy.context.view_layer.objects:
            o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active


def bake_texture(hi, lo, size, path, normal_path=None):
    """hi(細かい・頂点色)の色を lo(軽い)のテクスチャに焼き込む。
    normal_path を渡すと、hi の細かい凹凸(鱗・えら・いぼ・ひれの筋)も法線マップに焼き込む"""
    # UV 展開
    select_only([lo], lo)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.003)
    bpy.ops.object.mode_set(mode="OBJECT")
    img = bpy.data.images.new(lo.name + "_tex", size, size, alpha=False)
    # 焼き込み用の材質(hi: 頂点色を発光で出す / lo: 書き込み先の画像)
    hi.data.materials.clear()
    hi.data.materials.append(emission_vertex_material("bake_src"))
    lo.data.materials.clear()
    mat = bpy.data.materials.new(lo.name + "_mat")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.45
    nt.nodes.active = tex
    lo.data.materials.append(mat)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 1
    sc.render.bake.use_selected_to_active = True
    sc.render.bake.cage_extrusion = 0.03
    sc.render.bake.max_ray_distance = 0.12
    sc.render.bake.margin = 8
    select_only([hi, lo], lo)
    bpy.ops.object.bake(type="EMIT")
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    nimg = None
    if normal_path:
        nimg = bpy.data.images.new(lo.name + "_nrm", size, size, alpha=False)
        nimg.generated_color = (0.5, 0.5, 1.0, 1.0)  # 平らな面の色(焼かれない隙間もこれ)
        nimg.colorspace_settings.name = "Non-Color"
        ntex = nt.nodes.new("ShaderNodeTexImage")
        ntex.image = nimg
        nt.nodes.active = ntex
        sc.render.bake.normal_space = "TANGENT"
        bpy.ops.object.bake(type="NORMAL")
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nmap.space = "TANGENT"
        nmap.inputs["Strength"].default_value = 1.0
        nt.links.new(ntex.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])
        nimg.filepath_raw = normal_path
        nimg.file_format = "PNG"
        nimg.save()
    return img, nimg


def emission_vertex_material(name):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(attr.outputs["Color"], em.inputs["Color"])
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    return mat


def flat_material(name, color):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = 1.0
    return mat


def decimate_to(obj, budget):
    """全体(体+目+ひれ)をまとめて、左右対称のまま三角形の数を budget 以下に減らす。
    平らな所から先に減るので、目の丸みや体の輪郭は残る"""
    for _ in range(4):
        tris = tri_count(obj)
        if tris <= budget:
            break
        dm = obj.modifiers.new("dec", "DECIMATE")
        dm.ratio = max(0.01, budget / tris * 0.97)
        dm.use_symmetry = True
        dm.symmetry_axis = "X"
        dm.use_collapse_triangulate = True
        name = obj.name
        light = evaluated_copy(obj, name + "_dec")
        bpy.data.objects.remove(obj)
        light.name = name
        light.data.name = name
        obj = light
    return obj


def export_fish(d, outdir, budget=15000, tex_size=1024):
    """1匹分を作り、軽いメッシュ・テクスチャ(色 + 法線)・輪郭線を返す。
    Roblox の 1メッシュの上限は 20,000 三角形。
    - 細かい版: 体(十数万三角形)+ 目の模様まで全部入りの部品 → 焼き込みの元
    - 軽い版: 部品は作り直す(目は白目の形だけ・面は少なめ)、体は左右対称に間引いて合わせて budget 以下
    細かい凹凸(鱗・えら・いぼ・ひれの筋)は法線マップに、模様と目の絵は色のテクスチャに焼き込む"""
    body, detail = build_fish(d)
    hi = finish(body, detail, d, 1.0, keep_body=True)
    hi.name = d["id"] + "_hi"
    hi_tris = tri_count(hi)
    # 軽い版の部品。飾りの多い魚(九尾の尾・後光の輪・太鼓など)は、体の分が残るまで部品の分割を減らす
    detail_lo = None
    for parts_q in (1.0, 0.75, 0.55, 0.4):
        if detail_lo is not None:
            bpy.data.objects.remove(detail_lo)
        LOD.update(parts=parts_q, decals=False)
        try:
            _, detail_lo = build_fish(d, parts_only=True)
        finally:
            LOD.update(parts=QUALITY, decals=True)
        if tri_count(detail_lo) <= budget * 0.55:
            break
    # 体には最低 6,000 三角形を回す(合計の上限は 19,000。Roblox の上限 20,000 より少し下)
    parts_tris = tri_count(detail_lo)
    room = min(max(budget - parts_tris, 6000), 19000 - parts_tris)
    if room < 4000:
        raise RuntimeError(f"{d['id']}: 部品だけで {parts_tris} 三角形(体に回す分が足りない)")
    body = decimate_to(body, room)
    lo = finish(body, detail_lo, d, 1.0)
    lo.name = d["id"]
    lo.data.name = d["id"]
    # 面の向きを外向きにそろえる(Roblox は裏面を描かない)
    bm = bmesh.new()
    bm.from_mesh(lo.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(lo.data)
    bm.free()
    for p in lo.data.polygons:
        p.use_smooth = True
    bake_texture(hi, lo, tex_size, os.path.join(outdir, d["id"] + ".png"), os.path.join(outdir, d["id"] + "_nrm.png"))
    bpy.data.objects.remove(hi)
    ol = make_outline(lo, OUTLINE)
    ol.name = d["id"] + "_Outline"
    ol.data.materials.clear()
    ol.data.materials.append(flat_material("Outline", (0.03, 0.02, 0.04)))
    facing_check(lo, True)
    facing_check(ol, False)
    if tri_count(lo) > 20000 or tri_count(ol) > 20000:
        raise RuntimeError(f"{d['id']}: Roblox の上限(20,000 三角形)を超えた")
    dims = lo.dimensions
    info = {"length": round(dims.y, 4), "width": round(dims.x, 4), "height": round(dims.z, 4)}
    info.update({"tris": tri_count(lo), "outlineTris": tri_count(ol), "sourceTris": hi_tris})
    return lo, ol, info


# ---------------------------------------------------------------------------
# 描画


def setup_render(res):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 24
    sc.cycles.use_denoising = True
    sc.render.resolution_x = res
    sc.render.resolution_y = res
    sc.render.film_transparent = True
    sc.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.75, 0.8, 0.9, 1)
    bg.inputs[1].default_value = 0.9
    sc.world = world
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 2.4
    sun.angle = math.radians(8)
    so = bpy.data.objects.new("sun", sun)
    so.rotation_euler = (math.radians(40), math.radians(-25), math.radians(140))
    sc.collection.objects.link(so)
    cam = bpy.data.cameras.new("cam")
    cam.lens = 60
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    sc.camera = co
    return co


def aim_camera(cam, objs, shape, face=False):
    pts = []
    for o in objs:
        verts = list(o.data.vertices)
        for v in verts[:: max(1, len(verts) // 4000)]:
            pts.append(o.matrix_world @ v.co)
    if face:
        # 頭(+Y の前側 35%)だけを斜め前から大きく写す
        y0, y1 = min(p.y for p in pts), max(p.y for p in pts)
        pts = [p for p in pts if p.y > y1 - (y1 - y0) * 0.35]
        shape = "face"
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    center = (mn + mx) / 2
    radius = (mx - mn).length / 2
    if shape == "face":
        direction = Vector((0.85, 1.0, 0.3)).normalized()
    elif shape == "ray":
        direction = Vector((0.45, 0.85, 0.9)).normalized()
    else:
        direction = Vector((1.0, 0.75, 0.32)).normalized()
    dist = radius / math.tan(math.atan(18 / cam.data.lens)) * 1.05
    cam.location = center + direction * dist
    look = (center - cam.location).normalized()
    cam.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--defs", default="")
    ap.add_argument("--out", required=True)
    ap.add_argument("--ids", default="")
    ap.add_argument("--render", action="store_true")
    ap.add_argument("--res", type=int, default=480)
    ap.add_argument("--face", action="store_true", help="顔のアップも描く(--render と一緒に)")
    ap.add_argument("--export", action="store_true", help="Roblox 用に全魚を1つの GLB に書き出す")
    ap.add_argument("--luau", default="", help="大きさの表を書き出す Config/FishMeshes.luau のパス")
    ap.add_argument("--part", default="", help="並列で作る時の途中のファイル名(PNG の GLB + JSON を書く)")
    ap.add_argument("--merge", nargs="*", default=None, help="--part で作った GLB を1つにまとめる")
    ap.add_argument("--update", default="", help="--merge と一緒に: 今の GLB(この中の同じ魚だけ --merge の GLB で差し替える)")
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    a = ap.parse_args(argv)
    defs = json.load(open(a.defs)) if a.defs else []
    if isinstance(defs, dict) and "fish" in defs:  # tools/export_fish.luau の出力をそのまま使える
        defs = defs["fish"]
    ids = [x for x in a.ids.split(",") if x]
    os.makedirs(a.out, exist_ok=True)
    if a.merge is not None and a.update:
        manifest = run_update(a.update, a.out, a.merge)
        if a.luau:
            write_luau(manifest, a.luau)
        return
    if a.merge is not None:
        manifest = run_merge(a.out, a.merge)
        if a.luau:
            write_luau(manifest, a.luau)
        return
    if a.export:
        if a.part:
            run_export(defs, ids, a.out, a.part, "AUTO")
            return
        manifest = run_export(defs, ids, a.out)
        if a.luau:
            write_luau(manifest, a.luau)
        return
    for d in defs:
        if ids and d["id"] not in ids:
            continue
        bpy.ops.wm.read_factory_settings(use_empty=True)
        cam = setup_render(a.res) if a.render else None
        body, detail = build_fish(d)
        obj = finish(body, detail, d, 1.0)
        ol = make_outline(obj, OUTLINE)
        obj.data.materials.append(toon_material("toon"))
        ol.data.materials.append(ink_material("ink", (0.08, 0.05, 0.1)))
        # 輪郭線はカメラにだけ見せる(光や映り込みをさえぎらない。Roblox の CastShadow=false と同じ)
        ol.visible_shadow = False
        ol.visible_diffuse = False
        ol.visible_glossy = False
        ol.visible_transmission = False
        tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
        print(f"{d['id']}: {tris} tris body+detail, outline {sum(len(p.vertices) - 2 for p in ol.data.polygons)}")
        if a.render:
            aim_camera(cam, [obj], d["shape"])
            bpy.context.scene.render.filepath = os.path.join(a.out, d["id"] + ".png")
            bpy.ops.render.render(write_still=True)
            if a.face:
                aim_camera(cam, [obj], d["shape"], face=True)
                bpy.context.scene.render.filepath = os.path.join(a.out, d["id"] + "_face.png")
                bpy.ops.render.render(write_still=True)


def run_export(defs, ids, out, name="YokaiFishMeshes", image_format="JPEG"):
    """全魚を1つのシーンに並べて GLB に書き出す(Studio の「3D をインポート」1回で全部入る)。
    name/image_format は並列で作る時の途中のファイル用(PNG のまま書いて、--merge で1つにまとめる)"""
    texdir = os.path.join(out, "textures")
    os.makedirs(texdir, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    manifest = {}
    keep = []
    k = 0
    for d in defs:
        if ids and d["id"] not in ids:
            continue
        lo, ol, info = export_fish(d, texdir)
        # 並べて置く(位置はゲームでは使わない)
        offset = Vector(((k % 10) * 4.0, (k // 10) * 5.0, 0))
        lo.location = offset
        ol.location = offset
        keep += [lo, ol]
        manifest[d["id"]] = info
        print(f"{d['id']}: {info['tris']} tris + outline {info['outlineTris']}")
        k += 1
    # 余計なもの(焼き込みの元など)を消す
    for o in list(bpy.context.scene.objects):
        if o not in keep:
            bpy.data.objects.remove(o)
    # 名前をそろえる(Studio で読み込んだ時のパーツ名になる)
    for m in list(bpy.data.meshes):
        if m.users == 0:
            bpy.data.meshes.remove(m)
    for o in keep:
        o.data.name = o.name
    path = os.path.join(out, name + ".glb")
    export_glb(path, keep, image_format)
    json.dump(manifest, open(os.path.join(out, name + ".json" if name != "YokaiFishMeshes" else "manifest.json"), "w"), indent=1)
    print("exported", path, os.path.getsize(path) // 1024, "KB")
    return manifest


def export_glb(path, objs, image_format="JPEG"):
    select_only(objs, objs[0])
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_image_format=image_format,
        export_jpeg_quality=92,
        export_materials="EXPORT",
        export_vertex_color="NONE",
    )


def run_merge(out, parts):
    """並列で作った GLB(PNG 入り)を読み込んで、1つの GLB(JPEG)と manifest にまとめる"""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    manifest = {}
    for part in parts:
        bpy.ops.import_scene.gltf(filepath=part)
        mf = os.path.splitext(part)[0] + ".json"
        if os.path.exists(mf):
            manifest.update(json.load(open(mf)))
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in objs:
        o.data.name = o.name
    missing = [k for k in manifest if k not in bpy.data.objects or k + "_Outline" not in bpy.data.objects]
    if missing:
        raise RuntimeError("まとめる時に見つからない魚: " + ", ".join(missing))
    path = os.path.join(out, "YokaiFishMeshes.glb")
    export_glb(path, objs, "JPEG")
    manifest = dict(sorted(manifest.items()))
    json.dump(manifest, open(os.path.join(out, "manifest.json"), "w"), indent=1)
    print("merged", len(manifest), "fish ->", path, os.path.getsize(path) // 1024, "KB")
    return manifest


def run_update(base, out, parts):
    """今の GLB(全魚)の中の、parts に入っている魚だけを差し替える(作り直した数匹だけを入れ替える時)。
    manifest は base と同じフォルダの manifest.json を引き継ぎ、差し替えた魚の分を上書きする"""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    manifest = json.load(open(os.path.join(os.path.dirname(base), "manifest.json")))
    new = {}
    for part in parts:
        mf = os.path.splitext(part)[0] + ".json"
        new.update(json.load(open(mf)))
    bpy.ops.import_scene.gltf(filepath=base)
    # この GLB に入っている魚(魚は2つの GLB に分けてある: 沼・湖 / 川・海)
    present = {o.name.removesuffix("_Outline") for o in bpy.context.scene.objects if o.type == "MESH"}
    for o in list(bpy.context.scene.objects):
        if o.type == "MESH" and o.name.removesuffix("_Outline") in new:
            bpy.data.objects.remove(o)
    for m in list(bpy.data.meshes):
        if m.users == 0:
            bpy.data.meshes.remove(m)
    for part in parts:
        bpy.ops.import_scene.gltf(filepath=part)
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    for o in objs:
        if "." in o.name:
            raise RuntimeError("名前がぶつかった: " + o.name)
        o.data.name = o.name
    manifest.update(new)
    missing = [k for k in present | set(new) if k not in bpy.data.objects or k + "_Outline" not in bpy.data.objects]
    if missing:
        raise RuntimeError("見つからない魚: " + ", ".join(missing))
    os.makedirs(out, exist_ok=True)
    path = os.path.join(out, os.path.basename(base))
    export_glb(path, objs, "JPEG")
    manifest = dict(sorted(manifest.items()))
    json.dump(manifest, open(os.path.join(out, "manifest.json"), "w"), indent=1)
    print("updated", len(new), "of", len(manifest), "fish ->", path, os.path.getsize(path) // 1024, "KB")
    return manifest


def write_luau(manifest, path):
    src = open(path).read()
    rows = "\n".join(f'\t\t{k} = {{ length = {v["length"]}, width = {v["width"]}, height = {v["height"]} }},' for k, v in sorted(manifest.items()))
    start = src.index("\tsizes = ")
    end = src.index("\n}", start)
    src = src[:start] + "\tsizes = {\n" + rows + "\n\t} :: { [string]: { length: number, width: number, height: number } },\n" + src[end + 1 :]
    open(path, "w").write(src)
    print("wrote", path)


def run_verify(glb, out, res):
    """書き出した GLB を読み直して描く(ゲームに入る軽いメッシュ + テクスチャの見た目の確認)"""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=glb)
    cam = setup_render(res)
    # ゲームに近い明るさ(拡散光だけの材質なので、環境光を強めにする)
    bpy.context.scene.world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    bpy.data.objects["sun"].data.energy = 2.0
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bodies = [o for o in objs if not o.name.endswith("_Outline")]
    for o in objs:
        if o.name.endswith("_Outline"):
            o.data.materials.clear()
            o.data.materials.append(ink_material("ink", (0.08, 0.05, 0.1)))
            o.hide_render = True
            o.visible_shadow = False  # 輪郭線は影を作らない(Roblox の CastShadow=false と同じ)
            o.visible_diffuse = False
            o.visible_glossy = False
    for b in bodies:
        for o in objs:
            o.hide_render = not (o.name == b.name or o.name == b.name + "_Outline")
        aim_camera(cam, [b], "ray" if b.name.endswith("_ei") else "koi")
        bpy.context.scene.render.filepath = os.path.join(out, b.name + ".png")
        bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    if "--verify" in sys.argv:
        i = sys.argv.index("--verify")
        run_verify(sys.argv[i + 1], sys.argv[i + 2], int(sys.argv[i + 3]) if len(sys.argv) > i + 3 else 360)
    else:
        main()
