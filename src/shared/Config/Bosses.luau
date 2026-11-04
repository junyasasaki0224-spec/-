--!strict
-- ボス戦(協力)の相手。見た目と技は魚の表の fish をそのまま大きくして使う。
--   level    : ボスのレベル(能力値の計算に使う)
--   hpMult   : 体力の倍率(参加人数をさらに掛ける。人数が多いほど硬い)
--   atkMult  : 攻撃の倍率
--   recommend: おすすめの相棒のレベル(画面に出す目安)
--   reward   : 勝った時の小判とエサ(ボスごとに1日1回)。経験値は毎回
--   title    : 初めて倒した時の称号(省略可)
export type Boss = {
	id: string,
	fish: string,
	ja: string,
	en: string,
	jaDesc: string,
	enDesc: string,
	level: number,
	hpMult: number,
	atkMult: number,
	recommend: number,
	reward: { coins: number, bait: { id: string, amount: number }? },
	title: string?,
}

local Bosses: { Boss } = {
	{
		id = "oonamazu",
		fish = "raijin_namazu",
		ja = "ライドドン",
		en = "Raidodon",
		jaDesc = "地の底で暴れる雷の大鯰。腹の太鼓で地震を起こす。",
		enDesc = "A thunder catfish raging underground. Its belly drums shake the earth.",
		level = 26,
		hpMult = 4,
		atkMult = 1.0,
		recommend = 18,
		reward = { coins = 6000, bait = { id = "glow_shrimp", amount = 2 } },
	},
	{
		id = "umibozu",
		fish = "umibozu_ei",
		ja = "ウミボン",
		en = "Umibon",
		jaDesc = "嵐の夜に海から立ち上がる黒い大入道。",
		enDesc = "A black giant that rises from the sea on stormy nights.",
		level = 36,
		hpMult = 5,
		atkMult = 1.1,
		recommend = 28,
		reward = { coins = 15000, bait = { id = "aburaage", amount = 2 } },
	},
	{
		id = "yamata",
		fish = "yamata_chochin",
		ja = "ヤツアカリ",
		en = "Yatsuakari",
		jaDesc = "八つの灯りを持つ大妖怪。灯りがすべてともると手がつけられない。",
		enDesc = "A great yokai with eight lanterns. Once all eight are lit, nothing can stop it.",
		level = 48,
		hpMult = 6,
		atkMult = 1.2,
		recommend = 40,
		reward = { coins = 40000, bait = { id = "premium", amount = 3 } },
		title = "raid_master",
	},
	{
		id = "bake_kujira",
		fish = "bake_kujira",
		ja = "ホネクジ",
		en = "Honekuji",
		jaDesc = "骨だけの大鯨。泳いだあとには、怪しい鳥と魚の群れが渦を巻く。",
		enDesc = "A giant whale of bare bones. Eerie birds and fish swirl in its wake.",
		level = 50,
		hpMult = 7,
		atkMult = 1.3,
		recommend = 45,
		reward = { coins = 80000, bait = { id = "premium", amount = 5 } },
	},
}

return Bosses
