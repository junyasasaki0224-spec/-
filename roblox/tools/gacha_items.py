"""ガチャの着せ替え(GPT がデザインした 5種類×30点)を、Roblox Studio に取り込める形に作り直す。

入力: roblox/assets/items/source/(艇外装・ヘルメット・モーターカバー・ステアリング・艇首旗 の GLB と Catalog.csv)
出力:
  roblox/assets/items/import/<種類>.glb … Studio の「3D をインポート」で取り込む(種類ごとに1ファイル、各品を部品に分けてある)
  roblox/assets/items/items-manifest.json … 部品の名前・置く場所・大きさ・色(取り込んだ後に Rojo のモデルを作る時に使う)
  roblox/src/ItemCatalog.lua … ゲームの品の一覧(番号・種類・レア度・名前)

作り直す中身:
  ・座標をブラウザ版(メートル・前が +X)から Roblox の艇(1m=3.5 studs・前が -Z)に変える
  ・1つの品を「本体(模様の画像)」「金(UR の金属)」「シールド(ヘルメット)」「布(艇首旗。艇番の色が透けて見える)」に分ける
  ・Roblox の部品は頂点の色を使わないので、単色の面は画像の右端に色見本を足して、そこを指すようにする
使い方: python roblox/tools/gacha_items.py(--catalog で ItemCatalog.lua だけ)
"""
import csv
import json
import math
import os
import struct
import sys
import zlib

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SOURCE = os.path.join(ROOT, "assets", "items", "source")
OUT = os.path.join(ROOT, "assets", "items", "import")
STUDS = 3.5  # 1m = 3.5 studs(艇の物理と同じ)

# 種類: カタログの名前 → (ゲームの種類, 番号の頭, 艇のどの組に付けるか, ブラウザ版の艇の中での置き場所)
SLOTS = {
    "艇外装": ("hull", "hull", None, None),
    "ヘルメット": ("helmet", "helm", "RacerUpper", None),
    "モーターカバー": ("cowl", "cowl", "Motor", {"t": (-1.525, 0.3, 0.0)}),
    "ステアリング": ("wheel", "whl", "Wheel", {"t": (-0.1, 0.565, 0.0), "q": (0.0, 0.0, -0.8480480909347534, 0.5299192667007446)}),
    "艇首旗": ("flag", "flag", "Flag", {"t": (1.33, 0.6311942338943481, 0.0)}),
}
FILES = {"hull": "Hull", "helmet": "Helmet", "cowl": "MotorCowl", "wheel": "Wheel", "flag": "Pennant"}
PALETTE_X = 960  # 元の画像の幅。右に 64px の色見本を足して 1024 にする
WIDTH, HEIGHT, CELL = 1024, 512, 8


# ---- PNG の読み書き(Python に元からある zlib だけで) ----
def png_read(data):
    """8bit・RGB/RGBA・インターレースなしの PNG を (高さ, 幅, 4) の配列にする"""
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    pos, idat, w, h, ctype = 8, b"", 0, 0, 0
    while pos < len(data):
        n = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + n]
        if kind == b"IHDR":
            w, h, depth, ctype, _, _, inter = struct.unpack(">IIBBBBB", body)
            assert depth == 8 and ctype in (2, 6) and inter == 0
        elif kind == b"IDAT":
            idat += body
        pos += 12 + n
    ch = 3 if ctype == 2 else 4
    raw = zlib.decompress(idat)
    stride = w * ch
    out = np.zeros((h, stride), np.uint8)
    prev = np.zeros(stride, np.int32)
    for y in range(h):
        f = raw[y * (stride + 1)]
        line = np.frombuffer(raw, np.uint8, stride, y * (stride + 1) + 1).astype(np.int32)
        if f == 0:
            cur = line
        elif f == 2:
            cur = (line + prev) & 255
        elif f in (1, 3, 4):
            cur = np.zeros(stride, np.int32)
            for x in range(stride):
                a = cur[x - ch] if x >= ch else 0
                b = prev[x]
                c = prev[x - ch] if x >= ch else 0
                if f == 1:
                    pred = a
                elif f == 3:
                    pred = (a + b) // 2
                else:
                    p = a + b - c
                    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                    pred = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                cur[x] = (line[x] + pred) & 255
        else:
            raise ValueError("PNG filter")
        out[y] = cur
        prev = cur
    img = out.reshape(h, w, ch)
    if ch == 3:
        img = np.concatenate([img, np.full((h, w, 1), 255, np.uint8)], axis=2)
    return img


def png_write(img):
    """(高さ, 幅, 4) の配列を RGBA の PNG にする"""
    h, w, _ = img.shape
    raw = b"".join(b"\x00" + img[y].tobytes() for y in range(h))

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


# ---- GLB の読み書き ----
TYPES = {5126: np.float32, 5123: np.uint16, 5125: np.uint32, 5121: np.uint8}
SIZES = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def glb_read(path):
    d = open(path, "rb").read()
    n = struct.unpack_from("<I", d, 12)[0]
    j = json.loads(d[20:20 + n])
    return j, d[20 + n + 8:]


def accessor(j, b, i):
    a = j["accessors"][i]
    v = j["bufferViews"][a["bufferView"]]
    off = v.get("byteOffset", 0) + a.get("byteOffset", 0)
    k = SIZES[a["type"]]
    arr = np.frombuffer(b, TYPES[a["componentType"]], a["count"] * k, off).astype(np.float64 if a["componentType"] == 5126 else np.int64)
    if a.get("normalized") and a["componentType"] != 5126:
        arr = arr / np.iinfo(TYPES[a["componentType"]]).max
    return arr.reshape(a["count"], k) if k > 1 else arr


def quat_matrix(q):
    x, y, z, w = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])


def node_matrix(node):
    m = np.eye(4)
    if "matrix" in node:
        return np.array(node["matrix"]).reshape(4, 4).T
    s = np.diag(node.get("scale", [1, 1, 1]) + [1])
    r = np.eye(4)
    r[:3, :3] = quat_matrix(node.get("rotation", [0, 0, 0, 1]))
    t = np.eye(4)
    t[:3, 3] = node.get("translation", [0, 0, 0])
    return t @ r @ s @ m


# ブラウザ版の向き(前 +X・上 +Y)→ Roblox の艇の向き(前 -Z・上 +Y)。鏡写しにならない回転 + 大きさ
TO_ROBLOX = np.array([[0, 0, 1], [0, 1, 0], [-1, 0, 0]], np.float64)


def primitives(j, b, place):
    """GLB の全部の面を、置き場所の変換をかけて (材質名, 位置, 法線, UV, 色, 三角形) で返す"""
    base = np.eye(4)
    if place:
        base[:3, 3] = place["t"]
        if "q" in place:
            base[:3, :3] = quat_matrix(place["q"])
    out = []

    def walk(index, parent):
        node = j["nodes"][index]
        m = parent @ node_matrix(node)
        if "mesh" in node:
            for p in j["meshes"][node["mesh"]]["primitives"]:
                attr = p["attributes"]
                pos = accessor(j, b, attr["POSITION"])
                nor = accessor(j, b, attr["NORMAL"])
                uv = accessor(j, b, attr["TEXCOORD_0"])
                col = accessor(j, b, attr["COLOR_0"])[:, :3] if "COLOR_0" in attr else np.ones((len(pos), 3))
                idx = accessor(j, b, p["indices"]).reshape(-1, 3)
                used = np.unique(idx)
                remap = -np.ones(len(pos), np.int64)
                remap[used] = np.arange(len(used))
                pos = (m[:3, :3] @ pos[used].T).T + m[:3, 3]
                nor = (m[:3, :3] @ nor[used].T).T
                nor /= np.maximum(np.linalg.norm(nor, axis=1, keepdims=True), 1e-9)
                mat = j["materials"][p["material"]]
                factor = np.array(mat.get("pbrMetallicRoughness", {}).get("baseColorFactor", [1, 1, 1, 1])[:3])
                out.append((mat["name"], pos, nor, uv[used], col[used] * factor, remap[idx]))
        for child in node.get("children", []):
            walk(child, m)

    for root in j["scenes"][j.get("scene", 0)]["nodes"]:
        walk(root, base)
    return out


def image_of(j, b):
    """GLB に入っている模様の画像(1枚)"""
    view = j["bufferViews"][j["images"][0]["bufferView"]]
    start = view.get("byteOffset", 0)
    return png_read(b[start:start + view["byteLength"]])


class Palette:
    """画像の右端に単色の見本を並べる(8px 四方。同じ色は使い回す)"""

    def __init__(self, img):
        self.img = img
        self.cells = {}

    def uv(self, rgb):
        key = tuple(int(round(c * 255)) for c in np.clip(rgb, 0, 1))
        if key not in self.cells:
            n = len(self.cells)
            col, row = n % ((WIDTH - PALETTE_X) // CELL), n // ((WIDTH - PALETTE_X) // CELL)
            assert row < HEIGHT // CELL, "色見本が入りきりません"
            x, y = PALETTE_X + col * CELL, row * CELL
            self.img[y:y + CELL, x:x + CELL, :3] = key
            self.img[y:y + CELL, x:x + CELL, 3] = 255
            self.cells[key] = ((x + CELL / 2) / WIDTH, (y + CELL / 2) / HEIGHT)
        return self.cells[key]


def textured_part(prims, source_img, notes, fabric=False):
    """いくつかの面を1つの部品にまとめ、模様の画像を作る(単色の面は色見本を指す)"""
    img = np.full((HEIGHT, WIDTH, 4), 255, np.uint8)  # 色見本の余白も不透明(本体が透けないように)
    img[:, :PALETTE_X] = source_img
    corner = source_img[-1, -1, :3] / 255.0
    pal = Palette(img)
    P, N, U, T = [], [], [], []
    base = 0
    for _, pos, nor, uv, col, tri in prims:
        uvs = np.zeros((len(pos), 2))
        for i in range(len(pos)):
            u, v = uv[i]
            if u > 0.995 and v > 0.995:
                uvs[i] = pal.uv(col[i] * corner)
            else:
                if np.any(np.abs(col[i] - 1) > 0.02):
                    notes["tinted"] = notes.get("tinted", 0) + 1
                uvs[i] = (u * PALETTE_X / WIDTH, v)
        P.append(pos)
        N.append(nor)
        U.append(uvs)
        T.append(tri + base)
        base += len(pos)
    if fabric:
        # 布: 黒 + 透け具合(白いほど透ける)。下に置く部品の色(艇番の色)が透けて、模様 × 艇番の色に見える
        lum = (0.2126 * img[:, :, 0] + 0.7152 * img[:, :, 1] + 0.0722 * img[:, :, 2]) / 255.0
        img[:, :, 3] = np.clip(np.round((1 - lum) * 255), 0, 255).astype(np.uint8)
        img[:, :, :3] = 0
    return np.vstack(P), np.vstack(N), np.vstack(U), np.vstack(T), img


def swatch_colors(pos, uv, tri, img, min_y=None):
    """出走表の小さな色見本に使う「主な色」と「差し色」。面の中心の色を面積で数え、多い順に選ぶ
    (min_y があれば、その高さより上の面だけ。艇外装は船底の茶色を数えない)"""
    a, b, c = pos[tri[:, 0]], pos[tri[:, 1]], pos[tri[:, 2]]
    area = np.linalg.norm(np.cross(b - a, c - a), axis=1) / 2
    if min_y is not None:
        area = area * (((a[:, 1] + b[:, 1] + c[:, 1]) / 3) > min_y)
    cuv = (uv[tri[:, 0]] + uv[tri[:, 1]] + uv[tri[:, 2]]) / 3
    x = np.clip((cuv[:, 0] * WIDTH).astype(int), 0, WIDTH - 1)
    y = np.clip((cuv[:, 1] * HEIGHT).astype(int), 0, HEIGHT - 1)
    rgb = img[y, x, :3].astype(int)
    bins = {}
    for col, w in zip(rgb, area):
        key = tuple(col // 24)
        total, acc = bins.get(key, (0.0, np.zeros(3)))
        bins[key] = (total + w, acc + col * w)
    ranked = sorted(bins.values(), key=lambda t: -t[0])
    main = ranked[0][1] / ranked[0][0]
    accent = main
    for total, acc in ranked[1:]:
        cand = acc / total
        if np.abs(cand - main).sum() > 90:  # はっきり違う色を差し色にする
            accent = cand
            break
    pack = lambda v: (int(v[0]) << 16) | (int(v[1]) << 8) | int(v[2])
    return pack(np.clip(main, 0, 255)), pack(np.clip(accent, 0, 255))


def solid_part(prims, corner):
    """単色の部品(金・シールド)。色は面の平均"""
    P = np.vstack([p[1] for p in prims])
    N = np.vstack([p[2] for p in prims])
    cols = np.vstack([p[4] for p in prims]) * corner
    T, base = [], 0
    for p in prims:
        T.append(p[5] + base)
        base += len(p[1])
    return P, N, None, np.vstack(T), cols.mean(axis=0)


class GlbWriter:
    """部品ごとに1つのノード・1つのメッシュを持つ GLB を作る"""

    def __init__(self):
        self.j = {"asset": {"version": "2.0", "generator": "minato gacha_items.py"}, "scene": 0,
                  "scenes": [{"nodes": []}], "nodes": [], "meshes": [], "materials": [], "accessors": [],
                  "bufferViews": [], "buffers": [], "images": [], "textures": [], "samplers": [{"magFilter": 9729, "minFilter": 9729}]}
        self.bin = bytearray()

    def view(self, data, target=None):
        while len(self.bin) % 4:
            self.bin.append(0)
        v = {"buffer": 0, "byteOffset": len(self.bin), "byteLength": len(data)}
        if target:
            v["target"] = target
        self.bin.extend(data)
        self.j["bufferViews"].append(v)
        return len(self.j["bufferViews"]) - 1

    def acc(self, arr, kind, ctype, target):
        data = arr.astype(np.float32 if ctype == 5126 else np.uint32).tobytes()
        a = {"bufferView": self.view(data, target), "componentType": ctype, "count": len(arr), "type": kind}
        if kind == "VEC3":
            a["min"] = arr.min(axis=0).tolist()
            a["max"] = arr.max(axis=0).tolist()
        self.j["accessors"].append(a)
        return len(self.j["accessors"]) - 1

    def part(self, name, pos, nor, uv, tri, img=None, color=None):
        attrs = {"POSITION": self.acc(pos, "VEC3", 5126, 34962), "NORMAL": self.acc(nor, "VEC3", 5126, 34962)}
        mat = {"name": name, "doubleSided": True, "pbrMetallicRoughness": {"metallicFactor": 0, "roughnessFactor": 0.6}}
        if uv is not None:
            attrs["TEXCOORD_0"] = self.acc(uv, "VEC2", 5126, 34962)
            image = len(self.j["images"])
            self.j["images"].append({"bufferView": self.view(png_write(img)), "mimeType": "image/png", "name": name})
            self.j["textures"].append({"source": image, "sampler": 0})
            mat["pbrMetallicRoughness"]["baseColorTexture"] = {"index": len(self.j["textures"]) - 1}
            if img[:, :, 3].min() < 255:
                mat["alphaMode"] = "BLEND"
        else:
            mat["pbrMetallicRoughness"]["baseColorFactor"] = [float(c) for c in color] + [1.0]
        self.j["materials"].append(mat)
        idx = self.acc(tri.reshape(-1), "SCALAR", 5125, 34963)
        self.j["meshes"].append({"name": name, "primitives": [{"attributes": attrs, "indices": idx, "material": len(self.j["materials"]) - 1}]})
        self.j["nodes"].append({"name": name, "mesh": len(self.j["meshes"]) - 1})
        self.j["scenes"][0]["nodes"].append(len(self.j["nodes"]) - 1)

    def save(self, path):
        while len(self.bin) % 4:
            self.bin.append(0)
        self.j["buffers"] = [{"byteLength": len(self.bin)}]
        js = json.dumps(self.j, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        while len(js) % 4:
            js += b" "
        body = struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(self.bin), 0x004E4942) + bytes(self.bin)
        with open(path, "wb") as f:
            f.write(struct.pack("<III", 0x46546C67, 2, 12 + len(body)) + body)


def to_roblox(pos, nor):
    """ブラウザ版の座標(m)を Roblox の艇の座標(studs)に。部品の中心と、中心から見た頂点を返す"""
    p = (TO_ROBLOX @ pos.T).T * STUDS
    n = (TO_ROBLOX @ nor.T).T
    lo, hi = p.min(axis=0), p.max(axis=0)
    center = (lo + hi) / 2
    return p - center, n, center, hi - lo


def lua_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    os.makedirs(OUT, exist_ok=True)
    rows = list(csv.DictReader(open(os.path.join(SOURCE, "Catalog.csv"), encoding="utf-8-sig")))
    writers = {slot: GlbWriter() for slot in FILES}
    manifest, items, notes = [], [], {}
    for row in rows:
        slot, prefix, group, place = SLOTS[row["種類"]]
        number = int(row["ID"].split("_")[1])
        item_id = f"{prefix}{number:02d}"
        j, b = glb_read(os.path.join(SOURCE, row["ZIP内の位置"]))
        prims = primitives(j, b, place)
        img = image_of(j, b)
        corner = img[-1, -1, :3] / 255.0
        swatch = (0xF2F2F0, 0xF2F2F0)
        groups = {"Body": [], "Gold": [], "Visor": [], "Fabric": []}
        for prim in prims:
            name = prim[0]
            kind = "Gold" if name == "Polished gold" else "Visor" if name == "Smoked shield" else "Fabric" if name == "Lane fabric" else "Body"
            groups[kind].append(prim)
        # 金・シールドに模様の面がある時は本体にまとめる(単色で塗れないため)
        for kind in ("Gold", "Visor"):
            if any(np.any(p[3].max(axis=1) <= 0.995) for p in groups[kind]):
                groups["Body"] += groups[kind]
                groups[kind] = []
                notes.setdefault("merged", []).append(item_id + kind)
        # Visor.lua・RacerAvatar.lua が材質名(__名前__)でヘルメットの殻・シールド・飾りを見分ける
        tags = {"Body": "Helmet" if slot == "helmet" else "Paint", "Gold": "HelmetStripe" if slot == "helmet" else "Gold",
                "Visor": "Visor", "Fabric": "Fabric"}
        for kind, prs in groups.items():
            if not prs:
                continue
            name = f"{item_id}__{tags[kind]}__{kind}"
            if kind in ("Body", "Fabric"):
                pos, nor, uv, tri, image = textured_part(prs, img[:, :, :], notes, fabric=(kind == "Fabric"))
                color = None
                if kind == "Body":
                    swatch = swatch_colors(pos, uv, tri, image, 0.3 if slot == "hull" else None)
            else:
                pos, nor, uv, tri, color = solid_part(prs, corner)
                image = None
            local, n, center, size = to_roblox(pos, nor)
            writers[slot].part(name, local, n, uv, tri, image, color)
            manifest.append({"name": name, "item": item_id, "slot": slot, "group": group, "kind": kind,
                             "center": [round(float(c), 5) for c in center], "size": [round(float(s), 5) for s in size],
                             "color": None if color is None else [round(float(c), 4) for c in color],
                             "triangles": int(len(tri))})
        items.append({"id": item_id, "slot": slot, "r": row["レアリティ"], "name": row["意匠"], "no": number, "swatch": swatch})
    # 共通の艇番の板(左右だけ。船首の白い板はない): 艇外装を付けた時に、元の板の代わりに出す
    j, b = glb_read(os.path.join(SOURCE, "共通部品", "Plates.glb"))
    prims = primitives(j, b, None)
    pos, nor, _, tri, _ = solid_part(prims, np.ones(3))
    local, n, center, size = to_roblox(pos, nor)
    writers["hull"].part("SidePlates__NumberPlate__Plate", local, n, None, tri, None, np.ones(3))
    manifest.append({"name": "SidePlates__NumberPlate__Plate", "item": "plates", "slot": "hull", "group": None, "kind": "Plate",
                     "center": [round(float(c), 5) for c in center], "size": [round(float(s), 5) for s in size],
                     "color": [1, 1, 1], "triangles": int(len(tri))})
    if "--catalog" not in sys.argv:  # --catalog の時は ItemCatalog.lua だけ作り直す
        for slot, w in writers.items():
            w.save(os.path.join(OUT, FILES[slot] + ".glb"))
        with open(os.path.join(ROOT, "assets", "items", "items-manifest.json"), "w", encoding="utf-8", newline="\n") as f:
            json.dump(manifest, f, ensure_ascii=False, indent=1)
            f.write("\n")
    # ゲームの品の一覧(ItemCatalog.lua)
    lines = ["-- ガチャの着せ替えの一覧(tools/gacha_items.py が Catalog.csv から作る。手で書き換えない)",
             "-- kind: skin 艇外装 / helmet ヘルメット / cowl モーターカバー / wheel ステアリング / flag 艇首旗",
             "-- 見た目の部品は ReplicatedStorage.VisualAssets.Items の同じ id の Model(assets/items/Items.rbxmx)",
             "-- color / accent は出走表の小さな色見本(模様の主な色と差し色。面積で数えた)", "return {"]
    for it in items:
        kind = "skin" if it["slot"] == "hull" else it["slot"]
        main, accent = it["swatch"]
        lines.append(f'\t{{ id = "{it["id"]}", kind = "{kind}", r = "{it["r"]}", name = {lua_string(it["name"])}, no = {it["no"]}, color = 0x{main:06X}, accent = 0x{accent:06X} }},')
    lines.append("}")
    with open(os.path.join(ROOT, "src", "ItemCatalog.lua"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    sizes = {s: os.path.getsize(os.path.join(OUT, FILES[s] + ".glb")) // 1024 for s in FILES}
    print(len(items), "items,", len(manifest), "parts, KB:", sizes, "notes:", {k: (v if isinstance(v, int) else len(v)) for k, v in notes.items()})


if __name__ == "__main__":
    sys.exit(main())
