"""tools/map/export_map.luau の JSON(地形の操作とパーツ)を Blender で絵にする。
ゲームの見た目そのものではないが(Roblox の光・霧・水の揺れは無い)、配置・地形・景色の確認に使う。

  python tools/map/render_map.py build/map.json build/map_renders [--views swamp_top,swamp_spawn] [--res 1280] [--night]

地形は 2 スタッドの格子の高さ(と水面)に直して、なめらかな面にする。
"""

import argparse
import json
import math
import os
import sys

import bpy
import bmesh
import numpy as np
from mathutils import Vector

CELL = 2.0

# Roblox の地形の標準色(SetMaterialColor で変えたものは JSON の色を使う)
TERRAIN_COLORS = {
    "Grass": (106, 127, 63),
    "LeafyGrass": (115, 132, 74),
    "Mud": (58, 46, 36),
    "Rock": (102, 108, 111),
    "Ground": (102, 92, 59),
    "Sand": (143, 126, 95),
    "Slate": (63, 127, 107),
    "Cobblestone": (132, 123, 90),
    "Pavement": (148, 148, 140),
    "WoodPlanks": (139, 109, 79),
    "Snow": (195, 199, 218),
    "Basalt": (30, 30, 37),
    "Limestone": (206, 173, 148),
    "Sandstone": (137, 90, 71),
    "Salt": (198, 189, 181),
    "Asphalt": (115, 123, 107),
    "Brick": (138, 86, 62),
    "Concrete": (127, 102, 63),
}


def to_lin(c):
    return tuple(((x / 12.92) if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4) for x in c)


def rb(v):
    """Roblox の座標(Y が上) → Blender(Z が上)"""
    return Vector((v[0], -v[2], v[1]))


# ---------------------------------------------------------------------------
# 地形: 操作を順に当てて、格子ごとの「地面の高さ・材質・水面」を作る


class Grid:
    def __init__(self, fills):
        xs, zs = [], []
        for f in fills:
            if f["kind"] == "ball":
                c, r = f["center"], f["r"]
                xs += [c[0] - r, c[0] + r]
                zs += [c[2] - r, c[2] + r]
            else:
                c = f["cf"]
                s = f.get("size") or [f["r"] * 2, f["h"], f["r"] * 2]
                rad = math.hypot(s[0], s[2]) / 2
                xs += [c[0] - rad, c[0] + rad]
                zs += [c[2] - rad, c[2] + rad]
        self.x0, self.z0 = math.floor(min(xs)), math.floor(min(zs))
        self.nx = int(math.ceil((max(xs) - self.x0) / CELL)) + 1
        self.nz = int(math.ceil((max(zs) - self.z0) / CELL)) + 1
        self.top = np.full((self.nx, self.nz), -1e9)
        self.water = np.full((self.nx, self.nz), -1e9)
        self.mat = np.full((self.nx, self.nz), "", dtype=object)
        self.cx = self.x0 + (np.arange(self.nx) + 0.5) * CELL
        self.cz = self.z0 + (np.arange(self.nz) + 0.5) * CELL

    def window(self, minx, maxx, minz, maxz):
        i0 = max(0, int((minx - self.x0) / CELL) - 1)
        i1 = min(self.nx, int((maxx - self.x0) / CELL) + 2)
        j0 = max(0, int((minz - self.z0) / CELL) - 1)
        j1 = min(self.nz, int((maxz - self.z0) / CELL) + 2)
        return i0, i1, j0, j1

    def apply(self, f):
        if f["kind"] == "ball":
            c, r = f["center"], f["r"]
            i0, i1, j0, j1 = self.window(c[0] - r, c[0] + r, c[2] - r, c[2] + r)
            X, Z = np.meshgrid(self.cx[i0:i1], self.cz[j0:j1], indexing="ij")
            d2 = (X - c[0]) ** 2 + (Z - c[2]) ** 2
            inside = d2 < r * r
            h = np.sqrt(np.maximum(0, r * r - d2))
            self._column(i0, i1, j0, j1, inside, c[1] - h, c[1] + h, f["mat"])
            return
        c = f["cf"]
        if f["kind"] == "cylinder":
            size = [f["r"] * 2, f["h"], f["r"] * 2]
        else:
            size = f["size"]
        pos = np.array(c[:3])
        R = np.array(c[3:]).reshape(3, 3)
        rad = math.hypot(size[0], size[2]) / 2
        i0, i1, j0, j1 = self.window(pos[0] - rad, pos[0] + rad, pos[2] - rad, pos[2] + rad)
        X, Z = np.meshgrid(self.cx[i0:i1], self.cz[j0:j1], indexing="ij")
        # 部品の向きでの位置(地形の操作はほぼ水平なので、高さの軸は Y のまま)
        dx, dz = X - pos[0], Z - pos[2]
        lx = R[0, 0] * dx + R[2, 0] * dz
        lz = R[0, 2] * dx + R[2, 2] * dz
        if f["kind"] == "cylinder":
            inside = lx * lx + lz * lz <= (size[0] / 2) ** 2
        else:
            inside = (np.abs(lx) <= size[0] / 2 + 1e-6) & (np.abs(lz) <= size[2] / 2 + 1e-6)
        bottom = np.full(inside.shape, pos[1] - size[1] / 2)
        top = np.full(inside.shape, pos[1] + size[1] / 2)
        if f["kind"] == "wedge":
            # 斜めの面: 前(-Z)で低く、後ろ(+Z)で高い
            u = np.clip((lz + size[2] / 2) / size[2], 0, 1)
            top = bottom + size[1] * u
        self._column(i0, i1, j0, j1, inside, bottom, top, f["mat"])

    def _column(self, i0, i1, j0, j1, inside, bottom, top, mat):
        T = self.top[i0:i1, j0:j1]
        W = self.water[i0:i1, j0:j1]
        M = self.mat[i0:i1, j0:j1]
        if mat == "Air":
            cut = inside & (T > bottom - 1e-6) & (T <= top + 1e-6)
            T[cut] = bottom[cut]
            wc = inside & (W > bottom)
            W[wc] = bottom[wc]
        elif mat == "Water":
            W[inside] = np.maximum(W[inside], top[inside])
        else:
            up = inside & (top >= T - 1e-6)
            T[up] = top[up]
            M[up] = mat


def terrain_meshes(grid, colors):
    has = grid.top > -1e8
    # 地面: 格子の中心を頂点にして、4つそろった所に面を張る
    bm = bmesh.new()
    col = bm.loops.layers.float_color.new("Col")
    verts = {}
    for i in range(grid.nx):
        for j in range(grid.nz):
            if has[i, j]:
                verts[i, j] = bm.verts.new(rb((grid.cx[i], grid.top[i, j], grid.cz[j])))
    for i in range(grid.nx - 1):
        for j in range(grid.nz - 1):
            q = [(i, j), (i, j + 1), (i + 1, j + 1), (i + 1, j)]
            if all(k in verts for k in q):
                f = bm.faces.new([verts[k] for k in q])
                for loop, k in zip(f.loops, q):
                    c = colors.get(grid.mat[k], (0.4, 0.4, 0.4))
                    # 斜面は少し暗く、細かい揺らぎで単調にしない
                    jitter = 0.94 + 0.12 * ((hash(k) % 97) / 97)
                    loop[col] = (c[0] * jitter, c[1] * jitter, c[2] * jitter, 1)
    ground = bpy.data.meshes.new("Terrain")
    bm.to_mesh(ground)
    bm.free()
    # 水面
    bm = bmesh.new()
    wet = has & (grid.water > grid.top + 0.05)
    wet |= (~has) & (grid.water > -1e8)
    for i in range(grid.nx):
        for j in range(grid.nz):
            if wet[i, j]:
                x0, z0 = grid.x0 + i * CELL, grid.z0 + j * CELL
                y = grid.water[i, j]
                vs = [bm.verts.new(rb((x0 + a, y, z0 + b))) for a, b in ((0, 0), (0, CELL), (CELL, CELL), (CELL, 0))]
                bm.faces.new(vs)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=0.01)
    water = bpy.data.meshes.new("Water")
    bm.to_mesh(water)
    bm.free()
    return ground, water


# ---------------------------------------------------------------------------
# パーツ


def unit_shape(shape):
    """1x1x1 の形(Roblox の部品の中心が原点、Roblox の軸)の頂点と面"""
    if shape == "Ball":
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=0.5)
    elif shape == "Cylinder":
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=16, radius1=0.5, radius2=0.5, depth=1.0)
        # Blender の円柱は Z 軸 → Roblox の円柱は X 軸
        for v in bm.verts:
            x, y, z = v.co
            v.co = Vector((z, y, x))
    elif shape == "Wedge":
        bm = bmesh.new()
        p = [(-0.5, -0.5, -0.5), (0.5, -0.5, -0.5), (0.5, -0.5, 0.5), (-0.5, -0.5, 0.5), (-0.5, 0.5, 0.5), (0.5, 0.5, 0.5)]
        vs = [bm.verts.new(v) for v in p]
        for f in ((0, 1, 2, 3), (3, 2, 5, 4), (0, 4, 5, 1), (0, 3, 4), (1, 5, 2)):
            bm.faces.new([vs[k] for k in f])
    else:
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    vs = [tuple(v.co) for v in bm.verts]
    fs = [[v.index for v in f.verts] for f in bm.faces]
    bm.free()
    return vs, fs


SHAPES = {}

GLOWY = {"Neon"}
SHINY = {"Foil", "Glass", "Ice", "Metal", "DiamondPlate", "SmoothPlastic"}


def part_meshes(parts):
    """材質のまとまりごとに1つのメッシュへ(数千の部品でも軽い)"""
    groups = {}
    for p in parts:
        alpha = p["alpha"]
        if p["mat"] == "ForceField":
            alpha = max(alpha, 0.55)
        if alpha >= 0.97:
            continue
        kind = "neon" if p["mat"] in GLOWY else ("glass" if alpha > 0.05 or p["mat"] == "Glass" else ("shiny" if p["mat"] in SHINY else "matte"))
        if p["mat"] == "Foil":
            kind = "metal"
        key = (kind, round(alpha, 1))
        groups.setdefault(key, []).append(p)
    out = []
    for (kind, alpha), ps in groups.items():
        bm = bmesh.new()
        col = bm.loops.layers.float_color.new("Col")
        for p in ps:
            shape = p["shape"]
            if shape not in SHAPES:
                SHAPES[shape] = unit_shape(shape)
            vs, fs = SHAPES[shape]
            size = list(p["size"])
            if shape == "Ball":
                size = [min(size)] * 3
            elif shape == "Cylinder":
                d = min(size[1], size[2])
                size = [size[0], d, d]
            c = p["cf"]
            pos = np.array(c[:3])
            R = np.array(c[3:]).reshape(3, 3)
            lc = to_lin(p["color"])
            new = []
            for v in vs:
                lv = np.array(v) * size
                w = R @ lv + pos
                new.append(bm.verts.new(rb(w)))
            for f in fs:
                face = bm.faces.new([new[k] for k in f])
                for loop in face.loops:
                    loop[col] = (lc[0], lc[1], lc[2], 1)
        me = bpy.data.meshes.new(f"Parts_{kind}_{alpha}")
        bm.to_mesh(me)
        bm.free()
        out.append((me, kind, alpha))
    return out


# ---------------------------------------------------------------------------
# 材質・光・カメラ


def vcol_material(name, kind="matte", alpha=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = {"matte": 0.85, "shiny": 0.45, "metal": 0.3, "glass": 0.2, "neon": 0.5}[kind]
    if kind == "metal":
        bsdf.inputs["Metallic"].default_value = 0.9
    if kind == "neon":
        nt.links.new(attr.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 4.0
    if alpha > 0:
        bsdf.inputs["Alpha"].default_value = 1 - alpha
        mat.blend_method = "BLEND"
    return mat


def water_material(color):
    mat = bpy.data.materials.new("Water")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*to_lin(color), 1)
    bsdf.inputs["Roughness"].default_value = 0.08
    bsdf.inputs["Alpha"].default_value = 0.72
    bsdf.inputs["Specular IOR Level"].default_value = 0.6
    return mat


def setup_scene(res, night):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 24
    sc.cycles.use_denoising = True
    sc.render.resolution_x = res
    sc.render.resolution_y = int(res * 9 / 16)
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Medium High Contrast"
    sc.view_settings.exposure = 0.4 if night else -0.6
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    nt = world.node_tree
    bg = nt.nodes["Background"]
    sky = nt.nodes.new("ShaderNodeTexSky")
    sky.sky_type = "NISHITA"
    sky.sun_elevation = math.radians(-8 if night else 38)
    sky.sun_rotation = math.radians(150)
    sky.air_density = 1.4
    sky.dust_density = 2.5
    nt.links.new(sky.outputs["Color"], bg.inputs["Color"])
    # 夜も Roblox は月明かりと環境光(OutdoorAmbient)で真っ暗にはならない
    bg.inputs["Strength"].default_value = 0.12 if night else 0.35
    sc.world = world
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 0.55 if night else 3.2
    sun.color = (0.55, 0.65, 1.0) if night else (1.0, 0.95, 0.88)
    sun.angle = math.radians(2)
    so = bpy.data.objects.new("sun", sun)
    so.rotation_euler = (math.radians(52), 0, math.radians(150))
    sc.collection.objects.link(so)
    # 霧(Atmosphere の代わりに、うすい霧の箱)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    return cam


def add_fog(center, size, density):
    bpy.ops.mesh.primitive_cube_add(location=center)
    box = bpy.context.active_object
    box.scale = (size[0] / 2, size[1] / 2, size[2] / 2)
    mat = bpy.data.materials.new("Fog")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    vol = nt.nodes.new("ShaderNodeVolumePrincipled")
    vol.inputs["Density"].default_value = density
    vol.inputs["Color"].default_value = (0.78, 0.84, 0.88, 1)
    nt.links.new(vol.outputs["Volume"], out.inputs["Volume"])
    box.data.materials.append(mat)


def look(cam, eye, target, lens=24, ortho=None):
    cam.location = eye
    d = (target - eye).normalized()
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    if ortho:
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = ortho
    else:
        cam.data.type = "PERSP"
        cam.data.lens = lens
    cam.data.clip_end = 3000


def views(spots, ground_at):
    sw, vi = spots["swamp"], spots["nushi_lake"]

    def spot_pos(s, key):
        o = s["origin"]
        return (o["x"] + s[key]["x"], o["z"] + s[key]["z"])

    swc = spot_pos(sw, "water")
    vic = spot_pos(vi, "water")
    sws = spot_pos(sw, "spawn")
    vis = spot_pos(vi, "spawn")

    def eye(xz, up, back=(0, 0)):
        x, z = xz[0] + back[0], xz[1] + back[1]
        return rb((x, ground_at(x, z) + up, z))

    return {
        "swamp_top": dict(eye=rb((swc[0], 300, swc[1] + 0.01)), target=rb((swc[0], 0, swc[1])), ortho=250),
        "village_top": dict(eye=rb((vic[0], 300, vic[1] + 0.01)), target=rb((vic[0], 0, vic[1])), ortho=250),
        # 出現した時の画面(Roblox の標準カメラ: 頭の少し上・後ろ)
        "swamp_spawn": dict(eye=eye(sws, 10, (0, 12)), target=rb((swc[0], 2, swc[1] - 14)), lens=22),
        "village_spawn": dict(eye=eye(vis, 10, (0, 12)), target=rb((vic[0], 4, vic[1] - 10)), lens=22),
        "swamp_air": dict(eye=rb((swc[0] + 120, 95, swc[1] + 150)), target=rb((swc[0], 0, swc[1])), lens=26),
        "village_air": dict(eye=rb((vic[0] - 130, 95, vic[1] + 150)), target=rb((vic[0], 0, vic[1])), lens=26),
        "swamp_pier": dict(eye=rb((swc[0] - 8, 4.5, swc[1] + 30)), target=rb((swc[0] - 14, 2, swc[1] - 30)), lens=20),
        "village_huts": dict(eye=rb((vic[0], 4.5, vic[1] + 20)), target=rb((vic[0], 6, vic[1] - 60)), lens=20),
    }


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("json")
    ap.add_argument("out")
    ap.add_argument("--views", default="")
    ap.add_argument("--res", type=int, default=1280)
    ap.add_argument("--night", action="store_true")
    a = ap.parse_args(argv)
    data = json.load(open(a.json))
    os.makedirs(a.out, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    cam = setup_scene(a.res, a.night)

    grid = Grid(data["fills"])
    for f in data["fills"]:
        grid.apply(f)
    colors = {k: to_lin([x / 255 for x in v]) for k, v in TERRAIN_COLORS.items()}
    for k, v in data["materialColors"].items():
        colors[k] = to_lin(v)
    ground, water = terrain_meshes(grid, colors)
    for me, mat in ((ground, vcol_material("Ground", "matte")), (water, water_material(data["water"]["color"]))):
        ob = bpy.data.objects.new(me.name, me)
        bpy.context.scene.collection.objects.link(ob)
        me.materials.append(mat)
        for p in me.polygons:
            p.use_smooth = True
    for me, kind, alpha in part_meshes(data["parts"]):
        ob = bpy.data.objects.new(me.name, me)
        bpy.context.scene.collection.objects.link(ob)
        me.materials.append(vcol_material(me.name, kind, alpha))
    if a.night:
        for L in data["lights"]:
            li = bpy.data.lights.new("pl", "POINT")
            li.color = to_lin(L["color"])
            li.energy = 260 * (L["range"] / 10) ** 2
            li.shadow_soft_size = 0.3
            ob = bpy.data.objects.new("pl", li)
            ob.location = rb(L["pos"])
            bpy.context.scene.collection.objects.link(ob)

    def ground_at(x, z):
        i = int((x - grid.x0) / CELL)
        j = int((z - grid.z0) / CELL)
        if 0 <= i < grid.nx and 0 <= j < grid.nz and grid.top[i, j] > -1e8:
            return max(grid.top[i, j], grid.water[i, j])
        return 0.0

    vs = views(data["spots"], ground_at)
    names = [x for x in a.views.split(",") if x] or list(vs)
    for name in names:
        v = vs[name]
        look(cam, v["eye"], v["target"], v.get("lens", 24), v.get("ortho"))
        bpy.context.scene.render.filepath = os.path.join(a.out, name + (".night" if a.night else "") + ".png")
        bpy.ops.render.render(write_still=True)
        print("rendered", name)


if __name__ == "__main__":
    main()
