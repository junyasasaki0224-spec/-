-- 画面の言語(プレイヤー側)。12の言語に対応する:
--   日本語・English・Español・Português・Bahasa Indonesia・Français・Deutsch・한국어・简体中文・繁體中文・ไทย・Tiếng Việt
-- 初めて遊ぶ時は、その人の Roblox の言語(ふつうは国や端末の言語)に合わせる。対応していない言語なら、
-- いる国の言語、それもなければ英語。設定で選んだ言語があれば、それを使う(保存はサーバーの持ち物の lang)。
--
-- しくみ: ゲームの文字は日本語で書いてあり、画面(PlayerGui)の文字が変わるたびに訳の表(LangData)で置き換える。
--   ・そのままの文 → 表の訳
--   ・数や名前が入る文 → 表の「{1}」入りの文(例「あと {1} 点」)に当てはめて、{1} の中身も訳してから入れる
--   ・人が入力した文字(TextBox)と、表にない文(選手の名前など)はそのまま
-- 訳の表は roblox/i18n/*.txt(言語ごとの列)から python roblox/tools/build_lang.py で作る。
local RunService = game:GetService("RunService")
local LocalizationService = game:GetService("LocalizationService")
local Players = game:GetService("Players")

local Lang = {}
Lang.LIST = {
	{ code = "ja", name = "日本語" },
	{ code = "en", name = "English" },
	{ code = "es", name = "Español" },
	{ code = "pt", name = "Português" },
	{ code = "id", name = "Bahasa Indonesia" },
	{ code = "fr", name = "Français" },
	{ code = "de", name = "Deutsch" },
	{ code = "ko", name = "한국어" },
	{ code = "zhcn", name = "简体中文" },
	{ code = "zhtw", name = "繁體中文" },
	{ code = "th", name = "ไทย" },
	{ code = "vi", name = "Tiếng Việt" },
}
local SUPPORTED = {}
for _, l in Lang.LIST do
	SUPPORTED[l.code] = true
end
Lang.code = "ja"
local changed = Instance.new("BindableEvent")
-- 言語が変わった時(画面の並びを作り直す時に使う)
Lang.Changed = changed.Event

-- Roblox の言語(ja-jp など) → この表の言語
local function fromLocale(id: string): string?
	id = string.lower(id or "")
	local head = id:match("^(%a+)") or ""
	if head == "zh" then
		if id:find("tw") or id:find("hk") or id:find("mo") or id:find("hant") then
			return "zhtw"
		end
		return "zhcn"
	end
	if SUPPORTED[head] and head ~= "zhcn" and head ~= "zhtw" then
		return head
	end
	return nil
end
-- 国(ISO の2文字) → その国でふだん使う言語
local COUNTRY = {
	JP = "ja", US = "en", GB = "en", CA = "en", AU = "en", NZ = "en", IE = "en", PH = "en", SG = "en", IN = "en",
	ES = "es", MX = "es", AR = "es", CO = "es", CL = "es", PE = "es", VE = "es", EC = "es", GT = "es", CU = "es",
	BO = "es", DO = "es", HN = "es", PY = "es", SV = "es", NI = "es", CR = "es", PA = "es", UY = "es", PR = "es",
	BR = "pt", PT = "pt", AO = "pt", MZ = "pt",
	ID = "id",
	FR = "fr", BE = "fr", LU = "fr", MC = "fr",
	DE = "de", AT = "de", CH = "de", LI = "de",
	KR = "ko",
	CN = "zhcn", TW = "zhtw", HK = "zhtw", MO = "zhtw",
	TH = "th",
	VN = "vi",
}

-- 初めの言語を決める: Roblox の言語 → いる国 → 英語
function Lang.detect(player: Player?): string
	local code = fromLocale(LocalizationService.RobloxLocaleId)
	if code then
		return code
	end
	if player then
		local ok, country = pcall(LocalizationService.GetCountryRegionForPlayerAsync, LocalizationService, player)
		if ok and type(country) == "string" and COUNTRY[string.upper(country)] then
			return COUNTRY[string.upper(country)]
		end
	end
	return "en"
end

-- 訳の表(言語ごとに、使う時に作る)
local data = require(script.Parent:WaitForChild("LangData"))
local column = {}
for i, code in data.langs do
	column[code] = i + 1
end
local exact, templates, byTemplate = {}, {}, {}
local cache, cacheSize = {}, 0
-- 訳した後の文(毎コマ訳して入れた文を、画面の見張りがもう一度訳そうとした時に、すぐ返すため)
local produced = {}
local missing = {}

-- 「{1}」入りの文を、当てはめ用の形にする
local function escape(s: string): string
	return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end
local function compile(source: string, out: string)
	local order, literal, longest = {}, 0, ""
	local pattern = "^"
	local rest = source
	while true do
		local a, b, n = rest:find("{(%d)}")
		if not a then
			pattern ..= escape(rest)
			literal += #rest
			if #rest > #longest then
				longest = rest
			end
			break
		end
		local text = rest:sub(1, a - 1)
		pattern ..= escape(text) .. "(.-)"
		literal += #text
		if #text > #longest then
			longest = text
		end
		table.insert(order, tonumber(n))
		rest = rest:sub(b + 1)
	end
	return { pattern = pattern .. "$", order = order, out = out, literal = literal, longest = longest }
end

local function build(code: string)
	table.clear(exact)
	table.clear(templates)
	table.clear(byTemplate)
	table.clear(cache)
	table.clear(produced)
	cacheSize = 0
	local col = column[code]
	if not col then
		return
	end
	for _, row in data.rows do
		local source, out = row[1], row[col]
		if type(out) ~= "string" or out == "" then
			out = row[column.en] or source
		end
		if source:find("{%d}") then
			table.insert(templates, compile(source, out))
			byTemplate[source] = out
		else
			exact[source] = out
		end
	end
	-- 決まった文字の多い(当てはまる物が少ない)形から試す
	table.sort(templates, function(a, b)
		return a.literal > b.literal
	end)
end

local translate
-- 1つの行を訳す(depth は、{1} の中身を訳す深さ)。2つ目の値は、表に当てはまったか
local function translateLine(text: string, depth: number): (string, boolean)
	local hit = exact[text]
	if hit then
		return hit, true
	end
	-- 当てはまる形のうち、{1} などに入る文字がいちばん少ない(決まった文字で多く当たる)形を使う
	-- (「横風 {1}m」が「横風 1m　波 1cm」の終わりの m に当たって、波の部分まで {1} に入れないように)
	local best, bestCaptures, bestLength = nil, nil, math.huge
	for _, t in templates do
		if t.longest == "" or string.find(text, t.longest, 1, true) then
			local captures = { string.match(text, t.pattern) }
			if #captures > 0 and #captures == #t.order then
				local length = 0
				for _, c in captures do
					length += utf8.len(c) or #c
				end
				if length < bestLength then
					best, bestCaptures, bestLength = t, captures, length
				end
			end
		end
	end
	if best then
		local args = {}
		for i, n in best.order do
			local value = bestCaptures[i]
			args[n] = depth < 2 and (translateLine(value, depth + 1)) or value
		end
		return (best.out:gsub("{(%d)}", function(n)
			return args[tonumber(n)] or ""
		end)),
			true
	end
	return text, false
end

-- ひらがな・カタカナ・漢字があるか(全角の空白や「・」だけなら訳がなくてもよい)
local function hasJapanese(text: string): boolean
	for _, c in utf8.codes(text) do
		if (c >= 0x3041 and c <= 0x30FA) or (c >= 0x4E00 and c <= 0x9FFF) then
			return true
		end
	end
	return false
end

-- 文を今の言語に訳す。表にない文はそのまま
function translate(text: string): string
	if type(text) ~= "string" or Lang.code == "ja" or text == "" or not text:find("[\128-\255]") then
		return text
	end
	local hit = cache[text]
	if hit then
		return hit
	end
	if produced[text] then
		return text
	end
	local out, matched
	if text:find("\n") then
		local lines = {}
		matched = true
		for line in (text .. "\n"):gmatch("(.-)\n") do
			local done, ok = translateLine(line, 0)
			table.insert(lines, done)
			matched = matched and (ok or line == "" or not hasJapanese(line))
		end
		out = table.concat(lines, "\n")
	else
		out, matched = translateLine(text, 0)
	end
	-- 訳した後の文を覚えておく(それ自体が元の日本語の文でない時だけ)
	if out ~= text and not exact[out] then
		produced[out] = true
	end
	-- Studio では、訳がなかった日本語を覚えておく(表に足すため。属性 MinatoLangMissing で見られる)
	if RunService:IsStudio() and not matched and not missing[text] and hasJapanese(text) then
		missing[text] = true
		local player = Players.LocalPlayer
		if player then
			local list = {}
			for k in missing do
				table.insert(list, k)
			end
			player:SetAttribute("MinatoLangMissing", table.concat(list, "\n"))
		end
	end
	if cacheSize > 3000 then
		table.clear(cache)
		table.clear(produced)
		cacheSize = 0
	end
	cache[text] = out
	cacheSize += 1
	return out
end
Lang.translate = translate

-- 「{1}」入りの日本語の文に値を入れて、今の言語で返す(値も表にあれば訳す)
function Lang.t(source: string, ...): string
	local args = { ... }
	local out = Lang.code == "ja" and source or (byTemplate[source] or exact[source] or source)
	return (out:gsub("{(%d)}", function(n)
		local v = args[tonumber(n)]
		return v == nil and "" or translate(tostring(v))
	end))
end

-- 訳した文が枠からはみ出す時は、その文字だけ枠に入る大きさまで小さくする(元の大きさより大きくはしない)。
-- 日本語より長くなる言語(ドイツ語・タイ語など)で、ボタンや札の外へ文字が出ないようにするための守り
local fitted = setmetatable({}, { __mode = "k" })
local checking = setmetatable({}, { __mode = "k" })
local function fitLater(obj)
	if
		Lang.code == "ja"
		or fitted[obj]
		or checking[obj]
		or obj.TextScaled
		or obj.TextWrapped
		or obj.TextTruncate ~= Enum.TextTruncate.None
		or obj.AutomaticSize ~= Enum.AutomaticSize.None
	then
		return
	end
	checking[obj] = true
	-- 大きさと場所が決まった後(同じコマの終わり)に確かめる
	task.defer(function()
		checking[obj] = nil
		if obj.Parent and not obj.TextScaled and obj.AbsoluteSize.X > 0 and obj.TextBounds.X > obj.AbsoluteSize.X + 1 then
			fitted[obj] = true
			local size = Instance.new("UITextSizeConstraint")
			size.MaxTextSize = obj.TextSize
			size.MinTextSize = math.min(obj.TextSize, math.max(8, math.floor(obj.TextSize * 0.6)))
			size.Parent = obj
			obj.TextScaled = true
		end
	end)
end

-- 画面の文字を見張って、変わるたびに訳す
local origin = setmetatable({}, { __mode = "k" })
local shown = setmetatable({}, { __mode = "k" })
local function apply(obj)
	local text = obj.Text
	if shown[obj] == text then
		return
	end
	origin[obj] = text
	local out = translate(text)
	if out ~= text then
		shown[obj] = out
		obj.Text = out
	else
		shown[obj] = nil
	end
	fitLater(obj)
end
local placeholders = setmetatable({}, { __mode = "k" })
local function watchObject(obj)
	if obj:IsA("TextLabel") or obj:IsA("TextButton") then
		apply(obj)
		obj:GetPropertyChangedSignal("Text"):Connect(function()
			apply(obj)
		end)
	elseif obj:IsA("TextBox") then
		-- 入力した文字は訳さない。薄い案内の文字だけ
		placeholders[obj] = obj.PlaceholderText
		obj.PlaceholderText = translate(obj.PlaceholderText)
	end
end
local watching = false
function Lang.watch(gui: Instance)
	if watching then
		return
	end
	watching = true
	for _, d in gui:GetDescendants() do
		watchObject(d)
	end
	gui.DescendantAdded:Connect(watchObject)
end

-- 言語を変える("auto" はその人の Roblox の言語・国に合わせる)。画面の文字も訳し直す
function Lang.set(code: string?)
	if code == nil or code == "" or code == "auto" or not SUPPORTED[code] then
		code = Lang.detect(Players.LocalPlayer)
	end
	if code == Lang.code and next(exact) ~= nil then
		return
	end
	Lang.code = code :: string
	build(Lang.code)
	for obj, text in origin do
		if obj.Parent then
			local out = translate(text)
			shown[obj] = out
			obj.Text = out
			fitLater(obj)
		end
	end
	for obj, text in placeholders do
		if obj.Parent then
			obj.PlaceholderText = translate(text)
		end
	end
	changed:Fire(Lang.code)
end

-- 設定の値(保存は英数字だけ)→ 表示の名前
function Lang.name(code: string): string
	for _, l in Lang.LIST do
		if l.code == code then
			return l.name
		end
	end
	return code
end
Lang.SUPPORTED = SUPPORTED

return Lang
