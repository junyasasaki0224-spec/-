# アニメ風の妖怪魚(Blender で作ったメッシュ)

50種すべてを Blender でアニメキャラクター風の3Dモデルにしてあります。
`assets/fish/YokaiFishMeshes.glb` を Studio に1回読み込むだけで、ゲーム中の魚(釣果・図鑑・水槽・ぬし・相棒バトル)がすべてアニメ風に変わります。
読み込むまでの間は、これまでどおりパーツで組み立てた魚が出ます(ゲームは止まりません)。

## つくり

- **体**: 頭・胴・尾の付け根などの楕円体を、ボクセルで溶かして一体化したなめらかな体
- **目**: 縦長の白目、上が濃いグラデーションの虹彩、瞳、大小2つの光、太いまつげの線(目尻が跳ねる)。目の種類(かわいい・怒り眉・半目・猫目・一つ目・光る目・点の目・無し)はデザインの表のまま
- **塗り**: 平らな色に、2段のアニメ影と頭の上のツヤを焼き込み済み。Roblox の光の当たり方に左右されにくい
- **輪郭線**: 少し大きい裏返しの殻(`<id>_Outline`)。Roblox は裏面を描かないので、外周だけが線になる
- **レア度**: 大きさ・ひれの縁取り(伝説以上は金)・額の金の紋・後光の輪・鬼火はモデルに入っている。光の粒・炎・光源・変異の上塗りはゲーム側で付ける
- **軽さ**: 1匹 7,000〜15,000 三角形 + 輪郭線(Roblox の上限 20,000 以内)。テクスチャは 512〜1024px

書き出しのたびに、体の面が外向き・輪郭線の面が内向きになっているかを光線で自動検査しています(向きが逆だと Roblox で真っ黒になるため)。

## Studio に入れる手順(1回だけ)

1. Roblox Studio でゲームを開き、ログインしていることを確認する(読み込み時にメッシュと画像があなたのアカウントにアップロードされます)
2. **ファイル → 3D をインポート**(Import 3D)で `assets/fish/YokaiFishMeshes.glb` を選ぶ
3. 設定はそのままで読み込む。数分かかることがあります
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
| 一部の魚だけパーツの見た目のまま | `FishMeshes` の中にその魚の id の名前のパーツがあるか確認 |
| 前のパーツの見た目に戻したい | `FishMeshes` を削除する(または名前を変える) |

## 作り直す(デザインを変えた時)

魚の表(`tools/fish_designs.py` → `Config/Fish/*.luau`)を変えたら、次の2つで作り直せます。

```bash
lune run tools/export_fish.luau build/fish.json
blender -b -P tools/blender/yokai_fish.py -- --defs build/fish.json --out build/fish --export --luau src/shared/Config/FishMeshes.luau
cp build/fish/YokaiFishMeshes.glb assets/fish/
```

- お手元の Blender(4.2 以降)で動きます。Blender が無い環境では `pip install bpy==4.2.0`(Python 3.11)でも動きます
- 確認用の画像: `--ids hasu_koi,bake_fugu --render`、書き出した GLB の確認: `--verify assets/fish/YokaiFishMeshes.glb build/verify`
- 作り直した GLB は、上の「Studio に入れる手順」をもう一度行ってください
