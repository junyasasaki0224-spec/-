# CLAUDE.md

このリポジトリは「毎日1本ミニゲームを作って公開する」静的サイトです。

- 日次の新作開発を頼まれたら、`automation/DAILY_PROMPT.md` を上から順に実行する。
- 企画の判断基準は `automation/STRATEGY.md`、法務は `automation/legal/LEGAL.md` に従う（最優先）。
- 特定の既存ゲームの再現（名前・キャラ・絵・音・ステージ・見た目）は作らない。ジャンル共通のルールに独自の工夫を加える。
- 外部ライブラリ・外部素材・Webフォントは使わない。依存パッケージを増やさない（playwright はインストール済みのものを使う。`npm install playwright` しない）。
- 変更後は必ず `npm run check` を通す。テストを無効化して通すことは禁止。
- ゲームは `site/games/<slug>/` に閉じる。共通ファイル（`site/assets/*`、`scripts/*`）の変更は最小限にし、理由をPRに書く。
