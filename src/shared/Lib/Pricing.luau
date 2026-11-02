--!strict
-- 売値の計算: 基本の売値 × 重さの倍率(0.5〜2倍) × 変異の倍率 × 釣り場の倍率 (× VIP)
local Types = require(script.Parent.Types)

local Pricing = {}

-- 重さが範囲のどこにあるか (0..1)
function Pricing.weightT(fish: Types.FishDef, grams: number): number
	local lo, hi = fish.kg[1] * 1000, fish.kg[2] * 1000
	if hi <= lo then
		return 0.5
	end
	return math.clamp((grams - lo) / (hi - lo), 0, 1)
end

export type PriceContext = {
	rarityBasePrice: number,
	mutationMultiplier: number,
	spotMultiplier: number,
	sellMultiplier: number, -- VIP など
	weightMin: number,
	weightMax: number,
}

function Pricing.sellPrice(fish: Types.FishDef, grams: number, ctx: PriceContext): number
	local base = fish.price or ctx.rarityBasePrice
	local t = Pricing.weightT(fish, grams)
	local wMult = ctx.weightMin + (ctx.weightMax - ctx.weightMin) * t
	local price = base * wMult * ctx.mutationMultiplier * ctx.spotMultiplier * ctx.sellMultiplier
	return math.max(1, math.floor(price + 0.5))
end

return Pricing
