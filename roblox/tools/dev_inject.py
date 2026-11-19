"""検証用: Rojo の同期先を切り替えられない時(画面ロック中など)に、ロビーだけにある部品を Studio に足す Luau を作る。

dev.project.json と default.project.json を比べ、会場のプロジェクトにない部品(ロビーのスクリプト・ホームなど)と
目印 MinatoDevCombined を、MCP の execute_luau で足せる形の Luau の文に分けて書き出す。
足した物には属性 DevInjected を付ける(消す時はその印で探す)。
使い方: python roblox/tools/dev_inject.py <出力のフォルダ>  → chunk_01.luau …
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
LIMIT = 90000  # 1回で送る大きさの目安(文字数)


def classify(path):
    """ファイル名から、Roblox のスクリプトの種類を決める"""
    if path.endswith(".server.lua"):
        return "Script"
    if path.endswith(".client.lua"):
        return "LocalScript"
    return "ModuleScript"


def shrink(text):
    """送る量を減らす: 行頭の空白と、コメントだけの行を外す(長い文字列 [[ ]] を使っていないファイルだけ)"""
    if "[[" in text or "[=" in text:
        return text
    lines = []
    for line in text.split("\n"):
        t = line.strip()
        if not t or (t.startswith("--") and not t.startswith("--[")):
            continue
        lines.append(t)
    return "\n".join(lines) + "\n"


def long_string(text):
    """中身に出てこない長い括弧で囲む"""
    level = 1
    while ("]" + "=" * level + "]") in text:
        level += 1
    eq = "=" * level
    return "[" + eq + "[\n" + text + "]" + eq + "]"


def main():
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    dev = json.load(open(os.path.join(ROOT, "dev.project.json"), encoding="utf-8"))["tree"]
    race = json.load(open(os.path.join(ROOT, "default.project.json"), encoding="utf-8"))["tree"]
    items = []
    for service in ("ServerScriptService", "ReplicatedStorage"):
        for name, node in dev[service].items():
            if name.startswith("$") or name in race[service]:
                continue
            if "$path" in node and node["$path"].endswith(".lua"):
                items.append((f"game:GetService('{service}')", name, node["$path"]))
    sps = dev["StarterPlayer"]["StarterPlayerScripts"]
    for name, node in sps.items():
        if name not in race["StarterPlayer"]["StarterPlayerScripts"]:
            items.append(("game:GetService('StarterPlayer').StarterPlayerScripts", name, node["$path"]))
    chunks, current = [], []
    size = 0
    for parent, name, path in items:
        src = shrink(open(os.path.join(ROOT, path), encoding="utf-8").read())
        cls = classify(path)
        stmt = (
            f"do local p={parent} local s=p:FindFirstChild('{name}') "
            f"if s and not s:GetAttribute('DevInjected') then error('{name} はすでにあります(Rojo の物)') end "
            f"if not s then s=Instance.new('{cls}') s.Name='{name}' s:SetAttribute('DevInjected',true) end "
            f"s.Source={long_string(src)} s.Parent=p table.insert(done,'{name}') end\n"
        )
        if current and size + len(stmt) > LIMIT:
            chunks.append(current)
            current, size = [], 0
        current.append(stmt)
        size += len(stmt)
    current.append(
        "do local rs=game:GetService('ReplicatedStorage') if not rs:FindFirstChild('MinatoDevCombined') then "
        "local v=Instance.new('BoolValue') v.Name='MinatoDevCombined' v.Value=true v:SetAttribute('DevInjected',true) "
        "v.Parent=rs end table.insert(done,'MinatoDevCombined') end\n"
    )
    chunks.append(current)
    for i, c in enumerate(chunks, 1):
        with open(os.path.join(out_dir, f"chunk_{i:02d}.luau"), "w", encoding="utf-8", newline="\n") as f:
            f.write("local done={}\n" + "".join(c) + "return table.concat(done,',')\n")
    print(len(chunks), "chunks;", ", ".join(n for _, n, _ in items))


if __name__ == "__main__":
    main()
