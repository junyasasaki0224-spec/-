--!strict
-- 依頼板(毎日3つ)と、毎日のごほうび。
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Locale = require(Shared.Locale)
local Format = require(Shared.Lib.Format)

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local Root = require(script.Parent.Parent.UI.Root)
local State = require(script.Parent.Parent.ClientState)
local C = Theme.Colors

local player = Players.LocalPlayer
local Quests = {}

local panel: Kit.Panel
local list: ScrollingFrame
local dailyPanel: Kit.Panel

local function rerollProductId(): number
	for _, dp in Config.Products.DevProducts do
		if dp.key == "questReroll" then
			return dp.id
		end
	end
	return 0
end

function Quests.describe(q: any): string
	local count = q.count
	if q.kind == "catch_any" then
		return Locale.t("quest_catch_any", { count = count })
	elseif q.kind == "catch_rarity" then
		return Locale.t("quest_catch_rarity", { count = count, rarity = Locale.t("rarity_" .. q.minRarity) })
	elseif q.kind == "catch_weather" then
		return Locale.t("quest_catch_weather", { count = count, weather = Locale.t("weather_" .. q.weather) })
	elseif q.kind == "catch_time" then
		return Locale.t("quest_catch_time", { count = count, time = Locale.t("time_" .. q.time) })
	elseif q.kind == "catch_shape" then
		local shape = Locale.t("shape_" .. q.shape)
		if (q.minWeight or 0) > 0 then
			return Locale.t("quest_catch_shape", { count = count, shape = shape, kg = q.minWeight })
		end
		return Locale.t("quest_catch_shape_any", { count = count, shape = shape })
	elseif q.kind == "catch_mutation" then
		return Locale.t("quest_catch_mutation", { count = count })
	elseif q.kind == "sell_coins" then
		return Locale.t("quest_sell_coins", { count = Format.coins(count, Locale.get()) })
	end
	return q.id
end

local function rewardText(reward: any): string
	local parts = { "¥ " .. Format.coins(reward.coins or 0, Locale.get()) }
	if reward.bait then
		table.insert(parts, Locale.t("bait_" .. reward.bait.id) .. " ×" .. reward.bait.amount)
	end
	return table.concat(parts, "  +  ")
end

function Quests.render()
	if not panel.root.Visible or not State.profile then
		return
	end
	Kit.clear(list)
	local p = State.profile
	local rerollId = rerollProductId()
	for i, entry in p.quests.list do
		local q = Config.QuestById[entry.id]
		if q then
			local row = Kit.row(list, 96, i)
			Kit.label({
				Size = UDim2.new(0.62, 0, 0, 30),
				Position = UDim2.fromOffset(14, 8),
				Text = Quests.describe(q),
				TextXAlignment = Enum.TextXAlignment.Left,
				Font = Theme.Fonts.title,
				MaxTextSize = 22,
				Parent = row,
			})
			Kit.label({
				Size = UDim2.new(0.62, 0, 0, 22),
				Position = UDim2.fromOffset(14, 40),
				Text = rewardText(q.reward),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = C.goldLight,
				MaxTextSize = 17,
				Parent = row,
			})
			local bg, fill = Kit.bar(row, if entry.done then C.success else C.gold)
			bg.Size = UDim2.new(0.62, 0, 0, 12)
			bg.Position = UDim2.fromOffset(14, 70)
			fill.Size = UDim2.fromScale(math.clamp(entry.p / q.count, 0, 1), 1)
			Kit.label({
				Size = UDim2.fromOffset(120, 18),
				Position = UDim2.new(0.62, 20, 0, 66),
				Text = ("%s/%s"):format(
					Format.coins(entry.p, Locale.get()),
					Format.coins(q.count, Locale.get())
				),
				TextColor3 = C.textDim,
				MaxTextSize = 15,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = row,
			})
			local claim = Kit.button({
				Text = Locale.t(if entry.claimed then "quest_claimed" else "quest_claim"),
				Size = UDim2.fromOffset(130, 44),
				Position = UDim2.new(1, -12, 0, 10),
				AnchorPoint = Vector2.new(1, 0),
				Color = C.jade,
				MaxTextSize = 18,
				Parent = row,
			}, function()
				State.request("claimQuest", i)
			end)
			Kit.setEnabled(claim, entry.done and not entry.claimed, C.jade)
			if rerollId ~= 0 and not entry.done then
				Kit.button({
					Text = Locale.t("quest_reroll") .. " R$",
					Size = UDim2.fromOffset(130, 30),
					Position = UDim2.new(1, -12, 0, 58),
					AnchorPoint = Vector2.new(1, 0),
					Color = C.panelDark,
					MaxTextSize = 14,
					Parent = row,
				}, function()
					State.request("prepareReroll", i)
					MarketplaceService:PromptProductPurchase(player, rerollId)
				end)
			end
		end
	end
	Kit.label({
		Size = UDim2.new(1, 0, 0, 26),
		LayoutOrder = 99,
		Text = Locale.t("quest_reset"),
		TextColor3 = C.textDim,
		MaxTextSize = 16,
		Parent = list,
	})
end

local function renderDaily()
	local p = State.profile
	if not p then
		return
	end
	Kit.clear(dailyPanel.body)
	local rewards = Config.Tuning.DailyRewards
	local today = ((p.daily.streak - 1) % #rewards) + 1
	local row = Kit.new(
		"Frame",
		{ Size = UDim2.new(1, 0, 0.62, 0), BackgroundTransparency = 1, Parent = dailyPanel.body }
	)
	Kit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 8),
		Parent = row,
	})
	for i, r in rewards do
		local cell = Kit.new("Frame", {
			Size = UDim2.new(1 / #rewards, -8, 1, 0),
			BackgroundColor3 = if i == today
				then C.vermilion
				elseif i < today then C.jadeDark
				else C.panelLight,
			LayoutOrder = i,
			Parent = row,
		})
		Kit.corner(cell, Theme.CornerSmall)
		Kit.stroke(cell, C.gold, if i == today then 3 else 1, if i == today then 0 else 0.5)
		Kit.label({
			Size = UDim2.new(1, -8, 0.25, 0),
			Position = UDim2.fromOffset(4, 6),
			Text = Locale.t("daily_day", { n = i }),
			MaxTextSize = 16,
			Parent = cell,
		})
		Kit.label({
			Size = UDim2.new(1, -8, 0.3, 0),
			Position = UDim2.fromScale(0, 0.35),
			Text = "¥" .. Format.coins(r.coins, Locale.get()),
			TextColor3 = C.goldLight,
			Font = Theme.Fonts.title,
			MaxTextSize = 22,
			Parent = cell,
		})
		if r.bait then
			Kit.label({
				Size = UDim2.new(1, -8, 0.22, 0),
				Position = UDim2.fromScale(0, 0.7),
				Text = Locale.t("bait_" .. r.bait.id) .. "×" .. r.bait.amount,
				TextColor3 = C.textDim,
				MaxTextSize = 13,
				Parent = cell,
			})
		end
	end
	Kit.button({
		Text = Locale.t("daily_claim"),
		Size = UDim2.fromOffset(220, 56),
		Position = UDim2.new(0.5, 0, 1, -8),
		AnchorPoint = Vector2.new(0.5, 1),
		Color = C.jade,
		MaxTextSize = 26,
		Parent = dailyPanel.body,
	}, function()
		State.request("claimDaily")
		Root.close()
	end)
end

function Quests.init(gui: ScreenGui)
	panel = Kit.panel(gui, "Quests", UDim2.fromScale(0.7, 0.68))
	panel.close.Activated:Connect(function()
		Root.close()
	end)
	list = Kit.list(panel.body, 10)
	Root.register("quests", panel.root, function()
		panel.title.Text = Locale.t("quest_title")
		local p = State.profile
		if p and p.daily.pending then
			Root.open("daily")
			return
		end
		Quests.render()
	end)

	dailyPanel = Kit.panel(gui, "Daily", UDim2.fromScale(0.7, 0.5))
	dailyPanel.close.Activated:Connect(function()
		Root.close()
	end)
	Root.register("daily", dailyPanel.root, function()
		dailyPanel.title.Text = Locale.t("daily_title")
		renderDaily()
	end)
	State.Changed:Connect(Quests.render)
end

-- 参加時にごほうびがあれば表示
function Quests.showDailyIfPending()
	local p = State.profile
	-- 初めての人は「最初の30秒」の案内を優先する
	if p and p.daily.pending and p.tutorial >= 5 and not Root.isOpen() then
		Root.open("daily")
	end
end

return Quests
