# ショップの値段の決め方(2026-11-20)

Roblox で遊んでいる人たちと、ほかの人気ゲームの値段を調べて、ショップの値段を決め直した。
数字は `src/ShopConfig.lua` にある(ここは理由の説明)。

## 1. 遊んでいる人たち

- **年齢**:13歳未満がおよそ 3〜4 割(2025年の毎日遊ぶ人の数から)。年齢確認が入ってからは 13歳以上が多い。
  それでも、**小学生・中学生がお金を払う中心**と考える。
  - 2024年の内訳の例:9歳未満 20%・9〜12歳 20%・13〜16歳 16%・17〜24歳 25%・25歳以上 19%
  - 5〜8歳は、2026年6月から「Roblox Kids」アカウント(日本も対象)
- **日本**:毎日遊ぶ人は 2022年末から 2024年末で 2.2倍に増えた。
- **遊び方**:スマホ・タブレットが中心(このゲームもスマホ優先)。
- **お金の払い方**:子どもは、親に買ってもらうギフトカードや、アプリの中の決まった Robux の束で払うことが多い。
  - アプリの中の束:400 / 800 / 1700 Robux など(PC やギフトカードだと同じ値段で少し多く入る)
  - 円での目安:**アプリでは 1 Robux ≒ 約2円、PC・ギフトカードでは約1.6円**
    (400 Robux ≒ 約800円という表から。国・時期・買い方で変わるので、あくまで目安)
- **払う人の割合**:払う人は 1% 前後といわれる。たくさん払う少数の人よりも、
  **「はじめての1回」を払いやすくすること**と、**子どもが手元の Robux で買える値段**が大事。

## 2. ほかのゲームの値段(パス)

| ゲーム | パス | 値段 |
|---|---|---|
| Steal a Brainrot | VIP | 375 Robux |
| Steal a Brainrot | お金2倍 | 299 Robux |
| Doors | VIP | 400 Robux |
| Blox Fruits | 熟練度2倍 | 450 Robux |
| Zombie Hunters | VIP | 749 Robux |

- VIP は **300〜500 Robux** が多い。小さな買い物(開発者製品)は 25〜99 Robux から始まることが多い。
- 値段はよく変わるので、出す前にもう一度見る。

## 3. 決めたこと

考え方:

- **400 Robux の束1つで買える上限にする**:いちばん高い品(VIP パス・いちばん大きいコインの袋)を 399 Robux にした。
  前の 599・600 Robux は、400 の束1つでは買えず、子どもには届きにくい。
- **はじめての1回を安く**:いちばん小さい袋は 49 Robux(約80〜100円)。少しだけ残った Robux でも買える。
- **大きい袋ほど少しだけお得**:おまけは 0% → 10% → 20% → 30%。
  ただし、子どもがたくさん使いすぎないよう、**いちばん大きい袋は 399 Robux まで**(前の 599 Robux の袋はやめた)。
- **ガチャの基本**:1回(100コイン)はおよそ 10 Robux。10連(900コイン)が気持ちよく引ける量にそろえた。
- **遊ぶだけでも集まる**:ログイン・ミッション・レースで、1日 30分くらい遊ぶと 600〜700 コイン(ガチャ6〜7回)。
  お金を払わなくても、全部の品を少しずつ集められる。

| 品 | 中身 | 値段 | 円の目安 | 1 Robux あたり |
|---|---|---|---|---|
| c1 | 500 コイン(ガチャ5回) | 49 Robux | 約80〜100円 | 10.2 コイン |
| c2 | 1000 + おまけ 100(10連 + 2回) | 99 Robux | 約160〜200円 | 11.1 コイン |
| c3 | 2000 + おまけ 400(10連 ×2 + 6回) | 199 Robux | 約320〜400円 | 12.1 コイン |
| c4 | 4000 + おまけ 1200(10連 ×5 + 7回) | 399 Robux | 約640〜800円 | 13.0 コイン |
| VIP パス | ランク戦無制限・金の塗装とヘルメット・VIP の札・買った時 1000 コイン・毎日 100 コイン | 399 Robux | 約640〜800円 | — |

- VIP パスは、ほかのゲームの VIP(375〜400 Robux)と同じくらいにした。
  前に決めた「約1000円(600 Robux)」から下げた。
- レースの速さ・強さは、どの品でも変わらない(お金で勝てるようにはしない)。

## 4. 公開した後にすること

- **パスの地域ごとの値段(Regional Pricing)を入れる**:物価の安い国では、Roblox が自動で値段を下げる(最低で元の 30%)。
  パスを作る時に Creator Hub で選ぶ。開発者製品(コインの袋)には今はない。
- **値段の試し(Price Optimization)**:人が増えてきたら、Creator Hub の値段の試しの機能で、
  いくつかの値段を比べて決め直す(上の値段は、はじめの目安)。
- 急がせる売り方(「残りわずか」など、本当でないもの)はしない。

## 調べた所

- [Roblox の毎日遊ぶ人数と年齢(Statista)](https://www.statista.com/statistics/1190309/daily-active-users-worldwide-roblox)
- [Roblox の利用者の内訳(Exploding Topics)](https://explodingtopics.com/blog/roblox-stats)
- [Roblox の Q4 2025 の数字(Outlook Respawn)](https://respawn.outlookindia.com/gaming/gaming-news/roblox-daily-users-jump-69-to-record-144-million-in-q4-2025)
- [Roblox の日本での伸び(Business Insider Japan)](https://www.businessinsider.jp/article/2511-roblox-japan-business/)
- [Robux の値段(Roblox Wiki)](https://roblox.fandom.com/Robux)
- [Robux の値段(Pro Game Guides)](https://progameguides.com/roblox/roblox-price-guide-how-much-do-robux-cost)
- [収益化(Roblox 公式)](https://create.roblox.com/docs/production/monetization)
- [値段の試し(Roblox 公式)](https://create.roblox.com/docs/en-us/production/monetization/price-optimization)
- [パスの地域ごとの値段(Roblox DevForum)](https://devforum.roblox.com/t/introducing-regional-pricing-for-passes/3621382)
- [パスの値段の相談(Roblox DevForum)](https://devforum.roblox.com/t/what-is-a-good-price-threshold-for-game-passes/3598052)
- [Steal a Brainrot のパスの値段(BuffGet)](https://buffget.com/news/steal-a-brainrot-game-pass-prices-robux-2026)
- [Blox Fruits のパス(Sportskeeda)](https://www.sportskeeda.com/roblox-news/everything-know-gamepasses-roblox-blox-fruits)
- [Zombie Hunters のパス(Sportskeeda)](https://sportskeeda.com/roblox-news/exploring-gamepasses-roblox-zombie-hunters)
