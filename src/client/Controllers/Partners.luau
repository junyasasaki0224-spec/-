--!strict
-- 相棒パネル: 相棒の一覧 / 能力・技・経験値 / 魚を食べさせて育てる / 戦いに出す順番
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Locale = require(Shared.Locale)
local Format = require(Shared.Lib.Format)
local FishBuilder = require(Shared.Lib.FishBuilder)
local BattleLib = require(Shared.Lib.Battle)

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local Root = require(script.Parent.Parent.UI.Root)
local State = require(script.Parent.Parent.ClientState)
local C = Theme.Colors

local B = Config.Battle
local Partners = {}

local panel: Kit.Panel
local list: ScrollingFrame
local detail: Frame
local selected: string? = nil
local feeding = false
local detailModel: Model? = nil

function Partners.elementChip(parent: Instance, element: string, size: UDim2, pos: UDim2?): TextLabel
	local el = Config.ElementById[element] or Config.ElementById.none
	local chip = Kit.label({
		Size = size,
		Position = pos or UDim2.new(),
		BackgroundTransparency = 0,
		BackgroundColor3 = Color3.fromHex(el.color),
		Text = el.icon .. " " .. Locale.t("element_" .. element),
		TextColor3 = C.textDark,
		MaxTextSize = 16,
		Parent = parent,
	})
	Kit.corner(chip, UDim.new(1, 0))
	return chip
end

local function findPartner(uid: string?): any?
	local p = State.profile
	if not p or not uid then
		return nil
	end
	for _, f in p.partners do
		if f.uid == uid then
			return f
		end
	end
	return nil
end

local function teamIndex(uid: string): number?
	local p = State.profile
	return p and table.find(p.team, uid)
end

local function renderList()
	Kit.clear(list)
	local p = State.profile
	if #p.partners == 0 then
		Kit.label({
			Size = UDim2.new(1, 0, 0, 90),
			Text = Locale.t("partner_empty"),
			TextColor3 = C.textDim,
			TextWrapped = true,
			MaxTextSize = 18,
			Parent = list,
		})
		return
	end
	for i, f in p.partners do
		local def = Config.FishById[f.fishId]
		if not def then
			continue
		end
		local row = Kit.new("TextButton", {
			Size = UDim2.new(1, 0, 0, 72),
			BackgroundColor3 = if selected == f.uid then C.indigo else C.panelLight,
			AutoButtonColor = true,
			Text = "",
			LayoutOrder = i,
			Parent = list,
		})
		Kit.corner(row, Theme.CornerSmall)
		Kit.stroke(row, Color3.fromHex(Config.RarityById[def.rarity].color), 1.5)
		local vp = Kit.new("Frame", {
			Size = UDim2.fromOffset(64, 64),
			Position = UDim2.fromOffset(4, 4),
			BackgroundTransparency = 1,
			Parent = row,
		})
		Kit.viewport(vp, FishBuilder.build(def, { mutation = f.mutation }))
		Kit.label({
			Size = UDim2.new(1, -120, 0, 28),
			Position = UDim2.fromOffset(74, 6),
			Text = Locale.fishName(def) .. (if f.locked then " 🔒" else ""),
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Theme.Fonts.title,
			MaxTextSize = 20,
			Parent = row,
		})
		Kit.label({
			Size = UDim2.fromOffset(70, 22),
			Position = UDim2.fromOffset(74, 40),
			Text = "Lv " .. f.level,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = C.goldLight,
			MaxTextSize = 18,
			Parent = row,
		})
		Partners.elementChip(row, def.element, UDim2.fromOffset(90, 22), UDim2.fromOffset(146, 40))
		local ti = teamIndex(f.uid)
		if ti then
			local badge = Kit.label({
				Size = UDim2.fromOffset(34, 34),
				Position = UDim2.new(1, -8, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				BackgroundTransparency = 0,
				BackgroundColor3 = C.vermilion,
				Text = tostring(ti),
				Font = Theme.Fonts.title,
				MaxTextSize = 22,
				Parent = row,
			})
			Kit.corner(badge, UDim.new(1, 0))
		end
		row.Activated:Connect(function()
			selected = f.uid
			feeding = false
			Partners.render()
		end)
	end
end

local function statLine(parent: Instance, y: number, label: string, value: number, max: number, color: Color3)
	Kit.label({
		Size = UDim2.new(0.22, 0, 0, 20),
		Position = UDim2.fromOffset(0, y),
		Text = label,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 16,
		Parent = parent,
	})
	local bg, fill = Kit.bar(parent, color)
	bg.Size = UDim2.new(0.6, 0, 0, 10)
	bg.Position = UDim2.new(0.22, 0, 0, y + 5)
	fill.Size = UDim2.fromScale(math.clamp(value / max, 0.03, 1), 1)
	Kit.label({
		Size = UDim2.new(0.16, 0, 0, 20),
		Position = UDim2.new(0.84, 0, 0, y),
		Text = tostring(value),
		TextXAlignment = Enum.TextXAlignment.Right,
		MaxTextSize = 16,
		Parent = parent,
	})
end

local function renderFeedPicker(parent: Instance, partner: any, pdef: any)
	local p = State.profile
	local sl = Kit.list(parent, 6)
	local candidates = {}
	for _, food in p.creel do
		if not food.locked and Config.FishById[food.fishId] then
			table.insert(candidates, food)
		end
	end
	local function xpOf(food: any): number
		return BattleLib.feedXp(Config.FishById[food.fishId], food.grams, pdef)
	end
	table.sort(candidates, function(a, b)
		return xpOf(a) > xpOf(b)
	end)
	if #candidates == 0 then
		Kit.label({
			Size = UDim2.new(1, 0, 0, 50),
			Text = Locale.t("partner_no_food"),
			TextColor3 = C.textDim,
			MaxTextSize = 17,
			Parent = sl,
		})
	end
	for i, food in candidates do
		local fdef = Config.FishById[food.fishId]
		local row = Kit.row(sl, 50, i)
		local el = Config.ElementById[fdef.element]
		Kit.label({
			Size = UDim2.new(0.6, -10, 1, -10),
			Position = UDim2.fromOffset(10, 5),
			Text = ("%s %s  %s"):format(el.icon, Locale.fishName(fdef), Format.kg(food.grams)),
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 17,
			Parent = row,
		})
		local b = Kit.button({
			Text = ("+%d XP"):format(xpOf(food)),
			Size = UDim2.fromOffset(120, 38),
			Position = UDim2.new(1, -6, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Color = C.jade,
			MaxTextSize = 16,
			Parent = row,
		}, function()
			State.request("feed", { partner = partner.uid, food = food.uid })
		end)
		Kit.setEnabled(b, partner.level < B.MaxLevel, C.jade)
	end
end

local function renderDetail()
	Kit.clear(detail)
	detailModel = nil
	local partner = findPartner(selected)
	if not partner then
		Kit.label({
			Size = UDim2.new(1, 0, 0, 60),
			Position = UDim2.fromScale(0, 0.4),
			Text = Locale.t("partner_select"),
			TextColor3 = C.textDim,
			MaxTextSize = 18,
			Parent = detail,
		})
		return
	end
	local def = Config.FishById[partner.fishId]
	local stats = BattleLib.stats(def, partner.grams, partner.mutation, partner.level)

	local top =
		Kit.new("Frame", { Size = UDim2.new(1, 0, 0, 150), BackgroundColor3 = C.waterDeep, Parent = detail })
	Kit.corner(top)
	Kit.gradient(top, Color3.fromRGB(70, 140, 170), C.waterDeep)
	local vpHolder =
		Kit.new("Frame", { Size = UDim2.new(0.5, 0, 1, 0), BackgroundTransparency = 1, Parent = top })
	local model = FishBuilder.build(def, { mutation = partner.mutation })
	Kit.viewport(vpHolder, model)
	detailModel = model
	Kit.label({
		Size = UDim2.new(0.5, -10, 0, 34),
		Position = UDim2.new(0.5, 0, 0, 8),
		Text = Locale.fishName(def),
		Font = Theme.Fonts.title,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 26,
		Parent = top,
	})
	Kit.label({
		Size = UDim2.new(0.2, 0, 0, 26),
		Position = UDim2.new(0.5, 0, 0, 46),
		Text = "Lv " .. partner.level,
		TextColor3 = C.goldLight,
		Font = Theme.Fonts.title,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 22,
		Parent = top,
	})
	Partners.elementChip(top, def.element, UDim2.fromOffset(100, 26), UDim2.new(0.72, 0, 0, 46))
	local need = B.xpToNext(partner.level, def.rarity)
	local bg, fill = Kit.bar(top, C.success)
	bg.Size = UDim2.new(0.46, 0, 0, 12)
	bg.Position = UDim2.new(0.5, 0, 0, 86)
	fill.Size =
		UDim2.fromScale(if partner.level >= B.MaxLevel then 1 else math.clamp(partner.xp / need, 0, 1), 1)
	Kit.label({
		Size = UDim2.new(0.46, 0, 0, 20),
		Position = UDim2.new(0.5, 0, 0, 102),
		Text = if partner.level >= B.MaxLevel
			then "MAX"
			else Locale.t("partner_xp", { xp = partner.xp, need = need }),
		TextColor3 = C.textDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 15,
		Parent = top,
	})

	local body = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 1, -210),
		Position = UDim2.fromOffset(0, 158),
		BackgroundTransparency = 1,
		Parent = detail,
	})
	if feeding then
		renderFeedPicker(body, partner, def)
	else
		local left =
			Kit.new("Frame", { Size = UDim2.new(0.48, 0, 1, 0), BackgroundTransparency = 1, Parent = body })
		local maxStat = 400
		statLine(left, 0, "HP", stats.hp, maxStat * 1.4, C.success)
		statLine(left, 26, Locale.t("stat_atk"), stats.atk, maxStat, C.vermilion)
		statLine(left, 52, Locale.t("stat_def"), stats.def, maxStat, C.indigo)
		statLine(left, 78, Locale.t("stat_spd"), stats.spd, maxStat, C.goldLight)
		local right = Kit.new("Frame", {
			Size = UDim2.new(0.5, 0, 1, 0),
			Position = UDim2.fromScale(0.5, 0),
			BackgroundTransparency = 1,
			Parent = body,
		})
		Kit.new("UIListLayout", { Padding = UDim.new(0, 4), Parent = right })
		for _, id in BattleLib.movesFor(def, partner.level) do
			local mv = Config.MoveById[id]
			local el = Config.ElementById[if mv.element == "self" then def.element else mv.element]
			local chip = Kit.label({
				Size = UDim2.new(1, 0, 0, 26),
				BackgroundTransparency = 0,
				BackgroundColor3 = Color3.fromHex(el.color):Lerp(C.panel, 0.45),
				Text = ("%s %s%s"):format(
					el.icon,
					if Locale.get() == "ja" then mv.ja else mv.en,
					if mv.power > 0 then "  " .. mv.power else ""
				),
				MaxTextSize = 15,
				Parent = right,
			})
			Kit.corner(chip, Theme.CornerSmall)
		end
	end

	-- 操作ボタン
	local bar = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 46),
		Position = UDim2.new(0, 0, 1, -46),
		BackgroundTransparency = 1,
		Parent = detail,
	})
	Kit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = bar,
	})
	local function btn(text: string, color: Color3, enabled: boolean, fn: () -> ())
		local b = Kit.button(
			{ Text = text, Size = UDim2.new(0.24, -6, 1, 0), Color = color, MaxTextSize = 16, Parent = bar },
			fn
		)
		Kit.setEnabled(b, enabled, color)
	end
	btn(
		Locale.t(if feeding then "partner_feed_done" else "partner_feed"),
		C.jade,
		partner.level < B.MaxLevel or feeding,
		function()
			feeding = not feeding
			Partners.render()
		end
	)
	local ti = teamIndex(partner.uid)
	local p = State.profile
	btn(
		Locale.t(if ti then "partner_team_out" else "partner_team_in"),
		C.vermilion,
		ti ~= nil or #p.team < B.TeamSize,
		function()
			local team = table.clone(p.team)
			if ti then
				table.remove(team, ti)
			else
				table.insert(team, partner.uid)
			end
			State.request("setTeam", team)
		end
	)
	btn(if partner.locked then "🔒" else "🔓", C.panelDark, true, function()
		State.request("toggleLock", partner.uid)
	end)
	btn(Locale.t("partner_release"), C.indigo, true, function()
		State.request("removePartner", partner.uid)
		selected = nil
	end)
end

function Partners.render()
	if not panel or not panel.root.Visible or not State.profile then
		return
	end
	panel.title.Text = Locale.t("partner_title") .. ("  %d/%d"):format(#State.profile.partners, B.MaxPartners)
	if not findPartner(selected) then
		selected = if State.profile.partners[1] then State.profile.partners[1].uid else nil
	end
	renderList()
	renderDetail()
end

function Partners.init(gui: ScreenGui)
	panel = Kit.panel(gui, "Partners", UDim2.fromScale(0.86, 0.84))
	panel.close.Activated:Connect(function()
		Root.close()
	end)
	local listHolder =
		Kit.new("Frame", { Size = UDim2.new(0.4, -8, 1, 0), BackgroundTransparency = 1, Parent = panel.body })
	list = Kit.list(listHolder, 6)
	detail = Kit.new("Frame", {
		Size = UDim2.new(0.6, -8, 1, 0),
		Position = UDim2.new(0.4, 8, 0, 0),
		BackgroundTransparency = 1,
		Parent = panel.body,
	})
	Root.register("partners", panel.root, function()
		feeding = false
		Partners.render()
	end)
	State.Changed:Connect(Partners.render)
	RunService.RenderStepped:Connect(function()
		if detailModel and detailModel.Parent and panel.root.Visible then
			detailModel:PivotTo(CFrame.Angles(0, os.clock() * 0.8, 0))
		end
	end)
end

return Partners
