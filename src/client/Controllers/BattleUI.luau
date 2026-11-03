--!strict
-- 妖怪退治: 相手を選ぶパネルと、ポケモンのようなバトル画面。
-- 画面はサーバーから届いたイベントを順番に再生するだけ(ダメージや勝敗はサーバーが決める)。
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Locale = require(Shared.Locale)
local Format = require(Shared.Lib.Format)
local Remotes = require(Shared.Lib.Remotes)
local FishBuilder = require(Shared.Lib.FishBuilder)

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local Root = require(script.Parent.Parent.UI.Root)
local State = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Input)
local Sound = require(script.Parent.Sound)
local Cry = require(script.Parent.Cry)
local C = Theme.Colors

local B = Config.Battle
local BattleUI = {}

local gui: ScreenGui
local listPanel: Kit.Panel
local listFrame: ScrollingFrame
local teamBar: Frame

-- バトル画面
local screen: Frame? = nil
local view: any = nil -- 画面の部品
local current: any = nil -- サーバーから届いた最新の状態
local trainer: any = nil
local busy = false
local actionRemote: RemoteEvent

local function name(def: any): string
	return if def then Locale.fishName(def) else "?"
end

local function sideName(side: string, fishId: string): string
	local n = name(Config.FishById[fishId])
	return if side == "enemy" then Locale.t("battle_foe", { name = n }) else n
end

-- 相手の一覧 ----------------------------------------------------------------
local function renderList()
	if not listPanel.root.Visible or not State.profile then
		return
	end
	local p = State.profile
	listPanel.title.Text = Locale.t("battle_title")
	Kit.clear(teamBar)
	Kit.label({
		Size = UDim2.new(0.22, 0, 1, 0),
		Text = Locale.t("battle_your_team"),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 18,
		LayoutOrder = 0,
		Parent = teamBar,
	})
	local shown = 0
	for i, uid in p.team do
		for _, f in p.partners do
			if f.uid == uid then
				shown += 1
				local def = Config.FishById[f.fishId]
				local chip = Kit.label({
					Size = UDim2.new(0.22, 0, 1, -6),
					BackgroundTransparency = 0,
					BackgroundColor3 = C.panelLight,
					Text = ("%s %s Lv%d"):format(Config.ElementById[def.element].icon, name(def), f.level),
					MaxTextSize = 16,
					LayoutOrder = i,
					Parent = teamBar,
				})
				Kit.corner(chip, Theme.CornerSmall)
			end
		end
	end
	if shown == 0 then
		Kit.label({
			Size = UDim2.new(0.5, 0, 1, 0),
			Text = Locale.t("battle_need_partner"),
			TextColor3 = C.goldLight,
			MaxTextSize = 16,
			LayoutOrder = 1,
			Parent = teamBar,
		})
	end
	Kit.button({
		Text = Locale.t("hud_partners"),
		Size = UDim2.new(0.14, 0, 1, -6),
		Color = C.jadeDark,
		MaxTextSize = 16,
		LayoutOrder = 9,
		Parent = teamBar,
	}, function()
		Root.open("partners")
	end)

	Kit.clear(listFrame)
	for i, t in Config.Trainers do
		local cleared = p.battle.cleared[t.id] == true
		local unlocked = i == 1 or p.battle.cleared[Config.Trainers[i - 1].id] == true
		local row = Kit.row(listFrame, 92, i)
		Kit.label({
			Size = UDim2.new(0.5, 0, 0, 30),
			Position = UDim2.fromOffset(14, 6),
			Text = (if cleared then "✓ " elseif not unlocked then "🔒 " else "")
				.. (if Locale.get() == "ja" then t.ja else t.en),
			TextColor3 = if cleared then C.success elseif unlocked then C.text else C.textDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Theme.Fonts.title,
			MaxTextSize = 22,
			Parent = row,
		})
		local parts = {}
		for _, m in t.team do
			local def = Config.FishById[m.fish]
			table.insert(
				parts,
				("%s%s Lv%d"):format(
					Config.ElementById[def.element].icon,
					if unlocked then name(def) else "???",
					m.level
				)
			)
		end
		Kit.label({
			Size = UDim2.new(0.62, 0, 0, 22),
			Position = UDim2.fromOffset(14, 38),
			Text = table.concat(parts, "   "),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = C.textDim,
			MaxTextSize = 16,
			Parent = row,
		})
		local coins = if cleared then math.floor(t.reward.coins * B.RematchCoinRate) else t.reward.coins
		Kit.label({
			Size = UDim2.new(0.62, 0, 0, 20),
			Position = UDim2.fromOffset(14, 62),
			Text = "¥ " .. Format.coins(coins, Locale.get()) .. (if t.title and not cleared
				then "  +「" .. Locale.t("title_" .. t.title) .. "」"
				else ""),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = C.goldLight,
			MaxTextSize = 15,
			Parent = row,
		})
		local b = Kit.button({
			Text = Locale.t(if cleared then "battle_rematch" else "battle_challenge"),
			Size = UDim2.fromOffset(140, 50),
			Position = UDim2.new(1, -12, 0.5, 0),
			AnchorPoint = Vector2.new(1, 0.5),
			Color = C.vermilion,
			MaxTextSize = 20,
			Parent = row,
		}, function()
			State.request("startBattle", t.id)
		end)
		Kit.setEnabled(b, unlocked and #p.partners > 0)
	end
end

-- バトル画面の部品 ------------------------------------------------------------
local function hpColor(r: number): Color3
	return if r > 0.5 then C.success elseif r > 0.2 then C.goldLight else C.danger
end

local function makeCard(parent: Instance, pos: UDim2, anchor: Vector2)
	local card = Kit.new("Frame", {
		Size = UDim2.fromOffset(330, 92),
		Position = pos,
		AnchorPoint = anchor,
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.05,
		Parent = parent,
	})
	Kit.corner(card)
	Kit.stroke(card, C.gold, 2)
	local title = Kit.label({
		Size = UDim2.new(1, -110, 0, 30),
		Position = UDim2.fromOffset(14, 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Fonts.title,
		MaxTextSize = 22,
		Parent = card,
	})
	local level = Kit.label({
		Size = UDim2.fromOffset(80, 26),
		Position = UDim2.new(1, -12, 0, 8),
		AnchorPoint = Vector2.new(1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.goldLight,
		MaxTextSize = 20,
		Parent = card,
	})
	local bg, fill = Kit.bar(card, C.success)
	bg.Size = UDim2.new(1, -28, 0, 14)
	bg.Position = UDim2.fromOffset(14, 44)
	local hpText = Kit.label({
		Size = UDim2.new(1, -28, 0, 20),
		Position = UDim2.fromOffset(14, 62),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextColor3 = C.textDim,
		MaxTextSize = 16,
		Parent = card,
	})
	local dots = Kit.new("Frame", {
		Size = UDim2.fromOffset(120, 16),
		Position = UDim2.fromOffset(14, 64),
		BackgroundTransparency = 1,
		Parent = card,
	})
	Kit.new(
		"UIListLayout",
		{ FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), Parent = dots }
	)
	return { card = card, title = title, level = level, fill = fill, hpText = hpText, dots = dots }
end

local function makeStage(parent: Instance, pos: UDim2, anchor: Vector2, size: Vector2)
	local holder = Kit.new("Frame", {
		Size = UDim2.fromOffset(size.X, size.Y),
		Position = pos,
		AnchorPoint = anchor,
		BackgroundTransparency = 1,
		Parent = parent,
	})
	-- 足元の波紋
	local ring = Kit.new("Frame", {
		Size = UDim2.new(0.8, 0, 0, 34),
		Position = UDim2.new(0.5, 0, 1, -24),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(150, 220, 255),
		BackgroundTransparency = 0.65,
		Parent = holder,
	})
	Kit.corner(ring, UDim.new(1, 0))
	local vpf = Kit.viewport(holder, nil)
	return { holder = holder, vpf = vpf, model = nil :: Model?, fishId = "", base = pos }
end

local function setStageFish(stage: any, fishId: string, mutation: string?, faceLeft: boolean)
	if stage.fishId == fishId and stage.model then
		return
	end
	stage.fishId = fishId
	local def = Config.FishById[fishId]
	if not def then
		return
	end
	local model = FishBuilder.build(def, { mutation = mutation })
	Kit.setViewportModel(stage.vpf, model)
	stage.model = model
	stage.faceLeft = faceLeft
	stage.vpf.ImageTransparency = 0
end

local function updateCard(card: any, side: any)
	local f = side.team[side.active]
	local def = Config.FishById[f.fishId]
	card.title.Text = Config.ElementById[f.element].icon .. " " .. name(def)
	card.level.Text = "Lv " .. f.level
	local r = f.hp / math.max(1, f.maxHp)
	TweenService:Create(
		card.fill,
		TweenInfo.new(0.35),
		{ Size = UDim2.fromScale(math.clamp(r, 0, 1), 1), BackgroundColor3 = hpColor(r) }
	):Play()
	card.hpText.Text = ("%d / %d"):format(f.hp, f.maxHp)
	Kit.clear(card.dots)
	for _, m in side.team do
		local d = Kit.new("Frame", {
			Size = UDim2.fromOffset(14, 14),
			BackgroundColor3 = if m.hp > 0 then C.goldLight else C.disabled,
			Parent = card.dots,
		})
		Kit.corner(d, UDim.new(1, 0))
	end
end

local function setMessage(text: string)
	if view then
		view.message.Text = text
	end
end

-- 魚が鳴く(場に出た時。倒れた時は低く・ゆっくり)
local function cry(stage: any, fishId: string, fainted: boolean?)
	local opts = if fainted then { pitch = 0.78, volume = 0.6 } else { volume = 0.75 }
	Cry.say(fishId, stage.holder, UDim2.new(1, 0, 0, -8), opts)
end

local function shake(stage: any)
	local base = stage.base
	for i = 1, 6 do
		stage.holder.Position = base + UDim2.fromOffset(if i % 2 == 0 then 10 else -10, 0)
		task.wait(0.04)
	end
	stage.holder.Position = base
end

local function flash(stage: any, color: Color3)
	local f = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.4,
		ZIndex = 5,
		Parent = stage.holder,
	})
	Kit.corner(f, UDim.new(0, 30))
	TweenService:Create(f, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
	task.delay(0.42, function()
		f:Destroy()
	end)
end

local function floatText(stage: any, text: string, color: Color3)
	local l = Kit.label({
		Size = UDim2.fromOffset(200, 50),
		Position = UDim2.fromScale(0.5, 0.3),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = text,
		TextColor3 = color,
		Font = Theme.Fonts.title,
		MaxTextSize = 40,
		ZIndex = 6,
		Parent = stage.holder,
	})
	Kit.new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 2, Parent = l })
	TweenService
		:Create(l, TweenInfo.new(0.8), { Position = UDim2.fromScale(0.5, 0.05), TextTransparency = 1 })
		:Play()
	task.delay(0.85, function()
		l:Destroy()
	end)
end

local function setCommandsEnabled(on: boolean)
	if not view then
		return
	end
	for _, b in view.moveButtons do
		Kit.setEnabled(b, on and b:GetAttribute("HasMove") == true, b:GetAttribute("Color") :: any)
	end
	Kit.setEnabled(view.switchButton, on, C.indigo)
	Kit.setEnabled(view.runButton, on, C.panelDark)
end

local function refreshCommands()
	if not view or not current then
		return
	end
	local me = current.player
	local f = me.team[me.active]
	for i, b in view.moveButtons do
		local id = me.moves and me.moves[i]
		local mv = id and Config.MoveById[id]
		if mv then
			local el = Config.ElementById[if mv.element == "self" then f.element else mv.element]
			local color = Color3.fromHex(el.color):Lerp(C.panel, 0.25)
			b.Text = ("%s %s%s"):format(
				el.icon,
				if Locale.get() == "ja" then mv.ja else mv.en,
				if mv.power > 0 then "  " .. mv.power else ""
			)
			b:SetAttribute("HasMove", true)
			b:SetAttribute("Color", color)
		else
			b.Text = "—"
			b:SetAttribute("HasMove", false)
		end
	end
	setCommandsEnabled(not busy and not current.over)
end

local function applyState(st: any)
	current = st
	if not view then
		return
	end
	local pf = st.player.team[st.player.active]
	local ef = st.enemy.team[st.enemy.active]
	setStageFish(view.playerStage, pf.fishId, pf.mutation, false)
	setStageFish(view.enemyStage, ef.fishId, ef.mutation, true)
	updateCard(view.playerCard, st.player)
	updateCard(view.enemyCard, st.enemy)
	refreshCommands()
end

local function closeScreen()
	if screen then
		screen:Destroy()
		screen = nil
	end
	view = nil
	current = nil
	busy = false
	Input.setEnabled(true)
end

local function showSwitchPicker()
	if not view or not current or busy then
		return
	end
	local overlay = Kit.new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		Text = "",
		ZIndex = 40,
		Parent = screen,
	})
	local box = Kit.new("Frame", {
		Size = UDim2.fromOffset(420, 260),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.panel,
		ZIndex = 41,
		Parent = overlay,
	})
	Kit.corner(box)
	Kit.stroke(box, C.gold, 3)
	Kit.padding(box, 14)
	Kit.new("UIListLayout", { Padding = UDim.new(0, 8), Parent = box })
	for i, f in current.player.team do
		local def = Config.FishById[f.fishId]
		local ok = f.hp > 0 and i ~= current.player.active
		local b = Kit.button({
			Text = ("%s %s Lv%d   %d/%d"):format(
				Config.ElementById[f.element].icon,
				name(def),
				f.level,
				f.hp,
				f.maxHp
			),
			Size = UDim2.new(1, 0, 0, 52),
			Color = C.indigo,
			MaxTextSize = 18,
			Parent = box,
		}, function()
			overlay:Destroy()
			busy = true
			setCommandsEnabled(false)
			actionRemote:FireServer({ kind = "switch", slot = i })
		end)
		b.ZIndex = 42
		Kit.setEnabled(b, ok, C.indigo)
	end
	overlay.Activated:Connect(function()
		overlay:Destroy()
	end)
end

local function openScreen()
	closeScreen()
	Root.close()
	Input.setEnabled(false)
	local s = Kit.new("Frame", {
		Name = "Battle",
		Active = true, -- 下の HUD のボタンを押せないようにする
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 30,
		Parent = gui,
	})
	Kit.gradient(s, Color3.fromRGB(40, 34, 78), Color3.fromRGB(24, 64, 70))
	screen = s
	-- 水面の帯
	local water = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0.42, 0),
		Position = UDim2.fromScale(0, 0.58),
		BackgroundColor3 = C.water,
		BackgroundTransparency = 0.25,
		Parent = s,
	})
	Kit.gradient(water, Color3.fromRGB(70, 150, 180), C.waterDeep)

	local v: any = {}
	v.enemyStage = makeStage(s, UDim2.new(0.72, 0, 0.3, 0), Vector2.new(0.5, 0.5), Vector2.new(300, 220))
	v.playerStage = makeStage(s, UDim2.new(0.28, 0, 0.58, 0), Vector2.new(0.5, 0.5), Vector2.new(340, 240))
	v.enemyCard = makeCard(s, UDim2.new(0.05, 0, 0, 80), Vector2.new(0, 0))
	v.playerCard = makeCard(s, UDim2.new(0.95, 0, 0.5, 0), Vector2.new(1, 0.5))
	if trainer then
		Kit.label({
			Size = UDim2.fromOffset(330, 26),
			Position = UDim2.new(0.05, 0, 0, 176),
			Text = if Locale.get() == "ja" then trainer.ja else trainer.en,
			TextColor3 = C.goldLight,
			TextXAlignment = Enum.TextXAlignment.Left,
			MaxTextSize = 20,
			Parent = s,
		})
	end

	local bottom = Kit.new("Frame", {
		Size = UDim2.new(1, -40, 0, 170),
		Position = UDim2.new(0.5, 0, 1, -20),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.05,
		Parent = s,
	})
	Kit.corner(bottom)
	Kit.stroke(bottom, C.gold, 3)
	v.message = Kit.label({
		Size = UDim2.new(0.42, -20, 1, -24),
		Position = UDim2.fromOffset(16, 12),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		MaxTextSize = 24,
		Parent = bottom,
	})
	local grid = Kit.new("Frame", {
		Size = UDim2.new(0.58, -16, 1, -66),
		Position = UDim2.new(0.42, 0, 0, 10),
		BackgroundTransparency = 1,
		Parent = bottom,
	})
	Kit.new("UIGridLayout", {
		CellSize = UDim2.new(0.5, -6, 0.5, -6),
		CellPadding = UDim2.fromOffset(6, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	v.moveButtons = {}
	for i = 1, 4 do
		local b = Kit.button(
			{ Text = "", Color = C.panelLight, MaxTextSize = 18, LayoutOrder = i, Parent = grid },
			function()
				if busy or not current or current.over then
					return
				end
				busy = true
				setCommandsEnabled(false)
				actionRemote:FireServer({ kind = "move", index = i })
			end
		)
		table.insert(v.moveButtons, b)
	end
	local row = Kit.new("Frame", {
		Size = UDim2.new(0.58, -16, 0, 46),
		Position = UDim2.new(0.42, 0, 1, -54),
		BackgroundTransparency = 1,
		Parent = bottom,
	})
	Kit.new(
		"UIListLayout",
		{ FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), Parent = row }
	)
	v.switchButton = Kit.button({
		Text = Locale.t("battle_switch"),
		Size = UDim2.new(0.5, -3, 1, 0),
		Color = C.indigo,
		MaxTextSize = 18,
		Parent = row,
	}, showSwitchPicker)
	v.runButton = Kit.button({
		Text = Locale.t("battle_run"),
		Size = UDim2.new(0.5, -3, 1, 0),
		Color = C.panelDark,
		MaxTextSize = 18,
		Parent = row,
	}, function()
		if busy then
			return
		end
		busy = true
		setCommandsEnabled(false)
		actionRemote:FireServer({ kind = "run" })
	end)
	view = v

	-- 魚をゆらゆら動かす
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not screen or not view then
			conn:Disconnect()
			return
		end
		local t = os.clock()
		for _, st in { view.playerStage, view.enemyStage } do
			if st.model and st.model.Parent then
				local yaw = if st.faceLeft then math.pi else 0
				st.model:PivotTo(
					CFrame.new(0, math.sin(t * 2 + (if st.faceLeft then 1 else 0)) * 0.15, 0)
						* CFrame.Angles(0, yaw + math.sin(t * 1.3) * 0.15, 0)
				)
			end
		end
	end)
	local s2 = Kit.new("UIScale", { Scale = 1.1, Parent = s })
	TweenService:Create(s2, TweenInfo.new(0.3), { Scale = 1 }):Play()
end

-- イベントの再生 -----------------------------------------------------------
local function playEvents(events: { any })
	for _, e in events do
		if not view then
			return
		end
		local side = e.side
		local stage = if side == "enemy" then view.enemyStage else view.playerStage
		local st = current
		local fishId = if side and st then st[side].team[st[side].active].fishId else ""
		if e.kind == "move" then
			local mv = Config.MoveById[e.move]
			setMessage(
				Locale.t(
					"battle_used",
					{ name = sideName(side, fishId), move = if Locale.get() == "ja" then mv.ja else mv.en }
				)
			)
			Sound.play("click", 0.4, 0.8)
			task.wait(0.55)
		elseif e.kind == "miss" then
			setMessage(Locale.t("battle_miss"))
			task.wait(0.6)
		elseif e.kind == "damage" then
			Sound.play("splash", 0.5, if e.eff > 1 then 0.8 else 1.2)
			flash(stage, Color3.fromRGB(255, 80, 80))
			floatText(stage, "-" .. e.amount, if e.eff > 1 then C.goldLight else C.text)
			task.spawn(shake, stage)
			if st then
				local target = st[side].team[st[side].active]
				target.hp = e.hp
				updateCard(if side == "enemy" then view.enemyCard else view.playerCard, st[side])
			end
			local extra = {}
			if e.crit then
				table.insert(extra, Locale.t("battle_crit"))
			end
			if e.eff > 1 then
				table.insert(extra, Locale.t("battle_super"))
			elseif e.eff < 1 then
				table.insert(extra, Locale.t("battle_weak"))
			end
			task.wait(0.5)
			if #extra > 0 then
				setMessage(table.concat(extra, "\n"))
				task.wait(0.7)
			end
		elseif e.kind == "heal" then
			flash(stage, C.success)
			floatText(stage, "+" .. e.amount, C.success)
			setMessage(Locale.t("battle_heal", { name = sideName(side, fishId) }))
			if st then
				st[side].team[st[side].active].hp = e.hp
				updateCard(if side == "enemy" then view.enemyCard else view.playerCard, st[side])
			end
			task.wait(0.7)
		elseif e.kind == "stat" then
			local key = if e.delta > 0 then "battle_stat_up" else "battle_stat_down"
			setMessage(Locale.t(key, { name = sideName(side, fishId), stat = Locale.t("stat_" .. e.stat) }))
			flash(stage, if e.delta > 0 then C.goldLight else C.indigo)
			task.wait(0.7)
		elseif e.kind == "stun" then
			setMessage(Locale.t("battle_stun", { name = sideName(side, fishId) }))
			flash(stage, C.goldLight)
			task.wait(0.7)
		elseif e.kind == "stunned" then
			setMessage(Locale.t("battle_stunned", { name = sideName(side, fishId) }))
			task.wait(0.7)
		elseif e.kind == "faint" then
			setMessage(Locale.t("battle_faint", { name = sideName(side, e.fishId) }))
			TweenService:Create(stage.vpf, TweenInfo.new(0.5), { ImageTransparency = 1 }):Play()
			Sound.play("fail", 0.5, 0.7)
			cry(stage, e.fishId, true)
			if st then
				st[side].team[st[side].active].hp = 0
				updateCard(if side == "enemy" then view.enemyCard else view.playerCard, st[side])
			end
			task.wait(0.9)
		elseif e.kind == "switch" then
			if st then
				st[side].active = e.slot
				local f = st[side].team[e.slot]
				setStageFish(stage, f.fishId, f.mutation, side == "enemy")
				updateCard(if side == "enemy" then view.enemyCard else view.playerCard, st[side])
			end
			local n = name(Config.FishById[e.fishId])
			setMessage(
				if side == "player"
					then Locale.t("battle_go", { name = n })
					else Locale.t("battle_foe_sends", { name = n })
			)
			cry(stage, e.fishId)
			task.wait(0.9)
		elseif e.kind == "run" then
			setMessage(Locale.t("battle_ran"))
			task.wait(0.7)
		end
	end
end

local function showResult(r: any)
	if not screen then
		return
	end
	local overlay = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.4,
		ZIndex = 50,
		Parent = screen,
	})
	local card = Kit.new("Frame", {
		Size = UDim2.fromOffset(480, 400),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.panel,
		ZIndex = 51,
		Parent = overlay,
	})
	Kit.corner(card, UDim.new(0, 22))
	Kit.stroke(card, if r.win then C.goldLight else C.textDim, 4)
	Kit.padding(card, 18)
	Kit.new("UIListLayout", {
		Padding = UDim.new(0, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = card,
	})
	local function line(text: string, color: Color3, size: number, order: number)
		local l = Kit.label({
			Size = UDim2.new(1, 0, 0, size + 8),
			Text = text,
			TextColor3 = color,
			Font = Theme.Fonts.title,
			MaxTextSize = size,
			LayoutOrder = order,
			ZIndex = 52,
			Parent = card,
		})
		return l
	end
	line(
		Locale.t(if r.win then "battle_win" else "battle_lose"),
		if r.win then C.goldLight else C.textDim,
		40,
		1
	)
	if r.win then
		line(
			"¥ "
				.. Format.coins(r.coins, Locale.get())
				.. (if r.firstClear then "  " .. Locale.t("battle_first_clear") else ""),
			C.goldLight,
			22,
			2
		)
		if r.bait then
			line(Locale.t("bait_" .. r.bait.id) .. " ×" .. r.bait.amount, C.text, 18, 3)
		end
		if r.title then
			line(Locale.t("nushi_title_got", { title = Locale.t("title_" .. r.title) }), C.vermilion, 20, 4)
		end
	end
	for i, g in r.gains or {} do
		local def = Config.FishById[g.fishId]
		local text = ("%s  +%d XP"):format(name(def), g.xp)
		if g.levels > 0 then
			text ..= ("   Lv%d → Lv%d ▲"):format(g.from, g.level)
		end
		line(text, if g.levels > 0 then C.success else C.text, 18, 10 + i)
	end
	local b = Kit.button({
		Text = Locale.t("close"),
		Size = UDim2.fromOffset(200, 50),
		Color = C.jade,
		MaxTextSize = 22,
		LayoutOrder = 99,
	}, function()
		closeScreen()
		Root.open("battle")
	end)
	b.ZIndex = 53
	b.Parent = card
	if r.win then
		Sound.play("rare", 0.7, 1)
	end
	local s = Kit.new("UIScale", { Scale = 0.5, Parent = card })
	TweenService:Create(s, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

local queue: { any } = {}
local playing = false

local function handle(msg: any)
	if msg.kind == "start" then
		trainer = Config.TrainerById[msg.trainerId]
		openScreen()
		applyState(msg.state)
		busy = true
		setCommandsEnabled(false)
		local line = if trainer then (if Locale.get() == "ja" then trainer.jaLine else trainer.enLine) else ""
		setMessage(line)
		task.wait(1.4)
		local ef = msg.state.enemy.team[msg.state.enemy.active]
		setMessage(Locale.t("battle_foe_sends", { name = name(Config.FishById[ef.fishId]) }))
		if view then
			cry(view.enemyStage, ef.fishId)
		end
		task.wait(1.1)
		local pf = msg.state.player.team[msg.state.player.active]
		setMessage(Locale.t("battle_go", { name = name(Config.FishById[pf.fishId]) }))
		if view then
			cry(view.playerStage, pf.fishId)
		end
		task.wait(0.9)
		busy = false
		setMessage(Locale.t("battle_choose"))
		refreshCommands()
	elseif msg.kind == "turn" then
		if not view then
			return
		end
		busy = true
		setCommandsEnabled(false)
		playEvents(msg.events or {})
		applyState(msg.state)
		busy = false
		if not msg.state.over then
			setMessage(Locale.t("battle_choose"))
		end
		refreshCommands()
	elseif msg.kind == "result" then
		showResult(msg)
	end
end

function BattleUI.init(g: ScreenGui)
	gui = g
	actionRemote = Remotes.event("BattleAction")
	listPanel = Kit.panel(gui, "BattleList", UDim2.fromScale(0.8, 0.82))
	listPanel.close.Activated:Connect(function()
		Root.close()
	end)
	teamBar = Kit.new(
		"Frame",
		{ Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, Parent = listPanel.body }
	)
	Kit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = teamBar,
	})
	local holder = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 1, -52),
		Position = UDim2.fromOffset(0, 52),
		BackgroundTransparency = 1,
		Parent = listPanel.body,
	})
	listFrame = Kit.list(holder, 8)
	Root.register("battle", listPanel.root, renderList)
	State.Changed:Connect(renderList)

	-- サーバーからのメッセージは届いた順に1つずつ再生する
	Remotes.event("BattleState").OnClientEvent:Connect(function(msg)
		if type(msg) ~= "table" then
			return
		end
		table.insert(queue, msg)
		if playing then
			return
		end
		playing = true
		task.spawn(function()
			while #queue > 0 do
				handle(table.remove(queue, 1))
			end
			playing = false
		end)
	end)
end

return BattleUI
