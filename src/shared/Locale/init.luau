--!strict
-- 多言語(日本語・英語)。言語は Roblox のアカウント設定(LocaleId)から自動で決め、設定画面で切替可能。
local Locale = {}

local tables: { [string]: { [string]: string } } = {
	ja = require(script.ja) :: any,
	en = require(script.en) :: any,
}

local current = "en"

function Locale.detect(localeId: string?): string
	if localeId and localeId:lower():sub(1, 2) == "ja" then
		return "ja"
	end
	return "en"
end

function Locale.set(lang: string)
	if tables[lang] then
		current = lang
	end
end

function Locale.get(): string
	return current
end

function Locale.has(key: string): boolean
	return tables[current][key] ~= nil or tables.en[key] ~= nil
end

function Locale.t(key: string, args: { [string]: any }?, lang: string?): string
	local tbl = tables[lang or current] or tables.en
	local s = tbl[key] or tables.en[key] or key
	if args then
		s = s:gsub("{(%w+)}", function(k)
			local v = args[k]
			return if v ~= nil then tostring(v) else "{" .. k .. "}"
		end)
	end
	return s
end

-- 魚の名前・説明
function Locale.fishName(def: any, lang: string?): string
	return if (lang or current) == "ja" then def.ja else def.en
end

function Locale.fishDesc(def: any, lang: string?): string
	return if (lang or current) == "ja" then def.jaDesc else def.enDesc
end

-- 全キーが両言語にあるかをチェック(テスト用)
function Locale.missingKeys(): { string }
	local missing = {}
	for lang, tbl in tables do
		for other, otherTbl in tables do
			if other ~= lang then
				for k in otherTbl do
					if tbl[k] == nil then
						table.insert(missing, lang .. ":" .. k)
					end
				end
			end
		end
	end
	return missing
end

return Locale
