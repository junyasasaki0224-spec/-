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
