"""Studio で取り込んだガチャの着せ替えを、Rojo で使うモデル(assets/items/Items.rbxmx)にまとめる。

使い方:
  1. python roblox/tools/gacha_items.py で import/*.glb と items-manifest.json を作る
  2. Studio の「ファイル → インポート」で import/ の5つの GLB を取り込む(形と模様が、取り込んだ人のアカウントに登録される)
  3. 取り込んだ5つのモデルを1つのフォルダに入れ、右クリック →「保存 / エクスポート → ファイルに保存」で
     import/GachaImport.rbxmx(XML)として保存する
  4. python roblox/tools/package_items.py → assets/items/Items.rbxmx(番号の一覧 items-import.json も作る。
     import/ は Git に入れない。番号は items-import.json に残るので、取り込み直さなくても Items.rbxmx を作り直せる)

Items.rbxmx の中身: Model「Items」の下に、品ごとの Model(名前は品の番号 hull01 など)。その中に MeshPart。
  ・CFrame の位置は、艇の模型の原点から見た部品の中心(ヘルメットだけは、元のヘルメットの殻の中心から見た位置)。
    向きは縦の軸まわりに半回転(取り込みが半回転させた分を戻す。Outfit が部品に Turned の印を付け、Visor はそれを見る)
  ・大きさ・色・材質は items-manifest.json から。形と模様の番号は GachaImport.rbxmx から(名前で突き合わせる)
"""
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
ITEMS = os.path.join(os.path.dirname(HERE), "assets", "items")
ASSET = re.compile(r"rbxassetid://[1-9][0-9]*")
METAL, SMOOTH = 1088, 272  # Enum.Material の番号


def imported_ids(path):
    """取り込んだモデルのファイルから、部品の名前 → (形の番号, 模様の番号, 元の大きさ)"""
    out = {}
    for it in ET.parse(path).iterfind('.//Item[@class="MeshPart"]'):
        p = it.find("Properties")
        name = p.findtext('string[@name="Name"]')
        mesh = p.findtext('Content[@name="MeshContent"]/uri') or p.findtext('Content[@name="MeshId"]/url')
        tex = p.findtext('Content[@name="TextureContent"]/uri') or p.findtext('Content[@name="TextureID"]/url') or ""
        size = p.find('Vector3[@name="InitialSize"]')
        natural = [float(size.findtext(k)) for k in "XYZ"]
        if name in out or not ASSET.fullmatch(mesh or "") or (tex and not ASSET.fullmatch(tex)):
            sys.exit(f"番号がないか、同じ名前があります: {name}")
        out[name] = (mesh, tex, natural)
    return out


def main():
    manifest = json.load(open(os.path.join(ITEMS, "items-manifest.json"), encoding="utf-8"))
    # 取り込んだファイルがあれば読み、番号の一覧(items-import.json。Git に残す)を作り直す。なければ一覧を使う
    saved = os.path.join(ITEMS, "items-import.json")
    source = os.path.join(ITEMS, "import", "GachaImport.rbxmx")
    if os.path.exists(source):
        ids = imported_ids(source)
        with open(saved, "w", encoding="utf-8", newline="\n") as f:
            json.dump({k: list(v) for k, v in sorted(ids.items())}, f, indent=1)
            f.write("\n")
    else:
        ids = {k: tuple(v) for k, v in json.load(open(saved, encoding="utf-8")).items()}
    names = {row["name"] for row in manifest}
    if names != set(ids):
        sys.exit(f"部品の名前が合いません。足りない: {sorted(names - set(ids))[:5]} 余分: {sorted(set(ids) - names)[:5]}")
    doc = ET.Element("roblox", version="4")
    count = [0]

    def item(parent, cls, name):
        count[0] += 1
        element = ET.SubElement(parent, "Item", {"class": cls, "referent": f"RBX{count[0]}"})
        props = ET.SubElement(element, "Properties")
        ET.SubElement(props, "string", name="Name").text = name
        return element, props

    def prop(props, tag, name, value):
        ET.SubElement(props, tag, name=name).text = str(value)

    def vec(props, name, value):
        element = ET.SubElement(props, "Vector3", name=name)
        for key, v in zip("XYZ", value):
            ET.SubElement(element, key).text = repr(float(v))

    root, _ = item(doc, "Model", "Items")
    models = {}
    for row in manifest:
        key = row["item"]
        if key not in models:
            models[key] = item(root, "Model", key)[0]
        mesh, tex, natural = ids[row["name"]]
        fabric = row["kind"] == "Fabric"
        if fabric:
            # 旗の布: 模様 × 艇番の色にしたいので、色を掛けられる SpecialMesh(VertexColor)を使う。
            # 布の面は全部が模様の画像の範囲を指すので、同じ品の本体の模様の画像を使う(取り込んだ布の画像は透ける形で、色を掛けられない)
            part, props = item(models[key], "Part", row["name"])
            body = ids[row["item"] + "__Paint__Body"]
            _, sm = item(part, "SpecialMesh", "Mesh")
            prop(sm, "token", "MeshType", 5)
            for name, url in (("MeshId", mesh), ("TextureId", body[1])):
                content = ET.SubElement(sm, "Content", name=name)
                ET.SubElement(content, "url").text = url
            vec(sm, "Scale", [s / n for s, n in zip(row["size"], natural)])
            vec(sm, "VertexColor", [1, 1, 1])
        else:
            _, props = item(models[key], "MeshPart", row["name"])
            content = ET.SubElement(props, "Content", name="MeshId")
            ET.SubElement(content, "url").text = mesh
            if tex:
                content = ET.SubElement(props, "Content", name="TextureID")
                ET.SubElement(content, "url").text = tex
        frame = ET.SubElement(props, "CoordinateFrame", name="CFrame")
        # Studio の取り込みは GLB を縦の軸まわりに半回転させて読む(会場の FBX と同じ)。部品の向きを半回転させて元に戻す
        for k, v in zip(["X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"], row["center"] + [-1, 0, 0, 0, 1, 0, 0, 0, -1]):
            ET.SubElement(frame, k).text = repr(float(v))
        vec(props, "size", row["size"])
        if not fabric:
            vec(props, "InitialSize", natural)
        color = ET.SubElement(props, "Color3", name="Color")
        for k, v in zip("RGB", row["color"] or [1, 1, 1]):
            ET.SubElement(color, k).text = repr(float(v))
        gold = row["kind"] == "Gold"
        prop(props, "token", "Material", METAL if gold else SMOOTH)
        prop(props, "float", "Reflectance", 0.25 if gold else 0)
        prop(props, "float", "Transparency", 0.25 if row["kind"] == "Visor" else 0)
        prop(props, "bool", "Anchored", "true")
        if not fabric:
            prop(props, "bool", "DoubleSided", "true")
        prop(props, "bool", "CastShadow", "false" if row["kind"] in ("Fabric", "Plate") else "true")
        for k in ("CanCollide", "CanTouch", "CanQuery"):
            prop(props, "bool", k, "false")
        prop(props, "token", "RenderFidelity", 0)
    ET.indent(doc)
    out = os.path.join(ITEMS, "Items.rbxmx")
    ET.ElementTree(doc).write(out, encoding="utf-8", xml_declaration=True)
    print(len(models), "models,", len(manifest), "parts ->", out, os.path.getsize(out) // 1024, "KB")


if __name__ == "__main__":
    main()
