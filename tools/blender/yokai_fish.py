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

# ---------------------------------------------------------------------------
# 基本

RARITY_SCALE = {"common": 0.8, "uncommon": 0.92, "rare": 1.05, "epic": 1.2, "legendary": 1.4, "mythic": 1.65, "secret": 1.9}
RARITY_ORDER = {"common": 1, "uncommon": 2, "rare": 3, "epic": 4, "legendary": 5, "mythic": 6, "secret": 7}
INK = (0.07, 0.05, 0.09)
WHITE = (0.98, 0.97, 0.95)
GOLD = (0.95, 0.76, 0.31)
PINK = (1.0, 0.56, 0.66)
RED = (0.84, 0.15, 0.24)
LIGHT = Vector((0.35, 0.45, 0.82)).normalized()  # 塗りの影の向き


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


class Geo:
    """色つきの形を1つの bmesh に足していく入れ物"""

    def __init__(self):
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.float_color.new("Col")

    def add_sphere(self, center, radii, color, rot=None, seg=16, rings=10, taper=None):
        """楕円体を足す。taper=(強さ, べき) で +Y 側を細くして涙型にする"""
        tmp = bmesh.new()
        bmesh.ops.create_uvsphere(tmp, u_segments=seg, v_segments=rings, radius=1.0)
        for v in tmp.verts:
            x, y, z = v.co
            if taper:
                k, p = taper
                t = (y + 1) / 2  # 0(根元)..1(先)
                s = max(0.02, 1 - k * t**p)
                x *= s
                z *= s
            v.co = Vector((x * radii[0], y * radii[1], z * radii[2]))
        m = rot if rot is not None else Matrix.Identity(3)
        for v in tmp.verts:
            v.co = m @ v.co + Vector(center)
        self._merge(tmp, color)

    def add_torus(self, center, normal, major, minor, color, seg=40, sides=10, arc=1.0, start=0.0):
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

    def add_tube(self, points, radius, color, sides=6, radius_end=None):
        """点の列に沿った管(まつげ・ひげ・口の線など)"""
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
        self.add_sphere(points[0], (radius,) * 3, color, seg=10, rings=6)
        self.add_sphere(points[-1], ((radius_end or radius),) * 3, color, seg=10, rings=6)

    def add_disc(self, center, normal, rx, ry, color, up=Vector((0, 0, 1)), thick=0.012, seg=18):
        """表面に貼る平たい円(目・ほっぺ・紋など)。rx は横、ry は縦"""
        n = Vector(normal).normalized()
        upv = Vector(up) - n * Vector(up).dot(n)
        if upv.length < 1e-4:
            upv = Vector((0, 1, 0)) - n * n.y
        upv.normalize()
        side = upv.cross(n).normalized()
        rot = Matrix((side, n, upv)).transposed()  # Y 軸 = 法線(薄い方向)
        self.add_sphere(center, (rx, thick, ry), color, rot=rot, seg=seg, rings=6)

    def _merge(self, tmp, color):
        lc = to_linear(color)
        rgba = (lc[0], lc[1], lc[2], 1.0)
        layer = tmp.loops.layers.float_color.new("Col")
        for f in tmp.faces:
            for l in f.loops:
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
}

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


def build_fish(d):
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

    # --- 体(溶かして一体化) ---
    body = Geo()
    if d["shape"] == "eel":
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
        for c, r in shape["parts"]:
            body.add_sphere(sp(c), tuple(S @ Vector(r)), c1)
    if "bighead" in deco:
        (hc, hr) = head
        body.add_sphere(Vector(hc) + Vector((0, -hr[1] * 0.25, hr[2] * 0.7)), (hr[0] * 0.95, hr[1] * 0.9, hr[2] * 0.85), c1)
    if d["shape"] == "angler":
        body.add_sphere(sp((0, 0.62, -0.26)), tuple(S @ Vector((0.56, 0.32, 0.24))), c1)  # 大きなあご
    if d["shape"] == "catfish":
        body.add_sphere(sp((0, 0.82, -0.12)), tuple(S @ Vector((0.42, 0.2, 0.2))), c1)  # 平たい口先

    body_obj = body.to_object(d["id"] + "_raw")
    size = max(prop) * 2.3
    rm = body_obj.modifiers.new("remesh", "REMESH")
    rm.mode = "VOXEL"
    rm.voxel_size = 0.028 * size / 2.3
    rm.use_smooth_shade = True
    sm = body_obj.modifiers.new("smooth", "SMOOTH")
    sm.factor = 0.9
    sm.iterations = 14
    body_mesh = evaluated_copy(body_obj, d["id"] + "_body")
    bpy.data.objects.remove(body_obj)

    # 体の色: 明るいお腹・少し濃い背中・模様
    paint_body(body_mesh, d, head, c1, c2, c3, rng, S)

    # --- 細かい部品(目・ひれ・飾り) ---
    g = Geo()
    fin_col = lighten(c3, 0.18)
    rim = GOLD if order >= 5 else darken(c3, 0.15)
    has_rim = order >= 3
    fin_scale = 1 + (order - 1) * 0.07

    def fin(center, radii, rot, color=None, taper=(0.75, 1.4)):
        r = tuple(x * fin_scale if i != 0 else x for i, x in enumerate(radii))
        if has_rim:
            g.add_sphere(center, (r[0] * 0.7, r[1] * 1.1, r[2] * 1.12), rim, rot=rot, taper=taper)
        g.add_sphere(center, r, color or fin_col, rot=rot, taper=taper)

    tailY = sp((0, shape["tailY"], 0)).y
    tails = d.get("tails") or 0
    tail_kind = shape["tail"]
    if tails >= 2 and tail_kind != "whip":
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
    if "mane" in deco:
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
    elif shape["dorsal"] == "spines":
        for i in range(3):
            g.add_sphere(sp((0, -0.05 - i * 0.22, 0.6 - i * 0.05)), (0.035, 0.1, 0.2 - i * 0.03), c3, rot=frame(Vector((0, -0.3, 1))), taper=(0.95, 1.2))
    if order >= 4 and shape["dorsal"] != "none" and "mane" not in deco:
        fin(sp((0, -0.55, 0.3)), (0.03, 0.34, 0.12), frame(Vector((0, -0.85, 0.45))), c3)

    # 胸びれ
    if d["shape"] != "ray":
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

    add_face(g, d, head, deco, c1, c2, c3, order)
    add_decos(g, d, head, deco, c1, c2, c3, order, S, tailY)

    # レア度の飾り
    hc, hr = head
    if order >= 5 and not ({"coin", "okappa"} & deco):
        p, n = head_point(head, 0, 38)
        g.add_disc(p + n * 0.01, n, 0.1, 0.1, GOLD, up=Vector((0, 0, 1)) - n * n.z if abs(n.z) < 0.95 else Vector((0, 1, 0)), thick=0.02)
    if order >= 6:
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
# 体の塗り


def paint_body(obj, d, head, c1, c2, c3, rng, S):
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
    hc = Vector(head[0])
    head_r = max(head[1])
    belly_c = lighten(c1, 0.45) if pat != "belly" else c2
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
            # お腹は明るく、背中は少し濃く(アニメの塗り)
            if pat not in ("dango",):
                c = mix(c, belly_c, smoothstep(0.42, 0.22, h))
            c = mix(c, darken(c, 0.1), smoothstep(0.8, 0.98, h))
            # 2段のアニメ影(光は斜め上前から)と、頭の上のツヤの帯
            nrm = mesh.loops[li].normal if hasattr(mesh.loops[li], "normal") else poly.normal
            ndl = nrm.dot(LIGHT)
            if ndl < -0.05:
                c = (c[0] * 0.84, c[1] * 0.82, c[2] * 0.9)
            if nrm.z > 0.8 and (v - hc).length < head_r * 1.05 and abs(nrm.x) < 0.45:
                c = lighten(c, 0.32)
            lc = to_linear(c)
            col.data[li].color = (lc[0], lc[1], lc[2], 1.0)


# ---------------------------------------------------------------------------
# 顔


def eye_frame(n):
    up = Vector((0, 0, 1))
    up = (up - n * up.dot(n)).normalized()
    return up


def add_eye(g, center, n, w, h, style, iris, order, glow=False):
    """アニメの目。w, h は白目の幅と高さ"""
    up = eye_frame(n)
    side = up.cross(n).normalized()
    fwd_bias = Vector((0, 1, 0)) - n * n.y  # 瞳を少し前へ寄せる
    fwd_bias = fwd_bias.normalized() if fwd_bias.length > 1e-3 else side

    def at(du, dv, dn):
        return center + side * du + up * dv + n * dn

    if style == "dot":
        g.add_disc(at(0, 0, 0.01), n, w * 0.42, h * 0.5, INK, up=up, thick=0.02)
        g.add_disc(at(0, h * 0.18, 0.025), n, w * 0.12, w * 0.12, WHITE, up=up, thick=0.01)
        return
    sclera = (1.0, 0.86, 0.32) if style == "cat" else WHITE
    g.add_disc(at(0, 0, 0.0), n, w, h, sclera, up=up, thick=0.02)
    if style == "cat":
        g.add_disc(at(0, 0, 0.018), n, w * 0.16, h * 0.82, INK, up=up, thick=0.012)
    else:
        iris_main = iris
        iris_dark = darken(iris, 0.45)
        g.add_disc(at(0, -h * 0.05, 0.012), n, w * 0.74, h * 0.8, iris_main, up=up, thick=0.014)
        g.add_disc(at(0, h * 0.14, 0.018), n, w * 0.62, h * 0.48, iris_dark, up=up, thick=0.012)
        g.add_disc(at(0, -h * 0.02, 0.024), n, w * 0.34, h * 0.42, INK if not glow else lighten(iris, 0.6), up=up, thick=0.012)
        # 下の明るい反射
        g.add_disc(at(0, -h * 0.5, 0.022), n, w * 0.42, h * 0.16, lighten(iris, 0.45), up=up, thick=0.008)
    if not glow:
        g.add_disc(at(-w * 0.28, h * 0.32, 0.034), n, w * 0.24, w * 0.26, WHITE, up=up, thick=0.012)
        g.add_disc(at(w * 0.3, -h * 0.34, 0.034), n, w * 0.1, w * 0.1, WHITE, up=up, thick=0.01)
    # まつげの線(上の縁を太く、目尻を跳ねさせる)
    pts = []
    for i in range(13):
        a = math.radians(170 - i * 13)
        r = 1.04
        p = at(math.cos(a) * w * r, math.sin(a) * h * r * 0.95, 0.02)
        pts.append(p)
    tip = at(w * 1.25 * (1 if True else -1), h * 0.55, 0.02)
    pts.append(tip)
    g.add_tube(pts, 0.022 * (h / 0.2), INK, radius_end=0.012 * (h / 0.2))
    if style == "sleepy":
        g.add_disc(at(0, h * 0.42, 0.04), n, w * 1.12, h * 0.6, g_skin[0], up=up, thick=0.03)
        g.add_tube([at(-w, h * 0.0, 0.05), at(0, -h * 0.08, 0.055), at(w, h * 0.0, 0.05)], 0.02 * (h / 0.2), INK)
    if style == "angry":
        g.add_tube([at(-w * 0.9, h * 1.15, 0.03), at(w * 0.9, h * 1.45, 0.03)], 0.03 * (h / 0.2), INK)


g_skin = [None]


def add_face(g, d, head, deco, c1, c2, c3, order):
    eyes = d.get("eyes") or ("none" if "noface" in deco else ("big" if "big_eye" in deco else "normal"))
    mouth = d.get("mouth") or {"koi": "small", "catfish": "wide", "puffer": "o", "eel": "small", "angler": "grin", "ray": "none"}[d["shape"]]
    g_skin[0] = c1
    iris = c3 if d.get("c3") else c2
    # 虹彩の色が体と近すぎるときは補色寄りに
    if sum(abs(iris[i] - c1[i]) for i in range(3)) < 0.35:
        iris = mix(iris, (0.25, 0.45, 0.9), 0.6)
    glow = eyes == "glow" or order >= 6
    hc, hr = head
    scale_eye = min(hr[0], hr[2])
    if d["shape"] == "ray":
        yaw_side, pitch = 30, 32
    elif d["shape"] == "eel":
        yaw_side, pitch = 40, 18
    elif d["shape"] == "puffer":
        yaw_side, pitch = 34, 12
    else:
        yaw_side, pitch = 33, 14
    if eyes == "big":
        p, n = head_point(head, 0, 22 if d["shape"] != "ray" else 35)
        add_eye(g, p, n, scale_eye * 0.55, scale_eye * 0.62, "normal", iris, order, glow)
    elif eyes != "none":
        w = scale_eye * (0.33 if eyes == "cute" else 0.27)
        h = w * 1.25
        for s in (1, -1):
            p, n = head_point(head, s * yaw_side, pitch)
            add_eye(g, p, n, w, h, eyes, iris, order, glow)
            if s == -1:
                pass
    if "third_eye" in deco:
        p, n = head_point(head, 0, 52)
        add_eye(g, p, n, scale_eye * 0.16, scale_eye * 0.22, "normal", iris, order, glow)
    if "blush" in deco or eyes == "cute":
        for s in (1, -1):
            p, n = head_point(head, s * (yaw_side + 6), pitch - 22)
            g.add_disc(p + n * 0.005, n, scale_eye * 0.16, scale_eye * 0.09, PINK, thick=0.012)
    # 口
    p, n = head_point(head, 0, -12 if d["shape"] != "ray" else 10)
    side = Vector((1, 0, 0))
    up = eye_frame(n)
    w = scale_eye * 0.22
    lip = darken(c1, 0.75)

    def m(du, dv, dn=0.015):
        return p + side * du + up * dv + n * dn

    if mouth in ("small", "smile", "frown", "wide", "fangs", "geta"):
        width = w * (2.2 if mouth == "wide" else 1.0)
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
        center = Vector((0, -0.3, 0.35))
        R = 1.0
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
    if "sun_disc" in deco:
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


def finish(body, detail, d, scale, body_ratio=None):
    # 一つにまとめる(body_ratio を指定すると体だけ軽くしてから合わせる)
    if body_ratio is not None and body_ratio < 1:
        dm = body.modifiers.new("dec", "DECIMATE")
        dm.ratio = body_ratio
        light = evaluated_copy(body, body.name + "_lo")
        bpy.data.objects.remove(body)
        body = light
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bm.from_mesh(detail.data)
    mesh = bpy.data.meshes.new(d["id"])
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(d["id"], mesh)
    bpy.context.scene.collection.objects.link(obj)
    for p in mesh.polygons:
        p.use_smooth = True
    obj.scale = (scale, scale, scale)
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
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    if use_vertex:
        attr = nt.nodes.new("ShaderNodeVertexColor")
        attr.layer_name = "Col"
        col_out = attr.outputs["Color"]
    else:
        rgb = nt.nodes.new("ShaderNodeRGB")
        rgb.outputs[0].default_value = (*color, 1)
        col_out = rgb.outputs[0]
    # アニメの塗り: 影を「2段」にする(拡散光 → しきい値 → 影色/明るい色)
    diff = nt.nodes.new("ShaderNodeBsdfDiffuse")
    nt.links.new(col_out, diff.inputs["Color"])
    s2r = None
    emis = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(col_out, emis.inputs["Color"])
    emis.inputs["Strength"].default_value = 0.8
    add = nt.nodes.new("ShaderNodeAddShader")
    nt.links.new(diff.outputs[0], add.inputs[0])
    nt.links.new(emis.outputs[0], add.inputs[1])
    nt.links.new(add.outputs[0], out.inputs["Surface"])
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


def bake_texture(hi, lo, size, path):
    """hi(細かい・頂点色)の色を lo(軽い)のテクスチャに焼き込む"""
    # UV 展開
    select_only([lo], lo)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.004)
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
    bsdf.inputs["Roughness"].default_value = 0.6
    nt.nodes.active = tex
    lo.data.materials.append(mat)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 1
    sc.render.bake.use_selected_to_active = True
    sc.render.bake.cage_extrusion = 0.03
    sc.render.bake.max_ray_distance = 0.12
    sc.render.bake.margin = 6
    select_only([hi, lo], lo)
    bpy.ops.object.bake(type="EMIT")
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    return img


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


def export_fish(d, outdir, budget=7000):
    """1匹分を作り、軽いメッシュ・テクスチャ・輪郭線を返す"""
    body, detail = build_fish(d)
    # 細かい版(焼き込みの元)
    body_hi = body.copy()
    body_hi.data = body.data.copy()
    bpy.context.scene.collection.objects.link(body_hi)
    detail_hi = detail.copy()
    detail_hi.data = detail.data.copy()
    bpy.context.scene.collection.objects.link(detail_hi)
    hi = finish(body_hi, detail_hi, d, 1.0)
    hi.name = d["id"] + "_hi"
    # 軽い版: 体を予算に合わせて間引く
    detail_tris = tri_count(detail)
    body_tris = tri_count(body)
    ratio = max(0.03, min(1.0, (budget - detail_tris) / max(1, body_tris)))
    lo = finish(body, detail, d, 1.0, body_ratio=ratio)
    lo.name = d["id"]
    # 面の向きを外向きにそろえる(Roblox は裏面を描かない)
    bm = bmesh.new()
    bm.from_mesh(lo.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(lo.data)
    bm.free()
    size = 1024 if RARITY_ORDER[d["rarity"]] >= 3 else 512
    bake_texture(hi, lo, size, os.path.join(outdir, d["id"] + ".png"))
    bpy.data.objects.remove(hi)
    ol = make_outline(lo, 0.022)
    ol.name = d["id"] + "_Outline"
    ol.data.materials.clear()
    ol.data.materials.append(flat_material("Outline", (0.03, 0.02, 0.04)))
    facing_check(lo, True)
    facing_check(ol, False)
    dims = lo.dimensions
    return lo, ol, {"length": round(dims.y, 4), "width": round(dims.x, 4), "height": round(dims.z, 4), "tris": tri_count(lo), "outlineTris": tri_count(ol)}


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
    bg.inputs[1].default_value = 0.25
    sc.world = world
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 1.2
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


def aim_camera(cam, objs, shape):
    pts = []
    for o in objs:
        verts = list(o.data.vertices)
        for v in verts[:: max(1, len(verts) // 1500)]:
            pts.append(o.matrix_world @ v.co)
    mn = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    mx = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    center = (mn + mx) / 2
    radius = (mx - mn).length / 2
    if shape == "ray":
        direction = Vector((0.45, 0.85, 0.9)).normalized()
    else:
        direction = Vector((1.0, 0.75, 0.32)).normalized()
    dist = radius / math.tan(math.atan(18 / cam.data.lens)) * 1.05
    cam.location = center + direction * dist
    look = (center - cam.location).normalized()
    cam.rotation_euler = look.to_track_quat("-Z", "Y").to_euler()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--defs", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--ids", default="")
    ap.add_argument("--render", action="store_true")
    ap.add_argument("--res", type=int, default=480)
    ap.add_argument("--export", action="store_true", help="Roblox 用に全魚を1つの GLB に書き出す")
    ap.add_argument("--luau", default="", help="大きさの表を書き出す Config/FishMeshes.luau のパス")
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    a = ap.parse_args(argv)
    defs = json.load(open(a.defs))
    if isinstance(defs, dict) and "fish" in defs:  # tools/export_fish.luau の出力をそのまま使える
        defs = defs["fish"]
    ids = [x for x in a.ids.split(",") if x]
    os.makedirs(a.out, exist_ok=True)
    if a.export:
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
        ol = make_outline(obj, 0.022)
        obj.data.materials.append(toon_material("toon"))
        ol.data.materials.append(ink_material("ink", (0.08, 0.05, 0.1)))
        tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
        print(f"{d['id']}: {tris} tris body+detail, outline {sum(len(p.vertices) - 2 for p in ol.data.polygons)}")
        if a.render:
            aim_camera(cam, [obj], d["shape"])
            bpy.context.scene.render.filepath = os.path.join(a.out, d["id"] + ".png")
            bpy.ops.render.render(write_still=True)


def run_export(defs, ids, out):
    """全魚を1つのシーンに並べて GLB に書き出す(Studio の「3D をインポート」1回で全部入る)"""
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
    select_only(keep, keep[0])
    path = os.path.join(out, "YokaiFishMeshes.glb")
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_image_format="JPEG",
        export_jpeg_quality=90,
        export_materials="EXPORT",
        export_vertex_color="NONE",
    )
    json.dump(manifest, open(os.path.join(out, "manifest.json"), "w"), indent=1)
    print("exported", path, os.path.getsize(path) // 1024, "KB")
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
