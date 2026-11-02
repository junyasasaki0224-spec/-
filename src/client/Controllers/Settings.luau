--!strict
-- 設定: 言語・自動売却(ゲームパス)・称号・効果音
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Locale = require(Shared.Locale)

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local Root = require(script.Parent.Parent.UI.Root)
local State = require(script.Parent.Parent.ClientState)
local Sound = require(script.Parent.Sound)
local C = Theme.Colors

local Settings = {}
local panel: Kit.Panel
local list: ScrollingFrame
local onLanguageChanged: (() -> ())? = nil

local function row(order: number, text: string, buttonText: string, enabled: boolean, onClick: () -> ())
	local r = Kit.row(list, 64, order)
	Kit.label({
		Size = UDim2.new(0.6, 0, 1, -16),
		Position = UDim2.fromOffset(16, 8),
		Text = text,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 20,
		Parent = r,
	})
	local b = Kit.button({
		Text = buttonText,
		Size = UDim2.fromOffset(170, 44),
		Position = UDim2.new(1, -10, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Color = C.indigo,
		MaxTextSize = 18,
		Parent = r,
	}, onClick)
	Kit.setEnabled(b, enabled, C.indigo)
end

function Settings.render()
	if not panel.root.Visible or not State.profile then
		return
	end
	local p = State.profile
	Kit.clear(list)
	panel.title.Text = Locale.t("settings_title")
	row(
		1,
		Locale.t("settings_language"),
		if Locale.get() == "ja" then "English" else "日本語",
		true,
		function()
			local nextLang = if Locale.get() == "ja" then "en" else "ja"
			Locale.set(nextLang)
			State.request("setLang", nextLang)
			if onLanguageChanged then
				onLanguageChanged()
			end
			Settings.render()
		end
	)
	local autoSellText = if p.settings.autoSell > 0
		then Locale.t(
			"settings_autosell",
			{ rarity = Locale.t("rarity_" .. Config.Rarities[p.settings.autoSell].id) }
		)
		else Locale.t("settings_autosell_off")
	row(2, autoSellText, "▶", State.hasPass("autoSell"), function()
		State.request("setAutoSell", (p.settings.autoSell + 1) % (#Config.Rarities - 1))
	end)
	local titles = { "" }
	for _, t in p.titles do
		table.insert(titles, t)
	end
	local idx = table.find(titles, p.activeTitle) or 1
	row(
		3,
		if p.activeTitle ~= "" then "「" .. Locale.t("title_" .. p.activeTitle) .. "」" else "—",
		"▶",
		#titles > 1,
		function()
			State.request("setTitle", titles[idx % #titles + 1])
		end
	)
	row(
		4,
		if Sound.isMuted() then "🔇" else "🔊",
		if Sound.isMuted() then "ON" else "OFF",
		true,
		function()
			Sound.setMuted(not Sound.isMuted())
			Settings.render()
		end
	)
end

function Settings.init(gui: ScreenGui, languageChanged: () -> ())
	onLanguageChanged = languageChanged
	panel = Kit.panel(gui, "Settings", UDim2.fromScale(0.55, 0.6))
	panel.close.Activated:Connect(function()
		Root.close()
	end)
	list = Kit.list(panel.body, 10)
	Root.register("settings", panel.root, Settings.render)
	State.Changed:Connect(Settings.render)
end

return Settings
