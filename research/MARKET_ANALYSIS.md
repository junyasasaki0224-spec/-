# 市場分析（ベースライン・2026年11月時点）

毎日の企画は、この分析と「その日のトレンド調査」（`research/daily/`）の両方を根拠にする。
数値の多くはプラットフォーム自身の発表や業界メディアの二次情報なので、**方向性の参考**として扱う。
四半期に一度は見直す。

## 1. 事実（ソース付き）

### ブラウザゲーム
| 事実 | 出典 |
|---|---|
| 米国のブラウザゲームのプレイ時間は、ハイパーカジュアル＋パズルで99%超。ハイパーカジュアルが年間の79%で首位、朝の時間帯はパズルが首位 | CrazyGames調査。2025年5月〜2026年5月、17.4億セッション・8.62億時間（[PocketGamer.biz](https://www.pocketgamer.biz/report-hypercasual-and-puzzle-games-dominate-the-browser-gaming-space/)、[Outlook Respawn](https://respawn.outlookindia.com/gaming/gaming-news/hypercasual-and-puzzle-titles-dominate-99-of-web-browser-gaming)） |
| 平均セッションは約30分（米国） | 同上 |
| Webゲーマーの37%が1日に複数回プレイ。62%がWebで遊んだ後にゲームを購入／DLした経験あり | Poki「2026 State of Web Gaming」。英米のWebゲーマー2,000人・開発者400社の調査（[Poki](https://poki.com/blog/state-of-web-gaming-report-2026)、[GamesBeat](https://gamesbeat.com/new-study-shows-the-growth-engagement-discoverability-and-value-driving-web-gaming-exclusive/)） |
| 開発会社の53%が、今後12か月でモバイルゲームをブラウザ版に移植予定 | 同上（[PocketGamer.biz](https://www.pocketgamer.biz/report-53-plan-to-port-mobile-games-to-browser-in-next-12-months/)） |
| Pokiの収益分配は、Poki経由の流入なら50/50、自前の流入なら100%開発者。Web独占を求める | 二次情報（[tech-insider](https://tech-insider.org/crazygames-vs-poki-vs-coolmath-games-2026/)） |

### モバイルのカジュアル市場（ブラウザでも伸びる仕組みの先行指標）
| 事実 | 出典 |
|---|---|
| 2026年上半期、Merge-2ジャンルの売上がほぼ倍増して12.4億ドル。仕分け（sort）・ねじ（screw）・ブロック系パズルは売上+46% | AppMagic H1 2026（[gameindustrylibrary](https://gameindustrylibrary.com/documents/appmagic-mobile-casual-games-in-h1-2026-powered-by-mellow)、[mobidictum](https://mobidictum.com/sort-block-screw-mechanics-puzzle-games-market/)） |
| 仕分けパズルは2025年に+116% | 同上（[cinevva](https://app.cinevva.com/guides/casual-games-trends-2026)） |
| マッチ3・Merge・Blastのインストールシェアは、10年前の75%超から25%未満に低下 | 同上 |
| 上位のハイパーカジュアルは、30日後継続率5%以上が必要。上位パズルの約半数が連勝ボーナスや期間イベントを採用 | [PocketGamer.biz](https://www.pocketgamer.biz/what-happened-to-hypercasual-the-markets-evolution-over-the-past-year/) |

### 日本
- 国内ブラウザゲームのジャンル別の公的な統計は見つからなかった。
- 国内の主要な投稿先は unityroom、ふりーむ! など。
- 長く検索され続けているのは、タイピング・脳トレ・学習（都道府県・漢字・英単語・計算）など「目的があって探される」ゲーム（定性的な観察）。

### 法律（企画の自由度に直結）
- 日本：ゲームのルールはアイデアであり著作権で保護されない（釣りゲーム事件 知財高裁 平成24年）。
- 同様の判断は韓国・英国・米国にもある。ただし米国 Tetris v. Xio では「見た目の模倣」が侵害とされた。
- システムは特許の対象になりうる（2024年 任天堂 v. ポケットペア）。詳細は `automation/legal/LEGAL.md`。

## 2. 解釈（このサイトにとっての意味）

1. **需要の中心はパズルとハイパーカジュアル**
   - 1分で分かり、片手で遊べ、区切りのあるゲームが勝つ。
   - 特に仕分け・ブロック・合体（merge）は、モバイルでいま伸びている仕組み。ブラウザでも需要があると推定できる。
2. **継続の仕組みはカジュアル市場の定番を借りる**
   - 連勝、日替わり、連続日数、自己ベストの更新。
   - どれもルールの仕組みなので自由に使える。表現は自作する。
3. **供給は爆発している**
   - 大手のモバイル移植とAIによる量産で、汎用的な作品は埋もれる。
   - 個人が差をつける余地は「日本語・日本の季節や文化」「検索で探される用途」「ひとひねり（twist）」の3つ。
4. **定番そのままは勝てない**
   - ソリティア等はGoogle検索結果の画面で直接遊べるうえ、大手ポータルが独占している。
   - 定番は必ずtwistを入れてから出す。
5. **配信チャネルは後で足す**
   - Poki等はWeb独占を求めるため、自分のサイトとの両立は作品ごとに判断する。
   - 当たった作品だけ、ポータルへの配信を検討する。

## 3. 戦略への落とし込み
→ `automation/STRATEGY.md`（4レーンの配分と企画スコアリング）
