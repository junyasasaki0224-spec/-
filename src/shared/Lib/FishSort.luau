--!strict
-- 魚の並び替え(魚籠・水槽・相棒の一覧で使う)。純粋な関数なのでテストできる
local Config = require(script.Parent.Parent.Config)

local FishSort = {}

-- 並び順の種類(ボタンを押すたびに次へ)
FishSort.Modes = { "price", "rarity", "weight", "new", "name" }
FishSort.PartnerModes = { "level", "rarity", "weight", "new", "name" }

export type Context = {
	price: ((any) -> number)?, -- 値段(ClientState.priceOf)
	name: ((any) -> string)?, -- 表示名(言語で変わる)
}

local function rarityOrder(f: any): number
	local def = Config.FishById[f.fishId]
	local r = def and Config.RarityById[def.rarity]
	return if r then r.order else 0
end

-- 大きい順に比べる値(名前だけは文字の順)
local function key(f: any, mode: string, ctx: Context): number
	if mode == "price" then
		return if ctx.price then ctx.price(f) else 0
	elseif mode == "rarity" then
		-- 同じレア度なら重い順
		return rarityOrder(f) * 1e9 + (f.grams or 0)
	elseif mode == "weight" then
		return f.grams or 0
	elseif mode == "new" then
		return f.at or 0
	elseif mode == "level" then
		return (f.level or 0) * 1e3 + rarityOrder(f)
	end
	return 0
end

-- entries をその場で並び替えて返す。同じ値なら uid の順(毎回同じ並びになる)
function FishSort.sort(entries: { any }, mode: string, ctx: Context?): { any }
	local c: Context = ctx or {}
	if mode == "name" then
		local nameOf = c.name or function(f: any): string
			return f.fishId
		end
		table.sort(entries, function(a, b)
			local na, nb = nameOf(a), nameOf(b)
			if na ~= nb then
				return na < nb
			end
			if (a.grams or 0) ~= (b.grams or 0) then
				return (a.grams or 0) > (b.grams or 0)
			end
			return tostring(a.uid) < tostring(b.uid)
		end)
		return entries
	end
	local cache: { [any]: number } = {}
	for _, f in entries do
		cache[f] = key(f, mode, c)
	end
	table.sort(entries, function(a, b)
		if cache[a] ~= cache[b] then
			return cache[a] > cache[b]
		end
		return tostring(a.uid) < tostring(b.uid)
	end)
	return entries
end

-- 次の並び順
function FishSort.next(modes: { string }, mode: string): string
	for i, m in modes do
		if m == mode then
			return modes[i % #modes + 1]
		end
	end
	return modes[1]
end

return FishSort
