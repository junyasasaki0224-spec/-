--!strict
-- 共通の型定義

export type FishDef = {
	id: string,
	ja: string,
	en: string,
	spot: string,
	index: number,
	rarity: string,
	time: string,
	weather: string,
	kg: { number },
	price: number?,
	shape: string,
	c1: string,
	c2: string,
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
}

export type Conditions = {
	spot: string,
	time: string, -- "morning" | "day" | "night"
	weather: string,
}

return {}
