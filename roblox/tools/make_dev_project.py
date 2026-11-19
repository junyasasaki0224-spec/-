"""検証用(Studio だけ)の dev.project.json を作る: ロビー(lobby.project.json)と会場(default.project.json)を1つの場所にまとめる。

ホームの「出走」(フリーレース・スタート練習)を押すと、移動せずに同じ場所の中でレースが始まり、
「ロビーへ」でホームに戻る。目印は ReplicatedStorage の MinatoDevCombined(この印は Studio の中でだけ効く)。
公開には使わない(公開はロビーと会場を別々に作る。PUBLISH.md)。

使い方: python roblox/tools/make_dev_project.py  → roblox/dev.project.json
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def merge(a, b, path):
    """2つの木を合わせる。同じ名前で中身が違う時は止める(間違ってまとめないため)"""
    out = dict(a)
    for key, value in b.items():
        if key not in out:
            out[key] = value
        elif isinstance(out[key], dict) and isinstance(value, dict):
            out[key] = merge(out[key], value, path + "/" + key)
        elif out[key] != value:
            raise SystemExit(f"違う値があります: {path}/{key}: {out[key]!r} と {value!r}")
    return out


def main():
    lobby = json.load(open(os.path.join(ROOT, "lobby.project.json"), encoding="utf-8"))
    race = json.load(open(os.path.join(ROOT, "default.project.json"), encoding="utf-8"))
    tree = merge(lobby["tree"], race["tree"], "")
    tree["ReplicatedStorage"]["MinatoDevCombined"] = {"$className": "BoolValue", "$properties": {"Value": True}}
    project = {"name": "Minato Grand Prix (dev: lobby + race)", "tree": tree}
    with open(os.path.join(ROOT, "dev.project.json"), "w", encoding="utf-8", newline="\n") as f:
        json.dump(project, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print("ok", os.path.join(ROOT, "dev.project.json"))


if __name__ == "__main__":
    main()
