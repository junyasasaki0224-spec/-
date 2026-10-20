# my-roblox-game

Robloxゲーム開発用のプロジェクトです。コードは VS Code で書き、[Rojo](https://rojo.space/) で Roblox Studio に同期します。
サンプルとして「マップに出てくるコインを集めるとスコアが増える」簡単なゲームが入っています。

## フォルダ構成

| パス | Studio上の場所 | 役割 |
| --- | --- | --- |
| `src/server/` | `ServerScriptService.Server` | サーバーで動くスクリプト(`init.server.luau` が本体) |
| `src/client/` | `StarterPlayer.StarterPlayerScripts.Client` | 各プレイヤーの画面で動くスクリプト |
| `src/shared/` | `ReplicatedStorage.Shared` | サーバー/クライアント共通のモジュール |
| `default.project.json` | — | 上の対応関係を決めるRojoの設定 |
| `rokit.toml` | — | 使うツール(Rojo / StyLua / Selene)のバージョン |

ファイル名のルール: `〜.server.luau` = Script、`〜.client.luau` = LocalScript、`〜.luau` = ModuleScript。

## セットアップ手順(自分のPCでやること)

Roblox Studio は Windows / Mac 専用なので、ここから先は自分のPCで行ってください。

### 1. Robloxアカウントを作る
https://www.roblox.com/ でアカウントを作成(すでにあればOK)。

### 2. Roblox Studio をインストール
https://create.roblox.com/ を開いて「作成を開始(Start Creating)」→ Studio をダウンロードしてインストール。起動してログインします。

### 3. Git と VS Code をインストール
- Git: https://git-scm.com/
- VS Code: https://code.visualstudio.com/

### 4. このリポジトリをクローンして VS Code で開く
```sh
git clone https://github.com/junyasasaki0224-spec/-.git my-roblox-game
cd my-roblox-game
code .
```
VS Code 右下に「おすすめの拡張機能」が出たら全部インストール(Rojo / Luau LSP / StyLua / Selene)。

### 5. Rokit と開発ツールを入れる
Rokit のインストール方法は https://github.com/rojo-rbx/rokit を参照(Windowsはインストーラ、Macはターミナルで1行コマンド)。
入ったらプロジェクトのフォルダで:
```sh
rokit install
rojo --version   # 7.7.1 と出ればOK
```

### 6. Studio に Rojo プラグインを入れる
```sh
rojo plugin install
```
Studio を再起動すると、上部の「プラグイン」タブに Rojo が出てきます。

### 7. 同期して動かす
1. Studio で「Baseplate」テンプレートを開く
2. ターミナルで `rojo serve` を実行
3. Studio の Rojo プラグインで **Connect** を押す
4. Studio で ▶ プレイ → 黄色いコインに触るとスコア(右上の Coins)が増えれば成功!

以後は VS Code でファイルを保存するたびに Studio に自動で反映されます。

## よく使うコマンド

```sh
rojo serve                         # Studioとライブ同期
rojo build -o game.rbxl            # .rbxl ファイルを書き出す(Studioで直接開ける)
stylua src                         # コードを自動整形
selene src                         # コードのミス・悪い書き方をチェック
```

## 次にやること(アイデア)
- `src/shared/Config.luau` の数字を変えてゲームバランスをいじる
- コインを取ったときの音やエフェクトを足す
- DataStore でスコアを保存する
- 公式ドキュメント: https://create.roblox.com/docs (日本語あり)
