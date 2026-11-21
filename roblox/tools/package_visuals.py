"""Package Studio-imported mesh metadata and Blender manifests as Rojo XML models.

Usage: python roblox/tools/package_visuals.py boat|venue metadata.json
Metadata fields are name, mesh, cf (CFrame components), size (Vector3).
"""
import json
import math
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

kind, metadata = sys.argv[1:]
root = Path(__file__).resolve().parents[1] / 'assets/models'
manifest = json.loads((root / (kind+'-manifest.json')).read_text())
specs = {x['name']: x for x in manifest}
doc = ET.Element('roblox', version='4')
count = 0

def item(parent, cls, name):
    global count
    count += 1
    ref = 'RBX'+str(count)
    element = ET.SubElement(parent, 'Item', {'class': cls, 'referent': ref})
    properties = ET.SubElement(element, 'Properties')
    ET.SubElement(properties, 'string', name='Name').text = name
    return element, properties, ref

def prop(properties, tag, name, value):
    ET.SubElement(properties, tag, name=name).text = str(value)

def vec(properties, name, value):
    element = ET.SubElement(properties, 'Vector3', name=name)
    for key, value in zip('XYZ', value):
        ET.SubElement(element, key).text = str(value)

def cf(properties, name, value):
    element = ET.SubElement(properties, 'CoordinateFrame', name=name)
    for key, value in zip(['X','Y','Z','R00','R01','R02','R10','R11','R12','R20','R21','R22'], value):
        ET.SubElement(element, key).text = str(value)

def pivot(parent, origin):
    element, properties, ref = item(parent,'Part','Pivot')
    vec(properties,'size',[.05]*3)
    cf(properties,'CFrame',origin+[1,0,0,0,1,0,0,0,1])
    for key in ['CanCollide','CanTouch','CanQuery']: prop(properties,'bool',key,'false')
    prop(properties,'bool','Anchored','true')
    prop(properties,'float','Transparency',1)
    return ref

model, properties, _ = item(doc,'Model',kind.title())
prop(properties,'Ref','PrimaryPart',pivot(model,[0,0,0]))
groups = {}
for data in json.loads(Path(metadata).read_text()):
    spec = specs[data['name']]
    name = spec['group']
    if name not in groups:
        group, props, _ = item(model,'Model',name)
        x,y,z = spec['origin']
        origin = [-x,z,y] if kind=="boat" else [x,z,-y]
        prop(props,'Ref','PrimaryPart',pivot(group,origin))
        groups[name] = group
    _, props, _ = item(groups[name], 'MeshPart',data['name'])
    content = ET.SubElement(props,'Content',name='MeshId')
    ET.SubElement(content,'url').text = data['mesh']
    value = data['cf'][:]
    if kind=='venue':
        value[0]=-value[0]
        value[2]=-value[2]
        value[3:6]=[-v for v in value[3:6]]
        value[9:12]=[-v for v in value[9:12]]
    cf(props,'CFrame',value)
    vec(props,'size',data['size'])
    vec(props,'InitialSize',data.get('natural',data['size']))
    color = ET.SubElement(props,'Color3',name='Color')
    for key,v in zip('RGB',spec['color']): ET.SubElement(color,key).text=str(v)
    prop(props,'float','Transparency',.45 if spec['material'] in ('Glass','Visor') else 0)
    prop(props,'bool','Anchored','true')
    # 両面で描くと、艇の操縦席の内張り(Hull Cockpit)と甲板(Hull Deck)の境目で、
    # 裏の面が同じ深さに重なってちらつく。この2つは表だけで描く(ほかは裏返った面があるので両面のまま)
    single = kind=='boat' and spec['group']=='Hull' and spec['material'] in ('Cockpit','Deck')
    prop(props,'bool','DoubleSided','false' if single else 'true')
    for key in ['CanCollide','CanTouch','CanQuery']: prop(props,'bool',key,'false')
    prop(props,'token','RenderFidelity',0)
ET.indent(doc)
ET.ElementTree(doc).write(root/(kind.title()+'.rbxmx'),encoding='utf-8',xml_declaration=True)
print(kind,len(specs),'meshes packaged')
