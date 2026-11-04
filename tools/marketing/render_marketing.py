"""Roblox のゲームのアイコンとサムネイルの「絵」を作る(題字は compose.py で重ねる)。
ゲームと同じ水中の舞台(tools/battle/export_battle.luau の JSON)に、本物の魚の3Dモデルを並べて Blender で描く。

  lune run tools/battle/export_battle.luau build/battle.json
  python tools/marketing/render_marketing.py build/battle.json build/marketing_raw [--only icon,thumb_collection] [--samples 64]
  python3 tools/marketing/compose.py build/marketing_raw assets/marketing      # 題字・大きさ(Pillow)
"""

import argparse
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "battle"))
sys.path.insert(0, os.path.join(HERE, "..", "map"))
import render_battle as RB  # noqa: E402
import render_map as RM  # noqa: E402



def orbit(focus, yaw, pitch, dist):
    """BattleArena.orbit と同じ(Roblox の座標の CFrame を 12 個の数で返す)"""
    cy, sy = math.cos(yaw), math.sin(yaw)
    cp, sp = math.cos(-pitch), math.sin(-pitch)
    # R = Ry(yaw) * Rx(-pitch)
    r = [
        [cy, sy * sp, sy * cp],
        [0, cp, -sp],
        [-sy, cy * sp, cy * cp],
    ]
    pos = [focus[i] + r[i][2] * dist for i in range(3)]
    return [pos[0], pos[1], pos[2], r[0][0], r[0][1], r[0][2], r[1][0], r[1][1], r[1][2], r[2][0], r[2][1], r[2][2]]


def fish_cf(pos, heading, turn=0.3):
    """BattleArena.fishYaw と同じ向き(頭 = -Z を heading の方へ。turn だけカメラの方へ)"""
    yaw = (-math.pi / 2 - turn) if heading > 0 else (math.pi / 2 + turn)
    c, s = math.cos(yaw), math.sin(yaw)
    return [pos[0], pos[1], pos[2], c, 0, s, 0, 1, 0, -s, 0, c]


SCENES = {
    # アイコン: 主役は提灯あんこう(水の中で灯りがともる)。正方形
    "icon": {
        "size": (1024, 1024),
        # 魚が真ん中より少し下(上に題字が入る)。顔と提灯の灯りが切れないよう引いて写す
        "camera": orbit((-0.9, 8.6, 0), 0.12, 0.1, 11.5),
        "fov": 44,
        "focus": 11.5,
        "fish": [{"id": "chochin_anko", "pos": (0, 7, 0), "heading": -1, "turn": 0.55, "length": 6}],
    },
    # 図鑑: いろいろな妖怪魚が並ぶ。奥に強い魚(湖の月読鯉・川の大はんざき)、手前に小さな魚(レアほど大きいのが一目で分かる)
    "thumb_collection": {
        "size": (1920, 1080),
        "camera": orbit((0, 8, 0), 0.0, 0.05, 27),
        "fov": 46,
        "focus": 26,
        "fish": [
            {"id": "tsukuyomi_koi", "pos": (7.5, 10.2, -5.5), "heading": -1, "turn": 0.35, "length": 10.5},
            {"id": "o_hanzaki", "pos": (-8.5, 10.2, -3.5), "heading": 1, "turn": 0.4, "length": 9},
            {"id": "chochin_anko", "pos": (-1.5, 6.4, 2), "heading": -1, "turn": 0.45, "length": 4.2},
            {"id": "furin_kingyo", "pos": (-7.5, 5.4, 3.5), "heading": 1, "turn": 0.6, "length": 3.2},
            {"id": "bake_fugu", "pos": (8.5, 5.4, 3), "heading": -1, "turn": 0.6, "length": 3.2},
            {"id": "kappa_koi", "pos": (-12.5, 4.4, 4), "heading": 1, "turn": 0.7, "length": 3.4},
            {"id": "raijin_namazu", "pos": (3.5, 5.0, 4.5), "heading": -1, "turn": 0.4, "length": 4.4},
        ],
    },
    # 海の大物: 奥に化け鯨、まん中に磯撫で(鮫)と金鯱、手前に小さな恵比寿鯛(大きさの差が一目で分かる)
    "thumb_sea": {
        "size": (1920, 1080),
        "camera": orbit((0, 9, 0), 0.0, 0.06, 28),
        "fov": 48,
        "focus": 24,
        "fish": [
            {"id": "bake_kujira", "pos": (5.5, 12.5, -9), "heading": -1, "turn": 0.3, "length": 17},
            {"id": "isonade", "pos": (-8, 8.5, -1), "heading": 1, "turn": 0.45, "length": 9},
            {"id": "kin_shachi", "pos": (9, 5.8, 2.5), "heading": -1, "turn": 0.5, "length": 7.5},
            {"id": "ebisu_dai", "pos": (-1.5, 5.2, 6), "heading": 1, "turn": 0.6, "length": 2.6},
        ],
    },
}


def main():
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    ap = argparse.ArgumentParser()
    ap.add_argument("json")
    ap.add_argument("out")
    ap.add_argument("--only", default="")
    ap.add_argument("--samples", type=int, default=64)
    a = ap.parse_args(argv)
    data = json.load(open(a.json))
    os.makedirs(a.out, exist_ok=True)
    wanted = set(filter(None, a.only.split(",")))

    bpy.ops.wm.read_factory_settings(use_empty=True)
    cam = RB.setup(1920, a.samples)
    RB.underwater_world(data["fog"])
    for me, kind, alpha in RM.part_meshes(data["parts"]):
        me.materials.append(RM.vcol_material(me.name, kind, alpha))
        ob = bpy.data.objects.new(me.name, me)
        bpy.context.scene.collection.objects.link(ob)
        if kind == "glass":
            ob.visible_shadow = False
    RB.add_lights(data["lights"])
    RB.fog_volume(data["fog"])
    fish = RB.load_fish()
    shaft_mat = RB.beam_material()
    sc = bpy.context.scene

    # 舞台の場面(戦い・ボス)も、そのまま大きく描く
    scenes = dict(SCENES)
    for v in data["views"]:
        if v["name"] in ("attack", "boss"):
            scenes["thumb_" + v["name"]] = {"size": (1920, 1080), "view": v, "focus": 20 if v["name"] == "attack" else 30}

    for name, scene in scenes.items():
        if wanted and name not in wanted:
            continue
        sc.render.resolution_x, sc.render.resolution_y = scene["size"]
        if "view" in scene:
            view = scene["view"]
            specs = view["fish"]
        else:
            view = {"camera": scene["camera"], "fov": scene["fov"]}
            specs = [
                {"id": f["id"], "side": "", "cf": fish_cf(f["pos"], f["heading"], f.get("turn", 0.3)), "length": f["length"]}
                for f in scene["fish"]
            ]
        placed = [RB.place_fish(fish, s) for s in specs]
        RB.aim(cam, view)
        if scene["size"][0] == scene["size"][1]:
            cam.data.sensor_fit = "VERTICAL"
        # 被写界深度(主役にピント、奥はぼける)
        cam.data.dof.use_dof = True
        cam.data.dof.focus_distance = scene["focus"]
        cam.data.dof.aperture_fstop = 2.2 if name == "icon" else 4.0
        before = set(bpy.data.objects)
        RB.key_light(view)
        RB.add_beams(data["beams"], cam.matrix_world.translation, shaft_mat)
        path = os.path.join(a.out, name + ".png")
        sc.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("rendered", name)
        for o in placed + list(set(bpy.data.objects) - before):
            if o is not None:
                bpy.data.objects.remove(o, do_unlink=True)


if __name__ == "__main__":
    main()
