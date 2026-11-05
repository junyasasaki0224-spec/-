--!strict
-- 百鬼の祠(ガチャ)。勾玉(まがたま)か祈願札で祈ると、限定の魚や道具を授かる。
-- 確率はゲームの画面にいつも出す(Roblox の決まり: 有料のランダムな品は確率を見せる)。
-- 勾玉を Robux で買えない地域(PolicyService の ArePaidRandomItemsRestricted)では、買うボタンを出さない。
-- 数字を変えたら tests/run.luau と docs/GACHA.md の表も見直す。

local Gacha = {}

-- 1回 / 10回の勾玉。祈願札は1枚で1回(札を先に使い、足りない分を勾玉で払う)
Gacha.Cost = 150
Gacha.MaxPulls = 10

-- 星ごとの重み(合計 10000 = 100.00%)
Gacha.Stars = {
	{ star = 5, weight = 60 }, -- 0.6%  限定の魚(いちばん上)
	{ star = 4, weight = 540 }, -- 5.4% 限定の魚(伝説)
	{ star = 3, weight = 1400 }, -- 14%  限定の魚(極)
	{ star = 2, weight = 3000 }, -- 30%  良い道具
	{ star = 1, weight = 5000 }, -- 50%  小判・エサ
}

-- 天井: ★4以上は10回に1回は必ず。★5は90回目で必ず(★5が出たら数え直し)
Gacha.Pity = { star4 = 10, star5 = 90 }

-- 星ごとの限定の魚(Config/Fish/Shrine.luau の id)。同じ星の中は同じ確率
Gacha.Fish = {
	[5] = { "amaterasu_manbou", "yamata_orochi" },
	[4] = { "hi_no_tori", "koku_ryu", "yuki_hime" },
	[3] = { "gin_kitsune", "yozakura_kurage", "raijin_shumoku" },
} :: { [number]: { string } }

-- ★1・★2 の道具(重みで選ぶ)。coins は竿の段階で増える(Gacha.coinsFor)
export type Item = {
	kind: string, -- coins / bait / luck
	amount: number?, -- 小判の基本の額・エサの数
	id: string?, -- エサの id
	minutes: number?, -- 運2倍の分数
	weight: number,
}
Gacha.Items = {
	[2] = {
		{ kind = "coins", amount = 1500, weight = 40 },
		{ kind = "bait", id = "glow_shrimp", amount = 5, weight = 25 },
		{ kind = "bait", id = "premium", amount = 3, weight = 20 },
		{ kind = "luck", minutes = 10, weight = 15 },
	},
	[1] = {
		{ kind = "coins", amount = 400, weight = 50 },
		{ kind = "bait", id = "worm", amount = 10, weight = 30 },
		{ kind = "bait", id = "dango", amount = 5, weight = 20 },
	},
} :: { [number]: { Item } }

-- 小判は竿が良くなるほど多く(序盤の稼ぎを壊さず、後半も意味があるように)
function Gacha.coinsFor(base: number, rodTier: number): number
	return math.floor(base * (1 + 0.6 * (math.max(1, rodTier) - 1)))
end

-- 勾玉・祈願札のもらい方(遊んでいればたまる。1週間でおよそ10回ぶん)
Gacha.Earn = {
	welcomeTickets = 5, -- はじめて遊んだ時の祈願札
	daily = 50, -- 毎日のログイン報酬といっしょに
	dailyWeekTickets = 1, -- 7日続けた日に祈願札
	quest = 20, -- 依頼を1つ受け取るたび
	questAll = 50, -- その日の依頼を全部受け取った時のおまけ
	newFish = 20, -- 図鑑に新しい魚が載った時(釣りで)
	codexComplete = 300, -- 釣り場の図鑑を全部埋めた時
	codexCompleteTickets = 1,
	trainerFirst = 100, -- 妖怪退治の相手に初めて勝った時
	lordFirst = 300, -- 各地のぬしに初めて勝った時(trainerFirst の代わり)
	lordFirstTickets = 2,
	raidFirst = 300, -- 協力のボスに初めて勝った時
	raidFirstTickets = 1,
	raidDaily = 30, -- 協力のボスに勝った日(ボスごとに1日1回)
}

-- ★5を授かった時、サーバーの全員に知らせる
Gacha.AnnounceStar = 5

return Gacha
