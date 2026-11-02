--!strict
-- 妖怪退治の相手(上から順に挑戦できる)。1行 = 1人。
--   team   : 相手の魚 { fish = 魚のid, level = レベル, mutation = 変異(省略可) }(最大3匹)
--   reward : 初めて勝った時の報酬。2回目以降は小判が Battle.RematchCoinRate 倍
--   title  : 初めて勝った時にもらえる称号(省略可。Tuning.Titles と Locale に登録すること)
-- 新しい相手はこの表に1行足すだけで追加できる。

export type Trainer = {
	id: string,
	ja: string,
	en: string,
	jaLine: string,
	enLine: string,
	team: { { fish: string, level: number, mutation: string? } },
	reward: { coins: number, bait: { id: string, amount: number }? },
	title: string?,
}

local Trainers: { Trainer } = {
	{
		id = "kappa_kid",
		ja = "河童の子",
		en = "Kappa Kid",
		jaLine = "きゅうりを賭けて勝負だ!",
		enLine = "Let's battle! Loser gives up a cucumber!",
		team = { { fish = "kappa_haze", level = 3 } },
		reward = { coins = 300, bait = { id = "worm", amount = 5 } },
	},
	{
		id = "tanuki",
		ja = "化け狸",
		en = "Trickster Tanuki",
		jaLine = "ぽんぽこ! 化かし合いなら負けないぞ",
		enLine = "Pon-poko! Nobody out-tricks a tanuki!",
		team = { { fish = "doro_funa", level = 4 }, { fish = "bake_fugu", level = 5 } },
		reward = { coins = 700, bait = { id = "dango", amount = 3 } },
	},
	{
		id = "kitsune_bride",
		ja = "狐の嫁入り",
		en = "Fox Bride",
		jaLine = "晴れているのに雨…それは私たちの行列よ",
		enLine = "Rain under a clear sky... that's our procession.",
		team = { { fish = "hasu_koi", level = 7 }, { fish = "kitsunebi_ayu", level = 8 } },
		reward = { coins = 1500, bait = { id = "dango", amount = 5 } },
	},
	{
		id = "karasu_tengu",
		ja = "烏天狗",
		en = "Crow Tengu",
		jaLine = "山の修行の成果、見せてやろう",
		enLine = "Behold the fruits of my mountain training!",
		team = { { fish = "tengu_ei", level = 10 }, { fish = "raijin_namazu", level = 11 } },
		reward = { coins = 3000, bait = { id = "glow_shrimp", amount = 2 } },
	},
	{
		id = "yukionna",
		ja = "雪女",
		en = "Yuki-Onna",
		jaLine = "凍えるほど美しい戦いを…",
		enLine = "A battle so beautiful it freezes the heart...",
		team = {
			{ fish = "kiri_shirauo", level = 13 },
			{ fish = "nure_unagi", level = 13 },
			{ fish = "yukionna_ei", level = 14 },
		},
		reward = { coins = 6000, bait = { id = "glow_shrimp", amount = 3 } },
	},
	{
		id = "aka_oni",
		ja = "赤鬼",
		en = "Red Oni",
		jaLine = "がっはっは! 金棒の代わりに魚で勝負だ!",
		enLine = "Gahaha! Fish instead of clubs today!",
		team = { { fish = "chochin_anko", level = 17 }, { fish = "oni_unagi", level = 18 } },
		reward = { coins = 11000, bait = { id = "glow_shrimp", amount = 4 } },
		title = "oni_slayer",
	},
	{
		id = "nekomata",
		ja = "猫又",
		en = "Nekomata",
		jaLine = "にゃあ…二本の尾は伊達じゃないにゃ",
		enLine = "Meow... Two tails aren't just for show.",
		team = {
			{ fish = "hitotsume_namazu", level = 20 },
			{ fish = "rokurokubi_unagi", level = 21 },
			{ fish = "nekomata_koi", level = 22 },
		},
		reward = { coins = 18000, bait = { id = "aburaage", amount = 2 } },
	},
	{
		id = "nue",
		ja = "鵺",
		en = "Nue",
		jaLine = "ヒョー…ヒョー…",
		enLine = "Hyoo... hyoo...",
		team = {
			{ fish = "tsuchinoko_fugu", level = 25 },
			{ fish = "nue_namazu", level = 27, mutation = "gold" },
		},
		reward = { coins = 30000, bait = { id = "aburaage", amount = 3 } },
	},
	{
		id = "kyubi",
		ja = "九尾の狐",
		en = "Nine-Tailed Fox",
		jaLine = "千年の妖力、受けてみよ",
		enLine = "Face a thousand years of yoki!",
		team = {
			{ fish = "karakasa_fugu", level = 30 },
			{ fish = "kodama_koi", level = 31 },
			{ fish = "kyubi_koi", level = 33 },
		},
		reward = { coins = 60000, bait = { id = "premium", amount = 3 } },
	},
	{
		id = "swamp_lord",
		ja = "沼のぬし",
		en = "Lord of the Swamp",
		jaLine = "……よくぞここまで来た。沼の底の力、見せてやろう",
		enLine = "...You've come far. Witness the power of the depths.",
		team = {
			{ fish = "umibozu_ei", level = 36 },
			{ fish = "nue_namazu", level = 37 },
			{ fish = "numa_mizuchi", level = 40, mutation = "onibi" },
		},
		reward = { coins = 150000, bait = { id = "premium", amount = 10 } },
		title = "yokai_master",
	},
}

return Trainers
