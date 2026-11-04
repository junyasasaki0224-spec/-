--!strict
-- 百鬼の祠(ガチャ)の画面と、授かる時の演出。何が出るかはサーバーが決め、ここは見せるだけ。
--  * 祠の画面: いちばん上の限定の魚(★5)がゆっくり回る。勾玉・祈願札・天井までの回数・確率の表・勾玉の手に入れ方
--  * 演出: 暗転 → 札が並ぶ(★4以上が出る時は札が金色、★5は虹色に光る) → 札を順にめくる →
--          ★4以上の魚は1匹ずつ大きく見せる(回る魚・名前・「限定」の朱印・鳴き声) → まとめ
--  * 確率はいつでも見られる。勾玉を Robux で買うボタンは、買えない地域(PolicyService)では出さない
local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local PolicyService = game:GetService("PolicyService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Locale = require(Shared.Locale)
local Format = require(Shared.Lib.Format)
local Remotes = require(Shared.Lib.Remotes)
local FishBuilder = require(Shared.Lib.FishBuilder)
local GachaLib = require(Shared.Lib.Gacha)

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local Root = require(script.Parent.Parent.UI.Root)
local State = require(script.Parent.Parent.ClientState)
local Sound = require(script.Parent.Sound)
local Cry = require(script.Parent.Cry)
local C = Theme.Colors

local G = Config.Gacha
local player = Players.LocalPlayer
local Gacha = {}

-- 星の色(★1 灰・★2 青・★3 紫・★4 金・★5 虹の代表色)
local STAR_COLOR = {
	[1] = Color3.fromRGB(150, 150, 165),
	[2] = Color3.fromRGB(90, 160, 255),
	[3] = Color3.fromRGB(190, 110, 255),
	[4] = Color3.fromRGB(255, 205, 80),
	[5] = Color3.fromRGB(255, 120, 170),
}
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 110, 140)),
	ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 220, 110)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(130, 255, 170)),
	ColorSequenceKeypoint.new(0.75, Color3.fromRGB(120, 190, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 140, 255)),
})

local panel: Kit.Panel
local gui: ScreenGui
local showcase: ViewportFrame
local showcaseName: TextLabel
local showcaseKind: TextLabel
local walletLabel: TextLabel
local pityLabel: TextLabel
local pull1: TextButton
local pull10: TextButton
local ratesBox: Frame
local buyBox: Frame
local reveal: Frame? = nil
local showcaseIndex = 1
local showcaseModel: Model? = nil
local codexBefore: { [string]: boolean } = {}
local lastCount = 1
local paidAllowed: boolean? = nil -- 勾玉を Robux で買える地域か(調べるまで nil)

local function stars(n: number): string
	return string.rep("★", n)
end

local function wallet(): (number, number)
	local g = State.profile and State.profile.gacha
	if not g then
		return 0, 0
	end
	return g.magatama or 0, g.tickets or 0
end

-- n 回の払い方の文字(札を先に使う)
local function costText(n: number): string
	local m, t = wallet()
	local useT = math.min(n, t)
	local parts = {}
	if useT > 0 then
		table.insert(parts, Locale.t("gacha_cost_ticket", { n = useT }))
	end
	if n - useT > 0 then
		table.insert(parts, Locale.t("gacha_cost_magatama", { n = (n - useT) * G.Cost }))
	end
	local _ = m
	return table.concat(parts, " + ")
end

local function canPay(n: number): boolean
	local m, t = wallet()
	return GachaLib.cost(n, t, m, G.Cost) ~= nil
end

-- 祠の画面のいちばん上の魚(★5を順に見せる)
local function setShowcase(i: number)
	local ids = G.Fish[5]
	showcaseIndex = ((i - 1) % #ids) + 1
	local def = Config.FishById[ids[showcaseIndex]]
	if showcaseModel then
		showcaseModel:Destroy()
	end
	showcaseModel = FishBuilder.build(def, {})
	Kit.setViewportModel(showcase, showcaseModel :: Model)
	showcaseName.Text = ("%s  %s"):format(stars(5), Locale.fishName(def))
	showcaseKind.Text = ("%s · %s"):format(Locale.fishKind(def), Locale.t("codex_shrine_only"))
end

function Gacha.render()
	if not panel or not panel.root.Visible or not State.profile then
		return
	end
	panel.title.Text = Locale.t("shrine_title")
	local m, t = wallet()
	walletLabel.Text = ("%s %s    %s %d"):format(
		Locale.t("gacha_magatama"),
		Format.coins(m, Locale.get()),
		Locale.t("gacha_tickets"),
		t
	)
	local g = State.profile.gacha or {}
	pityLabel.Text = Locale.t("gacha_pity", {
		a = math.max(1, G.Pity.star4 - (g.pity4 or 0)),
		b = math.max(1, G.Pity.star5 - (g.pity5 or 0)),
	})
	pull1.Text = Locale.t("gacha_pull1") .. "\n" .. costText(1)
	pull10.Text = Locale.t("gacha_pull10") .. "\n" .. costText(G.MaxPulls)
	Kit.setEnabled(pull1, canPay(1), C.vermilion)
	Kit.setEnabled(pull10, canPay(G.MaxPulls), C.vermilion)
end

-- 確率の表(星ごと + 限定の魚の名前)
local function renderRates()
	Kit.clear(ratesBox)
	local list = Kit.list(ratesBox, 4)
	Kit.label({
		Size = UDim2.new(1, 0, 0, 30),
		Text = Locale.t("gacha_rates_title"),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.goldLight,
		MaxTextSize = 20,
		LayoutOrder = 0,
		Parent = list,
	})
	for i, r in GachaLib.rates(G) do
		local ids = G.Fish[r.star]
		local what = Locale.t("gacha_star_items")
		if ids then
			local names = {}
			for _, id in ids do
				table.insert(names, Locale.fishName(Config.FishById[id]))
			end
			what = Locale.t("gacha_star_fish") .. ": " .. table.concat(names, "・")
		end
		local row = Kit.label({
			Size = UDim2.new(1, 0, 0, 44),
			Text = ("%s  %.1f%%   %s"):format(stars(r.star), r.percent, what),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			TextColor3 = STAR_COLOR[r.star],
			MaxTextSize = 16,
			LayoutOrder = i,
			Parent = list,
		})
		row.Name = "Rate" .. r.star
	end
	Kit.label({
		Size = UDim2.new(1, 0, 0, 40),
		Text = Locale.t("gacha_pity_note"),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		TextColor3 = C.textDim,
		MaxTextSize = 14,
		LayoutOrder = 99,
		Parent = list,
	})
end

-- 勾玉の手に入れ方(遊んでたまる道と、Robux)
local function renderBuy()
	Kit.clear(buyBox)
	local list = Kit.list(buyBox, 4)
	Kit.label({
		Size = UDim2.new(1, 0, 0, 52),
		Text = Locale.t("gacha_earn"),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		TextColor3 = C.textDim,
		MaxTextSize = 14,
		LayoutOrder = 0,
		Parent = list,
	})
	if paidAllowed ~= true then
		return
	end
	local order = 0
	for _, dp in Config.Products.DevProducts do
		if dp.magatama and dp.id ~= 0 then
			order += 1
			local b = Kit.button({
				Text = ("%s   R$ %d"):format(Locale.t("product_" .. dp.key), dp.robux),
				Size = UDim2.new(1, 0, 0, 40),
				Color = C.jadeDark,
				MaxTextSize = 16,
				LayoutOrder = order,
				Parent = list,
			}, function()
				MarketplaceService:PromptProductPurchase(player, dp.id)
			end)
			b.Name = "Buy_" .. dp.key
		end
	end
end

-- 勾玉を Robux で買える地域か(ランダムな品の購入が制限されている地域では買うボタンを出さない)
local function checkPolicy()
	task.spawn(function()
		local ok, info = pcall(function()
			return PolicyService:GetPolicyInfoForPlayerAsync(player)
		end)
		paidAllowed = ok and type(info) == "table" and info.ArePaidRandomItemsRestricted == false
		if panel and panel.root.Visible then
			renderBuy()
		end
	end)
end

local function pull(n: number)
	if not canPay(n) then
		return
	end
	lastCount = n
	-- 新しく載った魚に「NEW」を付けるため、今の図鑑を覚えておく
	table.clear(codexBefore)
	for id in State.profile.codex or {} do
		codexBefore[id] = true
	end
	Kit.setEnabled(pull1, false)
	Kit.setEnabled(pull10, false)
	Sound.play("click", 0.5, 0.7)
	State.request("gachaPull", n)
end

-- 演出 ------------------------------------------------------------------------

local function tween(inst: Instance, t: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	TweenService
		:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal)
		:Play()
end

local function closeReveal()
	if reveal then
		reveal:Destroy()
		reveal = nil
	end
	Gacha.render()
end

-- 1枚の札(めくると中身)
local function card(parent: Instance, r: any, size: UDim2, order: number): (Frame, () -> ())
	local f = Kit.new("Frame", {
		Name = "Card" .. order,
		Size = size,
		BackgroundColor3 = C.panelDark,
		LayoutOrder = order,
		Parent = parent,
	})
	Kit.corner(f, Theme.CornerSmall)
	local stroke = Kit.stroke(f, C.gold, 2)
	-- 裏(お札の「封」)
	local back = Kit.label({
		Name = "Back",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.fromRGB(236, 224, 196),
		Text = "封",
		TextColor3 = C.vermilionDark,
		Font = Theme.Fonts.title,
		MaxTextSize = 40,
		Parent = f,
	})
	Kit.corner(back, Theme.CornerSmall)
	local face = Kit.new("Frame", {
		Name = "Face",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = f,
	})
	local function flip()
		back.Visible = false
		face.Visible = true
		stroke.Color = STAR_COLOR[r.star]
		stroke.Thickness = if r.star >= 4 then 4 else 2
		f.BackgroundColor3 = STAR_COLOR[r.star]:Lerp(C.panelDark, 0.75)
		if r.star >= 5 then
			Kit.new("UIGradient", { Color = RAINBOW, Rotation = 30, Parent = stroke })
		end
		Kit.label({
			Size = UDim2.new(1, -6, 0, 18),
			Position = UDim2.fromOffset(3, 2),
			Text = stars(r.star),
			TextColor3 = STAR_COLOR[r.star],
			MaxTextSize = 14,
			Parent = face,
		})
		local text: string
		if r.kind == "fish" then
			local def = Config.FishById[r.fishId]
			local vpHolder = Kit.new("Frame", {
				Size = UDim2.new(1, -6, 1, -46),
				Position = UDim2.fromOffset(3, 20),
				BackgroundTransparency = 1,
				Parent = face,
			})
			Kit.viewport(vpHolder, FishBuilder.build(def, { noRarityScale = true }))
			text = Locale.fishName(def)
		elseif r.kind == "coins" then
			text = Locale.t("gacha_item_coins", { n = Format.coins(r.amount or 0, Locale.get()) })
		elseif r.kind == "bait" then
			text =
				Locale.t("gacha_item_bait", { bait = Locale.t("bait_" .. tostring(r.id)), n = r.amount or 0 })
		else
			text = Locale.t("gacha_item_luck", { n = r.minutes or 0 })
		end
		Kit.label({
			Name = "What",
			Size = UDim2.new(1, -6, 0, 24),
			Position = UDim2.new(0, 3, 1, -26),
			Text = text,
			TextColor3 = if r.star >= 3 then C.goldLight else C.text,
			MaxTextSize = 14,
			Parent = face,
		})
		if r.kind == "fish" and not codexBefore[r.fishId] then
			local new = Kit.label({
				Name = "New",
				Size = UDim2.fromOffset(40, 18),
				Position = UDim2.new(1, -42, 0, 2),
				BackgroundTransparency = 0,
				BackgroundColor3 = C.vermilion,
				Text = Locale.t("gacha_new"),
				MaxTextSize = 12,
				Parent = face,
			})
			Kit.corner(new, UDim.new(1, 0))
		end
		Sound.play(if r.star >= 4 then "rare" else "click", 0.4, 0.8 + r.star * 0.1)
	end
	return f, flip
end

-- ★4以上の魚を1匹ずつ大きく見せる。終わったら done()
local function spotlight(root: Frame, r: any, done: () -> ())
	local def = Config.FishById[r.fishId]
	local stage = Kit.new("Frame", {
		Name = "Spotlight",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.15,
		ZIndex = 5,
		Parent = root,
	})
	-- 後ろの光(★5は虹、★4は金)
	local glow = Kit.new("Frame", {
		Name = "Glow",
		Size = UDim2.fromScale(0.7, 0.7),
		Position = UDim2.fromScale(0.5, 0.45),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = STAR_COLOR[r.star],
		BackgroundTransparency = 0.55,
		ZIndex = 5,
		Parent = stage,
	})
	Kit.corner(glow, UDim.new(1, 0))
	if r.star >= 5 then
		local grad = Kit.new("UIGradient", { Color = RAINBOW, Parent = glow })
		local conn
		conn = RunService.RenderStepped:Connect(function(dt)
			if not grad.Parent then
				conn:Disconnect()
				return
			end
			grad.Rotation = (grad.Rotation + dt * 90) % 360
		end)
	end
	local vpHolder = Kit.new("Frame", {
		Size = UDim2.fromScale(0.6, 0.55),
		Position = UDim2.fromScale(0.5, 0.42),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		ZIndex = 6,
		Parent = stage,
	})
	local model = FishBuilder.build(def, {})
	local vp = Kit.viewport(vpHolder, model)
	vp.ZIndex = 6
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not model.Parent then
			conn:Disconnect()
			return
		end
		model:PivotTo(CFrame.Angles(0, os.clock() * 0.9, 0))
	end)
	Kit.label({
		Name = "Stars",
		Size = UDim2.new(0.6, 0, 0, 34),
		Position = UDim2.new(0.5, 0, 0.72, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = stars(r.star),
		TextColor3 = STAR_COLOR[r.star],
		ZIndex = 6,
		MaxTextSize = 30,
		Parent = stage,
	})
	Kit.label({
		Name = "FishName",
		Size = UDim2.new(0.8, 0, 0, 52),
		Position = UDim2.new(0.5, 0, 0.78, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = Locale.fishName(def),
		Font = Theme.Fonts.title,
		ZIndex = 6,
		MaxTextSize = 46,
		Parent = stage,
	})
	Kit.label({
		Size = UDim2.new(0.8, 0, 0, 26),
		Position = UDim2.new(0.5, 0, 0.88, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = ("%s · %s"):format(Locale.fishKind(def), Locale.t("codex_shrine_only")),
		TextColor3 = C.textDim,
		ZIndex = 6,
		MaxTextSize = 20,
		Parent = stage,
	})
	-- 「限定」の朱印(大きく押して、少し傾いて止まる)
	local seal = Kit.label({
		Name = "Seal",
		Size = UDim2.fromOffset(110, 110),
		Position = UDim2.new(0.78, 0, 0.2, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 0,
		BackgroundColor3 = C.vermilion,
		Text = Locale.t("gacha_limited"),
		Font = Theme.Fonts.title,
		ZIndex = 7,
		Rotation = -40,
		MaxTextSize = 30,
		Parent = stage,
	})
	Kit.corner(seal, UDim.new(0, 16))
	Kit.stroke(seal, C.goldLight, 3)
	local sealScale = Kit.new("UIScale", { Scale = 2.4, Parent = seal })
	task.delay(0.6, function()
		tween(sealScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		tween(seal, 0.25, { Rotation = -12 })
		Sound.play("catch", 0.6, 0.7)
	end)
	Cry.play(def.id, { volume = 0.9 })
	local ok = Kit.button({
		Name = "Next",
		Text = Locale.t("gacha_ok"),
		Size = UDim2.fromOffset(200, 50),
		Position = UDim2.new(0.5, 0, 1, -16),
		AnchorPoint = Vector2.new(0.5, 1),
		Color = C.vermilion,
		Parent = stage,
	}, function()
		stage:Destroy()
		done()
	end)
	ok.ZIndex = 8
end

-- サーバーから結果が来たら演出する
function Gacha.show(msg: any)
	if type(msg) ~= "table" or type(msg.results) ~= "table" then
		return
	end
	closeReveal()
	local results = msg.results
	local best = 0
	for _, r in results do
		best = math.max(best, r.star or 0)
	end
	local root = Kit.new("Frame", {
		Name = "GachaReveal",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(6, 4, 14),
		BackgroundTransparency = 0.05,
		ZIndex = 40,
		Parent = gui,
	})
	reveal = root
	local top = Kit.label({
		Name = "Torii",
		Size = UDim2.new(1, 0, 0, 60),
		Position = UDim2.fromOffset(0, Root.topInset() + 8),
		Text = "⛩ " .. Locale.t("shrine_title"),
		TextColor3 = if best >= 5
			then Color3.fromRGB(255, 200, 230)
			elseif best >= 4 then C.goldLight
			else C.text,
		Font = Theme.Fonts.title,
		MaxTextSize = 36,
		Parent = root,
	})
	if best >= 4 then
		-- ★4以上が出る時は、札を並べる前に画面が光る(★5は虹)
		local flash = Kit.new("Frame", {
			Name = "Flash",
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = STAR_COLOR[best],
			BackgroundTransparency = 0.2,
			ZIndex = 41,
			Parent = root,
		})
		if best >= 5 then
			Kit.new("UIGradient", { Color = RAINBOW, Rotation = 45, Parent = flash })
		end
		tween(flash, 1.2, { BackgroundTransparency = 1 })
		Sound.play("rare", 0.8, if best >= 5 then 0.6 else 0.8)
		task.delay(1.3, function()
			flash:Destroy()
		end)
	end
	local _ = top
	local grid = Kit.new("Frame", {
		Name = "Cards",
		Size = UDim2.new(0.9, 0, 0.62, 0),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		Parent = root,
	})
	local many = #results > 1
	Kit.new("UIGridLayout", {
		CellSize = if many then UDim2.new(0.18, 0, 0.47, 0) else UDim2.new(0.3, 0, 0.9, 0),
		CellPadding = UDim2.new(0.02, 0, 0.04, 0),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	local flips: { () -> () } = {}
	for i, r in results do
		local _, flip = card(grid, r, UDim2.fromScale(1, 1), i)
		flips[i] = flip
	end
	local skipped = false
	local bottom = Kit.new("Frame", {
		Name = "Bottom",
		Size = UDim2.new(1, 0, 0, 56),
		Position = UDim2.new(0, 0, 1, -12),
		AnchorPoint = Vector2.new(0, 1),
		BackgroundTransparency = 1,
		Parent = root,
	})
	Kit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 12),
		Parent = bottom,
	})
	local function finish()
		Kit.clear(bottom)
		Kit.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 12),
			Parent = bottom,
		})
		Kit.button({
			Name = "Collect",
			Text = Locale.t("gacha_ok"),
			Size = UDim2.fromOffset(200, 52),
			Color = C.jade,
			Parent = bottom,
		}, closeReveal)
		local again = Kit.button({
			Name = "Again",
			Text = Locale.t("gacha_again") .. " ×" .. lastCount,
			Size = UDim2.fromOffset(200, 52),
			Color = C.vermilion,
			Parent = bottom,
		}, function()
			closeReveal()
			pull(lastCount)
		end)
		Kit.setEnabled(again, canPay(lastCount), C.vermilion)
	end
	-- めくり終わったら、★4以上の魚を順に大きく見せる
	local function showSpotlights()
		local queue = {}
		for _, r in results do
			if r.kind == "fish" and r.star >= 4 then
				table.insert(queue, r)
			end
		end
		local function nextOne()
			if not root.Parent then
				return
			end
			local r = table.remove(queue, 1)
			if r then
				spotlight(root, r, nextOne)
			else
				finish()
			end
		end
		nextOne()
	end
	Kit.button({
		Name = "Skip",
		Text = Locale.t("gacha_skip"),
		Size = UDim2.fromOffset(160, 48),
		Color = C.panelDark,
		Parent = bottom,
	}, function()
		if skipped then
			return
		end
		skipped = true
		for _, flip in flips do
			flip()
		end
		table.clear(flips)
		showSpotlights()
	end)
	-- 札を順にめくる(★4以上がある時は、少し間をおいてから)
	task.spawn(function()
		task.wait(if best >= 4 then 1.3 else 0.5)
		for i = 1, #results do
			if skipped or not root.Parent then
				return
			end
			local flip = flips[i]
			if flip then
				flips[i] = nil :: any
				flip()
			end
			task.wait(if results[i].star >= 4 then 0.45 else 0.18)
		end
		if not skipped and root.Parent then
			skipped = true
			showSpotlights()
		end
	end)
end

function Gacha.init(screen: ScreenGui)
	gui = screen
	panel = Kit.panel(gui, "Shrine", UDim2.fromScale(0.86, 0.84))
	panel.close.Activated:Connect(function()
		Root.close()
	end)
	-- 左: いちばん上の限定の魚(回る)
	local left = Kit.new("Frame", {
		Name = "Showcase",
		Size = UDim2.new(0.5, -6, 1, 0),
		BackgroundColor3 = C.panelDark,
		Parent = panel.body,
	})
	Kit.corner(left)
	local stroke = Kit.stroke(left, C.gold, 2)
	Kit.new("UIGradient", { Color = RAINBOW, Rotation = 30, Parent = stroke })
	Kit.label({
		Size = UDim2.new(1, -16, 0, 22),
		Position = UDim2.fromOffset(8, 6),
		Text = Locale.t("shrine_sub"),
		TextColor3 = C.goldLight,
		MaxTextSize = 16,
		Parent = left,
	})
	local vpHolder = Kit.new("Frame", {
		Size = UDim2.new(1, -16, 1, -96),
		Position = UDim2.fromOffset(8, 30),
		BackgroundTransparency = 1,
		Parent = left,
	})
	showcase = Kit.viewport(vpHolder, nil)
	showcaseName = Kit.label({
		Name = "ShowcaseName",
		Size = UDim2.new(1, -16, 0, 34),
		Position = UDim2.new(0, 8, 1, -64),
		Font = Theme.Fonts.title,
		TextColor3 = Color3.fromRGB(255, 200, 230),
		MaxTextSize = 26,
		Parent = left,
	})
	showcaseKind = Kit.label({
		Size = UDim2.new(1, -16, 0, 22),
		Position = UDim2.new(0, 8, 1, -28),
		TextColor3 = C.textDim,
		MaxTextSize = 15,
		Parent = left,
	})
	-- 右: 財布・天井・祈るボタン・確率・勾玉の手に入れ方
	local right = Kit.new("Frame", {
		Size = UDim2.new(0.5, -6, 1, 0),
		Position = UDim2.new(0.5, 6, 0, 0),
		BackgroundTransparency = 1,
		Parent = panel.body,
	})
	walletLabel = Kit.label({
		Name = "Wallet",
		Size = UDim2.new(1, 0, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.goldLight,
		MaxTextSize = 20,
		Parent = right,
	})
	pityLabel = Kit.label({
		Name = "Pity",
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.fromOffset(0, 32),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.textDim,
		MaxTextSize = 15,
		Parent = right,
	})
	pull1 = Kit.button({
		Name = "Pull1",
		Size = UDim2.new(0.5, -4, 0, 62),
		Position = UDim2.fromOffset(0, 60),
		MaxTextSize = 18,
		Parent = right,
	}, function()
		pull(1)
	end)
	pull10 = Kit.button({
		Name = "Pull10",
		Size = UDim2.new(0.5, -4, 0, 62),
		Position = UDim2.new(0.5, 4, 0, 60),
		MaxTextSize = 18,
		Parent = right,
	}, function()
		pull(G.MaxPulls)
	end)
	-- 確率 / 勾玉の切り替え
	local tabs = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 36),
		Position = UDim2.fromOffset(0, 130),
		BackgroundTransparency = 1,
		Parent = right,
	})
	ratesBox = Kit.new("Frame", {
		Name = "Rates",
		Size = UDim2.new(1, 0, 1, -172),
		Position = UDim2.fromOffset(0, 172),
		BackgroundTransparency = 1,
		Parent = right,
	})
	buyBox = Kit.new("Frame", {
		Name = "BuyMagatama",
		Size = UDim2.new(1, 0, 1, -172),
		Position = UDim2.fromOffset(0, 172),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = right,
	})
	local ratesTab, buyTab
	local function select(which: string)
		ratesBox.Visible = which == "rates"
		buyBox.Visible = which == "buy"
		ratesTab.BackgroundColor3 = if which == "rates" then C.vermilion else C.panelDark
		buyTab.BackgroundColor3 = if which == "buy" then C.vermilion else C.panelDark
	end
	ratesTab = Kit.button({
		Name = "RatesTab",
		Text = Locale.t("gacha_rates"),
		Size = UDim2.new(0.5, -4, 1, 0),
		Color = C.vermilion,
		MaxTextSize = 16,
		Parent = tabs,
	}, function()
		select("rates")
	end)
	buyTab = Kit.button({
		Name = "BuyTab",
		Text = Locale.t("gacha_buy"),
		Size = UDim2.new(0.5, -4, 1, 0),
		Position = UDim2.new(0.5, 4, 0, 0),
		Color = C.panelDark,
		MaxTextSize = 16,
		Parent = tabs,
	}, function()
		select("buy")
	end)
	Root.register("shrine", panel.root, function()
		select("rates")
		renderRates()
		renderBuy()
		setShowcase(showcaseIndex)
		Gacha.render()
	end)
	State.Changed:Connect(Gacha.render)
	-- ★5の魚をゆっくり回し、ときどき入れ替える
	local t = 0
	RunService.RenderStepped:Connect(function(dt)
		if not panel.root.Visible or not showcaseModel then
			return
		end
		t += dt
		showcaseModel:PivotTo(CFrame.Angles(0, os.clock() * 0.6, 0))
		if t > 6 then
			t = 0
			setShowcase(showcaseIndex + 1)
		end
	end)
	Remotes.event("GachaResult").OnClientEvent:Connect(Gacha.show)
	checkPolicy()
end

return Gacha
