# まいにちゲーム工房（仮）

毎日1本、AIがミニゲームを **市場調査 → 企画（採点）→ 法務チェック → 実装 → 自動テスト → PR提出** し、人間が遊んで確認してマージすると公開される仕組みです。

```
毎日 4:23 (JST) ──▶ Claude が自動起動
                     │ 1. 市場・トレンド調査（Web検索）
                     │ 2. 企画8案 → スコア表で採点 → 1案選択
                     │ 3. 法務チェック（著作権・商標・不競法・特許・景表法）
                     │ 4. 実装（外部素材なし・スマホ対応）
                     │ 5. npm run check（構造/商標語/実ブラウザ/自動プレイ）
                     │ 6. 研究ノート + PR 作成
                     ▼
あなた ──▶ PRを開いて遊ぶ → OKならマージ ──▶ GitHub Pages に自動公開
```

## ディレクトリ

| パス | 中身 |
|---|---|
| `automation/DAILY_PROMPT.md` | **日次ルーチンの指示書**（自動実行はこれを読んで動く） |
| `automation/STRATEGY.md` | 4レーンの配分・企画スコア表・品質基準・KPI |
| `automation/legal/LEGAL.md` | 法務ガイドラインとチェックリスト |
| `automation/legal/blocked-terms.txt` | 公開ページで使用禁止の作品名・商標（validate が検査） |
| `automation/PORTAL_GUIDE.md` | 大手ゲームサイト（CrazyGames / Poki）への出し方（オーナー向け） |
| `automation/templates/game/` | 新作の雛形 |
| `research/MARKET_ANALYSIS.md` | 市場分析（ベースライン・出典付き） |
| `research/SEASONAL_CALENDAR.md` | 季節・行事カレンダー |
| `research/daily/` | 毎日の調査・企画・採点・法務チェックの記録 |
| `site/` | 公開サイトのソース（`site/games/<slug>/` が各ゲーム） |
| `site/assets/core.js` | 共通ランタイム GameKit（保存・日替わり乱数・共有・広告・効果音・計測） |
| `scripts/` | validate / build / smoke-test / portfolio / new-game / build-portal / portal-test |

## コマンド

```bash
npm run check        # validate → build → 大手サイト用ビルド → 実ブラウザテスト → 英語版/SDKテスト
npm run portal       # 大手サイト提出用パッケージだけ作る（portal-dist/）
npm run serve        # dist/ を http://127.0.0.1:8080 で確認
npm run portfolio    # 既存ゲームの偏り分析（次に作るべきレーン/ジャンル）
npm run new -- <slug> "<タイトル>"   # 雛形作成
```

## 最初にやること（オーナー）

1. このブランチを `main` にマージする。マージ前は、日次PRがこのブランチ宛てに作られる。
2. GitHub の Settings → Pages → Source を **GitHub Actions** にする。`main` への push で自動公開される。
3. 公開URLが決まったら、`site.config.json` の `baseUrl` に設定する（canonical と sitemap 用）。
4. サイト名 `siteName` は仮なので、好きな名前に変える。変える前に商標の検索をすること。
5. 広告：ゲームが10本以上・遊び方ページが揃ってから AdSense に申請する。
   - 承認後、`adsense.client`（`ca-pub-...`）を設定する。
   - H5 Games Ads（ゲーム内広告）が承認されたら `h5GamesAds: true` にする。
6. 計測：GoatCounter（Cookie不要）のコードを `analytics.goatcounterCode` に設定する。
   - 週1回、数字を `research/performance.json` に転記する。
   - 日次の自動化はこのファイルを読んで、当たった作品の派生を優先する。

## 大手ゲームサイトへの提出

全作品について、英語版と CrazyGames / Poki のSDKを組み込んだ提出用パッケージが自動で作られます。
GitHub の Actions → 最新の CI → Artifacts の `portal-packages` からダウンロードできます。
どの作品をいつ出すか、どう出すかは `automation/PORTAL_GUIDE.md` を参照してください。

## 守っているルール（要約）

- ルール（アイデア）は借りてよいが、表現（名前・絵・音・キャラ・ステージ・見た目）は借りない。
- 外部素材・外部スクリプトは使わない。会員登録・個人情報の入力欄は作らない。
- 広告は操作エリアから離して置く。全画面広告はラウンド間などの自然な区切りでだけ出す。
- 詳細は `automation/legal/LEGAL.md`。法的助言ではないため、収益化が大きくなったら専門家のレビューを受けること。
