# 妖怪魚50種のデザイン仕様 → Config/Fish/*.luau を生成する(デザインを一覧で管理するための道具)
# 使い方: python3 tools/fish_designs.py   (ゲームのデータを書き換える)
# 見た目の項目: c1 体 / c2 模様 / c3 差し色 / pattern / deco / eyes / mouth / body {幅,高さ,長さ} / tails / size
import json, re, sys, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ---- 沼(30種)の見た目。ゲームの数値(レア度・時間・天気・重さ)は今の表から引き継ぐ ----
SWAMP_LOOK = {
    "doro_funa":        dict(c1="#6E5B3E", c2="#B9A57A", c3="#8C7A4E", pattern="belly",   eyes="dot",    mouth="frown", body=[1.05, 0.95, 1.0], deco=[]),
    "ashi_medaka":      dict(c1="#A8B86A", c2="#5E7A3A", c3="#E6DFA0", pattern="stripes", eyes="cute",   mouth="small", body=[0.8, 0.85, 1.1], size=0.75, deco=[]),
    "ko_namazu":        dict(c1="#5A5148", c2="#8A7B66", c3="#A39276", pattern="belly",   eyes="sleepy", mouth="wide",  body=[1.1, 0.9, 0.95], deco=["whiskers"]),
    "hotaru_dojo":      dict(c1="#3B3324", c2="#D7FF6B", c3="#9BBF3A", pattern="spots",   eyes="dot",    mouth="smile", size=0.75, deco=["glow"]),
    "ame_gaeru":        dict(c1="#5FB343", c2="#F2E58C", c3="#2F7A36", pattern="belly",   eyes="cute",   mouth="smile", body=[1.05, 0.85, 1.0], size=0.85, deco=["smooth"]),
    "kiri_shirauo":     dict(c1="#E3ECF0", c2="#9FC6D6", c3="#9FE3F0", pattern="gradient", eyes="dot",   mouth="small", body=[0.8, 0.8, 1.05], size=0.7, deco=[]),
    "hasu_koi":         dict(c1="#F4F1EA", c2="#E2483D", c3="#F5A3B5", pattern="patches", eyes="normal", mouth="small", deco=["lotus"]),
    "kappa_haze":       dict(c1="#6E9E4A", c2="#C9D88A", c3="#3F6B2E", pattern="spots",   eyes="cute",   mouth="geta",  body=[0.95, 0.95, 0.85], size=0.8, deco=[]),
    "kappa_koi":        dict(c1="#3F8F5A", c2="#D9C35A", c3="#7A5A2E", pattern="belly",   eyes="normal", mouth="beak",  deco=["crown"]),
    "hitotsume_namazu": dict(c1="#4A3F66", c2="#8C7FB5", c3="#B9A8E8", pattern="belly",   eyes="big",    mouth="tongue", deco=["whiskers"]),
    "bake_fugu":        dict(c1="#D79A3E", c2="#6B4520", c3="#6FAF4A", pattern="saddle",  eyes="cute",   mouth="smile", deco=["leaf", "blush", "smooth"]),
    "nure_unagi":       dict(c1="#2E5552", c2="#86B3AE", c3="#1C2626", pattern="stripes", eyes="sleepy", mouth="small", tails=2, deco=["hair"]),
    "kitsunebi_ayu":    dict(c1="#E8893A", c2="#FFE7B8", c3="#7AD8FF", pattern="belly",   eyes="sleepy", mouth="smile", size=0.9, deco=["ears", "flame"]),
    "sunakake_dojo":    dict(c1="#C9A86A", c2="#7E6233", c3="#E8D2A0", pattern="spots",   eyes="angry",  mouth="frown", size=0.85, deco=["whiskers", "hat"]),
    "tengu_ei":         dict(c1="#C0392B", c2="#F2D0A4", c3="#2B2222", pattern="belly",   eyes="angry",  mouth="none",  deco=["nose", "crest"]),
    "chochin_anko":     dict(c1="#35264A", c2="#FF9E3D", c3="#FFCE6B", pattern="spots",   eyes="cute",   mouth="grin",  deco=["lantern"]),
    "karakasa_fugu":    dict(c1="#D8443C", c2="#F7E9D7", c3="#C79A4B", pattern="stripes", eyes="big",    mouth="tongue", deco=["umbrella", "smooth"]),
    "raijin_namazu":    dict(c1="#2D3D7A", c2="#FFD84A", c3="#FFF2A8", pattern="stripes", eyes="angry",  mouth="fangs", deco=["drums", "horns", "whiskers", "glow"]),
    "yukionna_ei":      dict(c1="#BFDDF5", c2="#EAF6FF", c3="#1C2A3A", pattern="belly",   eyes="sleepy", mouth="small", deco=["hair", "glow"]),
    "nekomata_koi":     dict(c1="#26242A", c2="#F2F2F2", c3="#F2B84B", pattern="patches", eyes="cat",    mouth="smile", tails=2, deco=["ears", "bell"]),
    "nopperabo":        dict(c1="#E9E1EE", c2="#FFFFFF", c3="#B7A9C9", pattern="belly",   eyes="none",   mouth="none",  deco=["hat"]),
    "oni_unagi":        dict(c1="#B8322C", c2="#2A1A1A", c3="#F2C14E", pattern="stripes", eyes="angry",  mouth="fangs", body=[1.15, 1.1, 1.0], deco=["horns"]),
    "tsuchinoko_fugu":  dict(c1="#8A7A4A", c2="#5A4A2A", c3="#D8C27A", pattern="stripes", eyes="cute",   mouth="tongue", body=[1.1, 0.85, 1.35], deco=["coin", "smooth"]),
    "rokurokubi_unagi": dict(c1="#EADBCB", c2="#B03A5A", c3="#2B1B2E", pattern="belly",   eyes="sleepy", mouth="smile", body=[0.9, 0.9, 1.35], deco=["hair", "kanzashi"]),
    "kodama_koi":       dict(c1="#D6EBC4", c2="#6FAF4A", c3="#A7D98A", pattern="spots",   eyes="dot",    mouth="o",     body=[1.0, 1.1, 0.9], deco=["glow", "leaf"]),
    "nue_namazu":       dict(c1="#4A3220", c2="#D9A441", c3="#5E8C4A", pattern="stripes", eyes="angry",  mouth="fangs", tails=2, deco=["horns", "ears", "whiskers", "flame"]),
    "kyubi_koi":        dict(c1="#FFDC8A", c2="#FF8F3D", c3="#FFF0B8", pattern="belly",   eyes="sleepy", mouth="smile", tails=9, deco=["ears", "flame"]),
    "umibozu_ei":       dict(c1="#16182A", c2="#2E3456", c3="#6E7BD6", pattern="belly",   eyes="big",    mouth="none",  size=1.1, deco=["bighead", "glow"]),
    "numa_mizuchi":     dict(c1="#1F7A63", c2="#FFD34D", c3="#FFE9A3", pattern="spots",   eyes="angry",  mouth="fangs", deco=["antlers", "whiskers", "mane", "orb", "glow"]),
    "yamata_chochin":   dict(c1="#3A0F24", c2="#FF3D6E", c3="#FFC94D", pattern="stripes", eyes="angry",  mouth="grin",  deco=["lantern", "third_eye", "horns", "flame"]),
}

# ---- ぬしの湖(20種・新規) ----
LAKE = [
    # 並
    dict(id="koban_funa", ja="小判鮒", en="Koban Crucian", element="earth", rarity="common", time="any", weather="any", kg=[0.4, 1.6], shape="koi",
         c1="#A08A4E", c2="#D9C27A", c3="#7A6630", pattern="belly", eyes="dot", mouth="smile", body=[1.15, 1.0, 0.85], deco=["coin"],
         jaDesc="額に小判の模様。釣れると少し得した気分になる。", enDesc="A coin mark on its forehead. Catching one feels lucky."),
    dict(id="furin_kingyo", ja="風鈴金魚", en="Wind-Chime Goldfish", element="water", rarity="common", time="day", weather="sunny", kg=[0.1, 0.6], shape="koi",
         c1="#E8452E", c2="#FFFFFF", c3="#FFB3A1", pattern="patches", eyes="cute", mouth="o", body=[1.1, 1.15, 0.8], tails=3, size=0.8, deco=["bell"],
         jaDesc="夏の晴れた日、風鈴の音に誘われて泳ぎ出る。", enDesc="On sunny summer days it swims out to the sound of wind chimes."),
    dict(id="dango_unagi", ja="団子鰻", en="Dango Eel", element="earth", rarity="common", time="day", weather="any", kg=[0.3, 1.2], shape="eel",
         c1="#F3E7D3", c2="#F59AB5", c3="#8CC47A", pattern="dango", eyes="cute", mouth="smile", size=0.85, deco=["blush"],
         jaDesc="花見の季節に現れる、三色の鰻。甘い香りがする。", enDesc="A three-colored eel of cherry-blossom season. Smells sweet."),
    dict(id="kawara_ei", ja="瓦鱏", en="Roof-Tile Ray", element="earth", rarity="common", time="night", weather="any", kg=[0.8, 2.5], shape="ray",
         c1="#5D6470", c2="#3E434C", c3="#9AA3B0", pattern="stripes", eyes="dot", mouth="none", deco=[],
         jaDesc="古い寺の瓦がはがれて、夜の湖を泳ぎ出した。", enDesc="A tile that slid off an old temple roof and swam away at night."),
    dict(id="geta_fugu", ja="下駄河豚", en="Geta Puffer", element="water", rarity="common", time="any", weather="rain", kg=[0.3, 1.4], shape="puffer",
         c1="#C69C6D", c2="#7A5230", c3="#D7263D", pattern="saddle", eyes="normal", mouth="geta", deco=[],
         jaDesc="雨の日、からんころんと下駄の音を鳴らして泳ぐ。", enDesc="On rainy days it clip-clops like wooden sandals."),
    # 上
    dict(id="akaname_namazu", ja="垢嘗鯰", en="Akaname Catfish", element="spirit", rarity="uncommon", time="night", weather="any", kg=[0.8, 3.0], shape="catfish",
         c1="#C8483B", c2="#F08A6E", c3="#5A1E1A", pattern="belly", eyes="cute", mouth="tongue", deco=["whiskers"],
         jaDesc="風呂場の垢をなめて回る鯰。長い舌が自慢。", enDesc="It licks bathhouse grime clean. Proud of its long tongue."),
    dict(id="zashiki_koi", ja="座敷童鯉", en="Zashiki-Warashi Koi", element="spirit", rarity="uncommon", time="any", weather="any", kg=[0.5, 2.0], shape="koi",
         c1="#F6E3D3", c2="#D94F4F", c3="#2B2430", pattern="belly", eyes="cute", mouth="smile", deco=["okappa", "blush"],
         jaDesc="おかっぱ頭の鯉。見た者の家には福が来るという。", enDesc="A bob-haired koi. The home of whoever sees it is blessed."),
    dict(id="ittan_ei", ja="一反木綿鱏", en="Ittan-Momen Ray", element="spirit", rarity="uncommon", time="any", weather="fog", kg=[0.5, 2.0], shape="ray",
         c1="#F2F0E8", c2="#DCD6C8", c3="#A79F8E", pattern="belly", eyes="dot", mouth="none", deco=["cloth"],
         jaDesc="霧の夜、一反の布のようにひらひらと泳ぐ。", enDesc="On foggy nights it flutters like a long strip of cloth."),
    dict(id="tsurube_fugu", ja="釣瓶河豚", en="Tsurube Puffer", element="earth", rarity="uncommon", time="night", weather="any", kg=[1.0, 3.0], shape="puffer",
         c1="#8B5A2B", c2="#5C3A1A", c3="#F2D16B", pattern="stripes", eyes="angry", mouth="grin", deco=["crest"],
         jaDesc="夜道の木の上から、どすんと落ちてくる大きな頭。", enDesc="A huge head that drops from trees onto night roads."),
    # 特上
    dict(id="kasha_namazu", ja="火車鯰", en="Kasha Catfish", element="fire", rarity="rare", time="night", weather="any", kg=[2.0, 7.0], shape="catfish",
         c1="#2A2230", c2="#FF7A2E", c3="#FFB547", pattern="saddle", eyes="cat", mouth="fangs", deco=["fire_wheel", "ears"],
         jaDesc="炎の車を引く猫の妖怪が、鯰に化けたもの。", enDesc="A cat demon that pulls a burning cart, now a catfish."),
    dict(id="ushioni_ei", ja="牛鬼鱏", en="Ushi-Oni Ray", element="earth", rarity="rare", time="any", weather="rain", kg=[3.0, 9.0], shape="ray",
         c1="#3B2F2A", c2="#8A2B2B", c3="#E8D7B0", pattern="spots", eyes="angry", mouth="fangs", deco=["horns"],
         jaDesc="雨の日の水辺に現れる、牛の頭を持つ鱏。", enDesc="An ox-headed ray that haunts shores on rainy days."),
    dict(id="komainu_koi", ja="狛犬鯉", en="Komainu Koi", element="earth", rarity="rare", time="any", weather="any", kg=[1.5, 5.0], shape="koi",
         c1="#4FA59A", c2="#E8C65A", c3="#2E6B64", pattern="patches", eyes="angry", mouth="fangs", body=[1.05, 1.05, 0.95], deco=["crest", "bell"],
         jaDesc="神社を守る狛犬の鯉。本当は二匹いるはず。", enDesc="A shrine-guardian koi. There should be a pair..."),
    dict(id="nurari_unagi", ja="ぬらりひょん鰻", en="Nurarihyon Eel", element="spirit", rarity="rare", time="night", weather="any", kg=[1.0, 5.0], shape="eel",
         c1="#D9C2A7", c2="#5B4A7A", c3="#2B2440", pattern="belly", eyes="sleepy", mouth="smile", deco=["bighead", "beard"],
         jaDesc="いつの間にか家に上がり込んでいる、妖怪の総大将。", enDesc="The supreme yokai boss who slips into homes unnoticed."),
    # 極
    dict(id="fujin_ei", ja="風神鱏", en="Fujin Ray", element="thunder", rarity="epic", time="any", weather="any", kg=[4.0, 12.0], shape="ray",
         c1="#3E8E5E", c2="#CDE8B0", c3="#F2F0E8", pattern="belly", eyes="angry", mouth="fangs", deco=["wind_bag", "horns"],
         jaDesc="雷神の相棒。背中の風袋で嵐を起こす。", enDesc="Raijin's partner. Its wind bag stirs up storms."),
    dict(id="gasha_unagi", ja="がしゃどくろ鰻", en="Gashadokuro Eel", element="spirit", rarity="epic", time="night", weather="any", kg=[3.0, 15.0], shape="eel",
         c1="#EDE6D6", c2="#3A3530", c3="#FF3D3D", pattern="ribs", eyes="glow", mouth="grin", body=[1.1, 1.05, 1.1], deco=[],
         jaDesc="夜に骨の鳴る音がしたら、それはもう近い。", enDesc="If you hear rattling bones at night, it's already close."),
    dict(id="kingyo_hime", ja="金魚姫", en="Goldfish Princess", element="water", rarity="epic", time="day", weather="any", kg=[0.8, 3.0], shape="koi",
         c1="#FF6B4A", c2="#FFE0D6", c3="#FFD34D", pattern="patches", eyes="cute", mouth="smile", body=[1.15, 1.2, 0.85], tails=4, deco=["kanzashi", "frills", "blush"],
         jaDesc="城の池から逃げ出した、金魚のお姫さま。", enDesc="A goldfish princess who escaped the castle pond."),
    # 伝説
    dict(id="yatagarasu_ei", ja="八咫烏鱏", en="Yatagarasu Ray", element="fire", rarity="legendary", time="any", weather="any", kg=[6.0, 20.0], shape="ray",
         c1="#1A1A22", c2="#3A3A48", c3="#FFB547", pattern="belly", eyes="normal", mouth="beak", deco=["sun_disc", "crest"],
         jaDesc="太陽の使い。道に迷った者を正しい方へ導く。", enDesc="Messenger of the sun. It guides the lost the right way."),
    dict(id="houou_koi", ja="鳳凰鯉", en="Phoenix Koi", element="fire", rarity="legendary", time="morning", weather="any", kg=[4.0, 14.0], shape="koi",
         c1="#E8483B", c2="#FFC94D", c3="#3FB7A8", pattern="gradient", eyes="sleepy", mouth="small", deco=["plumes", "crest", "flame"],
         jaDesc="朝日とともに舞い上がる、不死の鯉。", enDesc="An undying koi that rises with the morning sun."),
    # 神話
    dict(id="ryujin", ja="龍神", en="Ryujin", element="water", rarity="mythic", time="any", weather="any", kg=[40.0, 120.0], shape="eel",
         c1="#E8F1F2", c2="#7FC8D8", c3="#FFD34D", pattern="spots", eyes="angry", mouth="fangs", size=1.1, deco=["antlers", "mane", "whiskers", "orb", "shimenawa"],
         jaDesc="湖の底の宮に住む龍の神。ぬしの湖の本当の主。", enDesc="The dragon god of the lake-bottom palace. The lake's true lord."),
    # 秘伝
    dict(id="tsukuyomi_koi", ja="月読鯉", en="Tsukuyomi Koi", element="spirit", rarity="secret", time="night", weather="fog", kg=[20.0, 80.0], shape="koi",
         c1="#2B3A6B", c2="#C9D6FF", c3="#F4F1C8", pattern="gradient", eyes="glow", mouth="small", tails=3, deco=["moon", "frills", "kanzashi"],
         jaDesc="霧の夜、湖に映った月から生まれるという鯉。", enDesc="Said to be born from the moon's reflection on foggy nights."),
]

LOOK_KEYS = ["shape", "c1", "c2", "c3", "pattern", "eyes", "mouth", "body", "tails", "deco", "size"]

def lua_val(v):
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v) if isinstance(v, float) else str(v)
    if isinstance(v, list):
        return "{ " + ", ".join(lua_val(x) for x in v) + " }" if v else "{}"
    raise TypeError(v)

ORDER = ["id", "ja", "en", "element", "rarity", "time", "weather", "kg", "shape", "c1", "c2", "c3", "pattern", "eyes", "mouth", "body", "tails", "deco", "size", "jaDesc", "enDesc"]

def row(f):
    parts = []
    for k in ORDER:
        if k in f and f[k] is not None:
            parts.append(f"{k} = {lua_val(f[k])}")
    return "\t{ " + ", ".join(parts) + " },"

HEADER = """--!strict
-- {title}。1行 = 1匹。tools/fish_designs.py で生成(デザインの意図は docs/FISH_DESIGN.md)。
--   id      : 一意な英数字(保存データのキーになるので、公開後に変更しないこと)
--   ja / en : 名前
--   element : 属性 water(水) / fire(火) / thunder(雷) / earth(土) / spirit(霊)  ※相棒バトル用
--   rarity  : common / uncommon / rare / epic / legendary / mythic / secret
--   time    : any / day / night / morning(朝。昼にも含まれる)
--   weather : any / sunny / rain / fog / thunder
--   kg      : 重さの範囲 {{ 最小, 最大 }}
--   shape   : koi(鯉) / catfish(鯰) / puffer(河豚) / eel(鰻) / angler(提灯) / ray(鱏)
--   c1, c2, c3 : 色(体, 模様, 差し色)
--   pattern : plain / stripes / spots / belly / patches / saddle / gradient / ribs / dango
--   eyes    : normal / cute / angry / sleepy / big(一つ目) / cat / glow / dot / none
--   mouth   : small / wide / o / smile / frown / open / tongue / fangs / grin / geta / beak / none
--   body    : 体つき {{ 幅, 高さ, 長さ }} の倍率 / tails : 尾の本数 / size : 大きさの微調整(レア度の大きさに掛け算)
--   deco    : 飾り(一覧は Config/init.luau の DECOS)
--   jaDesc / enDesc : 図鑑の説明
-- レア度の格(大きさ・ツヤ・縁取り・金・後光)は FishBuilder が自動で付ける。

local F = {{
{rows}
}}

return F
"""

def main():
    export = os.path.join(sys.argv[1]) if len(sys.argv) > 1 else None
    swamp_src = open(os.path.join(ROOT, "src/shared/Config/Fish/Swamp.luau")).read()
    # 今の沼の表からゲームの数値を読む(id ごとの行)
    swamp = []
    for m in re.finditer(r'\{\s*id = "([a-z_]+)",(.*?)\n?\t\},', swamp_src, re.S):
        fid = m.group(1)
        body = m.group(2)
        def get(key):
            mm = re.search(key + r' = ("(?:[^"\\]|\\.)*"|\{[^}]*\})', body)
            return mm.group(1) if mm else None
        f = {"id": fid}
        for k in ["ja", "en", "element", "rarity", "time", "weather", "shape", "jaDesc", "enDesc"]:
            f[k] = json.loads(get(k))
        kg = get("kg")
        f["kg"] = [float(x) for x in re.findall(r"[\d.]+", kg)]
        look = dict(SWAMP_LOOK[fid])
        f.update(look)
        swamp.append(f)
    assert len(swamp) == 30, len(swamp)
    open(os.path.join(ROOT, "src/shared/Config/Fish/Swamp.luau"), "w").write(
        HEADER.format(title="沼の妖怪魚(30種)", rows="\n".join(row(f) for f in swamp)))
    open(os.path.join(ROOT, "src/shared/Config/Fish/NushiLake.luau"), "w").write(
        HEADER.format(title="ぬしの湖の妖怪魚(20種)", rows="\n".join(row(f) for f in LAKE)))
    print("wrote", len(swamp), "+", len(LAKE))

if __name__ == "__main__":
    main()
