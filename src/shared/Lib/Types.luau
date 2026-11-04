--!strict
-- 共通の型定義

export type FishDef = {
	id: string,
	ja: string, -- 名前(カタカナのあだ名)
	en: string,
	kindJa: string?, -- 種類(もとになった魚と妖怪。図鑑と釣果の画面に小さく出る)
	kindEn: string?,
	spot: string,
	index: number,
	rarity: string,
	element: string,
	time: string,
	weather: string,
	kg: { number },
	price: number?,
	shape: string,
	c1: string,
	c2: string,
	c3: string?, -- 差し色(省略可)
	body: { number }?, -- 体つき { 幅, 高さ, 長さ } の倍率(省略で {1,1,1})
	eyes: string?, -- 目の描き方(省略で形ごとの標準)
	mouth: string?, -- 口の描き方(省略で形ごとの標準)
	tails: number?, -- 尾の本数(猫又は2、九尾は9 など)
	pattern: string,
	deco: { string },
	size: number,
	jaDesc: string,
	enDesc: string,
}

-- 1匹の釣果(魚籠・水槽に入る)
export type CaughtFish = {
	uid: string,
	fishId: string,
	grams: number, -- 重さはグラムの整数で保存(小数の誤差を避ける)
	mutation: string?,
	spot: string,
	at: number,
	locked: boolean?, -- お気に入り(売れない・食べさせられない)
}

-- 相棒(魚籠の魚 + レベルと経験値)
export type Partner = CaughtFish & {
	level: number,
	xp: number,
}

export type Conditions = {
	spot: string,
	time: string, -- "morning" | "day" | "night"
	weather: string,
}

return {}
