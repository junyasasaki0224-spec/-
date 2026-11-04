# 公開前チェックリスト

まず `lune run tools/launch_check.luau` で、コード側に残っている設定(課金の ID・鳴き声の音・アイコンなど)を一覧にする。✗ が 0 になれば、コード側の準備は終わり。

## Studio / Creator Dashboard の設定
- [ ] ゲーム設定 → セキュリティ → **API サービスへの Studio アクセスを有効化**(テスト時のみでOK。本番の保存には不要)
- [ ] ゲーム設定 → 場所 → **最大プレイヤー数 = 10**(村の釣り小屋が10軒のため。増やす場合は `World/Village.luau` の `HUT_COUNT` も同じ数に)
- [ ] アバターの設定: R15 推奨(R6 でも竿は右腕に付きます)
- [ ] 体験のアンケート(Experience Questionnaire)に回答し、年齢区分を確認(暴力表現なし・課金あり)
- [ ] ゲームのアイコン・サムネイル: `assets/marketing/`(icon.png = 題字つき / icon_plain.png = 題字なし、thumb_*.png = 1920×1080)。作り直すときは `python tools/marketing/render_marketing.py build/battle.json assets/marketing`(ゲームと同じ舞台と本物の魚のモデルで描く)

## 課金商品を作って ID を入れる
Creator Dashboard → 体験 → 収益化 で作成し、`src/shared/Config/Products.luau` の `id = 0` を書き換えます。
- [ ] ゲームパス: 2倍の運(399) / 自動釣り(299) / 自動売却(149) / VIP(299) / 大きな魚籠(149) / 水槽の拡張(199)
- [ ] 開発者アイテム: 運のお札(79) / サーバー大漁(199) / 高級エサ10個(49) / 依頼の入れ替え(29)
- [ ] 報酬型広告: 利用条件を満たしてから、広告報酬用の開発者アイテムを作り `RewardedAd.devProductId` を設定し `enabled = true`。**有効にする前に Roblox の最新ドキュメントで AdService の関数名を確認**(`MonetizationService.showRewardedAd`)
- [ ] Studio のテスト購入で各商品を1回ずつ買い、効果と「二重に付与されないこと」を確認

## 見た目と音を入れる
- [ ] `assets/fish/YokaiFishMeshes.glb` を読み込んで ReplicatedStorage.FishMeshes に置く([ANIME_MESHES.md](ANIME_MESHES.md))
- [ ] 勾玉の商品3つ(`magatamaS/M/L`)を作り、ID を `Config/Products.luau` に入れる。祠の確率の表が見えること・買えない地域で買うボタンが出ないことを確かめる([GACHA.md](GACHA.md))
- [ ] BGM 6曲 `assets/sounds/bgm/{village,swamp,river,sea,battle,boss}.ogg` をアップロードし、ID を `Config/Music.luau` の各曲の `soundId` に入れる([MUSIC.md](MUSIC.md))
- [ ] `assets/sounds/YokaiCries.ogg` をアップロードし、ID を `Config/Cries.luau` の `soundId` に入れる([CRIES.md](CRIES.md))

## 遊んで確認(Studio の Play / 2人以上は「テスト → サーバーとクライアント」)
- [ ] 沼の桟橋に出現 → 案内どおり 投げる → 「!」→ 引き上げ → 「上」以上の魚 → 図鑑登録 → 狸に売る(30秒以内)
- [ ] 水辺から離れて投げると「水辺に近づこう」
- [ ] 魚籠が満杯だと投げられない(自動売却パスがあれば売られる)
- [ ] 竿を買うと見た目が変わる / エサが1回ごとに減る
- [ ] 鳥居で村へ移動 → 竿屋・エサ屋・依頼板・水槽(自分の小屋)が開く
- [ ] 水槽に飾った魚が他のプレイヤーにも見える
- [ ] 昼夜(20分)・天気(10分)で見た目と釣れる魚が変わる
- [ ] ぬし(毎時30分〜35分、サーバー時刻)に2人以上で参加して成功・失敗の両方
- [ ] 日本語/英語の切替で看板・ボタン・画面がすべて切り替わる
- [ ] 村・沼・川・海で BGM が変わり、バトルでバトルの曲になる(設定の「🎵 BGM」で止まる)
- [ ] 魚を釣った時・図鑑の「🔊 鳴き声」・バトルで魚が鳴き、吹き出しが出る(音をオフにすると鳴かない)
- [ ] スマホ表示(Studio のデバイスエミュレーター)で右下ボタンだけで最後まで遊べる
- [ ] 退出 → 再参加でデータが残っている / 2つのサーバーを素早く移動してもデータが巻き戻らない
- [ ] **オンライン**(「テスト → サーバーとクライアント」で2〜3人):
  - [ ] なかま → ⚔ で申し込み → 相手の右上にカード → 受ける → 対戦。「相手は選び終わった!」・残り時間の帯・時間切れ・降参(2回押す)
  - [ ] 「受け取らない」にした人のボタンが押せない / 対戦中の人に「対戦中」
  - [ ] ランダム対戦: 2人で同時に押すとつながる / 1人だけだと10秒後に「ほかのサーバーの釣り人のチーム」と戦う(MemoryStore は公開後・API アクセス有効時のみ。Studio では見つからずに終わってよい)
  - [ ] ボス戦: 部屋を作る → 他の人に募集のカード → 参加 → 始める → ボスの体力が全員で減る → 半分で怒る → 勝つと全員に小判(2回目は「受け取り済み」)
  - [ ] スタンプが頭の上に出る / 相手の言語で表示される
  - [ ] 対戦の途中でゲームを閉じると、残った人が勝つ
  - [ ] 友達の招待画面・友達申請画面が出る(公開後のゲームで確認)

## 公開後に見る数字(AnalyticsService)
- オンボーディングのファネル: Joined → FirstCast → FirstHook → FirstCatch → FirstSell → FirstRod
- 経済: 小判の入手(SellFish / AutoSell / Quest / Daily / CodexComplete)と消費(BuyRod / BuyBait / UnlockSpot)
- カスタム: Catch_legendary 以上、Unlock_<釣り場>、Purchase_<商品>、NushiReward、SuspiciousReel(不正の疑い)
