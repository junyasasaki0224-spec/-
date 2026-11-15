"""Run with Blender --background --python export_roblox.py -- boat|venue OUTPUT_DIR.

Build from source, split by material and <=18k triangles, retain each source origin.
FBX coordinates are studs. Boat forward is -Z, venue uses game X/Z coordinates.
"""
import json
import math
import runpy
import sys
from pathlib import Path

import bpy
from mathutils import Matrix

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import bl_util

kind, destination = sys.argv[sys.argv.index('--') + 1:]
assert kind in ('boat', 'venue')
destination = Path(destination).resolve()
destination.mkdir(parents=True, exist_ok=True)
# Roblox uses material colors. Browser light-map baking is unnecessary here.
bl_util.bake_ao = lambda *args, **kwargs: None
bl_util.export_glb = lambda *args, **kwargs: None
sys.argv = [str(HERE / ('build_' + kind + '.py')), 'unused.glb']
runpy.run_path(sys.argv[0], run_name='__main__')
rotation = Matrix.Rotation(-math.pi / 2, 4, 'Z') if kind == 'boat' else Matrix.Identity(4)
transform = Matrix.Scale(3.5, 4) @ rotation
manifest = []
sources = [o for o in bpy.context.scene.objects if o.type == 'MESH']
for source in sources:
    source.data.calc_loop_triangles()
    groups = {}
    for triangle in source.data.loop_triangles:
        points = [source.data.vertices[v].co.copy() for v in triangle.vertices]
        stack = [points]
        while stack:
            points = stack.pop()
            edges = [(points[(i+1)%3]-points[i]).length for i in range(3)]
            longest = max(range(3), key=lambda i: edges[i])
            if kind == 'venue' and edges[longest] > 140:
                a, b, c = points[longest], points[(longest+1)%3], points[(longest+2)%3]
                midpoint = (a+b)/2
                stack.extend([(a,midpoint,c),(midpoint,b,c)])
                continue
            center = sum(points, points[0]*0)/3
            cell = (math.floor(center.x/120), math.floor(center.y/120)) if kind == 'venue' else (0,0)
            key = (triangle.material_index, *cell)
            groups.setdefault(key, []).append(points)
    for (slot, cell_x, cell_y), triangles in groups.items():
        material = source.data.materials[slot]
        for start in range(0, len(triangles), 18000):
            faces = triangles[start:start + 18000]
            mesh = bpy.data.meshes.new('ExportMesh')
            mesh.from_pydata([v for face in faces for v in face], [],
                             [(i*3,i*3+1,i*3+2) for i in range(len(faces))])
            mesh.materials.append(material)
            name = f'{source.name}__{material.name}__{cell_x}_{cell_y}_{start // 18000:02}'
            obj = bpy.data.objects.new(name, mesh)
            bpy.context.collection.objects.link(obj)
            obj.matrix_world = transform @ source.matrix_world
            for polygon in mesh.polygons:
                polygon.use_smooth = True
            manifest.append({'name': name, 'group': source.name, 'material': material.name,
                             'triangles': len(faces), 'origin': list(obj.matrix_world.translation),
                             'color': list(next(n for n in material.node_tree.nodes if n.type == 'BSDF_PRINCIPLED').inputs['Base Color'].default_value),
                             'roughness': next(n for n in material.node_tree.nodes if n.type == 'BSDF_PRINCIPLED').inputs['Roughness'].default_value})
    bpy.data.objects.remove(source, do_unlink=True)
bpy.context.scene.unit_settings.system = 'NONE'
bpy.ops.export_scene.fbx(filepath=str(destination / (kind + '.fbx')),
    object_types={'MESH'}, axis_forward='-Z', axis_up='Y', global_scale=0.01,
    apply_unit_scale=False, bake_anim=False, use_custom_props=False)
(destination / (kind + '-manifest.json')).write_text(json.dumps(manifest, indent=2), encoding='utf8', newline='\n')
print('EXPORTED', kind, len(manifest), 'meshes, max', max(x['triangles'] for x in manifest))
