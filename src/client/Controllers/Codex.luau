--!strict
-- 妖怪魚図鑑。釣った魚は3Dで回して見られる。未発見はシルエットと出現条件のヒントだけ。
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Locale = require(Shared.Locale)
local Format = require(Shared.Lib.Format)
local FishBuilder = require(Shared.Lib.FishBuilder)

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local Root = require(script.Parent.Parent.UI.Root)
local Cry = require(script.Parent.Cry)
local State = require(script.Parent.Parent.ClientState)
local C = Theme.Colors

local Codex = {}

local panel: Kit.Panel
local grid: ScrollingFrame
local detail: Frame
local progressLabel: TextLabel
local selected: string? = nil
local cards: { [string]: { frame: TextButton, known: boolean?, stroke: UIStroke } } = {}
local detailModel: Model? = nil
local spotFilter = "swamp"

local function hint(def: any): string
	return Locale.t(
		"codex_hint",
		{ time = Locale.t("time_" .. def.time), weather = Locale.t("weather_" .. def.weather) }
	)
end

local function renderDetail()
	Kit.clear(detail)
	detailModel = nil
	local p = State.profile
	local id = selected
	if not p or not id then
		return
	end
	local def = Config.FishById[id]
	if not def then
		return
	end
	local entry = p.codex[id]
	local rarity = Config.RarityById[def.rarity]
	local vpHolder =
		Kit.new("Frame", { Size = UDim2.new(1, 0, 0.45, 0), BackgroundColor3 = C.waterDeep, Parent = detail })
	Kit.corner(vpHolder)
	Kit.gradient(vpHolder, Color3.fromRGB(70, 140, 170), C.waterDeep)
	local model = FishBuilder.build(def, { silhouette = entry == nil })
	Kit.viewport(vpHolder, model, nil, 2.4) -- レアな魚ほど大きく映る
	detailModel = model
	-- 見つけた魚は鳴き声を聞ける
	local fid: string = id :: string
	if entry and Cry.text(fid) then
		Kit.button({
			Name = "CryButton",
			Text = "🔊 " .. Locale.t("cry_play"),
			Size = UDim2.fromOffset(120, 36),
			Position = UDim2.new(1, -8, 0, 8),
			AnchorPoint = Vector2.new(1, 0),
			Color = C.indigo,
			MaxTextSize = 18,
			Parent = vpHolder,
		}, function()
			Cry.say(fid, vpHolder, UDim2.new(1, -8, 0, 52))
		end)
	end
	Kit.label({
		Size = UDim2.new(1, 0, 0, 24),
		Position = UDim2.fromScale(0, 0.47),
		Text = (if def.limited then "◆" .. Locale.t("gacha_limited") .. "  " else "")
			.. Locale.t("rarity_" .. def.rarity),
		TextColor3 = if def.limited then Color3.fromRGB(255, 200, 230) else Color3.fromHex(rarity.color),
		MaxTextSize = 20,
		Parent = detail,
	})
	Kit.label({
		Size = UDim2.new(1, 0, 0, 36),
		Position = UDim2.new(0, 0, 0.47, 26),
		Text = if entry then Locale.fishName(def) else Locale.t("codex_unknown"),
		Font = Theme.Fonts.title,
		MaxTextSize = 30,
		Parent = detail,
	})
	local lines = {}
	-- 見つけた魚は、種類(もとになった魚と妖怪)も出す
	table.insert(
		lines,
		(if entry then Locale.fishKind(def) .. "  ·  " else "")
			.. (
				if def.limited
					then Locale.t("codex_shrine_only")
					else Locale.t("spot_" .. def.spot) .. "  ·  " .. hint(def)
			)
	)
	if entry then
		table.insert(
			lines,
			Locale.t("codex_best", { kg = Format.kg(entry.best) })
				.. "   "
				.. Locale.t("codex_count", { n = entry.n })
		)
		local muts = {}
		for _, m in Config.Mutations do
			if entry.muts[m.id] then
				table.insert(muts, Locale.t("mutation_" .. m.id))
			end
		end
		if #muts > 0 then
			table.insert(lines, "◆ " .. table.concat(muts, " / "))
		end
		table.insert(lines, Locale.fishDesc(def))
	end
	Kit.label({
		Size = UDim2.new(1, 0, 0.4, -70),
		Position = UDim2.new(0, 0, 0.47, 66),
		Text = table.concat(lines, "\n"),
		TextColor3 = C.textDim,
		Font = Theme.Fonts.body,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		MaxTextSize = 17,
		Parent = detail,
	})
end

local function buildGrid()
	Kit.clear(grid)
	table.clear(cards)
	local p = State.profile
	if not p then
		return
	end
	local total, found = 0, 0
	for _, def in Config.Fish do
		if def.spot == spotFilter then
			total += 1
			local known = p.codex[def.id] ~= nil
			if known then
				found += 1
			end
			local rarity = Config.RarityById[def.rarity]
			local card = Kit.new("TextButton", {
				Name = def.id,
				BackgroundColor3 = if known then C.panelLight else C.panelDark,
				AutoButtonColor = true,
				Text = "",
				LayoutOrder = def.index,
				Parent = grid,
			})
			Kit.corner(card, Theme.CornerSmall)
			local stroke = Kit.stroke(
				card,
				Color3.fromHex(rarity.color),
				if selected == def.id then 3.5 else 1.5,
				if known then 0 else 0.5
			)
			local vp = Kit.new("Frame", {
				Size = UDim2.new(1, -8, 1, -30),
				Position = UDim2.fromOffset(4, 4),
				BackgroundTransparency = 1,
				Parent = card,
			})
			Kit.viewport(vp, FishBuilder.build(def, { silhouette = not known }))
			Kit.label({
				Size = UDim2.new(1, -6, 0, 22),
				Position = UDim2.new(0, 3, 1, -25),
				Text = if known then Locale.fishName(def) else ("No.%02d"):format(def.index),
				TextColor3 = if known then C.text else C.textDim,
				MaxTextSize = 15,
				Parent = card,
			})
			card.Activated:Connect(function()
				-- 選択の枠だけ更新(30個のビューポートを作り直さない)
				local prev = selected and cards[selected]
				if prev then
					prev.stroke.Thickness = 1.5
				end
				selected = def.id
				stroke.Thickness = 3.5
				renderDetail()
			end)
			cards[def.id] = { frame = card, known = known, stroke = stroke }
		end
	end
	local spot = Config.SpotById[spotFilter]
	progressLabel.Text = Locale.t("codex_progress", { n = found, max = total })
		.. (
			if spot and spot.completionReward > 0
				then "   " .. Locale.t(
					"codex_complete_reward",
					{ coins = Format.coins(spot.completionReward, Locale.get()) }
				)
				else ""
		)
end

function Codex.init(gui: ScreenGui)
	panel = Kit.panel(gui, "Codex", UDim2.fromScale(0.86, 0.84))
	panel.close.Activated:Connect(function()
		Root.close()
	end)
	-- 釣り場のタブ(魚がいる釣り場だけ)
	local tabs = Kit.new(
		"Frame",
		{ Size = UDim2.new(0.62, 0, 0, 36), BackgroundTransparency = 1, Parent = panel.body }
	)
	Kit.new(
		"UIListLayout",
		{ FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), Parent = tabs }
	)
	local spotIds = {}
	for _, f in Config.Fish do
		if not table.find(spotIds, f.spot) then
			table.insert(spotIds, f.spot)
		end
	end
	local tabButtons: { [string]: TextButton } = {}
	-- タブには短い名前(「ぬしの湖(釣り村)」→「ぬしの湖」)
	local function shortName(id: string): string
		local t = Locale.t("spot_" .. id)
		t = t:gsub("%s*%(.*$", "")
		t = t:gsub("（.*$", "")
		return t
	end
	local function paintTabs()
		for id, b in tabButtons do
			b.BackgroundColor3 = if id == spotFilter then C.vermilion else C.panelDark
			b.Text = shortName(id)
		end
	end
	for _, id in spotIds do
		-- 釣り場が増えても横一列に収まるよう、幅は等分
		tabButtons[id] = Kit.button({
			Text = "",
			Size = UDim2.new(1 / #spotIds, -6, 1, 0),
			Color = C.panelDark,
			MaxTextSize = 16,
			Parent = tabs,
		}, function()
			spotFilter = id
			selected = nil
			paintTabs()
			buildGrid()
			renderDetail()
		end)
	end
	paintTabs()
	progressLabel = Kit.label({
		Size = UDim2.new(0.62, 0, 0, 26),
		Position = UDim2.fromOffset(0, 40),
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 20,
		TextColor3 = C.goldLight,
		Parent = panel.body,
	})
	local gridHolder = Kit.new("Frame", {
		Size = UDim2.new(0.62, -8, 1, -72),
		Position = UDim2.fromOffset(0, 72),
		BackgroundTransparency = 1,
		Parent = panel.body,
	})
	grid = Kit.new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.gold,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		Parent = gridHolder,
	})
	Kit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(104, 112),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	Kit.new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), Parent = grid })
	detail = Kit.new("Frame", {
		Size = UDim2.new(0.38, -8, 1, 0),
		Position = UDim2.new(0.62, 8, 0, 0),
		BackgroundTransparency = 1,
		Parent = panel.body,
	})

	Root.register("codex", panel.root, function()
		panel.title.Text = Locale.t("codex_title")
		buildGrid()
		renderDetail()
	end)
	State.Changed:Connect(function()
		if panel.root.Visible then
			-- 新しく発見した魚がある時だけ作り直す
			local p = State.profile
			for id, c in cards do
				if (p.codex[id] ~= nil) ~= c.known then
					buildGrid()
					renderDetail()
					return
				end
			end
		end
	end)
	RunService.RenderStepped:Connect(function()
		if detailModel and detailModel.Parent and panel.root.Visible then
			detailModel:PivotTo(CFrame.Angles(0, os.clock() * 0.8, 0))
		end
	end)
end

return Codex
