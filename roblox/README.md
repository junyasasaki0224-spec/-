# Roblox 試作版

このディレクトリは Rojo プロジェクトです。物理・AI・レース判定はメートル単位で計算し、描画座標は１メートルを3.5 studsに換算します。Roblox Studio での動作確認はまだ行っていません。

レースを計算だけで確認する場合、プロジェクトの親ディレクトリで以下を実行します。

```sh
python3 roblox/tools/run_sim.py 60
```

公式 Luau CLI `luau` をインストールして PATH に追加してください。Windows で `python3` が動かない場合は `python` を使います。計算テストは Studio でのオンライン対戦や描画を検証するものではありません。

`assets/engine-loop.wav` は合成したエンジン音です。Roblox Studio に取り込み、利用できるアセットIDを得たら `src/AudioConfig.lua` の `engineAssetId` に `rbxassetid://...` 形式で設定します。初期値は空で、そのままでは音は再生されません。元の Blender の艇・会場のモデルと実況は未移植です。

## 成績とランキングの試作

`default.project.json` はレース会場、`lobby.project.json` はランキングを表示するロビーです。同じ Roblox ゲーム内にそれぞれの場所を用意し、`src/LobbyConfig.lua` の `racePlaceId` をレース会場の場所 ID に設定してください。初期値の 0 では、ロビーから会場へ移動できません。

レースの結果はサーバーで記録します。通常の練習レースも出走数・１着数・完走タイムに含めます。フライングと途中退出は出走数に含め、１着とベストタイムには含めません。現在のレースは練習扱いのため、レートは変動しません。ランク戦を作る際は、クライアントからの申告を信用せず、レースの種類をサーバーで確認したうえでレート計算を有効にしてください。

保存には DataStore を使います。Studio では本番と別のストア名を使います。Studio で確認するには API サービスへのアクセスを許可し、テレポートの実際の確認には公開済みのテスト用ゲームが必要です。保存が失敗するとサーバー稼働中は再試行しますが、サービス障害が続いたままサーバーが終了した場合の保存は保証できません。重複防止に直近128レースの ID を保持します。

ランキングはサーバーで１分ごとに更新し、上位50人を表示します。本人の順位は最大５ページ（250件）まで調べ、記録がその範囲より下と確認できた場合は「251位以下」と表示します。記録や順位を確かめられないときは更新待ちと表示します。ランキング情報の更新が一時的に失敗した場合は再試行し、次にロビーへ入った時にも保存済み成績から修復します。

公式 Luau CLI が使える環境では、純粋な計算のテストを次のように実行できます。

```sh
luau roblox/tests/rating.spec.luau
luau roblox/tests/results.spec.luau
```

## データ削除依頼

Roblox からの削除依頼に備える設定と手順は [DATA_DELETION.md](DATA_DELETION.md) を参照してください。

## フレンドとの部屋（T9 の試作）

ロビーの「部屋を作る」から専用会場へ移動し、画面上の６文字の合言葉を友達に伝えます。ロビーで合言葉を入力して「部屋に入る」を選ぶか、部屋内の「友達を招待」から招待できます。招待を受けた人は、ロビーに届いた合言葉を確認して「部屋に入る」を押してください。招待から直接会場に入る場合も同じ合言葉をサーバーで確認します。主催者の「レース開始」でレースが始まり、空きは AI が走ります。６人を超えた人はそのレースを観戦し、次のレースでは既存の順番待ちの仕組みで交代します。主催者が不在の間は次のレースを開始できません。主催者が期限内に同じ合言葉で戻れば再開できます。

合言葉の有効期間は作成から２時間です。期限が切れても会場にいる人のレースは続きますが、新しい参加や主催者の再入場はできません。作り直す場合はロビーから新しい部屋を作ってください。部屋の対戦はレートを変動させません。出走・１着・ベストタイムの扱いは既存の練習と同じで、AI 相手の記録を集計するかどうかは T11 で判断待ちです。

初期値のままでは会場の場所 ID が未設定です。同じゲーム内にロビーとレース会場を公開し、`LobbyConfig.lua` にレース会場 ID を設定してください。７人以上の観戦を確認するには、レース会場の最大参加人数を７人以上にしてください。参加先の移動・招待・複数サーバー間の一時保存は Studio の通常プレイだけでは確認できないため、テスト公開版で複数アカウントを使って確認してください。本人確認に使う内部の移動先情報は画面に表示しません。

## ランク戦（T10 の試作）

ロビーの「ランク戦」を押すと対戦相手を探します。レート差が最初は100以内、待機10秒ごとに許容差が100ずつ広がります。６人そろったとき、または最初の人が30秒待ったときに、その時点の参加者で専用会場に移動します。合わない相手は待機を続け、足りない艇は AI で埋めます。待機はボタンで取り消せます。会場では最初の人の到着から20秒待ち、到着した参加者で始めます。終了後は「ロビーに戻る」を押します。レートは人間が２人以上で出走したランク戦だけで変わります。フレンド部屋・練習では変動せず、AI はレート計算に含みません。

同時に複数のロビーから同じ人を選ばないため、待機者全員を一つの MemoryStore の項目でまとめて更新する試作です。登録済みの待機・移動中の合計は60人までです。いっぱいのときや別の参加処理が残っているときは後からやり直してください。人数が増えると通信上限や更新の競合が課題になるため、本格公開前には負荷を測り、規模に合わせた設計の見直しが必要です。通信や移動に失敗した場合は再試行を案内し、期限切れの待機情報は自動で無効になります。

会場 ID の設定、テスト公開と複数アカウントでの確認が必要です。Studio の通常プレイだけでは実際の場所移動を確認できません。組が決まると、その組を決めたロビーが会場(予約サーバー)を1つ予約し、入場用の鍵を待機情報に書き込みます。どのロビーにいる人も、その鍵で同じ会場へ移動します。予約に失敗した時や、15秒たっても鍵が書き込まれない時(そのロビーが止まった時など)は、組をほどいて待ち直しにします。会場では、その会場に割り当てられた参加者かを確かめてから入場させます。ルールの単体テストは `luau roblox/tests/match-policy.spec.luau` です。

## T16 前半（ホーム・コイン・持ち物）

ロビーの入口は新しい Home です。ホームからレース選択の8枚を開きます。通信対戦・ランキングは既存ロビーの画面につながり、その「ホーム」で戻れます。モード3〜5の新しい対戦方式や支部・招待は次回の担当範囲です。

Meta.lua は src/meta.js の品目23種・確率・価格・重複還元・報酬・経験値・級別を移した計算です。サーバーの PlayerStats と同じプレイヤーの保存項目に meta を追加します。日本時間0時にミッションとログインメールを更新します。既存のランク対戦用 rating と、ブラウザ版に合わせたシーズン級別用 meta.rate は別に持ちます。ランク戦の結果で meta.rate にもブラウザ版の増減を反映します。

MetaLobby は get / pull / equip / mail / mission だけを受け付けます。報酬額、持ち物、レート、抽選の乱数は受け取りません。サーバーが発行し保存した token が一致するときだけ UpdateAsync 内で処理して、次の token に進めます。抽選の乱数は保存の再試行中は同じ値を使います。通信結果が不明な場合、画面の再試行は元の token を再送します。金額と報酬の両方を同じ保存で確定し、未保存の表示だけを先に増やしません。保存の自動再試行は既存の5回の処理を利用します。

レースの報酬は既存のレースID重複防止と同じ保存で適用します。過去版同様に直近128レースを保持する方式です。サーバー終了中に障害が続いた場合の未保存報酬の回復は、既存方式の制約が残ります。

未公開のStudioでは MetaService がサーバー内の一時データを使います。終了すると消えます。本番と公開済みのStudioでは DataStore を使用します。本番保存と切り離した画面確認に使ってください。検証用の報酬追加コードは納品ファイルに含めていません。

倉庫の装備はサーバーから艇テンプレートの属性として配信し、各クライアントが同じ色を表示します。レース開始のたびに装備を読み直すので、前の人の色が残りません。ホームとカードの艇表示はRobloxの部品で作ったプレビューです。Blenderモデルの取り込み（L1）とカード画像のアセット登録は別途必要です。

計算は luau roblox/tests/meta.spec.luau、一括検証は sh tools/check-all.sh です。文法チェックは公式Luauの loadstring を使い、Windowsで luau-compile が使えない環境にも対応します。シミュレーションの失敗がパイプで隠れないように一括検証も修正しました。

## Blenderの艇・会場（L1）

Boat.rbxmx / Venue.rbxmx はStudioのImporterで登録したMeshIdを含みます。Rojoで両プロジェクトを生成すると ReplicatedStorage.VisualAssets に入り、ロビーとレースが自動で使用します。物理とコースの座標はメートル、表示は1m=3.5 studsです。

再生成はプロジェクトの一番上で次を実行します。

    blender -b --factory-startup --python assets/blender/export_roblox.py -- boat roblox/assets/models
    blender -b --factory-startup --python assets/blender/export_roblox.py -- venue roblox/assets/models

既存のbuild_boat.py / build_venue.pyから生成し、材質と元の部品名で分割します。会場はさらに120mの区画と長い辺の分割を使い、三角形は18,000以下にします。FBXはcentimeter変換を補正済みです。Importerの軸変換に合わせ、会場のMeshPartを原点の周りにY軸180度回してゲーム座標に戻します（package_visuals.pyが処理）。Studioで「シーン位置を使用して挿入」「ピボットをシーン起源に設定」を有効にし、大きさの警告がないことを確かめてください。艇の全長は約11.7studsです。

公式の上限は1メッシュ20,000三角形・各軸2,048studsです。会場を1つのメッシュへ結合しないでください。
https://create.roblox.com/docs/onboarding/artists
https://create.roblox.com/docs/reference/engine/classes/MeshPart
https://create.roblox.com/docs/studio/importer

取り込み直したモデル内のMeshPartについて name / mesh（MeshId）/ cf（CFrame:GetComponents()の12個）/ size（X,Y,Z）/ natural（MeshSizeのX,Y,Z）をJSON配列へ書き出し、次でRojo用にまとめます。

    python roblox/tools/package_visuals.py boat boat-import.json
    python roblox/tools/package_visuals.py venue venue-import.json

原点はmanifestから復元します。Wheel・Motor・RacerUpperは透明Pivotを回転の中心にします。Anchored・CanCollide=falseにして既存の独自の衝突計算へ引き継ぎます。倉庫の色は HullWhite / Trim / Deck / MotorRed / Helmet / HelmetStripe の材質名から適用します。Mesh所有者と公開ゲームの所有者が異なる時は、ゲームで読み取る許可をRoblox側で設定し、公開環境で確認してください。

## カード画像

今回、8枚とも登録済みでCardImages.luaにIDを入れてあります。所有者を変える時は次の手順で登録し直してください。

assets/cards/ の8枚をStudioのファイル→インポートから、ゲームと同じ所有者へ登録します。画像のアセットIDをコピーし、roblox/src/CardImages.lua の同名キーに rbxassetid://番号 の形式で入れます。順番は season / online / ta / friend / gp / event / single / practice。ImageLabelは画像をCropで表示し、金枠と角丸は画面側で付けます。

参照したAPI
https://create.roblox.com/docs/reference/engine/classes/ImageLabel
https://create.roblox.com/docs/reference/engine/classes/UIStroke
https://create.roblox.com/docs/reference/engine/classes/UICorner
https://create.roblox.com/docs/reference/engine/classes/Model
https://create.roblox.com/docs/reference/engine/classes/PVInstance
https://create.roblox.com/docs/reference/engine/classes/BasePart

Studioのホームは表示名を「テストレーサー」にして、レビュー写真へのアカウント名の写り込みを防ぎます。公開ゲームは通常の表示名です。

## T17 ①（シーズン・オンライン・イベントの待ち合わせと AI 補充）

ホームの「レース」→ シーズン / オンライン / イベントのカード →「参加する」で並びます。6人そろえばすぐ、2人以上なら最初の人が30秒待った時点で、1人だけなら60秒で、空きを AI（達人）で埋めて出走します。待っている間は「3/6 人　出走まで あと 25 秒」と取り消しボタンが出て、ホームに戻っても同じ表示が残ります。

公開していない Studio では MemoryStore と会場への移動が使えないため、同じ決まりをロビーのサーバーの中だけで動かし、組が決まると「出走が決まりました（人 1・AI 5）。Studio では会場へ移動しません」と出ます。会場側の動き（AI 達人・イベントの水面・出走表と結果）は、レース会場のプロジェクトを同期した place で、ワークスペースに文字列の属性 `MinatoTestMode` を `event`（または `ranked` / `online`）として付けてから遊ぶと確かめられます。

AI がいるレースのレートは人間どうしの着順だけで決まります（1人なら動きません）。イベントはコイン2倍・レートなしです。計算のテストは `luau roblox/tests/online-rules.spec.luau` と `luau roblox/tests/match-policy.spec.luau`、達人の AI だけの60レースは `python roblox/tools/run_sim.py 60 4` です。

公開した会場での複数人の待ち合わせ・移動・結果の保存は、`LobbyConfig.racePlaceId` を設定したテスト公開で確かめてください。

## T17 ②（タイムアタックの記録の共有）

ホームの「レース」→ タイムアタックのカード → コースを選んで「このコースで走る」。1人用の会場で、無風・波なし・ほかの艇なしで3周します。ゴールすると、会場のサーバーが記録した入力から走りを再現し、同じタイムになった時だけ世界ランキングに登録します。結果には「自己ベスト更新」「世界 n位」が出て、「もう一度走る」で同じ会場からやり直せます。コースの世界1位の走りは、水色の半透明の艇（ゴースト）として一緒に走ります。

Studio で確かめる時は、レース会場のプロジェクトを同期した place のワークスペースに、文字列の属性 `MinatoTestMode` = `ta` と数の属性 `MinatoTestLane` = 1〜6 を付けて遊びます。保存はしませんが、記録の確かめは本番と同じに動き、2回目からは直前の走りがゴーストになります。単体テストは `luau roblox/tests/time-attack.spec.luau` です。

## イベント内のランキング

イベントのレースでは、着順で 10・8・6・4・2・1 点（失格は0点）がたまり、その日（日本時間）の合計で順位が付きます。ホームのイベントの画面に、今日の上位10人と自分の順位が出ます。記録は MemoryStore に置き、2日で自動で消えます。

## T17 ③（大会）

ホームの「レース」→ 大会のカード。タブで「受付中」「開催中」「終了」の大会を見られます。「大会を作る」では、大会名・人数・形式・開始・公開の5つだけを選び、確認の画面で「この内容で開催」を押します。大会名は Roblox の文字フィルターを通してから保存します。合言葉の大会は、カードに出る6文字のコードを伝えた人だけが参加できます。主催者は「開始を早める」「中止」ができます。

始まると6人ずつの組に分かれ、組ごとの会場で予選を走ります（得点は 10・8・6・4・2・1 点）。予選が終わると得点の上位6人が優勝戦の会場へ移り、ほかの人は「優勝戦を観戦する」を押せます。優勝が決まると、ロビーにいる全員に知らせます。開催中の大会は、得点表を見たり、走っている組を観戦したりできます。

Studio で確かめる時: ロビーの place では、会場への移動以外（作る・参加・開始を早める・開催中・得点表・中止）がそのまま試せます。レース会場の place では、ワークスペースに文字列の属性 `MinatoTestMode` = `gp` を付けて遊ぶと、自分1人の大会で予選2走と優勝戦を同じ会場で走れます。公開版では、レース会場の最大参加人数を観戦の分も考えて12人以上にしてください。

公開版での確認の手順（オーナー）: 2つ以上のアカウントでロビーに入り、片方が「大会を作る」→ 人数6・そろったら・だれでも → もう片方が参加 → 主催者が「開始を早める」→ 両方が同じ組の会場へ移ること、予選2走の後に優勝戦の会場へ移ること、ロビーに優勝の知らせが出ることを確かめます。

保存先は OrderedDataStore `MinatoTA0_v1`〜`MinatoTA5_v1`（コース別のタイム）と DataStore `MinatoTAGhost_v1`（コース別の世界1位の走り）です。データ削除の依頼があった時は、この2つからも該当するユーザーの記録を消してください（ゴーストは、そのユーザーの走りなら消す）。

## T18 の水面・会場とオーナー用の画像設定

① 水面・光・航跡の差分を最初に、② 会場の差分をその上に展開する。ロビーとレース会場をそれぞれの Rojo 設定から組み立てる。確認用の写真は review/t18/ にあり、公開する場所には同期しない。

### 会場画像を用意する

- `roblox/assets/venue/Crowd.png` は客席用の透明な3段の画像、`Windows.png` は窓枠の影・反射とブラインド、`Lamps.png` は照明塔のレンズ。元画像と、登録前に使う同じ画素の Luau データを同時に作り直せる。プロジェクトの一番上で実行する。

```sh
blender --background --factory-startup --python-exit-code 1 --python assets/blender/build_venue_images.py
```

- 登録する際は**オーナーが、公開先と同じ所有者（個人またはグループ）**を選び、Studio の Asset Manager から上記3枚をインポートする。PNG の寸法・透明部分を保つ。それぞれの審査が終わったら画像のアセット ID をコピーする。
- `roblox/src/VenueImages.lua` の Crowd、Windows、Lamps に対応する値を `rbxassetid://数字` の形で入れる。両方の place に反映し、非公開のテスト先で別の端末から客席・スタンド・照明塔が見えることを確認する。読み込み権限・審査の状態も所有者側で確認する。
- 空欄なら端末内で共通の小さい画像を最大3枚だけ組み立てる。端末やゲームの権限で画像を作れないときは、軽い観客・窓の影・照明の図形を使う。この手順で Mesh/Image API の権限を有効にする必要はない。登録した ID が誤っている場合は、正しい ID に直すか空欄に戻す。
- 元の会場 FBX は部品を分割する時に窓の UV（画像を貼る座標）を保持しない。既存の窓枠の後ろと照明盤の正面だけに画像を合わせ、窓上部と縦枠に影を描いた。建物全体の頂点に陰影を焼き直す方式は採用していない。レース会場の大時計は黄色が12秒、黒が60秒で一周。会場の時刻が1.5秒に達したら黄色の針を消す。

公式資料: [地形の水](https://create.roblox.com/docs/reference/engine/classes/Terrain)、[光](https://create.roblox.com/docs/reference/engine/classes/Lighting)、[粒](https://create.roblox.com/docs/reference/engine/classes/ParticleEmitter)、[航跡](https://create.roblox.com/docs/reference/engine/classes/Trail)、[部品上の表示](https://create.roblox.com/docs/reference/engine/classes/SurfaceGui)、[端末内の画像](https://create.roblox.com/docs/reference/engine/classes/EditableImage)、[アセット管理](https://create.roblox.com/docs/projects/assets/manager)。
