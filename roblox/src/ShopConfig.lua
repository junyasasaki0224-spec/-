-- Robux で買える物の一覧(ショップ)。見た目だけで、レースの速さ・強さは変わらない。ガチャやコインとは結び付けない。
-- product / pass は Creator Hub(作成 → 体験 → 収益化)で作った番号を入れる(PUBLISH.md)。0 の間は「準備中」と出て買えない。
-- price は作る時の目安(画面には Roblox から取った本当の値段を出す)。
return {
	-- 開発者製品(1回ずつ買う): ショップ限定の塗装とヘルメット
	products = {
		{ item = "x1", product = 0, price = 99 }, -- 塗装 さくら
		{ item = "x2", product = 0, price = 99 }, -- 塗装 ネオンナイト
		{ item = "x3", product = 0, price = 99 }, -- 塗装 朱漆
		{ item = "x4", product = 0, price = 49 }, -- ヘルメット さくら
		{ item = "x5", product = 0, price = 49 }, -- ヘルメット ネオン
	},
	-- ゲームパス(1回買えばずっと): VIP。金の塗装とヘルメット、ホームの VIP の札
	vip = { pass = 0, price = 199, items = { "v1", "v2" } },
}
