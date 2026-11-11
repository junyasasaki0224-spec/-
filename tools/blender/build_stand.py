# ============================================================
#  Blender (bpy) によるスタンドのモジュール(幅10mの1スパン)生成
#   階段状の客席(1階・上層)、ガラスのカーテンウォールと方立、スラブ、
#   片持ちの大屋根と鉄骨梁・母屋、柱、照明、通路口、背面棟
#  Cyclesでアンビエントオクルージョンを頂点に焼き込み、UV.x に格納して glTF 出力。
#  ゲーム側でこのスパンを横に並べてスタンド全体を組む。
#  実行: python tools/blender/build_stand.py assets/stand.glb [プレビュー出力先]
#  座標: X=スタンドの長手, -Y=奥行き(コースから離れる方向), Z=高さ
# ============================================================
import sys, os, math
import numpy as np
import bpy
from mathutils import Vector

OUT = sys.argv[1] if len(sys.argv) > 1 else 'assets/stand.glb'
PREVIEW = sys.argv[2] if len(sys.argv) > 2 else None
BW = 10.0  # スパン幅
X0, X1 = -BW / 2, BW / 2


class Builder:
    def __init__(self):
        self.v, self.f, self.m = [], [], []

    def quad(self, p0, p1, p3, mat, cell=2.5):
        """p0→p1, p0→p3 を辺とする四角形。法線は (p1-p0)×(p3-p0)。AO用に格子分割"""
        p0, p1, p3 = (np.asarray(p, float) for p in (p0, p1, p3))
        nu = max(1, int(math.ceil(np.linalg.norm(p1 - p0) / cell)))
        nv = max(1, int(math.ceil(np.linalg.norm(p3 - p0) / cell)))
        b = len(self.v)
        for j in range(nv + 1):
            for i in range(nu + 1):
                self.v.append(tuple(p0 + (p1 - p0) * i / nu + (p3 - p0) * j / nv))
        for j in range(nv):
            for i in range(nu):
                a = b + j * (nu + 1) + i
                self.f.append((a, a + 1, a + nu + 2, a + nu + 1)); self.m.append(mat)

    def box(self, x0, x1, d0, d1, z0, z1, mat, faces='fbtdlr', cell=2.5):
        ya, yb = -d0, -d1  # 手前(コース側) / 奥
        if 'f' in faces: self.quad((x1, ya, z0), (x0, ya, z0), (x1, ya, z1), mat, cell)
        if 'b' in faces: self.quad((x0, yb, z0), (x1, yb, z0), (x0, yb, z1), mat, cell)
        if 't' in faces: self.quad((x0, yb, z1), (x1, yb, z1), (x0, ya, z1), mat, cell)
        if 'd' in faces: self.quad((x0, ya, z0), (x1, ya, z0), (x0, yb, z0), mat, cell)
        if 'r' in faces: self.quad((x1, yb, z0), (x1, ya, z0), (x1, yb, z1), mat, cell)
        if 'l' in faces: self.quad((x0, ya, z0), (x0, yb, z0), (x0, ya, z1), mat, cell)


LOW = dict(n=22, d0=0.6, z0=0.6, tread=0.68, riser=0.34)       # 1階スタンド
UP = dict(n=24, d0=10.5, z0=20.0, tread=0.79, riser=0.50)      # 上層スタンド
ROOF = dict(d0=-5.0, zf=41.0, d1=44.5, zb=38.4, th=0.5)


def roof_z(d):
    t = (d - ROOF['d0']) / (ROOF['d1'] - ROOF['d0'])
    return ROOF['zf'] + (ROOF['zb'] - ROOF['zf']) * t


def bay():
    B = Builder()
    # --- 客席(蹴上げ+踏面) と座席の背 ---
    for T in (LOW, UP):
        for i in range(T['n']):
            d = T['d0'] + i * T['tread']; za = T['z0'] + i * T['riser']; zb = za + T['riser']
            B.quad((X1, -d, za), (X0, -d, za), (X1, -d, zb), 'step')
            B.quad((X0, -(d + T['tread']), zb), (X1, -(d + T['tread']), zb), (X0, -d, zb), 'step')
            for xa, xb in ((X0 + 0.7, -0.6), (0.6, X1 - 0.7)):   # 中央と両端は通路
                B.box(xa, xb, d + T['tread'] - 0.2, d + T['tread'] - 0.1, zb, zb + 0.42, 'seat', 'ft', cell=9)
    # 最前列の壁
    B.box(X0, X1, 0.25, 0.6, 0.0, 1.0, 'concrete', 'ft')
    B.quad((X1, -0.3, 1.0), (X0, -0.3, 1.0), (X1, -0.3, 1.45), 'glassrail', 9)
    # --- コンコース壁と通路口 ---
    dT = LOW['d0'] + LOW['n'] * LOW['tread']          # 1階席の最上段奥
    zT = LOW['z0'] + LOW['n'] * LOW['riser']
    B.quad((X0, -17.0, zT), (X1, -17.0, zT), (X0, -dT, zT), 'floor')   # 通路
    for xa, xb in ((X0, -1.4), (1.4, X1)):
        B.quad((xb, -17.0, zT), (xa, -17.0, zT), (xb, -17.0, 11.0), 'concrete')
    B.quad((1.4, -17.0, zT + 2.3), (-1.4, -17.0, zT + 2.3), (1.4, -17.0, 11.0), 'concrete')
    B.quad((1.4, -17.6, zT), (-1.4, -17.6, zT), (1.4, -17.6, zT + 2.3), 'dark', 9)   # 通路口の奥
    B.box(-1.4, 1.4, 17.0, 17.6, zT, zT + 2.3, 'concrete', 'lr')
    # --- スラブ・ガラス・方立 (2層) ---
    for zs in (11.0, 15.0):
        B.box(X0, X1, 15.4, 17.3, zs, zs + 0.5, 'slab', 'ftd')
        B.quad((X1, -15.5, zs + 0.5), (X0, -15.5, zs + 0.5), (X1, -15.5, zs + 1.55), 'glassrail', 9)
        B.box(X0, X1, 15.45, 15.55, zs + 1.55, zs + 1.62, 'mullion', 'ftd', cell=9)
        B.quad((X1, -17.0, zs + 0.5), (X0, -17.0, zs + 0.5), (X1, -17.0, zs + 4.0), 'glass')
        for xm in (X0, -2.5, 0.0, 2.5):
            B.box(xm - 0.06, xm + 0.06, 16.82, 17.0, zs + 0.5, zs + 4.0, 'mullion', 'flr', cell=9)
        B.box(X0, X1, 16.86, 17.0, zs + 2.2, zs + 2.3, 'mullion', 'ftd', cell=9)
    # --- 上層の張り出し: 軒裏と鼻先 ---
    B.quad((X0, -UP['d0'], 19.5), (X1, -UP['d0'], 19.5), (X0, -17.0, 19.5), 'soffit')
    B.quad((X1, -UP['d0'], 19.5), (X0, -UP['d0'], 19.5), (X1, -UP['d0'], 21.3), 'slab')
    B.quad((X0, -(UP['d0'] + 0.25), 21.3), (X1, -(UP['d0'] + 0.25), 21.3), (X0, -UP['d0'], 21.3), 'slab', 9)
    B.quad((X1, -17.0, 19.0), (X0, -17.0, 19.0), (X1, -17.0, 19.5), 'slab', 9)
    # --- 上層の背後: 放送席のガラス帯 ---
    dU = UP['d0'] + UP['n'] * UP['tread']; zU = UP['z0'] + UP['n'] * UP['riser']
    B.quad((X1, -dU, zU), (X0, -dU, zU), (X1, -dU, zU + 1.2), 'concrete')
    B.quad((X1, -dU, zU + 1.2), (X0, -dU, zU + 1.2), (X1, -dU, zU + 3.6), 'glass')
    B.quad((X1, -dU, zU + 3.6), (X0, -dU, zU + 3.6), (X1, -dU, roof_z(dU) - 0.5), 'concrete')
    for xm in (X0, 0.0):
        B.box(xm - 0.06, xm + 0.06, dU - 0.15, dU, zU + 1.2, zU + 3.6, 'mullion', 'flr', cell=9)
    # --- 背面棟 ---
    B.box(X0, X1, dU, 46.0, 0.0, 36.5, 'concrete', 'bt', cell=3.0)
    for k in range(8):
        B.quad((X0 + 0.6, -46.04, 2.6 + k * 4.2), (X1 - 0.6, -46.04, 2.6 + k * 4.2), (X0 + 0.6, -46.04, 4.6 + k * 4.2), 'glass', 9)
    # --- 大屋根 ---
    d0, d1, th = ROOF['d0'], ROOF['d1'], ROOF['th']
    B.quad((X0, -d1, roof_z(d1)), (X1, -d1, roof_z(d1)), (X0, -d0, roof_z(d0)), 'roof_top')
    B.quad((X0, -d0, roof_z(d0) - th), (X1, -d0, roof_z(d0) - th), (X0, -d1, roof_z(d1) - th), 'roof_under')
    B.quad((X1, -d0, roof_z(d0) - th - 0.5), (X0, -d0, roof_z(d0) - th - 0.5), (X1, -d0, roof_z(d0) + 0.15), 'slab', 9)   # 鼻先
    # 主梁(先端ほど薄い)
    gx0, gx1 = X0 - 0.22, X0 + 0.22
    for da, db in ((d0, 12.0), (12.0, 30.0), (30.0, d1)):
        ha = 0.7 + 2.6 * min(1, (da - d0) / (30 - d0)); hb = 0.7 + 2.6 * min(1, (db - d0) / (30 - d0))
        za, zb = roof_z(da) - th, roof_z(db) - th
        for x, sgn in ((gx1, 1), (gx0, -1)):
            p0, p1, p3 = (x, -da, za - ha), (x, -db, zb - hb), (x, -da, za)
            if sgn > 0: B.quad((x, -db, zb - hb), (x, -da, za - ha), (x, -db, zb), 'steel')
            else: B.quad(p0, p1, p3, 'steel')
        B.quad((gx0, -da, za - ha), (gx1, -da, za - ha), (gx0, -db, zb - hb), 'steel')
    # 母屋
    for dk in np.arange(d0 + 3, d1 - 1, 5.5):
        z = roof_z(dk) - th
        B.box(X0, X1, dk, dk + 0.28, z - 0.42, z, 'steel', 'fbd', cell=9)
    # 柱
    for dc in (30.6, 43.6):
        B.box(X0 - 0.6, X0 + 0.6, dc - 0.6, dc + 0.6, 0.0, roof_z(dc) - th - 3.0, 'concrete', 'fblr', cell=3.0)
    # 照明
    for xl in (-3.75, -1.25, 1.25, 3.75):
        z = roof_z(-3.0) - th
        B.box(xl - 0.45, xl + 0.45, -3.3, -2.7, z - 0.32, z - 0.02, 'lamp_body', 'fblr', cell=9)
        B.quad((xl - 0.42, 3.27, z - 0.33), (xl + 0.42, 3.27, z - 0.33), (xl - 0.42, 2.73, z - 0.33), 'light', 9)
    return B


def to_object(name, B, mats):
    me = bpy.data.meshes.new(name)
    me.from_pydata(B.v, [], B.f); me.update()
    names = sorted(set(B.m))
    for n in names:
        me.materials.append(mats[n])
    for p, n in zip(me.polygons, B.m):
        p.material_index = names.index(n)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    cols = {'step': (0.62, 0.62, 0.6), 'seat': (0.1, 0.35, 0.3), 'concrete': (0.78, 0.76, 0.72), 'floor': (0.5, 0.5, 0.5), 'dark': (0.03, 0.03, 0.04),
            'slab': (0.9, 0.9, 0.88), 'glass': (0.35, 0.5, 0.62), 'glassrail': (0.6, 0.75, 0.8), 'mullion': (0.7, 0.72, 0.74), 'soffit': (0.45, 0.45, 0.46),
            'roof_top': (0.92, 0.92, 0.92), 'roof_under': (0.72, 0.74, 0.76), 'steel': (0.88, 0.88, 0.9), 'lamp_body': (0.3, 0.3, 0.32), 'light': (1, 0.97, 0.85)}
    mats = {}
    for k, c in cols.items():
        m = bpy.data.materials.new(k); m.diffuse_color = (*c, 1); mats[k] = m
    B = bay()
    ob = to_object('Bay', B, mats)
    # 隣のスパンと地面を遮蔽物として置き、中央スパンにAOを焼く
    occ = []
    for dx in (-BW, BW):
        o = to_object('occ', B, mats); o.location.x = dx; occ.append(o)
    bpy.ops.mesh.primitive_plane_add(size=400, location=(0, 0, 0)); ground = bpy.context.active_object
    me = ob.data
    attr = me.color_attributes.new('AO', 'FLOAT_COLOR', 'POINT')
    me.color_attributes.active_color = attr
    sc.render.engine = 'CYCLES'; sc.cycles.device = 'CPU'; sc.cycles.samples = 96
    w = bpy.data.worlds.new('W'); sc.world = w
    try:
        w.light_settings.distance = 22.0
    except Exception as e:
        print('ao distance', e)
    bpy.ops.object.select_all(action='DESELECT')
    ob.select_set(True); bpy.context.view_layer.objects.active = ob
    sc.render.bake.target = 'VERTEX_COLORS'
    bpy.ops.object.bake(type='AO')
    ao = np.array([c.color[0] for c in attr.data])
    print('AO baked: min %.2f mean %.2f max %.2f  verts %d tris %d' % (ao.min(), ao.mean(), ao.max(), len(me.vertices), sum(len(p.vertices) - 2 for p in me.polygons)))
    uv = me.uv_layers.new(name='UVMap')
    for li, loop in enumerate(me.loops):
        uv.data[li].uv = (float(ao[loop.vertex_index]), 0.0)
    if PREVIEW:
        render_preview(PREVIEW, ob, occ, mats)
    for o in occ + [ground]:
        bpy.data.objects.remove(o)
    os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_yup=True, export_texcoords=True, export_normals=True, export_materials='EXPORT')
    print('exported', OUT, os.path.getsize(OUT) // 1024, 'KB')


def render_preview(outdir, ob, occ, mats):
    sc = bpy.context.scene
    sc.cycles.samples = 32; sc.view_settings.view_transform = 'Standard'
    sc.render.resolution_x = 1200; sc.render.resolution_y = 700
    w = sc.world; w.use_nodes = True
    w.node_tree.nodes['Background'].inputs[0].default_value = (0.6, 0.75, 1.0, 1); w.node_tree.nodes['Background'].inputs[1].default_value = 0.8
    sun = bpy.data.objects.new('Sun', bpy.data.lights.new('Sun', 'SUN')); sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(-40), 0, math.radians(25)); sc.collection.objects.link(sun)
    cam = bpy.data.objects.new('Cam', bpy.data.cameras.new('Cam')); sc.collection.objects.link(cam); sc.camera = cam; cam.data.lens = 28
    for nm, pos, tgt in (('front', (-16, 38, 9), (0, -10, 18)), ('low', (-9, 16, 2.0), (2, -12, 16))):
        cam.location = pos
        cam.rotation_euler = (Vector(tgt) - Vector(pos)).to_track_quat('-Z', 'Y').to_euler()
        sc.render.filepath = f'{outdir}/stand_{nm}.png'
        bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(sun); bpy.data.objects.remove(cam)


build()
