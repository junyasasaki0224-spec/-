--!strict
-- お店パネル: 魚籠(売る) / 水槽 / 竿屋 / エサ屋 / 釣り場 / 特別な品(Robux)
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local CollectionService = game:GetService("CollectionService")

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
local Shop = {}

local TABS = { "sell", "tank", "rods", "bait", "spots", "robux" }
local TAB_KEYS = {
	sell = "shop_tab_sell",
	tank = "shop_tab_tank",
	rods = "shop_tab_rods",
	bait = "shop_tab_bait",
	spots = "shop_tab_spots",
	robux = "shop_tab_robux",
}

local panel: Kit.Panel
local tabBar: Frame
local content: Frame
local currentTab = "rods"
local tabButtons: { [string]: TextButton } = {}
local sellAllOrder = 2

local function coins(n: number): string
	return Format.coins(n, Locale.get())
end

local function nearMerchant(): boolean
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	for _, m in CollectionService:GetTagged("Merchant") do
		if m:IsA("BasePart") and (m.Position - root.Position).Magnitude <= 22 then
			return true
		end
	end
	return false
end

-- 1行の中の要素(左: 色帯+文字, 右: ボタン群)
local function itemRow(
	list: Instance,
	order: number,
	color: Color3,
	title: string,
	sub: string
): (Frame, Frame)
	local row = Kit.row(list, 64, order)
	local strip = Kit.new("Frame", {
		Size = UDim2.new(0, 8, 1, -12),
		Position = UDim2.fromOffset(6, 6),
		BackgroundColor3 = color,
		Parent = row,
	})
	Kit.corner(strip, UDim.new(1, 0))
	Kit.label({
		Size = UDim2.new(0.55, -24, 0, 30),
		Position = UDim2.fromOffset(22, 4),
		Text = title,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 22,
		Font = Theme.Fonts.title,
		Parent = row,
	})
	Kit.label({
		Size = UDim2.new(0.55, -24, 0, 22),
		Position = UDim2.fromOffset(22, 36),
		Text = sub,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.textDim,
		MaxTextSize = 16,
		Font = Theme.Fonts.body,
		Parent = row,
	})
	local right = Kit.new("Frame", {
		Size = UDim2.new(0.45, -8, 1, -12),
		Position = UDim2.new(1, -8, 0, 6),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		Parent = row,
	})
	Kit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		Parent = right,
	})
	return row, right
end

local function smallButton(
	parent: Instance,
	text: string,
	color: Color3,
	enabled: boolean,
	onClick: () -> ()
): TextButton
	local b = Kit.button(
		{ Text = text, Size = UDim2.fromOffset(96, 42), Color = color, MaxTextSize = 18, Parent = parent },
		onClick
	)
	Kit.setEnabled(b, enabled, color)
	return b
end

local function fishRows(list: Instance, entries: { any }, mode: string)
	local p = State.profile
	local near = nearMerchant()
	table.sort(entries, function(a, b)
		return State.priceOf(a) > State.priceOf(b)
	end)
	for i, f in entries do
		local def = Config.FishById[f.fishId]
		if def then
			local rarity = Config.RarityById[def.rarity]
			local title = Locale.fishName(def)
				.. (if f.mutation then " ✦" .. Locale.t("mutation_" .. f.mutation) else "")
			local sub = ("%s · %s · %s %s"):format(
				Locale.t("rarity_" .. def.rarity),
				Format.kg(f.grams),
				coins(State.priceOf(f)),
				Locale.t("coins")
			)
			local _, right = itemRow(list, i, Color3.fromHex(rarity.color), title, sub)
			if mode == "sell" then
				smallButton(right, Locale.t("shop_sell"), C.vermilion, near, function()
					State.request("sell", f.uid)
				end)
				smallButton(
					right,
					Locale.t("shop_to_tank"),
					C.indigo,
					#p.tank < State.tankCapacity(),
					function()
						State.request("toTank", f.uid)
					end
				)
			else
				smallButton(right, Locale.t("tank_remove"), C.indigo, true, function()
					State.request("fromTank", f.uid)
				end)
			end
		end
	end
end

local renderers: { [string]: (Frame) -> () } = {}

renderers.sell = function(body)
	local p = State.profile
	local header =
		Kit.new("Frame", { Size = UDim2.new(1, 0, 0, 50), BackgroundTransparency = 1, Parent = body })
	local near = nearMerchant()
	Kit.label({
		Size = UDim2.new(0.45, 0, 1, -8),
		Position = UDim2.fromOffset(4, 4),
		Text = if near
			then Locale.t("hud_creel", { n = #p.creel, max = State.creelCapacity() })
			else Locale.t("shop_need_merchant"),
		TextColor3 = if near then C.text else C.goldLight,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 20,
		Parent = header,
	})
	local cycle = Kit.button({
		Text = Locale.t("rarity_" .. Config.Rarities[sellAllOrder].id) .. " ▾",
		Size = UDim2.fromOffset(110, 42),
		Position = UDim2.new(1, -254, 0, 4),
		Color = C.panelDark,
		MaxTextSize = 18,
		Parent = header,
	}, function()
		sellAllOrder = sellAllOrder % (#Config.Rarities - 1) + 1
		Shop.render()
	end)
	cycle.TextColor3 = Color3.fromHex(Config.Rarities[sellAllOrder].color)
	local sellAll = Kit.button({
		Text = Locale.t(
			"shop_sell_all",
			{ rarity = Locale.t("rarity_" .. Config.Rarities[sellAllOrder].id) }
		),
		Size = UDim2.fromOffset(240, 42),
		Position = UDim2.new(1, -4, 0, 4),
		AnchorPoint = Vector2.new(1, 0),
		Color = C.vermilion,
		MaxTextSize = 18,
		Parent = header,
	}, function()
		State.request("sellAll", sellAllOrder)
	end)
	sellAll.Size = UDim2.fromOffset(136, 42)
	Kit.setEnabled(sellAll, near and #p.creel > 0)
	local listHolder = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 1, -56),
		Position = UDim2.fromOffset(0, 56),
		BackgroundTransparency = 1,
		Parent = body,
	})
	local list = Kit.list(listHolder)
	if #p.creel == 0 then
		Kit.label({
			Size = UDim2.new(1, 0, 0, 60),
			Text = Locale.t("shop_empty_creel"),
			TextColor3 = C.textDim,
			Parent = list,
		})
	end
	fishRows(list, table.clone(p.creel), "sell")
end

renderers.tank = function(body)
	local p = State.profile
	Kit.label({
		Size = UDim2.new(1, 0, 0, 36),
		Text = ("%s  %d/%d"):format(Locale.t("tank_title"), #p.tank, State.tankCapacity()),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 20,
		Parent = body,
	})
	local listHolder = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 1, -42),
		Position = UDim2.fromOffset(0, 42),
		BackgroundTransparency = 1,
		Parent = body,
	})
	local list = Kit.list(listHolder)
	if #p.tank == 0 then
		Kit.label({
			Size = UDim2.new(1, 0, 0, 60),
			Text = Locale.t("tank_empty"),
			TextColor3 = C.textDim,
			Parent = list,
		})
	end
	fishRows(list, table.clone(p.tank), "tank")
end

renderers.rods = function(body)
	local p = State.profile
	local list = Kit.list(body)
	for _, rod in Config.Rods do
		local sub = Locale.t("shop_rod_stats", {
			luck = math.floor(rod.luck * 100 + 0.5),
			reel = math.floor((rod.reelSpeed - 1) * 100 + 0.5),
			net = math.floor((rod.netSize - 1) * 100 + 0.5),
		})
		local title = Locale.t("rod_name", { tier = rod.tier })
		local _, right = itemRow(list, rod.tier, Color3.fromHex(rod.accent), title, sub)
		if rod.tier <= p.rodTier then
			smallButton(
				right,
				Locale.t(if rod.tier == p.rodTier then "shop_equipped" else "shop_owned"),
				C.jadeDark,
				false,
				function() end
			)
		elseif rod.tier == p.rodTier + 1 then
			local b = smallButton(right, coins(rod.price), C.vermilion, p.coins >= rod.price, function()
				State.request("buyRod", rod.tier)
			end)
			b.Size = UDim2.fromOffset(140, 42)
		else
			smallButton(right, coins(rod.price), C.disabled, false, function() end)
		end
	end
end

renderers.bait = function(body)
	local p = State.profile
	local list = Kit.list(body)
	local noneRow, noneRight = itemRow(list, 0, C.textDim, Locale.t("bait_none"), "")
	local _ = noneRow
	smallButton(
		noneRight,
		Locale.t(if p.equippedBait == "" then "shop_equipped" else "shop_equip"),
		C.jadeDark,
		p.equippedBait ~= "",
		function()
			State.request("equipBait", "")
		end
	)
	for _, bait in Config.Baits do
		local have = p.bait[bait.id] or 0
		local sub = Locale.t("shop_bait_stats", {
			bite = "-" .. math.floor((1 - bait.biteTime) * 100 + 0.5),
			luck = math.floor(bait.luck * 100 + 0.5),
		}) .. "  ·  " .. Locale.t("shop_bait_count", { n = have })
		local _, right =
			itemRow(list, bait.order, Color3.fromHex(bait.color), Locale.t("bait_" .. bait.id), sub)
		if have > 0 then
			smallButton(
				right,
				Locale.t(if p.equippedBait == bait.id then "shop_equipped" else "shop_equip"),
				C.jadeDark,
				p.equippedBait ~= bait.id,
				function()
					State.request("equipBait", bait.id)
				end
			)
		end
		if bait.price > 0 then
			smallButton(right, coins(bait.price), C.vermilion, p.coins >= bait.price, function()
				State.request("buyBait", { id = bait.id, amount = 1 })
			end)
			smallButton(
				right,
				"×10 " .. coins(bait.price * 10),
				C.vermilion,
				p.coins >= bait.price * 10,
				function()
					State.request("buyBait", { id = bait.id, amount = 10 })
				end
			)
		end
	end
end

renderers.spots = function(body)
	local p = State.profile
	local list = Kit.list(body)
	local spots = table.clone(Config.Spots)
	table.sort(spots, function(a, b)
		return a.order < b.order
	end)
	for _, spot in spots do
		local sub = ("×%s"):format(tostring(spot.priceMultiplier))
		if not spot.available then
			sub ..= "  ·  " .. Locale.t("shop_coming_soon")
		elseif not p.spots[spot.id] then
			sub ..= "  ·  " .. Locale.t("shop_need_rod", { tier = spot.unlockRodTier })
		end
		local _, right = itemRow(
			list,
			spot.order,
			if spot.available then C.jade else C.disabled,
			Locale.t("spot_" .. spot.id),
			sub
		)
		if not spot.available then
			smallButton(right, Locale.t("shop_coming_soon"), C.disabled, false, function() end)
		elseif p.spots[spot.id] then
			smallButton(right, Locale.t("shop_travel"), C.jade, true, function()
				State.request("travel", spot.id)
				Root.close()
			end)
		else
			local ok = p.coins >= spot.unlockCoins and p.rodTier >= spot.unlockRodTier
			local b = smallButton(right, coins(spot.unlockCoins), C.vermilion, ok, function()
				State.request("unlockSpot", spot.id)
			end)
			b.Size = UDim2.fromOffset(140, 42)
		end
	end
end

renderers.robux = function(body)
	local list = Kit.list(body)
	local any = false
	local order = 0
	for _, gp in Config.Products.GamePasses do
		if gp.id ~= 0 then
			any = true
			order += 1
			local owned = State.hasPass(gp.key)
			local _, right = itemRow(
				list,
				order,
				C.gold,
				Locale.t("pass_" .. gp.key),
				Locale.t("pass_" .. gp.key .. "_desc")
			)
			smallButton(
				right,
				if owned then Locale.t("product_owned") else ("R$ %d"):format(gp.robux),
				C.jade,
				not owned,
				function()
					MarketplaceService:PromptGamePassPurchase(player, gp.id)
				end
			)
		end
	end
	for _, dp in Config.Products.DevProducts do
		if dp.id ~= 0 and dp.key ~= "questReroll" then
			any = true
			order += 1
			local _, right = itemRow(
				list,
				order,
				C.vermilion,
				Locale.t("product_" .. dp.key),
				Locale.t("product_" .. dp.key .. "_desc")
			)
			smallButton(right, ("R$ %d"):format(dp.robux), C.jade, true, function()
				MarketplaceService:PromptProductPurchase(player, dp.id)
			end)
		end
	end
	local ad = Config.Products.RewardedAd
	if ad.enabled and ad.devProductId ~= 0 then
		any = true
		local _, right = itemRow(list, 999, C.indigo, Locale.t("ad_luck"), "")
		smallButton(right, "▶", C.indigo, true, function()
			State.request("watchAd", true)
		end)
	end
	if not any then
		Kit.label({
			Size = UDim2.new(1, 0, 0, 60),
			Text = Locale.t("robux_none"),
			TextColor3 = C.textDim,
			Parent = list,
		})
	end
end

function Shop.render()
	if not panel or not panel.root.Visible or not State.profile then
		return
	end
	for name, b in tabButtons do
		b.BackgroundColor3 = if name == currentTab then C.vermilion else C.panelDark
		b.Text = Locale.t(TAB_KEYS[name])
	end
	Kit.clear(content)
	local body =
		Kit.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = content })
	renderers[currentTab](body)
end

function Shop.init(gui: ScreenGui)
	panel = Kit.panel(gui, "Shop", UDim2.fromScale(0.82, 0.8))
	panel.title.Text = Locale.t("shop_title")
	panel.close.Activated:Connect(function()
		Root.close()
	end)
	tabBar =
		Kit.new("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, Parent = panel.body })
	Kit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = tabBar,
	})
	for i, name in TABS do
		tabButtons[name] = Kit.button({
			Text = "",
			Size = UDim2.new(1 / #TABS, -6, 1, 0),
			Color = C.panelDark,
			MaxTextSize = 18,
			LayoutOrder = i,
			Parent = tabBar,
		}, function()
			currentTab = name
			Shop.render()
		end)
	end
	content = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 1, -54),
		Position = UDim2.fromOffset(0, 54),
		BackgroundTransparency = 1,
		Parent = panel.body,
	})
	Root.register("shop", panel.root, function(tab)
		if type(tab) == "string" and renderers[tab] then
			currentTab = tab
		end
		panel.title.Text = Locale.t("shop_title")
		Shop.render()
	end)
	State.Changed:Connect(Shop.render)
	player:GetAttributeChangedSignal("Passes"):Connect(Shop.render)
end

return Shop
