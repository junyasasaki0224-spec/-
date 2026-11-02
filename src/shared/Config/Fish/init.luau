--!strict
-- 全釣り場の魚の表をまとめる。釣り場を追加したら SOURCES に1行足す。
-- 並び順(図鑑の順番)は「釣り場の順 → 表の行の順」。
local Types = require(script.Parent.Parent.Lib.Types)

local SOURCES: { { spot: string, list: { any } } } = {
	{ spot = "swamp", list = require(script.Swamp) :: any },
	-- { spot = "river", list = require(script.River) :: any },
}

local all: { Types.FishDef } = {}
for _, src in SOURCES do
	for index, row in src.list do
		local def = table.clone(row)
		def.spot = src.spot
		def.index = index
		def.deco = def.deco or {}
		def.size = def.size or 1
		table.insert(all, def :: any)
	end
end

return all
