--!strict
-- ゲーム全体の調整値。数値はすべて初期値。公開後のデータを見てここだけ直せばよい。

local Tuning = {}

Tuning.Fishing = {
	biteMinSeconds = 3, -- アタリまでの最短
	biteMaxSeconds = 15, -- アタリまでの最長
	hookWindow = 1.0, -- 「!」から合わせるまでの猶予(秒)
	latencyAllowance = 0.45, -- 通信遅延の許容(サーバー側の判定に加算)
	castMinDistance = 8, -- 最短の飛距離(スタッド)
	castMaxDistance = 42, -- 最長の飛距離
	castMaxHoldSeconds = 1.6, -- この長さ押すと最大パワー
	distanceLuckBonus = 0.20, -- 最大まで飛ばした時の運ボーナス(+20%)
	maxLuck = 20, -- 運の上限(倍率)
	shoreDistance = 14, -- 水辺からこの距離以内でないと投げられない
	netBaseSize = 0.26, -- 網の枠の大きさ(ゲージ高さに対する割合)
	startProgress = 0.20, -- 巻き取りゲージの初期値
	tensionDecay = 0.10, -- 枠の中にいる間に張りが戻る速さ(/秒)
	reelTimeoutSeconds = 90, -- 引き上げの最長時間(これを超えると逃げる)
	minReelFactor = 0.80, -- 最短クリア時間の何割より速い報告を不正とみなすか
	autoFishSpeed = 0.7, -- 自動釣りは手動の7割の速さ
	autoFishReelSeconds = 2.5,
	weightSkew = 1.6, -- 重さの偏り(大きいほど軽い魚が多い)
	weightPriceMin = 0.5, -- 重さによる売値の倍率(最軽量)
	weightPriceMax = 2.0, -- 重さによる売値の倍率(最重量)
}

-- 最初の1匹(直帰を防ぐ)
Tuning.FirstCatch = {
	biteSeconds = 1.6,
	minRarity = "uncommon", -- 「上」以上を保証
	easy = true, -- 魚がゆっくり、枠が大きい
}

Tuning.Inventory = {
	creelBase = 30, -- 魚籠に入る数
	creelPassBonus = 50,
	tankBase = 6, -- 水槽に飾れる数
	tankPassMultiplier = 2,
}

Tuning.Boosts = {
	luckPassMultiplier = 2,
	luckCharmMinutes = 15,
	serverLuckMinutes = 15,
	vipSellMultiplier = 1.2,
	premiumBaitPerPurchase = 10,
}

-- 昼夜と天気。全サーバーで同じ時刻・同じ天気になる(サーバー時刻から計算)。
Tuning.World = {
	dayLengthSeconds = 20 * 60, -- 20分で1日
	weatherPeriodSeconds = 10 * 60, -- 10分ごとに天気が変わる
	weatherWeights = { sunny = 45, rain = 25, fog = 20, thunder = 10 },
	-- 時間帯(ClockTime)。morning は day にも含まれる
	morningStart = 5,
	dayStart = 8,
	nightStart = 19,
}

-- ぬし釣り
Tuning.Nushi = {
	periodSeconds = 60 * 60, -- 1時間に1回
	offsetSeconds = 30 * 60, -- 毎時30分に出現(サーバー時刻)
	durationSeconds = 5 * 60, -- 5分間
	baseRequired = 60, -- 必要な巻き取り量(1人が完璧に1秒巻くと 1)
	perPlayerRequired = 45, -- 参加者1人ごとに増える量
	contributionPerSecondCap = 1.0, -- 1秒あたりの貢献の上限(不正対策)
	minContribution = 10, -- 報酬に必要な最低貢献
	rewardMinRarity = "epic", -- 報酬の魚は「極」以上
	topTitleCount = 3, -- 称号をもらえる上位人数
	joinRadius = 60,
}

-- デイリー報酬(7日周期)
Tuning.DailyRewards = {
	{ coins = 200 },
	{ coins = 400, bait = { id = "worm", amount = 10 } },
	{ coins = 700 },
	{ coins = 1000, bait = { id = "dango", amount = 5 } },
	{ coins = 1500 },
	{ coins = 2500, bait = { id = "glow_shrimp", amount = 3 } },
	{ coins = 5000, bait = { id = "premium", amount = 3 } },
}

Tuning.Quests = {
	perDay = 3,
	-- 1日の切り替え: 日本時間 4:00 (UTC 19:00)
	dayOffsetSeconds = -19 * 3600,
}

Tuning.Leaderboard = {
	refreshSeconds = 120,
	topCount = 10,
	writeMinIntervalSeconds = 30, -- 同じプレイヤーの記録を書き込む最短間隔
}

Tuning.Data = {
	storeName = "YokaiFishing_Profiles_v1",
	autosaveSeconds = 90,
	sessionLockStaleSeconds = 5 * 60, -- 自動保存で更新されるロックがこれより古ければ「落ちたサーバー」とみなす
	loadRetries = 5,
	maxPurchaseHistory = 100,
}

-- 称号
Tuning.Titles = {
	"angler_novice",
	"swamp_master",
	"nushi_hunter",
	"vip",
}

return Tuning
