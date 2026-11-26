-- Robux で買える物の一覧(ショップ)。レースの速さ・強さは変わらない。
--   ・コインの袋(開発者製品、何度でも買える): ガチャを引けるコイン
--   ・みなと VIP 会員(サブスクリプション。毎月 Robux で自動で続く): 特典は下の vip
-- コインはガチャ(中身がランダム)に使うため、Roblox の決まりで、地域によっては買えない
-- (PolicyService の ArePaidRandomItemsRestricted。ShopService がサーバーで確かめる)。
-- product / subscription は Creator Hub(作成 → 体験 → 収益化)で作った番号を入れる(PUBLISH.md)。
-- 0 や "" の間は「準備中」と出て買えない。
-- price は作る時の目安(画面には Roblox から取った本当の値段を出す)。決め方は roblox/PRICING.md:
--   遊ぶ人の中心は小中学生・スマホ。いちばん高い品も 400 Robux の束1つで買える 399 Robux まで。
return {
	-- コインの袋。coins が本体、bonus がおまけ(届くのは合計)。ガチャ1回(100コイン)≒ 10 Robux、おまけは 0→10→20→30%
	coins = {
		{ key = "c1", coins = 500, bonus = 0, product = 0, price = 49 },
		{ key = "c2", coins = 1000, bonus = 100, product = 0, price = 99 },
		{ key = "c3", coins = 2000, bonus = 400, product = 0, price = 199 },
		{ key = "c4", coins = 4000, bonus = 1200, product = 0, price = 399 },
	},
	-- みなと VIP 会員(サブスクリプション。目安 月 199 Robux ≒ 約320〜400円。理由は PRICING.md)
	--   subscription は Creator Hub の「収益化 → サブスクリプション」で Robux 払いで作った番号("EXP-" で始まる)。
	--   日本では円などのお金で払うサブスクリプションは使えないので、Robux 払いで作る
	--   特典は、会員の間だけ:
	--   ・ランク戦が無制限(ふつうは1日 Meta.RANKED_DAILY 回)
	--   ・金の塗装とヘルメット(items)、ホームの VIP の札。会員が切れたら使えなくなり、着ていればスタンダードに戻る
	--   ・毎日 dailyCoins コイン(メール)。初めて会員になった時だけ welcomeCoins コイン(更新や入り直しでは届かない)
	--   (コインが買えない地域では、コインの特典は付かない)
	vip = { subscription = "", price = 199, items = { "v1", "v2" }, welcomeCoins = 1000, dailyCoins = 100 },
	-- Roblox のバッジ(プロフィールに並ぶ物。お金はかからない)。ランクに届いた時にロビーのサーバーが渡す。
	-- Creator Hub(作成 → 体験 → 関連アイテム → バッジ)で作った番号を入れる。0 の間は渡さない(ゲームの中のバッジ・称号は 0 でも付く)
	badges = { S = 0, A1 = 0, A3 = 0, B3 = 0, C3 = 0 },
}
