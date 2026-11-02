--!strict
-- 常に表示する情報(小判・魚籠・エサ・時刻と天気・ぬし・運)とメニューボタン。
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Locale = require(Shared.Locale)
local Format = require(Shared.Lib.Format)
local WorldClock = require(Shared.Lib.WorldClock)

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local Root = require(script.Parent.Parent.UI.Root)
local State = require(script.Parent.Parent.ClientState)
local C = Theme.Colors

local player = Players.LocalPlayer
local HUD = {}

local coinLabel: TextLabel
local creelLabel: TextLabel
local baitLabel: TextLabel
local clockLabel: TextLabel
local nushiLabel: TextLabel
local luckLabel: TextLabel
local questDot: Frame
local autoButton: TextButton
local buttons: { [string]: TextButton } = {}
local lastCoins = -1

local function pill(parent: Instance, pos: UDim2, width: number, icon: string, iconColor: Color3): TextLabel
	local f = Kit.new("Frame", {
		Size = UDim2.fromOffset(width, 44),
		Position = pos,
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.1,
		Parent = parent,
	})
	Kit.corner(f, UDim.new(1, 0))
	Kit.stroke(f, C.gold, 2)
	local ic = Kit.label({
		Size = UDim2.fromOffset(36, 36),
		Position = UDim2.fromOffset(4, 4),
		BackgroundTransparency = 0,
		BackgroundColor3 = iconColor,
		Text = icon,
		MaxTextSize = 22,
		Parent = f,
	})
	Kit.corner(ic, UDim.new(1, 0))
	return Kit.label({
		Size = UDim2.new(1, -52, 1, -12),
		Position = UDim2.fromOffset(46, 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 24,
		Font = Theme.Fonts.title,
		Parent = f,
	})
end

local function menuButton(
	parent: Instance,
	order: number,
	icon: string,
	labelKey: string,
	color: Color3,
	onClick: () -> ()
): TextButton
	local b = Kit.button({
		Name = labelKey,
		Size = UDim2.fromOffset(72, 72),
		Color = color,
		Text = "",
		LayoutOrder = order,
		Corner = UDim.new(0, 18),
		Parent = parent,
	}, onClick)
	Kit.label({ Size = UDim2.new(1, 0, 0.6, 0), Text = icon, MaxTextSize = 34, Parent = b })
	local l = Kit.label({
		Name = "Caption",
		Size = UDim2.new(1, 0, 0.36, 0),
		Position = UDim2.fromScale(0, 0.64),
		Text = Locale.t(labelKey),
		MaxTextSize = 14,
		Parent = b,
	})
	l:SetAttribute("LocKey", labelKey)
	buttons[labelKey] = b
	return b
end

function HUD.relabel()
	for key, b in buttons do
		local cap = b:FindFirstChild("Caption") :: TextLabel?
		if cap then
			cap.Text = Locale.t(key)
		end
	end
	HUD.refresh()
end

function HUD.refresh()
	local p = State.profile
	if not p then
		return
	end
	local lang = Locale.get()
	if p.coins ~= lastCoins then
		if lastCoins >= 0 and p.coins > lastCoins then
			local s = coinLabel.Parent and coinLabel.Parent:FindFirstChildOfClass("UIScale")
				or Kit.new("UIScale", { Parent = coinLabel.Parent })
			s.Scale = 1.15
			TweenService:Create(s, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
		lastCoins = p.coins
	end
	coinLabel.Text = Format.coins(p.coins, lang)
	creelLabel.Text = ("%d/%d"):format(#p.creel, State.creelCapacity())
	creelLabel.TextColor3 = if #p.creel >= State.creelCapacity() then C.danger else C.text
	if p.equippedBait ~= "" then
		baitLabel.Text = ("%s ×%d"):format(Locale.t("bait_" .. p.equippedBait), p.bait[p.equippedBait] or 0)
	else
		baitLabel.Text = Locale.t("bait_none")
	end
	local done = false
	for _, q in p.quests.list do
		if q.done and not q.claimed then
			done = true
		end
	end
	questDot.Visible = done or p.daily.pending
	autoButton.Visible = State.hasPass("autoFish")
	local autoCaption = autoButton:FindFirstChild("Caption") :: TextLabel?
	if autoCaption then
		autoCaption.Text =
			Locale.t(if player:GetAttribute("AutoFishing") then "hud_auto_on" else "hud_auto_off")
	end
	autoButton.BackgroundColor3 = if player:GetAttribute("AutoFishing") then C.jade else C.panelLight
end

function HUD.init(gui: ScreenGui)
	local top = Kit.new(
		"Frame",
		{ Name = "HUD", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = gui }
	)
	coinLabel = pill(top, UDim2.fromOffset(20, 70), 200, "¥", C.gold)
	creelLabel = pill(top, UDim2.fromOffset(20, 120), 150, "🐟", C.indigo)
	baitLabel = pill(top, UDim2.fromOffset(20, 170), 200, "🍡", C.jadeDark)
	local baitBtn = Kit.new(
		"TextButton",
		{ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", Parent = baitLabel.Parent }
	)
	baitBtn.Activated:Connect(function()
		Root.open("shop", "bait")
	end)
	local creelBtn = Kit.new(
		"TextButton",
		{ Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "", Parent = creelLabel.Parent }
	)
	creelBtn.Activated:Connect(function()
		Root.open("shop", "sell")
	end)

	-- 時刻・天気・ぬし
	local clockFrame = Kit.new("Frame", {
		Size = UDim2.fromOffset(300, 40),
		Position = UDim2.new(0.5, 0, 0, 64),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.15,
		Parent = top,
	})
	Kit.corner(clockFrame, UDim.new(1, 0))
	Kit.stroke(clockFrame, C.gold, 2)
	clockLabel = Kit.label({
		Size = UDim2.new(1, -20, 1, -10),
		Position = UDim2.fromOffset(10, 5),
		MaxTextSize = 20,
		Parent = clockFrame,
	})
	nushiLabel = Kit.label({
		Size = UDim2.fromOffset(300, 24),
		Position = UDim2.new(0.5, 0, 0, 108),
		AnchorPoint = Vector2.new(0.5, 0),
		MaxTextSize = 18,
		TextColor3 = C.textDim,
		Parent = top,
	})
	Kit.new(
		"UIStroke",
		{ Color = Color3.new(0, 0, 0), Thickness = 1.5, Transparency = 0.3, Parent = nushiLabel }
	)
	luckLabel = Kit.label({
		Size = UDim2.fromOffset(140, 26),
		Position = UDim2.fromOffset(20, 218),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.success,
		MaxTextSize = 20,
		Parent = top,
	})
	Kit.new(
		"UIStroke",
		{ Color = Color3.new(0, 0, 0), Thickness = 1.5, Transparency = 0.3, Parent = luckLabel }
	)

	-- メニュー(右側の縦並び)
	local menu = Kit.new("Frame", {
		Size = UDim2.fromOffset(72, 480),
		Position = UDim2.new(1, -20, 0, 70),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Parent = top,
	})
	Kit.new(
		"UIListLayout",
		{ Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = menu }
	)
	menuButton(menu, 1, "📖", "hud_codex", C.indigo, function()
		Root.toggle("codex")
	end)
	menuButton(menu, 2, "🏮", "hud_shop", C.vermilion, function()
		Root.toggle("shop", "rods")
	end)
	local qb = menuButton(menu, 3, "📜", "hud_quests", C.jadeDark, function()
		Root.toggle("quests")
	end)
	questDot = Kit.new("Frame", {
		Size = UDim2.fromOffset(16, 16),
		Position = UDim2.new(1, -4, 0, 4),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = C.danger,
		Visible = false,
		ZIndex = 5,
		Parent = qb,
	})
	Kit.corner(questDot, UDim.new(1, 0))
	menuButton(menu, 4, "🧺", "hud_bag", C.panelLight, function()
		Root.toggle("shop", "sell")
	end)
	autoButton = menuButton(menu, 5, "⚙", "hud_auto_off", C.panelLight, function()
		State.request("setAuto", player:GetAttribute("AutoFishing") ~= true)
	end)
	menuButton(menu, 6, "☰", "hud_settings", C.panelDark, function()
		Root.toggle("settings")
	end)

	State.Changed:Connect(HUD.refresh)
	player:GetAttributeChangedSignal("AutoFishing"):Connect(HUD.refresh)

	local W = Config.Tuning.World
	local NT = Config.Tuning.Nushi
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.25 then
			return
		end
		acc = 0
		local now = workspace:GetServerTimeNow()
		local clock = WorldClock.clockTime(now, W)
		local phase = WorldClock.phase(clock, W)
		local weather = WorldClock.weatherAt(now, W)
		local icon = if phase == "night" then "🌙" elseif phase == "morning" then "🌅" else "☀"
		local wIcon = if weather == "rain"
			then "☔"
			elseif weather == "fog" then "🌫"
			elseif weather == "thunder" then "⚡"
			else ""
		clockLabel.Text = ("%s %s  %s %s  %02d:%02d"):format(
			icon,
			Locale.t("time_" .. phase),
			wIcon,
			Locale.t("weather_" .. weather),
			math.floor(clock),
			math.floor((clock % 1) * 60)
		)
		local active, remain = WorldClock.nushi(now, NT)
		if active then
			nushiLabel.Text = Locale.t("hud_nushi_now", { t = Format.time(remain) })
			nushiLabel.TextColor3 = C.goldLight
		else
			nushiLabel.Text = Locale.t("hud_nushi_in", { t = Format.time(remain) })
			nushiLabel.TextColor3 = C.textDim
		end
		local luck = State.luck()
		luckLabel.Text = Locale.t("hud_luck", { x = ("%.1f"):format(luck) })
		luckLabel.Visible = luck > 1.001
	end)
	HUD.refresh()
end

return HUD
