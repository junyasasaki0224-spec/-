"""バトルの水中の舞台(tools/battle/export_battle.luau の JSON)と、本物の魚の3Dモデルを Blender で絵にする。
ゲームと同じ組み立てコード・同じカメラの計算・同じ魚のメッシュ(assets/fish/YokaiFishMeshes.glb)を使う。
Roblox の光そのものではないが(霧・ブルーム・粒子は近似)、立体の見え方・配置・カメラの確認に使う。

  python tools/battle/render_battle.py build/battle.json build/battle_renders [--views battle,attack] [--res 1280] [--samples 48]
"""

import argparse
import json
import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "map"))
import render_map as RM  # noqa: E402  (部品のメッシュ化と材質は地図の描画と同じ)

GLB = os.path.join(HERE, "..", "..", "assets", "fish", "YokaiFishMeshes.glb")

# Roblox の座標(Y が上) → Blender(Z が上)
C = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))


def roblox_matrix(cf):
    """Roblox の CFrame(12個の数) → 4x4(Roblox の座標のまま)"""
    x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf
    return Matrix(((r00, r01, r02, x), (r10, r11, r12, y), (r20, r21, r22, z), (0, 0, 0, 1)))


def to_blender(m, local_is_roblox):
    """Roblox の CFrame を Blender の物の行列へ。
    local_is_roblox=True: 物の中の座標も Roblox 流(カメラ。-Z が前、+Y が上で同じ)
    False: 物の中の座標が Blender 流(glTF から読んだメッシュは読み込み時に Y 上 → Z 上に直されている)"""
    c4 = C.to_4x4()
    return c4 @ m if local_is_roblox else c4 @ m @ c4.inverted()


def underwater_world(fog):
    sc = bpy.context.scene
    world = bpy.data.worlds.new("sea")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (*RM.to_lin(fog["color"]), 1)
    bg.inputs["Strength"].default_value = 1.8
    sc.world = world


def setup(res, samples):
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    sc.cycles.use_denoising = True
    sc.cycles.volume_step_rate = 4.0
    sc.render.resolution_x = res
    sc.render.resolution_y = int(res * 9 / 16)
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Medium High Contrast"
    sc.view_settings.exposure = 0.2
    # 太陽は真上近く(水面から差し込む)
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 4.0
    sun.color = (0.85, 0.97, 1.0)
    sun.angle = math.radians(6)
    so = bpy.data.objects.new("sun", sun)
    so.rotation_euler = (math.radians(14), math.radians(8), 0)
    sc.collection.objects.link(so)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    return cam


def fog_volume(fog, size=420, height=80):
    """水の濁り(ゲームの FogStart/FogEnd の代わりに、うすい青の霧)"""
    bpy.ops.mesh.primitive_cube_add(location=(0, 0, height / 2 - 2))
    box = bpy.context.active_object
    box.name = "Water"
    box.scale = (size / 2, size / 2, height / 2)
    mat = bpy.data.materials.new("WaterVolume")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    vol = nt.nodes.new("ShaderNodeVolumePrincipled")
    vol.inputs["Density"].default_value = 0.011
    vol.inputs["Color"].default_value = (*RM.to_lin(fog["color"]), 1)
    vol.inputs["Anisotropy"].default_value = 0.55
    vol.inputs["Absorption Color"].default_value = (0.25, 0.75, 0.85, 1)
    nt.links.new(vol.outputs["Volume"], out.inputs["Volume"])
    box.data.materials.append(mat)
    box.visible_shadow = False


def beam_material():
    mat = bpy.data.materials.new("LightShaft")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    mix = nt.nodes.new("ShaderNodeMixShader")
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (0.75, 0.95, 1.0, 1)
    em.inputs["Strength"].default_value = 1.0
    uv = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    # 上(v=0)は少し見え、下へ行くほど消える(ゲームの Transparency 0.6 → 1)
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = (0.26, 0.26, 0.26, 1)
    ramp.color_ramp.elements[1].position = 1.0
    ramp.color_ramp.elements[1].color = (0, 0, 0, 1)
    nt.links.new(uv.outputs["UV"], sep.inputs["Vector"])
    nt.links.new(sep.outputs["Y"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], mix.inputs["Fac"])
    nt.links.new(tr.outputs["BSDF"], mix.inputs[1])
    nt.links.new(em.outputs["Emission"], mix.inputs[2])
    nt.links.new(mix.outputs["Shader"], out.inputs["Surface"])
    return mat


def add_beams(beams, eye, mat):
    """光の筋: カメラの方を向いた板(ゲームの Beam の FaceCamera と同じ)"""
    for b in beams:
        top, bottom = RM.rb(b["top"]), RM.rb(b["bottom"])
        axis = (bottom - top).normalized()
        mid = (top + bottom) / 2
        side = axis.cross((eye - mid).normalized()).normalized()
        vs = [top - side * b["w0"] / 2, top + side * b["w0"] / 2, bottom + side * b["w1"] / 2, bottom - side * b["w1"] / 2]
        me = bpy.data.meshes.new("shaft")
        me.from_pydata([tuple(v) for v in vs], [], [(0, 1, 2, 3)])
        uv = me.uv_layers.new()
        for loop, (u, v) in zip(uv.data, ((0, 0), (1, 0), (1, 1), (0, 1))):
            loop.uv = (u, v)
        me.materials.append(mat)
        ob = bpy.data.objects.new("shaft", me)
        ob.visible_shadow = False
        bpy.context.scene.collection.objects.link(ob)


def add_lights(lights):
    for L in lights:
        li = bpy.data.lights.new("pl", "POINT")
        li.color = tuple(L["color"])
        # Roblox の明るさと届く距離 → だいたいの強さ
        li.energy = L.get("brightness", 1) * L["range"] ** 2 * 1.6
        li.shadow_soft_size = 0.4
        ob = bpy.data.objects.new("pl", li)
        ob.location = RM.rb(L["pos"])
        bpy.context.scene.collection.objects.link(ob)


def load_fish():
    """GLB を1回だけ読み、魚ごとの物を名前で引けるようにする(輪郭線は描かない)"""
    before = set(bpy.data.objects)
    # 魚は2つの GLB に分けてある(沼・湖 / 川・海)
    for path in (GLB, GLB.replace("YokaiFishMeshes.glb", "YokaiFishMeshes_RiverSea.glb")):
        if os.path.exists(path):
            bpy.ops.import_scene.gltf(filepath=path)
    fish = {}
    for o in set(bpy.data.objects) - before:
        if o.type != "MESH":
            continue
        if o.name.endswith("_Outline"):
            o.hide_render = True
            o.visible_shadow = False
            continue
        fish[o.name] = o
        o.hide_render = True
    return fish


def place_fish(fish, spec):
    src = fish.get(spec["id"])
    if src is None:
        print("no mesh for", spec["id"])
        return None
    ob = src.copy()
    bpy.context.scene.collection.objects.link(ob)
    ob.hide_render = False
    # メッシュの中心と大きさ(Roblox の向きの軸で測る)
    corners = [C.inverted() @ Vector(c) for c in ob.bound_box]
    lo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
    hi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
    center = (lo + hi) / 2
    longest = max(hi - lo)
    s = spec["length"] / longest
    m = roblox_matrix(spec["cf"]) @ Matrix.Scale(s, 4) @ Matrix.Translation(-center)
    ob.matrix_world = to_blender(m, local_is_roblox=False)
    return ob


def key_light(view):
    """ゲームと同じ、カメラについて回るやわらかい光(カメラの少し上・前)"""
    m = roblox_matrix(view["camera"]) @ Matrix.Translation((0, 5, -4))
    li = bpy.data.lights.new("key", "POINT")
    li.color = (1.0, 0.96, 0.9)
    li.energy = 1.4 * 46**2 * 1.6
    li.shadow_soft_size = 2
    ob = bpy.data.objects.new("key", li)
    ob.matrix_world = to_blender(m, local_is_roblox=True)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def aim(cam, view):
    cam.matrix_world = to_blender(roblox_matrix(view["camera"]), local_is_roblox=True)
    cam.data.sensor_fit = "VERTICAL"
    cam.data.angle = math.radians(view["fov"])
    cam.data.clip_end = 600


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("json")
    ap.add_argument("out")
    ap.add_argument("--views", default="")
    ap.add_argument("--res", type=int, default=1280)
    ap.add_argument("--samples", type=int, default=48)
    a = ap.parse_args(argv)
    data = json.load(open(a.json))
    os.makedirs(a.out, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    cam = setup(a.res, a.samples)
    underwater_world(data["fog"])
    for me, kind, alpha in RM.part_meshes(data["parts"]):
        me.materials.append(RM.vcol_material(me.name, kind, alpha))
        ob = bpy.data.objects.new(me.name, me)
        bpy.context.scene.collection.objects.link(ob)
        if kind == "glass":
            ob.visible_shadow = False  # 水面や泡は影を作らない(ゲームでも CastShadow=false)
    add_lights(data["lights"])
    fog_volume(data["fog"])
    fish = load_fish()
    shaft_mat = beam_material()
    wanted = set(filter(None, a.views.split(",")))
    for view in data["views"]:
        if wanted and view["name"] not in wanted:
            continue
        placed = [place_fish(fish, f) for f in view["fish"]]
        aim(cam, view)
        shafts_before = set(bpy.data.objects)
        key_light(view)
        add_beams(data["beams"], cam.matrix_world.translation, shaft_mat)
        bpy.context.scene.render.filepath = os.path.join(a.out, view["name"] + ".png")
        bpy.ops.render.render(write_still=True)
        print("rendered", view["name"])
        for o in placed + list(set(bpy.data.objects) - shafts_before):
            if o is not None:
                bpy.data.objects.remove(o, do_unlink=True)


if __name__ == "__main__":
    main()
