# アニメ風の妖怪魚(Blender で作ったメッシュ)

50種すべてを Blender でアニメキャラクター風の3Dモデルにしてあります。
`assets/fish/YokaiFishMeshes.glb` を Studio に1回読み込むだけで、ゲーム中の魚(釣果・図鑑・水槽・ぬし・相棒バトル)がすべてアニメ風に変わります。
読み込むまでの間は、これまでどおりパーツで組み立てた魚が出ます(ゲームは止まりません)。

## つくり

1匹ずつ「細かい版」と「ゲーム用の軽い版」の2つを作り、細かい版の見た目を軽い版のテクスチャに焼き込んでいます。

| | 細かい版(焼き込みの元) | ゲーム用(GLB に入るもの) |
| --- | --- | --- |
| 三角形 | 1匹 8〜18万 | 1匹 約14,600〜14,800 + 輪郭線 約7,300(Roblox の上限 20,000 以内) |
| 色 | 頂点ごとの色 | 1024px の色テクスチャ(全種) |
| 凹凸 | 彫った形そのもの | 1024px の法線マップ(全種) |

- **体**: 頭・胴・尾の付け根などの楕円体を、細かいボクセルで溶かして一体化したなめらかな体。その上に彫り込み:
  - 鯉型: 重なった鱗(尾の側の縁だけ弧にする)、えらぶたの「)」形の線(鱗はえらより後ろだけ)
  - 鯉型・なまず型・うなぎ型: 点線の側線
  - あんこう型: いぼ / ふぐ型: 毛穴 / えい型: 背中の明るい点々 / なまず型・うなぎ型: ぬめったまだら
  - 全体に細かい肌の凹凸
- **目**: 頭の丸みに沿って曲がった白目(上にわずかな影)、なめらかなグラデーションの虹彩と淡い縁、瞳、ひかえめな光1つ。上まぶたは細い線(真っ黒ではなく、肌の色を濃くした色)。キラキラさせすぎない、フィギュアのような落ち着いた目。目の種類(かわいい・怒り眉・半目・猫目・一つ目・光る目・点の目・無し)はデザインの表のまま
- **ひれ**: 根元から放射状の筋、根元→先のグラデーション、筋の間のぎざぎざの縁、縁取りの色(レアほど太く、伝説以上は金)
- **塗り**: 影は描き込まず、ゲームの光と法線マップの凹凸で立体に見せる(ソフトビニールのフィギュアのような見た目)。光の当たらない下側だけほんのり暗くし、鱗やひれの筋の色はひかえめ
- **輪郭線**: 細い裏返しの殻(`<id>_Outline`)。Roblox は裏面を描かないので、外周だけが細い縁取りになる(描いた線ではなく、立体の縁に見える細さ)
- **レア度**: 大きさ・ひれの縁取り・額の金の紋・後光の輪・鬼火はモデルに入っている。光の粒・炎・光源・変異の上塗りはゲーム側で付ける

ゲーム用の軽い版は、体を左右対称のまま間引き、目は白目の形だけにしています(虹彩・瞳・光の絵はテクスチャに入っているので、薄い板を何枚も重ねなくてよい)。
書き出しのたびに、次を自動で検査しています。

- 体の面が外向き・輪郭線の面が内向きになっているか(光線で確認。向きが逆だと Roblox で真っ黒・透明になる)
- どのメッシュも 20,000 三角形を超えていないか

## Studio に入れる手順(1回だけ)

1. Roblox Studio でゲームを開き、ログインしていることを確認する(読み込み時にメッシュと画像があなたのアカウントにアップロードされます)
2. **ファイル → 3D をインポート**(Import 3D)で `assets/fish/YokaiFishMeshes.glb`(約 41MB)を選ぶ
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

細かい版を作るので、1匹 2〜5分かかります。1匹ずつ別のファイルに書き出して同時に4匹ずつ作り、最後に1つにまとめると速く、途中で止まっても続きから作り直せます(できた魚は飛ばす)。

```bash
lune run tools/export_fish.luau build/fish.json
python3 -c "import json; print('\n'.join(f['id'] for f in json.load(open('build/fish.json'))['fish']))" > build/ids.txt
mkdir -p build/fish/each
xargs -P 4 -I{} sh -c '[ -f build/fish/each/{}.glb ] || blender -b -P tools/blender/yokai_fish.py -- --defs build/fish.json --out build/fish/each --ids {} --export --part {}' < build/ids.txt
blender -b -P tools/blender/yokai_fish.py -- --out build/fish --merge build/fish/each/*.glb --luau src/shared/Config/FishMeshes.luau
cp build/fish/YokaiFishMeshes.glb assets/fish/
```

- お手元の Blender(4.2 以降)で動きます。Blender が無い環境では `pip install bpy==4.2.0`(Python 3.11)でも動きます
- 確認用の画像: `--ids hasu_koi,bake_fugu --render --face`(`--face` で顔のアップも)、書き出した GLB の確認: `--verify assets/fish/YokaiFishMeshes.glb build/verify`
- 数匹だけ作り直す時は、その魚だけ書き出して、今の GLB の中の同じ魚だけを差し替えられます(ほかの魚は作り直さない):

```bash
blender -b -P tools/blender/yokai_fish.py -- --defs build/fish.json --out build/fishexp --ids nue_namazu,kyubi_koi --export --part some
blender -b -P tools/blender/yokai_fish.py -- --out assets/fish --update assets/fish/YokaiFishMeshes.glb --merge build/fishexp/some.glb --luau src/shared/Config/FishMeshes.luau
```

- 作り直した GLB は、上の「Studio に入れる手順」をもう一度行ってください(`ReplicatedStorage.FishMeshes` を消してから読み込み直す)
