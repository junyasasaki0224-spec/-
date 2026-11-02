--!strict
-- 課金商品の表。id = 0 のものは「未設定」として購入ボタンを表示しない。
-- 公開前に Creator Dashboard で商品を作り、ここに ID を書き込む(docs/LAUNCH.md 参照)。
-- ※ID は公開情報なのでコードに書いてよい。APIキーなどの秘密情報は絶対に書かないこと。

export type GamePass = { key: string, id: number, robux: number }
export type DevProduct = { key: string, id: number, robux: number }

local Products = {}

Products.GamePasses = {
	{ key = "luck2x", id = 0, robux = 399 }, -- 運が永久に2倍
	{ key = "autoFish", id = 0, robux = 299 }, -- 自動釣り
	{ key = "autoSell", id = 0, robux = 149 }, -- 自動売却
	{ key = "vip", id = 0, robux = 299 }, -- 売値+20%、金の称号
	{ key = "bigCreel", id = 0, robux = 149 }, -- 魚籠 +50
	{ key = "bigTank", id = 0, robux = 199 }, -- 水槽 2倍
} :: { GamePass }

Products.DevProducts = {
	{ key = "luckCharm", id = 0, robux = 79 }, -- 15分間 自分の運2倍
	{ key = "serverLuck", id = 0, robux = 199 }, -- 15分間 サーバー全員の運2倍
	{ key = "premiumBait10", id = 0, robux = 49 }, -- 高級エサ10個
	{ key = "questReroll", id = 0, robux = 29 }, -- 依頼を1つ入れ替え
} :: { DevProduct }

-- 報酬型動画広告(Roblox の Rewarded Video Ads)。使えない地域・端末では自動で非表示。
Products.RewardedAd = {
	enabled = false, -- 公開後、広告の利用条件を満たしたら true にする
	devProductKey = "adLuck", -- 広告報酬用の開発者アイテム(Creator Dashboardで作成)
	devProductId = 0,
	luckMinutes = 10,
}

return Products
