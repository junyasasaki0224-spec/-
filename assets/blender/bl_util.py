"""Blender (bpy) 用の小さなヘルパー。ヘッドレスで動かす前提。
座標系: X=前, Y=左, Z=上 (glTF 書き出しで X=前, Y=上, Z=右 になる)"""
import bpy, bmesh, math
from mathutils import Vector, Matrix, Euler

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    return sc

_mats = {}
def mat(name, color=(0.8, 0.8, 0.8), rough=0.5, metal=0.0, alpha=1.0, emit=None):
    if name in _mats: return _mats[name]
    m = bpy.data.materials.new(name)
    try: m.use_nodes = True
    except Exception: pass
    b = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    b.inputs['Base Color'].default_value = (*color, 1)
    b.inputs['Roughness'].default_value = rough
    b.inputs['Metallic'].default_value = metal
    if alpha < 1:
        b.inputs['Alpha'].default_value = alpha
        try: m.surface_render_method = 'BLENDED'
        except Exception: pass
        try: m.blend_method = 'BLEND'
        except Exception: pass
    if emit:
        b.inputs['Emission Color'].default_value = (*emit[:3], 1)
        b.inputs['Emission Strength'].default_value = emit[3] if len(emit) > 3 else 1
    _mats[name] = m
    return m

class Builder:
    """複数マテリアルの面を貯めて1つのメッシュオブジェクトにする"""
    def __init__(self):
        self.bm = bmesh.new()
        self.mats = []
        self.uv = None
    def mi(self, m):
        if isinstance(m, str): m = _mats[m]
        if m not in self.mats: self.mats.append(m)
        return self.mats.index(m)
    def vert(self, p): return self.bm.verts.new(p)
    def face(self, vs, m, uvs=None, smooth=True):
        try: f = self.bm.faces.new(vs)
        except ValueError: return None
        f.material_index = self.mi(m); f.smooth = smooth
        if uvs:
            if self.uv is None: self.uv = self.bm.loops.layers.uv.new('UVMap')
            for l, uv in zip(f.loops, uvs): l[self.uv].uv = uv
        return f
    def _tag_new(self, before, m, smooth, M=None):
        mi = self.mi(m)
        for f in self.bm.faces:
            if f.index == -1 or f not in before:
                f.material_index = mi; f.smooth = smooth
    def prim(self, kind, m, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1), smooth=True, **kw):
        M = Matrix.Translation(loc) @ Euler(rot, 'XYZ').to_matrix().to_4x4() @ Matrix.Diagonal((*scale, 1))
        if kind == 'box': result = bmesh.ops.create_cube(self.bm, size=1, matrix=M)
        elif kind == 'cyl': result = bmesh.ops.create_cone(self.bm, cap_ends=True, cap_tris=False, segments=kw.get('seg', 20), radius1=kw.get('r1', 0.5), radius2=kw.get('r2', kw.get('r1', 0.5)), depth=1, matrix=M)
        elif kind == 'sphere': result = bmesh.ops.create_uvsphere(self.bm, u_segments=kw.get('seg', 20), v_segments=kw.get('rings', 12), radius=0.5, matrix=M)
        elif kind == 'ico': result = bmesh.ops.create_icosphere(self.bm, subdivisions=kw.get('sub', 2), radius=0.5, matrix=M)
        mi = self.mi(m)
        new = {f for v in result['verts'] for f in v.link_faces}
        for f in new: f.material_index = mi; f.smooth = smooth
        return new
    def box(self, m, size, loc, rot=(0, 0, 0), bevel=0.0, smooth=False):
        new = self.prim('box', m, loc, rot, size, smooth=smooth)
        if bevel > 0:
            edges = list({e for f in new for e in f.edges})
            r = bmesh.ops.bevel(self.bm, geom=edges, offset=bevel, segments=2, profile=0.6, affect='EDGES')
            mi = self.mi(m)
            for f in r['faces']: f.material_index = mi; f.smooth = True
            for f in new:
                if f.is_valid: f.smooth = True
        return new
    def cyl(self, m, r, depth, loc, rot=(0, 0, 0), r2=None, seg=20, smooth=True):
        return self.prim('cyl', m, loc, rot, (1, 1, depth), smooth=smooth, r1=r, r2=r if r2 is None else r2, seg=seg)
    def sphere(self, m, size, loc, rot=(0, 0, 0), seg=20, rings=12):
        return self.prim('sphere', m, loc, rot, size, seg=seg, rings=rings)
    def tube(self, m, pts, r, seg=10):
        """折れ線に沿った円筒"""
        for a, b in zip(pts[:-1], pts[1:]):
            a, b = Vector(a), Vector(b); d = b - a
            q = Vector((0, 0, 1)).rotation_difference(d.normalized())
            M = Matrix.Translation((a + b) / 2) @ q.to_matrix().to_4x4() @ Matrix.Diagonal((1, 1, d.length, 1))
            result = bmesh.ops.create_cone(self.bm, cap_ends=True, segments=seg, radius1=r, radius2=r, depth=1, matrix=M)
            mi = self.mi(m)
            for f in {f for v in result['verts'] for f in v.link_faces}:
                f.material_index = mi; f.smooth = True
    def torus(self, m, R, r, loc, rot=(0, 0, 0), seg=28, sseg=8):
        M = Matrix.Translation(loc) @ Euler(rot, 'XYZ').to_matrix().to_4x4()
        ring = []
        for i in range(seg):
            a = 2 * math.pi * i / seg; row = []
            for j in range(sseg):
                b = 2 * math.pi * j / sseg
                row.append(self.vert(M @ Vector(((R + r * math.cos(b)) * math.cos(a), (R + r * math.cos(b)) * math.sin(a), r * math.sin(b)))))
            ring.append(row)
        for i in range(seg):
            for j in range(sseg):
                self.face([ring[i][j], ring[(i + 1) % seg][j], ring[(i + 1) % seg][(j + 1) % sseg], ring[i][(j + 1) % sseg]], m)
    def build(self, name, origin=(0, 0, 0), merge=1e-5, sharp_angle=40, recalc=True, parent=None):
        bm = self.bm
        if merge: bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=merge)
        if recalc: bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        o = Vector(origin)
        for v in bm.verts: v.co -= o
        me = bpy.data.meshes.new(name)
        bm.to_mesh(me); bm.free()
        for m in self.mats: me.materials.append(m)
        if sharp_angle is not None:
            try: me.set_sharp_from_angle(angle=math.radians(sharp_angle))
            except Exception as e: print('sharp', e)
        ob = bpy.data.objects.new(name, me)
        ob.location = o
        bpy.context.scene.collection.objects.link(ob)
        if parent: 
            ob.parent = parent
            ob.matrix_parent_inverse = parent.matrix_world.inverted()
        return ob

def apply_mods(ob):
    """モディファイアを適用した結果でメッシュを置き換える"""
    bpy.context.view_layer.update()
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    old = ob.data
    ob.modifiers.clear()
    ob.data = me
    bpy.data.meshes.remove(old)
    return ob

def skin_object(name, joints, edges, m, subsurf=2, origin=(0, 0, 0)):
    """joints: [(pos, (rx, ry))], edges: [(i, j)] → スキンモディファイアで有機的な形にする"""
    me = bpy.data.meshes.new(name)
    o = Vector(origin)
    me.from_pydata([tuple(Vector(p) - o) for p, _ in joints], edges, [])
    ob = bpy.data.objects.new(name, me); ob.location = o
    bpy.context.scene.collection.objects.link(ob)
    sk = ob.modifiers.new('skin', 'SKIN'); sk.use_smooth_shade = True
    for i, (_, r) in enumerate(joints):
        d = me.skin_vertices[0].data[i]
        d.radius = r if isinstance(r, tuple) else (r, r)
        d.use_root = (i == 0)
    if subsurf:
        ss = ob.modifiers.new('ss', 'SUBSURF'); ss.levels = subsurf; ss.render_levels = subsurf
    me.materials.append(m)
    apply_mods(ob)
    for p in ob.data.polygons: p.use_smooth = True
    return ob

def join(objs, name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs: o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    objs[0].name = name; objs[0].data.name = name
    return objs[0]

def bake_ao(objs, samples=48, lo=0.25, gamma=0.85, dist=1.5):
    """AO を頂点カラー(Col)に焼く"""
    sc = bpy.context.scene
    sc.cycles.samples = samples
    sc.render.bake.target = 'VERTEX_COLORS'
    if sc.world is None: sc.world = bpy.data.worlds.new('w')
    try: sc.world.light_settings.distance = dist
    except Exception: pass
    for ob in objs:
        if ob.type != 'MESH': continue
        me = ob.data
        attr = me.color_attributes.get('Col') or me.color_attributes.new('Col', 'BYTE_COLOR', 'CORNER')
        me.color_attributes.active_color = attr
        try: me.color_attributes.render_color_index = list(me.color_attributes).index(attr)
        except Exception: pass
        bpy.ops.object.select_all(action='DESELECT')
        ob.select_set(True); bpy.context.view_layer.objects.active = ob
        bpy.ops.object.bake(type='AO')
        for d in attr.data:
            c = d.color; v = lo + (1 - lo) * (max(c[0], 0.0) ** gamma)
            d.color = (v, v, v, 1)
        print('baked', ob.name, len(me.polygons), 'faces')

def export_glb(path, objs=None):
    bpy.ops.object.select_all(action='DESELECT')
    if objs:
        for o in objs: o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', use_selection=bool(objs), export_apply=True,
                              export_yup=True, export_vertex_color='ACTIVE', export_all_vertex_colors=False,
                              export_active_vertex_color_when_no_material=True,
                              export_animations=False, export_cameras=False, export_lights=False)
    import os
    print('exported', path, os.path.getsize(path) // 1024, 'KB')

def preview(path, cam_pos, look, lens=50, res=(960, 540), samples=48, sun=(0.9, 0.3, -0.75), ground=True, world=(0.55, 0.7, 0.95), strength=1.0):
    sc = bpy.context.scene
    tmp = []
    cam = bpy.data.objects.new('pcam', bpy.data.cameras.new('pcam')); cam.data.lens = lens
    sc.collection.objects.link(cam); tmp.append(cam)
    cam.location = cam_pos
    d = Vector(look) - Vector(cam_pos)
    cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
    sc.camera = cam
    sd = bpy.data.lights.new('psun', 'SUN'); sd.energy = 4.0; sd.angle = 0.03
    so = bpy.data.objects.new('psun', sd); sc.collection.objects.link(so); tmp.append(so)
    so.rotation_euler = Euler(sun, 'XYZ')
    if sc.world is None: sc.world = bpy.data.worlds.new('w')
    try: sc.world.use_nodes = True
    except Exception: pass
    bg = next(n for n in sc.world.node_tree.nodes if n.type == 'BACKGROUND')
    bg.inputs[0].default_value = (*world, 1); bg.inputs[1].default_value = strength
    if ground:
        b = Builder(); mat('pv_ground', (0.08, 0.25, 0.3), 0.15)
        v = [b.vert(p) for p in [(-60, -60, -0.02), (60, -60, -0.02), (60, 60, -0.02), (-60, 60, -0.02)]]
        b.face(v, 'pv_ground'); tmp.append(b.build('pv_ground', recalc=False))
    sc.cycles.samples = samples
    try: sc.cycles.use_denoising = True
    except Exception: pass
    sc.render.resolution_x, sc.render.resolution_y = res
    sc.render.filepath = path
    sc.render.image_settings.file_format = 'PNG'
    bpy.ops.render.render(write_still=True)
    for o in tmp: bpy.data.objects.remove(o, do_unlink=True)
    print('rendered', path)
