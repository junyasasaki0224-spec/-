"""Validate generated meshes and rig pivots without Roblox."""
import json
import math
from pathlib import Path
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1] / 'assets/models'
for kind in ('boat','venue'):
    manifest = json.loads((root/(kind+'-manifest.json')).read_text())
    meshes = json.loads((root/(kind+'-import.json')).read_text())
    assert len(manifest)==len(meshes)
    assert {m['name'] for m in manifest}=={m['name'] for m in meshes}
    assert all(0<m['triangles']<=18000 for m in manifest)
    assert all(0<v<=2048 for m in meshes for v in m['size'])
    assert all(math.isfinite(v) for m in meshes for v in m['cf'])
    tree = ET.parse(root/(kind.title()+'.rbxmx'))
    parts = tree.findall('.//Item[@class="MeshPart"]')
    assert len(parts)==len(meshes)
    for p in parts:
        assert p.find('./Properties/Vector3[@name="InitialSize"]') is not None
        assert p.find('./Properties/bool[@name="CanCollide"]').text=='false'
        assert p.find('./Properties/Content[@name="MeshId"]/url').text.startswith('rbxassetid://')
    if kind=='boat':
        groups = {p.find('./Properties/string[@name="Name"]').text:p for p in tree.findall('.//Item[@class="Model"]')}
        for name in ('Wheel','Motor','RacerUpper'):
            assert groups[name].find('./Properties/Ref[@name="PrimaryPart"]') is not None
        for name in ('HullWhite','Trim','Deck','MotorRed','Helmet','HelmetStripe'):
            assert any(m['material']==name for m in manifest)
    print(kind, len(parts), 'meshes OK, triangles',sum(m['triangles'] for m in manifest))
