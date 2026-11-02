# データの足し方(コードを書かずに増やす)

追加したら `lune run tests/run.luau` を実行してください。表の間違い(存在しないレア度・色の書式・名前の抜けなど)はテストと、サーバー起動時の Output(`[Config] ...`)で分かります。

## 妖怪魚を1匹足す

`src/shared/Config/Fish/Swamp.luau` に1行足します。

```lua
{ id = "kawa_tengu", ja = "川天狗", en = "River Tengu", rarity = "rare", time = "night", weather = "any",
  kg = { 1.0, 4.0 }, shape = "koi", c1 = "#B03A2E", c2 = "#F2D0A4", pattern = "stripes", deco = { "horns" },
  jaDesc = "図鑑の説明", enDesc = "Index text" },
```

| 項目 | 書けるもの |
| --- | --- |
| rarity | common(並) / uncommon(上) / rare(特上) / epic(極) / legendary(伝説) / mythic(神話) / secret(秘伝) |
| time | any / day / night / morning(朝は昼にも含まれる) |
| weather | any / sunny / rain / fog / thunder |
| shape | koi(鯉) / catfish(鯰) / puffer(河豚) / eel(鰻) / angler(提灯) / ray(鱏) |
| pattern | plain / stripes / spots / belly |
| deco | horns / lantern / whiskers / third_eye / big_eye / crown / flame / long_tail / noface / glow(いくつでも) |
| size | 見た目の大きさ(省略で1) |
| price | 基本の売値を上書きしたい時だけ |

- `id` は保存データのキーです。**公開後に変えない・消さない**こと(消すと図鑑から消えます)。
- 遊べる釣り場には、並〜神話の各レア度に `time = "any", weather = "any"` の魚が1匹以上必要です(テストで確認)。

## 釣り場を足す(例: 川)

1. `Config/Spots.luau` の `river` の行を `available = true` にし、`origin`(ワールドの位置)・`water`(水面の楕円)・`spawn` を決める
2. `Config/Fish/River.luau` を作り、魚の行を並べる
3. `Config/Fish/init.luau` の `SOURCES` に `{ spot = "river", list = require(script.River) :: any },` を足す
4. 景色: `src/server/World/Swamp.luau` をコピーして `River.luau` を作り、`init.server.luau` で `require(script.World.River).build()` を呼ぶ(地形は `Terrain.build` が楕円の池を作るので、川なら `rx` を小さく `rz` を長くする)
5. 村の鳥居(移動先)はお店の「釣り場」タブから行けます。村に専用の鳥居を置く場合は `Village.luau` で `Build.torii` と `Build.prompt(gate, "prompt_travel", "travel:river")`
6. 文言: `Locale/ja.luau` と `en.luau` の `spot_river` は登録済み

## 釣り場ごとの特別な変異

`Config/Mutations.luau` に行を足し(`global = false`)、`Spots.luau` の `mutations = { "crystal" }` に id を書きます。見た目は `Lib/FishBuilder.luau` の `MUTATION_LOOK` に1行。

## 依頼を足す

`Config/Quests.luau` に1行。種類(kind)は catch_any / catch_rarity / catch_weather / catch_time / catch_shape / catch_mutation / sell_coins。

## 数値を調整する

ほぼすべて `Config/Tuning.luau` にあります(アタリの時間、引き上げの難しさ、ぬしの必要量、デイリー報酬、自動保存の間隔など)。レア度ごとの値は `Rarities.luau`、竿は `Rods.luau`。

## 文言

`Locale/ja.luau` と `Locale/en.luau` の両方に同じキーで足します(片方だけだとテストが失敗します)。
