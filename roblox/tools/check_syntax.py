"""Compile project Luau with the official CLI, including platforms without luau-compile."""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
files = sorted(root.glob("src/*.lua")) + sorted(root.glob("tests/*.luau")) + [root / "tools/simulation.lua"]
source = ""
for path in files:
    code = path.read_text(encoding="utf-8")
    marker = "===="
    while "]" + marker + "]" in code:
        marker += "="
    source += 'assert(loadstring([' + marker + '[' + code + ']' + marker + '], "' + path.name + '"))\n'
with tempfile.TemporaryDirectory(prefix="minato-syntax-") as directory:
    path = Path(directory) / "check.luau"
    path.write_text(source, encoding="utf-8")
    subprocess.run([shutil.which("luau") or "luau", str(path)], check=True)
print(f"Luau syntax: {len(files)} files OK")
