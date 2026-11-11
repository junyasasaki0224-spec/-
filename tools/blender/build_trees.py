# ============================================================
#  Blender (bpy) による樹木モデルの生成: 広葉樹 / 桜 / 針葉樹
#  枝葉の塊を距離場で融合 → 凹凸をつけて表面抽出 → Blenderでリダクション → glTF
#  実行: python tools/blender/build_trees.py assets/trees.glb
#  高さ1・根元が原点。葉の明暗(下ほど暗い)は UV.x に格納
# ============================================================
import sys, os, math
import numpy as np
import bpy
sys.argv = [sys.argv[0]] + sys.argv[1:]
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from build_models import Shape

OUT = sys.argv[1] if len(sys.argv) > 1 else 'assets/trees.glb'
rng = np.random.default_rng(7)


def lump(V, amp, f):
    """葉むらの凹凸"""
    n = np.sin(V[:, 0] * f + 1.3) * np.sin(V[:, 1] * f * 1.1 + 0.7) * np.sin(V[:, 2] * f * 0.9 + 2.1)
    n += 0.5 * np.sin(V[:, 0] * f * 2.3) * np.sin(V[:, 1] * f * 1.9 + 1.0) * np.sin(V[:, 2] * f * 2.1)
    c = V.mean(0)
    d = V - c; d /= np.maximum(np.linalg.norm(d, axis=1, keepdims=True), 1e-6)
    return V + d * (n * amp)[:, None]


def obj(name, V, F, mat, tris, shade=None, smooth=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(map(float, v)) for v in V], [], [tuple(map(int, f[::-1])) for f in F])
    me.update(); me.materials.append(mat)
    layer = me.uv_layers.new(name='UVMap')
    sh = shade if shade is not None else np.ones(len(V))
    for li, loop in enumerate(me.loops):
        layer.data[li].uv = (float(sh[loop.vertex_index]), 0.0)
    ob = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(ob)
    bpy.context.view_layer.objects.active = ob; ob.select_set(True)
    m = ob.modifiers.new('dec', 'DECIMATE'); m.ratio = min(1.0, tris / len(F)); bpy.ops.object.modifier_apply(modifier=m.name)
    for p in ob.data.polygons: p.use_smooth = smooth
    ob.select_set(False)
    print(name, len(ob.data.polygons), 'tris')
    return ob


def canopy(blobs, k):
    S = Shape()
    for c, r in blobs:
        S.ell(c, r, 'b', 'leaf', k=k)
    return S


def build():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    leaf = bpy.data.materials.new('leaf'); bark = bpy.data.materials.new('bark')
    # --- 広葉樹(ケヤキ型: 上に広がる) ---
    S = Shape()
    S.cap((0, 0, 0), (0.01, 0, 0.46), 0.05, 0.032, 'b', 'bark', k=0.02)
    for a in (0.3, 2.3, 4.4):
        S.cap((0, 0, 0.36), (0.22 * math.cos(a), 0.22 * math.sin(a), 0.66), 0.026, 0.012, 'b', 'bark', k=0.02)
    V, F = S.mesh(vox=0.012); obj('broad_trunk', V, F, bark, 90)
    blobs = [((0, 0, 0.72), (0.27, 0.27, 0.24))]
    for i in range(8):
        a = i * 0.785 + rng.uniform(-0.2, 0.2); r = rng.uniform(0.2, 0.3); z = rng.uniform(0.56, 0.84)
        blobs.append(((r * math.cos(a), r * math.sin(a), z), (rng.uniform(0.15, 0.2),) * 2 + (rng.uniform(0.13, 0.17),)))
    V, F = canopy(blobs, 0.07).mesh(vox=0.022); V = lump(V, 0.022, 21)
    obj('broad_leaf', V, F, leaf, 340, shade=np.clip(0.5 + (V[:, 2] - 0.45) * 1.15, 0.45, 1.05))
    # --- 桜(横に広く、低い) ---
    S = Shape()
    S.cap((0, 0, 0), (0.02, 0, 0.34), 0.05, 0.036, 'b', 'bark', k=0.02)
    for a in (0.6, 2.0, 3.6, 5.2):
        S.cap((0.01, 0, 0.28), (0.3 * math.cos(a), 0.3 * math.sin(a), 0.56), 0.03, 0.012, 'b', 'bark', k=0.02)
    V, F = S.mesh(vox=0.012); obj('cherry_trunk', V, F, bark, 110)
    blobs = [((0, 0, 0.64), (0.3, 0.3, 0.17))]
    for i in range(9):
        a = i * 0.7 + rng.uniform(-0.2, 0.2); r = rng.uniform(0.28, 0.42); z = rng.uniform(0.52, 0.72)
        blobs.append(((r * math.cos(a), r * math.sin(a), z), (rng.uniform(0.15, 0.2),) * 2 + (rng.uniform(0.10, 0.13),)))
    V, F = canopy(blobs, 0.06).mesh(vox=0.022); V = lump(V, 0.02, 24)
    obj('cherry_leaf', V, F, leaf, 360, shade=np.clip(0.6 + (V[:, 2] - 0.45) * 1.2, 0.55, 1.05))
    # --- 針葉樹 ---
    S = Shape(); S.cap((0, 0, 0), (0, 0, 0.3), 0.035, 0.03, 'b', 'bark', k=0.01)
    V, F = S.mesh(vox=0.012); obj('conifer_trunk', V, F, bark, 30)
    S = Shape()
    for z0, z1, r in ((0.18, 0.55, 0.26), (0.40, 0.78, 0.19), (0.64, 1.0, 0.12)):
        S.cap((0, 0, z0), (0, 0, z1), r, 0.015, 'b', 'leaf', k=0.03)
    V, F = S.mesh(vox=0.018); V = lump(V, 0.012, 30)
    obj('conifer_leaf', V, F, leaf, 220, shade=np.clip(0.55 + (V[:, 2] - 0.2) * 0.6, 0.5, 1.0))
    os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_yup=True, export_texcoords=True, export_normals=True, export_materials='EXPORT')
    print('exported', OUT, os.path.getsize(OUT) // 1024, 'KB')


build()
