# アニメ風の妖怪魚(Blender で作ったメッシュ)

50種すべてを Blender でアニメキャラクター風の3Dモデルにしてあります。
`assets/fish/YokaiFishMeshes.glb` を Studio に1回読み込むだけで、ゲーム中の魚(釣果・図鑑・水槽・ぬし・相棒バトル)がすべてアニメ風に変わります。
読み込むまでの間は、これまでどおりパーツで組み立てた魚が出ます(ゲームは止まりません)。

## つくり

1匹ずつ「細かい版」と「ゲーム用の軽い版」の2つを作り、細かい版の見た目を軽い版のテクスチャに焼き込んでいます。

| | 細かい版(焼き込みの元) | ゲーム用(GLB に入るもの) |
| --- | --- | --- |
| 三角形 | 1匹 13〜18万 | 1匹 15,000 以下 + 輪郭線 7,500 前後(Roblox の上限 20,000 以内) |
| 色 | 頂点ごとの色 | 1024px の色テクスチャ(全種) |
| 凹凸 | 彫った形そのもの | 1024px の法線マップ(全種) |

- **体**: 頭・胴・尾の付け根などの楕円体を、細かいボクセルで溶かして一体化したなめらかな体。その上に彫り込み:
  - 鯉型: 重なった鱗(尾の側の縁だけ弧にする)、えらぶたの「)」形の線(鱗はえらより後ろだけ)
  - 鯉型・なまず型・うなぎ型: 点線の側線
  - あんこう型: いぼ / ふぐ型: 毛穴 / えい型: 背中の明るい点々 / なまず型・うなぎ型: ぬめったまだら
  - 全体に細かい肌の凹凸
- **目**: 頭の丸みに沿って曲がった白目(上に影)、放射の筋と縁の濃い輪がある虹彩(上が濃いグラデーション)、輪のある瞳、斜めの楕円の光と小さな丸、レアな魚とかわいい目には星のきらめき。上まつげの太い線と目尻の3本の跳ね、下まつげ、二重の線。目の種類(かわいい・怒り眉・半目・猫目・一つ目・光る目・点の目・無し)はデザインの表のまま
- **ひれ**: 根元から放射状の筋、根元→先のグラデーション、筋の間のぎざぎざの縁、縁取りの色(レアほど太く、伝説以上は金)
- **塗り**: 平らな色に、2段のアニメ影と頭の上のツヤを焼き込み済み。Roblox の光の当たり方に左右されにくい
- **輪郭線**: 少し大きい裏返しの殻(`<id>_Outline`)。Roblox は裏面を描かないので、外周だけが線になる
- **レア度**: 大きさ・ひれの縁取り・額の金の紋・後光の輪・鬼火はモデルに入っている。光の粒・炎・光源・変異の上塗りはゲーム側で付ける

ゲーム用の軽い版は、体を左右対称のまま間引き、目は白目の形だけにしています(虹彩・瞳・光の絵はテクスチャに入っているので、薄い板を何枚も重ねなくてよい)。
書き出しのたびに、次を自動で検査しています。

- 体の面が外向き・輪郭線の面が内向きになっているか(光線で確認。向きが逆だと Roblox で真っ黒・透明になる)
- どのメッシュも 20,000 三角形を超えていないか

## Studio に入れる手順(1回だけ)

1. Roblox Studio でゲームを開き、ログインしていることを確認する(読み込み時にメッシュと画像があなたのアカウントにアップロードされます)
2. **ファイル → 3D をインポート**(Import 3D)で `assets/fish/YokaiFishMeshes.glb` を選ぶ
3. 設定はそのままで読み込む。数分かかることがあります(色と法線マップは、各魚の `SurfaceAppearance` として入ります)
4. ワークスペースに読み込まれたモデルを **ReplicatedStorage** へドラッグし、名前を **`FishMeshes`** に変える
   - 中に `hasu_koi` と `hasu_koi_Outline` のように、魚の id と `<id>_Outline` の名前のパーツが並んでいれば OK(フォルダやモデルの入れ子になっていても探せます)
5. プレイして確認する

Rojo は `ReplicatedStorage.Shared` だけを同期するので、`FishMeshes` は Rojo に消されません。

### うまくいかない時

| 症状 | 直し方 |
| --- | --- |
| 魚が後ろ向きに泳ぐ | `src/shared/Config/FishMeshes.luau` の `rotationY = 180` |
| 魚が大きすぎる・小さすぎる | 同じファイルの `unit`(既定 1.2)を変える |
| 魚が真っ黒 | 輪郭線のパーツの `DoubleSided` がオンになっていないか確認(オフにする) |
| 鱗などの凹凸が見えない | 魚のパーツの中に `SurfaceAppearance`(NormalMap 付き)があるか確認。無ければ読み込みの設定でテクスチャを入れ直す |
| 輪郭線に色がついている | ゲームが自動で単色にします(輪郭線の `SurfaceAppearance` は外す)。Studio の見た目だけなら気にしなくてよい |
| 一部の魚だけパーツの見た目のまま | `FishMeshes` の中にその魚の id の名前のパーツがあるか確認 |
| 前のパーツの見た目に戻したい | `FishMeshes` を削除する(または名前を変える) |

## 作り直す(デザインを変えた時)

魚の表(`tools/fish_designs.py` → `Config/Fish/*.luau`)を変えたら、次で作り直せます。

```bash
lune run tools/export_fish.luau build/fish.json
blender -b -P tools/blender/yokai_fish.py -- --defs build/fish.json --out build/fish --export --luau src/shared/Config/FishMeshes.luau
cp build/fish/YokaiFishMeshes.glb assets/fish/
```

細かい版を作るので、1匹 1〜2分かかります。CPU が4つ以上あるなら、4つに分けて同時に作り、最後に1つにまとめると速くなります(`--ids` は魚の id をカンマ区切り)。

```bash
B="blender -b -P tools/blender/yokai_fish.py --"
$B --defs build/fish.json --out build/fish --export --part part0 --ids <id,id,...> &
$B --defs build/fish.json --out build/fish --export --part part1 --ids <id,id,...> &
# …part2, part3 も同じ
wait
$B --out build/fish --merge build/fish/part0.glb build/fish/part1.glb build/fish/part2.glb build/fish/part3.glb --luau src/shared/Config/FishMeshes.luau
```

- お手元の Blender(4.2 以降)で動きます。Blender が無い環境では `pip install bpy==4.2.0`(Python 3.11)でも動きます
- 確認用の画像: `--ids hasu_koi,bake_fugu --render --face`(`--face` で顔のアップも)、書き出した GLB の確認: `--verify assets/fish/YokaiFishMeshes.glb build/verify`
- 作り直した GLB は、上の「Studio に入れる手順」をもう一度行ってください
