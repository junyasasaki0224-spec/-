"""Copy owner-imported mesh IDs by exact part name while retaining the game's rig."""
import argparse
import json
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

root = Path(__file__).resolve().parents[1] / "assets" / "models"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("kind", choices=["boat", "venue"])
parser.add_argument("selection", type=Path, help="Studio selection saved as XML (.rbxmx)")
args = parser.parse_args()
metadata = root / (args.kind + "-import.json")
rows = json.loads(metadata.read_text(encoding="utf-8"))
parts = {}
for mesh in ET.parse(args.selection).iterfind('.//Item[@class="MeshPart"]/Properties'):
    name = mesh.findtext('string[@name="Name"]')
    uri = mesh.findtext('Content[@name="MeshId"]/url') or mesh.findtext('Content[@name="MeshContent"]/uri')
    if name in parts or not re.fullmatch(r"rbxassetid://[1-9][0-9]*", uri or ""):
        parser.error(f"Missing ID or duplicate part: {name}")
    size = mesh.find('Vector3[@name="InitialSize"]')
    natural = [float(size.findtext(k)) for k in "XYZ"] if size is not None else None
    if natural is not None and not all(0 < x <= 2048 for x in natural):
        parser.error(f"Invalid mesh size: {name}")
    parts[name] = (uri, natural)
expected = {row["name"] for row in rows}
if set(parts) != expected:
    parser.error(f"Part names differ. Missing: {sorted(expected-set(parts))}; extra: {sorted(set(parts)-expected)}")
for row in rows:
    row["mesh"], natural = parts[row["name"]]
    if natural is not None:
        row["natural"] = natural
staged = metadata.with_suffix(".pending.json")
try:
    staged.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    subprocess.run([sys.executable, str(Path(__file__).with_name("package_visuals.py")), args.kind, str(staged)], check=True)
    staged.replace(metadata)
finally:
    staged.unlink(missing_ok=True)
print(f"Updated {len(rows)} mesh IDs in {args.kind}.")
