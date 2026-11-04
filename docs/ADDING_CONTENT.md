# データの足し方(コードを書かずに増やす)

追加したら `lune run tests/run.luau` を実行してください。表の間違い(存在しないレア度・色の書式・名前の抜けなど)はテストと、サーバー起動時の Output(`[Config] ...`)で分かります。

## 妖怪魚を1匹足す

魚の表(`Config/Fish/Swamp.luau` / `NushiLake.luau` / `River.luau` / `Sea.luau`)は `tools/fish_designs.py` から作っています。
新しい魚は `tools/fish_designs.py` に1行足して `python3 tools/fish_designs.py` を実行してください(表に直接書いても動きますが、次に生成した時に消えます)。
見た目の項目(目・口・体つき・尾の本数・飾り)は [FISH_DESIGN.md](FISH_DESIGN.md) を参照。表の1行の例:

```lua
{ id = "kawa_tengu", ja = "カワテン", en = "Kawaten", kindJa = "川天狗", kindEn = "River Tengu", rarity = "rare", time = "night", weather = "any",
  kg = { 1.0, 4.0 }, shape = "koi", c1 = "#B03A2E", c2 = "#F2D0A4", pattern = "stripes", deco = { "horns" },
  jaDesc = "図鑑の説明", enDesc = "Index text" },
```

| 項目 | 書けるもの |
| --- | --- |
| ja / en | 名前。カタカナのあだ名(3〜6文字)と、その読みのローマ字([FISH_DESIGN.md](FISH_DESIGN.md) のルール0) |
| kindJa / kindEn | 種類(もとになった魚と妖怪。例: 川天狗 / River Tengu)。図鑑と釣果の画面に小さく出る |
| rarity | common(並) / uncommon(上) / rare(特上) / epic(極) / legendary(伝説) / mythic(神話) / secret(秘伝) |
| time | any / day / night / morning(朝は昼にも含まれる) |
| weather | any / sunny / rain / fog / thunder |
| shape | koi(鯉) / catfish(鯰) / puffer(河豚) / eel(鰻) / angler(提灯) / ray(鱏) / shark(鮫) / orca(鯱) / salmon(鮭) / salamander(山椒魚) / whale(鯨) / sturgeon(蝶鮫) |
| pattern | plain / stripes / spots / belly / patches / saddle / gradient / ribs / dango / orca(鯱の白黒) |
| eyes | normal / cute / angry / sleepy / big / cat / glow / dot / none |
| mouth | small / wide / o / smile / frown / open / tongue / fangs / grin / geta / beak / jaws(鮫の歯) / none |
| body | 体つき { 幅, 高さ, 長さ } の倍率(省略で {1,1,1}) |
| tails | 尾の本数(1〜9) |
| deco | 目印の飾り(38種。一覧は Config/init.luau の DECOS) |
| size | 見た目の大きさの微調整(省略で1。レア度の大きさに掛け算) |
| c3 | (省略可)差し色。ひれ・角の先・皿の縁に使う |
| element | 相棒バトルの属性 water / fire / thunder / earth / spirit |
| price | 基本の売値を上書きしたい時だけ |

- 色と飾りの決め方は [FISH_DESIGN.md](FISH_DESIGN.md) のルールに合わせてください。見た目は `lune run tools/export_fish.luau out.json` で確認できます
- `id` は保存データのキーです。**公開後に変えない・消さない**こと(消すと図鑑から消えます)。
- 遊べる釣り場には、並〜神話の各レア度に `time = "any", weather = "any"` の魚が1匹以上必要です(テストで確認)。
- **魚は本物が住んでいる場所の釣り場に置きます**。鱏・河豚・鮟鱇・鮫・鯱・鯨の形は海だけ、鯰・鮭・山椒魚・蝶鮫の形は淡水(沼・湖・川)だけ(テストで確認)。強い魚(伝説・神話・秘伝)は、どの釣り場にもその場所らしいものを置きます
- 鳴き声: `tools/cries/yokai_cries.py` にレシピを足して作り直し、音をアップロードし直します([CRIES.md](CRIES.md))。レシピが無くても形から自動で作ります
- 3Dモデル: その魚だけ Blender で書き出して GLB の中で差し替えます([ANIME_MESHES.md](ANIME_MESHES.md) の「数匹だけ作り直す時」)

## 釣り場を足す(例: 滝つぼ)

川(`World/River.luau`)と海(`World/Sea.luau`)がお手本です。

1. `Config/Spots.luau` の `waterfall` の行を `available = true` にし、`origin`(ワールドの位置)・`water`(水面の楕円)・`spawn`・解放の条件(`unlockRodTier` / `unlockCoins`)・売値の倍率を決める。`lune run tests/economy_sim.luau` で何分で開くかを確かめる
2. `tools/fish_designs.py` に魚の表(`WATERFALL = [...]`)を足して表を書き出す(`Config/Fish/Waterfall.luau`)。並〜神話の各レア度に `time = "any", weather = "any"` の魚を1匹以上
3. `Config/Fish/init.luau` の `SOURCES` に `{ spot = "waterfall", list = require(script.Waterfall) :: any },` を足す
4. 景色: `River.luau` をコピーして `Waterfall.luau` を作り、`init.server.luau` と `tools/map/export_map.luau` で `build()` を呼ぶ。出現地点は `Enabled = false`(最初は沼に出る)。`tests/world_smoke.luau` に1つテストを足す
   - 地形は `Terrain.build` が楕円の池を作る(川は `rx` を小さく `rz` を長く)。海のように片側を外海にするなら `Sea.luau` の `isOcean`
5. 移動はお店の「釣り場」タブと、各釣り場の村への鳥居(`travel:nushi_lake`)
6. 文言: `Locale/ja.luau` と `en.luau` の `spot_<id>`(登録済み)と、図鑑の称号 `title_<id>_master`(`Tuning.Titles` にも)
7. 3Dモデル・鳴き声を作る(上の「妖怪魚を1匹足す」)

## 釣り場ごとの特別な変異

`Config/Mutations.luau` に行を足し(`global = false`)、`Spots.luau` の `mutations = { "crystal" }` に id を書きます。見た目は `Lib/FishBuilder.luau` の `MUTATION_LOOK` に1行。

## 依頼を足す

`Config/Quests.luau` に1行。種類(kind)は catch_any / catch_rarity / catch_weather / catch_time / catch_shape / catch_mutation / sell_coins。

## 数値を調整する

ほぼすべて `Config/Tuning.luau` にあります(アタリの時間、引き上げの難しさ、ぬしの必要量、デイリー報酬、自動保存の間隔など)。レア度ごとの値は `Rarities.luau`、竿は `Rods.luau`。

## 妖怪退治の相手を足す

`Config/Trainers.luau` に1行。上から順番に挑戦できます(前の相手に勝つと次が開く)。

```lua
{ id = "kawauso", ja = "川獺", en = "River Otter", jaLine = "勝負だ!", enLine = "Let's go!",
  team = { { fish = "nure_unagi", level = 12 }, { fish = "tengu_ei", level = 13, mutation = "gold" } },
  reward = { coins = 4000, bait = { id = "glow_shrimp", amount = 2 } } },
```

- `team` は最大3匹。魚は図鑑の魚の id を使います(見た目・能力・技は自動で決まる)
- `title` を付ける場合は `Tuning.Titles` と Locale(`title_<id>`)にも足す
- テストが「一番強い魚のレベルが前の相手より高いか」を確認します

## 属性・技を足す

`Config/Battle.luau`
- 魚の属性は魚の表の `element`(water / fire / thunder / earth / spirit)
- 技は `Moves` に1行。`effect` は atk_down / def_down / atk_up / def_up / heal / stun / first
- 属性ごとに覚える技は `ElementMoves`、体の形ごとの技は `ShapeMove`、覚えるレベルは `LearnLevels`
- 相性は `Chart`、能力は `ShapeStats` と `RarityPower`、経験値は `xpToNext` と `FeedXp`

## 文言

`Locale/ja.luau` と `Locale/en.luau` の両方に同じキーで足します(片方だけだとテストが失敗します)。
