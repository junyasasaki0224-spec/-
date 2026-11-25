# 「みなとグランプリ」を Roblox で公開する

## ロビーと会場を作る

1. 元の e7af074 のフォルダに差分 ZIP を重ねる。プロジェクトの一番上でターミナルを開く。Rojo 7 のコマンドが使えることを `rojo --version` で確認する。[Rojo の導入](https://rojo.space/docs/v7/getting-started/installation/)
2. 次の2行を実行する。Lobby は最初に入る場所、Race は出走時に移る場所になる。

   ```sh
   rojo build roblox/lobby.project.json -o Lobby.rbxl
   rojo build roblox/default.project.json -o Race.rbxl
   ```

3. Studio にオーナーでログインし、**Lobby.rbxl** を開く。「File → Publish to Roblox」でゲームを新規作成する。所有者を個人かグループから選び、名前を「みなとグランプリ」、対応端末を PC・スマートフォン・タブレットにする。最初は非公開で保存する。この場所が開始場所になる。[ゲームと場所の公開](https://create.roblox.com/docs/production/publishing/publish-games-and-places)
4. **Race.rbxl** を別の Studio ウィンドウで開く。「File → Publish to Roblox As…」で手順3のゲームを選び、「Add as a new place」で「レース会場」を追加する。Creator Dashboard の同じゲームの Places に、開始場所とレース会場が1つずつ並ぶことを確認する。
5. レース会場を Dashboard から Studio で開き、コマンドバーで `print(game.PlaceId, game.GameId)` を実行する。最初の数字が会場の **Place ID**。ロビーを同じ方法で開くと2番目の数字が一致し、最初の数字だけが異なる。プロジェクトの `roblox/src/LobbyConfig.lua` の `racePlaceId = 0` の 0 を、会場の Place ID に置き換える。数字に引用符を付けない。
6. Dashboard の Places から会場の設定を開き、サーバーの最大人数を **12人以上** にして保存する。艇は6艇で、残りは観戦に使う。Audience → Access Settings の場所へのアクセスは「Secure within universe only」を選び、会場へはロビーのサーバーから移動させる。[場所間の移動とアクセス設定](https://create.roblox.com/docs/projects/teleport)

## 所有者の素材をまとめて登録する

7. 次の表を上から進める。Studio の Asset Manager または 3D Importer で公開ゲームと同じ所有者を選ぶ。画像は複数選択してまとめて取り込める。審査後に **画像または音声の Asset ID** をコピーする。画像・音の設定値の書式は `"rbxassetid://数字"`。利用権限が必要な素材は公開ゲームに権限を付ける。[アセット管理](https://create.roblox.com/docs/projects/assets/manager)・[音声の権限](https://create.roblox.com/docs/audio/assets)

   | 登録する元ファイル | ID を反映する場所 |
   |---|---|
   | `roblox/assets/models/boat.fbx`（艇・選手・モーター）、`venue.fbx`（会場、同じフォルダ） | 手順8で `boat-import.json`・`venue-import.json` と `Boat.rbxmx`・`Venue.rbxmx` を生成。両方の場所が同じモデルを使う |
   | `assets/cards/` の `season.jpg`・`online.jpg`・`ta.jpg`・`friend.jpg`・`gp.jpg`・`event.jpg`・`single.jpg`・`practice.jpg` | `roblox/src/CardImages.lua` に拡張子を除いた同名の欄が8つある |
   | `roblox/assets/audio/minato-sfx.wav`(効果音を並べた物) | `roblox/src/AudioConfig.lua` の `sfx` |
   | `roblox/assets/audio/minato-loops.wav`(エンジン・水切り・観客) | `roblox/src/AudioConfig.lua` の `loops` |
   | `roblox/assets/audio/minato-music.wav`(ホームの BGM) | `roblox/src/AudioConfig.lua` の `music` |
   | `roblox/assets/audio/minato-opening.wav`(オープニングの曲。ブラウザ版と同じ曲を `roblox/tools/record-opening.js` で録音した物) | `roblox/src/AudioConfig.lua` の `opening` |
   | `roblox/assets/audio/minato-gacha.wav`(ガチャの演出の曲。`roblox/tools/record-gacha.js` で合成した物) | `roblox/src/AudioConfig.lua` の `gacha` |
   | `roblox/assets/venue/Crowd.png`・`Windows.png`・`Lamps.png` | `roblox/src/VenueImages.lua` の `Crowd`・`Windows`・`Lamps`(2026-11-17 に登録済み) |

8. モデルは Studio で FBX を1つずつ開き、部品名を保ち、「シーン位置を使用して挿入」「ピボットをシーン起源に設定」を選んで取り込む。Explorer で取り込んだモデルだけを選び、右クリックの「Save to File…」で形式 **Roblox XML Model (.rbxmx)** を選ぶ。プロジェクトの一番上に `owner-boat.rbxmx`・`owner-venue.rbxmx` として保存し、次を実行する。名前が欠けていれば対象の部品が表示される。元の取り込みと同じ軸・単位を使う。出力モデルには元の可動部の中心が入る。[3D Importer](https://create.roblox.com/docs/studio/importer)

   ```sh
   python roblox/tools/owner_meshes.py boat owner-boat.rbxmx
   python roblox/tools/owner_meshes.py venue owner-venue.rbxmx
   python roblox/tools/check_visuals.py
   ```

9. 手順2で両方を再度作り、各ファイルを Studio で開いて「Publish to Roblox As…」を選ぶ。**Lobby → 既存の開始場所、Race → 既存のレース会場** の順に上書きする。別の端末から絵・音・モデルを確認する。画像が未登録ならカードは紺地と金の絵、会場は端末内の絵または図形になる。エンジン音は登録後に鳴る。

## 公開の前に止める検証用の仕組み

- `roblox/src/MetaService.lua` の `TEST_UNLOCK_ALL` を **false** にする(true の間は、Studio とゲームの持ち主だけ、全部の品を倉庫で着せ替えられる)
- `roblox/dev.project.json`(ロビーと会場をまとめた検証用の場所)は公開に使わない。公開はロビー(`lobby.project.json`)と会場(`default.project.json`)を別々に作る

## ガチャの着せ替え(GPT がデザインした 5種類×30点)

- 形(メッシュ)と模様(画像)は、2026-11-21 に Studio の取り込み(作り手「自分」)で**オーナーのアカウントに登録済み**。番号は `roblox/assets/items/Items.rbxmx`(元の一覧 `items-import.json`)
- ゲームをグループなど別の持ち主で公開する時は、その持ち主から読めるように、Creator Hub で素材の使用を許可するか、その持ち主で取り込み直す(手順は `roblox/README.md` の「ガチャの着せ替え」)
- `rojo build` で作った place には番号がそのまま入る。Studio の生同期だけは形が入らないので、`roblox/tools/studio_item_meshes.lua` で写す(公開には関係ない)

## ショップ(Robux でガチャのコインと VIP パスを売る)

- Creator Hub でゲームを開き、「収益化 → 開発者製品」で、下の表のコインの袋を4つ作る。作ったら製品の番号(ID)を `roblox/src/ShopConfig.lua` の `coins` の `product` に入れる
- 「収益化 → パス」で VIP パスを作り、番号を `ShopConfig.lua` の `vip.pass` に入れる
- アイコンは `roblox/assets/shop/`(c1〜c4 と vip の PNG)。`python roblox/tools/make_shop_icons.py` で作り直せる
- 番号を入れたら、手順2・9のとおりロビーと会場を作り直して上書きする。番号が 0 の品は、ショップで「準備中」と出て買えない
- 値段は Robux で決める。円での値段は Robux の買い方(端末・お店)で変わる(アプリでは 1 Robux ≒ 約2円、PC・ギフトカードでは約1.6円が目安)。値段の決め方は [roblox/PRICING.md](roblox/PRICING.md)
- VIP パスを作る時は「地域ごとの値段(Regional Pricing)」を入れる(物価の安い国では Roblox が自動で下げる)

  | 品(`key`) | 種類 | 名前 | 中身 | 値段の目安 |
  |---|---|---|---|---|
  | c1 | 開発者製品 | コイン 500 | 500 コイン(ガチャ5回ぶん) | 49 Robux |
  | c2 | 開発者製品 | コイン 1100 | 1000 + おまけ 100 コイン | 99 Robux |
  | c3 | 開発者製品 | コイン 2400 | 2000 + おまけ 400 コイン | 199 Robux |
  | c4 | 開発者製品 | コイン 5200 | 4000 + おまけ 1200 コイン | 399 Robux |
  | vip | パス | みなと VIP パス | ランク戦が無制限(ふつうは1日5回)、金の塗装とヘルメット、ホームの VIP の札、買った時に 1000 コイン、毎日 100 コイン | 399 Robux(約640〜800円) |

- コインはガチャ(中身がランダム)に使うので、Roblox の「有料のランダムアイテム」にあたる。
  - 地域によっては売れない。サーバーの `ShopService.lua` が `PolicyService` で確かめ、売れない地域の人にはコインの袋の購入画面を出さず、VIP のコインの特典も付けない(ランク戦無制限と金の品は付く)
  - ガチャの確率は、ガチャの画面とショップに、引く前に出している(表示も抽選も `Meta.lua` の同じ表から作る)。N 50% / R 30% / SR 14% / SSR 4.5% / UR 1.5%。5種類150点(N40/R40/SR35/SSR20/UR15点)をまとめた1つのガチャで引く(1つあたり N 1.25% / R 0.75% / SR 0.4% / SSR 0.225% / UR 0.1%)
- 品を渡すのはサーバーの `ShopService.lua` だけ。Roblox から届いた購入を、保存できてから「受け取り済み」にする(同じ購入は1回だけ渡す)
- 公開前に、テスト用の場所で「テスト購入」(Studio の購入はお金がかからない)をして、コインと品が届くことを確かめる

## 公開範囲・質問票・データ

10. Roblox で動く本番の保存はサーバーが行う。Studio でも保存を試す場合は、**別に作ったテスト用ゲーム**を開き、Experience Settings → Security → Enable Studio Access to API Services をオンにし、Workspace の属性 `MinatoLiveData` を true にして保存する(付けないと Studio では保存しない)。本番とテストで同じデータに書き込まないよう、テスト用ロビーにはテスト用会場の ID を入れる。外部 HTTP や第三者ゲームへの移動は今回の機能には不要。[Data Stores](https://create.roblox.com/docs/cloud-services/data-stores)
11. Dashboard のゲームの Content Ratings 質問票を開き、実際に表示される内容に沿って回答する。描写には艇の衝突・沈没、交流には大会名や招待がある。抽選(ガチャ)に使うコインは、遊んで得るほか Robux でも買える(**有料のランダムアイテムあり**と答える)。着順への賭け、換金はない。Robux で買えるのはコインの袋と VIP パス(ランク戦無制限・見た目の品・コイン)。公開する最終版に追加した購入や描写があれば回答にも反映する。対象年齢は提出後の判定を確認する。[質問票](https://create.roblox.com/docs/production/promotion/content-ratings)・[ランダムアイテム](https://create.roblox.com/docs/production/monetization/paid-random-items)
12. ゲームの説明文の例。「架空のみなと競艇場で、6艇の3周レース。スタートを練習して、友達との対戦や大会に挑もう。艇外装・ヘルメット・モーターカバー・ステアリング・艇首旗の着せ替えのガチャはゲーム内コインで引けます(コインは遊んで貯めるほか、ショップでも買えます。確率はガチャの画面に出ています)。VIPパスではランク戦が無制限になります。買える物でレースの速さは変わりません。着順に賭ける仕組みはありません。」
    - ゲームのページの絵の下書き: `roblox/assets/store/` に、アイコン(`icon-512.png`、512×512)とサムネイル2枚(`thumbnail-1-race.jpg`・`thumbnail-2-leader.jpg`、1920×1080)。Studio のテストプレイでレース中の画面の文字を消して写した(画面の大きさの都合で、元の絵を少し引き伸ばしている)。Creator Hub のゲーム(Experience)の設定にあるアイコンとサムネイルの欄で登録する(画面の名前は Roblox 側の変更で変わることがあるので、その時の画面で確かめる)。文字入れはしていない(言語ごとにサムネイルを分ける時に足せる)
13. Dashboard の Data Stores Manager → RTBF Deletion で、同梱の [削除設定と依頼対応](roblox/DATA_DELETION.md) の表を順に登録する。世界1位の走りなど、複数人で共有するキーの確認手順も読む。[削除テンプレート](https://create.roblox.com/docs/cloud-services/data-stores/right-to-be-forgotten)
14. Dashboard の「Publish settings → Manage Audience → Manage access」で Playtest タブを開き、早期テスターを招待する。Studio の Play を終了して **Roblox アプリ**から開始場所に入る。下の表を終えたら、同じ Manage access の Public タブで公開対象を選び、Save Changes を押す。一般公開するときは Friends 限定を解除する。初回のリリース案内が表示されたら、所有者の画面で質問票と公開条件の確認を完了する。公開条件・選択できる対象は所有者の画面で確認する。別の参加者が公開ページの再生ボタンからロビーに入れれば公開確認完了。[公開範囲と条件](https://create.roblox.com/docs/production/publishing/publish-games-and-places)

## 公開先での確認表

結果は日付・端末・期待どおりかを記録する。画面写真はゲーム画面だけを撮り、表示名・チャット・招待先・合言葉は隠す。

| 1人で行う操作 | 合格の目安 |
|---|---|
| スマホ縦・横と PC で開始場所に入り、8枚すべてのカードとホームのタイルを開く | 戻る、下へスクロール、カードを押す操作ができる。文章や操作部が隠れない |
| スタート練習で早く出る・0秒直後を狙う・何もしない・もう一度・戻る | フライング・ST・出遅れが区別され、コインとレートが動かない |
| メールを1回受取、無料コインで抽選、倉庫で装備。終了して別端末で再入室 | 残高・アイテム・装備が一致し、同じメールをもう一度受け取れない |
| 音量・画質・レバーを変更し、会場でフリーレースを完走 | 設定と装備が反映され、会場へ移れて結果が出る。音量0でエンジンが消える |
| タイムアタックの同一コースを2回完走し、イベントも1回完走 | 自己ベストと順位、イベント得点が反映される。再入室後も記録が残る |
| 未登録・登録済みの素材をテスト用ゲームで比べる。iPhone 実機で6艇走行時の昼と夜を測る | 未登録でも操作できる。登録後は8枚の絵、観客、艇、会場、エンジンを別端末でも確認できる。fps は向き・設定と一緒に記録する |

| 2〜3人で行う操作 | 合格の目安 |
|---|---|
| 2人でオンラインに並ぶ。1人が取り消して並び直す | 待機人数が一致し、約30秒後に同じ会場へ入る。空きは AI。通常オンラインのレートは変わらない |
| シーズンで2人が対戦して着順と再入室後のレートを比べる | 両者の結果が同じ。AIを含む同じ結果の報酬・レートが再入室で二重にならない |
| A がフレンド部屋を作り、B は合言葉、C は招待から入る。無効な合言葉も試す | 3人は同じ部屋。無効な合言葉では案内が出る。招待先や合言葉が他の部屋に出ない |
| 大会を作り、別の人が参加。主催者が開始を早め、予選2走から決勝まで走る | 同じ組へ移り、得点と優勝者が一致する。失格者は観戦でき、艇を操作できない |
| 終了・再接続後にコイン、装備、順位を各人で確認する | 他の参加者の成績が混ざらず、ランキングが集計後に更新される |
