--!strict
-- 数字・重さの表示
local Format = {}

local function trim(n: number): string
	local s = ("%.1f"):format(n)
	s = s:gsub("%.0$", "")
	return s
end

function Format.coins(n: number, lang: string): string
	n = math.floor(n)
	if lang == "ja" then
		if n >= 1e12 then
			return trim(n / 1e12) .. "兆"
		elseif n >= 1e8 then
			return trim(n / 1e8) .. "億"
		elseif n >= 1e4 then
			return trim(n / 1e4) .. "万"
		end
		return tostring(n)
	end
	if n >= 1e12 then
		return trim(n / 1e12) .. "T"
	elseif n >= 1e9 then
		return trim(n / 1e9) .. "B"
	elseif n >= 1e6 then
		return trim(n / 1e6) .. "M"
	elseif n >= 1e4 then
		return trim(n / 1e3) .. "K"
	end
	return tostring(n)
end

function Format.kg(grams: number): string
	local kg = grams / 1000
	if kg >= 100 then
		return ("%.1fkg"):format(kg)
	end
	return ("%.2fkg"):format(kg)
end

function Format.time(seconds: number): string
	seconds = math.max(0, math.floor(seconds))
	return ("%d:%02d"):format(seconds // 60, seconds % 60)
end

function Format.percent(p: number): string
	if p >= 0.01 then
		return trim(p * 100) .. "%"
	end
	return ("%.2f%%"):format(p * 100)
end

return Format
