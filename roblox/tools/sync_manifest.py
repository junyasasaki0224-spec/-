"""Rojo のプラグインを押せない時(画面がロックされている時など)に、Studio へスクリプトを送るための一覧を作る。

  python roblox/tools/sync_manifest.py

roblox/.sync/default.json と lobby.json に「どのスクリプトをどこへ置くか」を書き出す。
そのあと roblox/ を手元のサーバーで配信し(python -m http.server 8765 --bind 127.0.0.1)、
Studio の MCP(execute_luau)から一覧を読んで、変わったスクリプトだけ Source を書き換える。
ふだんは Rojo の生同期を使う。これは Lua のスクリプトだけを送る(モデルや設定は送らない)。
"""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / ".sync"


def walk(node, path, rows):
    for key, value in node.items():
        if key.startswith("$") or not isinstance(value, dict):
            continue
        here = path + [key]
        file = value.get("$path")
        if isinstance(file, str) and file.endswith(".lua"):
            kind = "Script" if file.endswith(".server.lua") else "LocalScript" if file.endswith(".client.lua") else "ModuleScript"
            data = (ROOT / file).read_bytes()
            rows.append({"path": here, "class": kind, "file": file, "hash": hashlib.sha1(data).hexdigest()[:12]})
        walk(value, here, rows)


def main():
    OUT.mkdir(exist_ok=True)
    for name in ("default", "lobby"):
        tree = json.loads((ROOT / f"{name}.project.json").read_text(encoding="utf-8"))["tree"]
        rows = []
        walk(tree, [], rows)
        (OUT / f"{name}.json").write_text(json.dumps(rows, ensure_ascii=False), encoding="utf-8")
        print(name, len(rows), "scripts")


if __name__ == "__main__":
    main()
