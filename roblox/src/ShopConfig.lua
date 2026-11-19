-- Robux で買える物の一覧(ショップ)。レースの速さ・強さは変わらない。
--   ・コインの袋(開発者製品、何度でも買える): ガチャを引けるコイン
--   ・みなと VIP パス(ゲームパス、1回買えばずっと): 特典は下の vip
-- コインはガチャ(中身がランダム)に使うため、Roblox の決まりで、地域によっては買えない
-- (PolicyService の ArePaidRandomItemsRestricted。ShopService がサーバーで確かめる)。
-- product / pass は Creator Hub(作成 → 体験 → 収益化)で作った番号を入れる(PUBLISH.md)。0 の間は「準備中」と出て買えない。
-- price は作る時の目安(画面には Roblox から取った本当の値段を出す)。
return {
	-- コインの袋。coins が本体、bonus がおまけ(届くのは合計)
	coins = {
		{ key = "c1", coins = 500, bonus = 0, product = 0, price = 49 },
		{ key = "c2", coins = 1000, bonus = 100, product = 0, price = 99 },
		{ key = "c3", coins = 3000, bonus = 500, product = 0, price = 299 },
		{ key = "c4", coins = 6000, bonus = 1500, product = 0, price = 599 },
	},
	-- みなと VIP パス(目安 600 Robux = 約1000円。円での値段は Robux の買い方で変わる)
	--   ・ランク戦が無制限(ふつうは1日 Meta.RANKED_DAILY 回)
	--   ・金の塗装とヘルメット(items)、ホームの VIP の札
	--   ・買った時に welcomeCoins コイン、毎日 dailyCoins コイン(コインが買えない地域では、コインの特典は付かない)
	vip = { pass = 0, price = 600, items = { "v1", "v2" }, welcomeCoins = 1000, dailyCoins = 100 },
}
