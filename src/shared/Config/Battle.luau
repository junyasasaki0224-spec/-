--!strict
-- 相棒バトル(妖怪退治)のデータ。釣った魚を「相棒」にして、魚を食べさせて育て、妖怪と戦う。
-- 数値はすべて初期値。技・属性・相性は表に行を足すだけで増やせる。

local Battle = {}

-- 属性。魚の表(Fish/*.luau)の element に書く
Battle.Elements = {
	{ id = "water", color = "#4FA8FF", icon = "💧" },
	{ id = "fire", color = "#FF7A45", icon = "🔥" },
	{ id = "thunder", color = "#FFD34D", icon = "⚡" },
	{ id = "earth", color = "#C2A36B", icon = "⛰" },
	{ id = "spirit", color = "#B377FF", icon = "👻" },
	{ id = "none", color = "#C9CED6", icon = "◆" }, -- 技だけが持つ「無属性」
}

-- 相性: Chart[攻撃の属性][守る側の属性] = 倍率(書いていない組み合わせは 1倍)
-- 水 → 火 → 土 → 雷 → 水 の順に強い(逆は半分)。霊は霊に強い。
Battle.Chart = {
	water = { fire = 2, thunder = 0.5 },
	fire = { earth = 2, water = 0.5 },
	earth = { thunder = 2, fire = 0.5 },
	thunder = { water = 2, earth = 0.5 },
	spirit = { spirit = 2 },
}

-- 体の形ごとの基本の能力(Lv1・並のとき)
Battle.ShapeStats = {
	koi = { hp = 50, atk = 50, def = 50, spd = 50 }, -- 平均型
	catfish = { hp = 65, atk = 52, def = 55, spd = 30 }, -- 重くて硬い
	puffer = { hp = 72, atk = 36, def = 72, spd = 24 }, -- 守り型
	eel = { hp = 44, atk = 60, def = 36, spd = 72 }, -- 速攻型
	angler = { hp = 52, atk = 66, def = 44, spd = 38 }, -- 攻撃型
	ray = { hp = 56, atk = 46, def = 60, spd = 46 }, -- 守り寄り
	-- 大物(伝説以上の魚だけの形)。合計は少し高め
	shark = { hp = 52, atk = 70, def = 42, spd = 58 }, -- 鋭い攻めと速さ
	orca = { hp = 70, atk = 62, def = 54, spd = 36 }, -- 重く強い
	salmon = { hp = 56, atk = 66, def = 44, spd = 56 }, -- 川を上る力(攻めと速さ)
	salamander = { hp = 82, atk = 56, def = 68, spd = 18 }, -- 川の主: とても硬く、遅い
	whale = { hp = 96, atk = 56, def = 60, spd = 20 }, -- 海の主: 体力がけた違い
	sturgeon = { hp = 66, atk = 50, def = 74, spd = 30 }, -- 湖の古代魚: 鎧のように硬い
}

-- レア度による能力の倍率
Battle.RarityPower = {
	common = 1.0,
	uncommon = 1.12,
	rare = 1.25,
	epic = 1.4,
	legendary = 1.6,
	mythic = 1.85,
	secret = 2.1,
}

Battle.Growth = 0.06 -- 1レベルごとに能力 +6%
Battle.MaxLevel = 50
Battle.MutationBonus = 0.08 -- 変異の売値倍率 1 につき能力 +8%(金1.5倍 → +4%)
Battle.WeightBonus = { 0.95, 1.1 } -- 一番軽い〜一番重い個体の能力倍率

-- 次のレベルまでの経験値: floor(10 × Lv^1.5)(魚を食べさせるだけなら Lv20 まで約80分の釣りが目安)
-- レア度による育ちやすさ: 必要な経験値の倍率(レアほど育つのが遅い。そのぶん能力は高い)
Battle.RarityGrowth = {
	common = 1.0,
	uncommon = 1.15,
	rare = 1.35,
	epic = 1.6,
	legendary = 2.0,
	mythic = 2.5,
	secret = 3.0,
}

function Battle.xpToNext(level: number, rarity: string?): number
	local mult = if rarity then (Battle.RarityGrowth[rarity] or 1) else 1
	return math.floor(10 * level ^ 1.5 * mult)
end

-- 魚を食べさせた時の経験値(食べた魚のレア度)。同じ属性なら 1.5倍、重いほど少し多い(0.75〜1.25倍)
Battle.FeedXp = {
	common = 12,
	uncommon = 35,
	rare = 90,
	epic = 240,
	legendary = 750,
	mythic = 2600,
	secret = 9000,
}
Battle.FeedSameElement = 1.5

Battle.MaxPartners = 6 -- 相棒にできる数
Battle.TeamSize = 3 -- 戦いに出せる数
Battle.MaxTurns = 80 -- これを超えたら負け(長引き防止)
Battle.IdleTimeoutSeconds = 180 -- 操作が無いまま放置すると負け
Battle.WinXpPerEnemyLevel = 9 -- 勝つと 敵のレベル合計 × これ を出場した相棒が受け取る
Battle.RematchCoinRate = 0.2 -- 2回目以降の勝利は小判 20%(経験値は満額)
Battle.CritChance = 0.06
Battle.StageStep = 0.25 -- 能力の上げ下げ1段階あたり ±25%(最大 ±3段階)

-- 技
-- power: 威力(0 なら攻撃しない) / acc: 命中(%) / effect: 追加効果 / chance: 追加効果の確率
-- effect: atk_down / def_down(相手)、def_up / atk_up(自分)、heal(自分の最大HPの割合)、stun(相手が1回休み)、first(先制)
export type Move = {
	id: string,
	ja: string,
	en: string,
	element: string,
	power: number,
	acc: number,
	effect: string?,
	chance: number?,
	amount: number?,
}

Battle.Moves = {
	-- 体の形の技(無属性)
	{ id = "leap", ja = "滝登り", en = "Waterfall Leap", element = "none", power = 55, acc = 95 },
	{
		id = "whisker_whip",
		ja = "ひげ叩き",
		en = "Whisker Whip",
		element = "none",
		power = 45,
		acc = 100,
		effect = "def_down",
		chance = 0.3,
	},
	{
		id = "puff_up",
		ja = "トゲ膨らみ",
		en = "Puff Up",
		element = "none",
		power = 0,
		acc = 100,
		effect = "def_up",
	},
	{
		id = "coil",
		ja = "巻きつき",
		en = "Coil Strike",
		element = "none",
		power = 40,
		acc = 100,
		effect = "first",
	},
	{
		id = "lure",
		ja = "誘いの灯",
		en = "Luring Light",
		element = "none",
		power = 0,
		acc = 100,
		effect = "atk_down",
	},
	{ id = "tail_strike", ja = "尾の一撃", en = "Tail Strike", element = "none", power = 62, acc = 88 },
	{
		id = "jaw_crush",
		ja = "噛み砕き",
		en = "Jaw Crush",
		element = "none",
		power = 60,
		acc = 95,
		effect = "def_down",
	},
	{ id = "breach_slam", ja = "大波返し", en = "Breach Slam", element = "none", power = 75, acc = 85 },
	{
		id = "upstream_rush",
		ja = "遡上突き",
		en = "Upstream Rush",
		element = "none",
		power = 55,
		acc = 100,
		effect = "first",
	},
	{
		id = "swallow_whole",
		ja = "丸のみ",
		en = "Swallow Whole",
		element = "none",
		power = 70,
		acc = 85,
		effect = "atk_down",
	},
	{
		id = "spout",
		ja = "潮吹き",
		en = "Spout",
		element = "none",
		power = 60,
		acc = 100,
		effect = "def_down",
	},
	{
		id = "armor_bash",
		ja = "鎧当て",
		en = "Armor Bash",
		element = "none",
		power = 50,
		acc = 100,
		effect = "def_up",
	},
	{
		id = "rest",
		ja = "ひと休み",
		en = "Rest",
		element = "none",
		power = 0,
		acc = 100,
		effect = "heal",
		amount = 0.35,
	},
	-- 属性の技
	{ id = "water_jet", ja = "水鉄砲", en = "Water Jet", element = "water", power = 50, acc = 100 },
	{ id = "whirlpool", ja = "大渦", en = "Whirlpool", element = "water", power = 85, acc = 90 },
	{ id = "foxfire", ja = "狐火", en = "Foxfire", element = "fire", power = 50, acc = 100 },
	{ id = "onibi_storm", ja = "鬼火の嵐", en = "Will-o'-Storm", element = "fire", power = 85, acc = 90 },
	{ id = "spark", ja = "静電気", en = "Spark", element = "thunder", power = 50, acc = 100 },
	{
		id = "thunderclap",
		ja = "雷鳴",
		en = "Thunderclap",
		element = "thunder",
		power = 80,
		acc = 88,
		effect = "stun",
		chance = 0.2,
	},
	{
		id = "mud_throw",
		ja = "泥かけ",
		en = "Mud Throw",
		element = "earth",
		power = 45,
		acc = 100,
		effect = "atk_down",
		chance = 0.3,
	},
	{ id = "quake", ja = "地割れ", en = "Quake", element = "earth", power = 85, acc = 90 },
	{ id = "grudge", ja = "怨念", en = "Grudge", element = "spirit", power = 50, acc = 100 },
	{
		id = "night_parade",
		ja = "百鬼夜行",
		en = "Night Parade",
		element = "spirit",
		power = 85,
		acc = 90,
	},
	-- 百鬼の祠の限定の魚だけの技(体の形の技の代わり)。強さは体の形の技と同じくらいにして、課金で強くなりすぎないようにする
	{
		id = "silver_dance",
		ja = "銀狐の舞",
		en = "Silver Fox Dance",
		element = "spirit",
		power = 55,
		acc = 100,
		effect = "atk_down",
		chance = 0.3,
	},
	{
		id = "petal_storm",
		ja = "花吹雪",
		en = "Petal Storm",
		element = "earth",
		power = 60,
		acc = 95,
		effect = "def_down",
		chance = 0.3,
	},
	{
		id = "thunder_drum",
		ja = "雷太鼓",
		en = "Thunder Drum",
		element = "thunder",
		power = 50,
		acc = 100,
		effect = "first",
	},
	{
		id = "phoenix_wing",
		ja = "不死鳥の羽ばたき",
		en = "Phoenix Wing",
		element = "fire",
		power = 60,
		acc = 95,
		effect = "heal",
		amount = 0.15,
	},
	{
		id = "black_lightning",
		ja = "黒雷",
		en = "Black Lightning",
		element = "thunder",
		power = 70,
		acc = 90,
	},
	{
		id = "blizzard_breath",
		ja = "吹雪の息",
		en = "Blizzard Breath",
		element = "water",
		power = 60,
		acc = 95,
		effect = "atk_down",
		chance = 0.3,
	},
	{
		id = "heavenly_dawn",
		ja = "天岩戸開き",
		en = "Heavenly Dawn",
		element = "fire",
		power = 75,
		acc = 90,
	},
	{
		id = "eight_fangs",
		ja = "八岐の顎",
		en = "Eight Fangs",
		element = "spirit",
		power = 75,
		acc = 88,
		effect = "def_down",
		chance = 0.3,
	},
	-- 極以上だけが覚える必殺技(属性は自分と同じ)
	{ id = "yoki_burst", ja = "妖気解放", en = "Yoki Burst", element = "self", power = 110, acc = 85 },
} :: { Move }

-- 体の形ごとの技
Battle.ShapeMove = {
	koi = "leap",
	catfish = "whisker_whip",
	puffer = "puff_up",
	eel = "coil",
	angler = "lure",
	ray = "tail_strike",
	shark = "jaw_crush",
	orca = "breach_slam",
	salmon = "upstream_rush",
	salamander = "swallow_whole",
	whale = "spout",
	sturgeon = "armor_bash",
}

-- 属性ごとの技(覚えるレベル順)
Battle.ElementMoves = {
	water = { "water_jet", "whirlpool" },
	fire = { "foxfire", "onibi_storm" },
	thunder = { "spark", "thunderclap" },
	earth = { "mud_throw", "quake" },
	spirit = { "grudge", "night_parade" },
}

-- 覚えるレベル。技は最大4つで、5つ目を覚えたら一番古い技を忘れる
Battle.LearnLevels = {
	elementBasic = 1,
	shape = 1,
	rest = 8,
	elementStrong = 15,
	special = 25, -- 極以上のみ
	specialMinRarityOrder = 4,
}

return Battle
