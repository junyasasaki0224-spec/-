--!strict
-- 対戦: 相手を選ぶ画面(妖怪退治 / ボス戦 / オンライン対戦 のタブ)と、水の中のバトル画面。
-- 画面はサーバーから届いたイベントを順番に再生するだけ(ダメージや勝敗はサーバーが決める)。
-- バトル画面は3種類で共通: 妖怪退治(コンピューター)・対戦(人 / ほかのサーバーのチームの写し)・ボス戦(協力)
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Locale = require(Shared.Locale)
local Format = require(Shared.Lib.Format)
local Remotes = require(Shared.Lib.Remotes)
local FishBuilder = require(Shared.Lib.FishBuilder)
local BattleLib = require(Shared.Lib.Battle)
local WorldClock = require(Shared.Lib.WorldClock)

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local Root = require(script.Parent.Parent.UI.Root)
local State = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Input)
local Sound = require(script.Parent.Sound)
local Cry = require(script.Parent.Cry)
local Music = require(script.Parent.Music)
local Online = require(script.Parent.Online)
local BattleScene = require(script.Parent.BattleScene)
local BattleAdvice = require(Shared.Lib.BattleAdvice)
local C = Theme.Colors

local B = Config.Battle
local O = Config.Online
local player = Players.LocalPlayer
local BattleUI = {}

local TABS = { "trainers", "boss", "online" }
local TAB_ICON = { trainers = "👹", boss = "🐲", online = "⚔" }

local gui: ScreenGui
local listPanel: Kit.Panel
local teamBar: Frame
local tab = "trainers"
local tabButtons: { [string]: TextButton } = {}
local pages: { [string]: ScrollingFrame } = {}
local roomDot: Frame

-- バトル画面
local screen: Frame? = nil
local view: any = nil -- 画面の部品
local current: any = nil -- サーバーから届いた最新の状態
local trainer: any = nil
local busy = false
local actionRemote: RemoteEvent

local mode = "trainer" -- "trainer" / "pvp" / "raid"
local opponent: any = nil -- 対戦の相手 { name, title, rating } / { ghost = true, ... }
local boss: any = nil -- ボス戦のボス(Config.Bosses の行)
local raidInfo: any = nil
local raidInfoAt = 0
local deadline: number? = nil -- 対戦で技を選ぶ期限(届いた時刻 + 秒数)
local chosen = false -- 対戦で選び終わって相手を待っている
local confirmUntil = 0 -- 降参/抜ける の確認(もう一度押す)
local resultShown = false

local function name(def: any): string
	return if def then Locale.fishName(def) else "?"
end

local function sideName(side: string, fishId: string): string
	local n = name(Config.FishById[fishId])
	return if side == "enemy" then Locale.t("battle_foe", { name = n }) else n
end

local function today(): number
	return WorldClock.dayIndex(
		math.floor(workspace:GetServerTimeNow()),
		Config.Tuning.Quests.dayOffsetSeconds
	)
end

local function teamMaxLevel(p: any): number
	local best = 0
	for _, uid in p.team do
		for _, f in p.partners do
			if f.uid == uid then
				best = math.max(best, f.level)
			end
		end
	end
	return best
end

-- 相手を選ぶ画面 ------------------------------------------------------------------
local teamKey = ""

local function renderTeamBar(p: any)
	-- 中身が変わった時だけ作り直す(毎秒の更新でボタンが作り直されないように)
	local parts = { Locale.get() }
	for _, uid in p.team do
		for _, f in p.partners do
			if f.uid == uid then
				table.insert(parts, ("%s:%d"):format(f.fishId, f.level))
			end
		end
	end
	local key = table.concat(parts, ",")
	if key == teamKey then
		return
	end
	teamKey = key
	Kit.clear(teamBar)
	Kit.label({
		Size = UDim2.new(0.16, 0, 1, 0),
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
	Kit.button({
		Text = Locale.t("battle_chart"),
		Size = UDim2.new(0.14, 0, 1, -6),
		Color = C.indigo,
		MaxTextSize = 16,
		LayoutOrder = 10,
		Parent = teamBar,
	}, function()
		BattleUI.showChart(listPanel.root)
	end)
end

local function renderTrainers(p: any)
	local listFrame = pages.trainers
	Kit.clear(listFrame)
	local day = today()
	for i, t in Config.Trainers do
		local cleared = p.battle.cleared[t.id] == true
		local unlocked = i == 1 or p.battle.cleared[Config.Trainers[i - 1].id] == true
		local row = Kit.row(listFrame, 92, i)
		Kit.label({
			Size = UDim2.new(0.5, 0, 0, 30),
			Position = UDim2.fromOffset(14, 6),
			Text = (if cleared then "○ " elseif not unlocked then "🔒 " else "")
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
		-- 再戦の小判は相手ごとに1日1回。もらった日は「受け取り済み」と先に見せる
		local paidToday = cleared and (p.battle.rematchPaid or {})[t.id] == day
		local coins = if cleared then math.floor(t.reward.coins * B.RematchCoinRate) else t.reward.coins
		local text = if paidToday
			then Locale.t("battle_rematch_paid")
			else "¥ " .. Format.coins(coins, Locale.get()) .. (if t.title and not cleared
				then "  +「" .. Locale.t("title_" .. t.title) .. "」"
				else "")
		Kit.label({
			Size = UDim2.new(0.62, 0, 0, 20),
			Position = UDim2.fromOffset(14, 62),
			Text = text,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = if paidToday then C.textDim else C.goldLight,
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

-- ボス戦のタブ(部品は一度だけ作って、中身だけ書き換える。毎秒の残り時間を出すため)
type BossRow = { rec: TextLabel, reward: TextLabel, roomLine: TextLabel, button: TextButton }
local bossRows: { [string]: BossRow } = {}
local bossRules: TextLabel
local myRoom: any = {}

local function buildBossPage()
	local page = pages.boss
	bossRules = Kit.label({
		Size = UDim2.new(1, 0, 0, 40),
		TextWrapped = true,
		TextColor3 = C.textDim,
		Font = Theme.Fonts.body,
		MaxTextSize = 15,
		LayoutOrder = 0,
		Parent = page,
	})
	-- 自分がいる部屋
	local card = Kit.row(page, 118, 1)
	card.BackgroundColor3 = C.jadeDark
	Kit.stroke(card, C.goldLight, 2)
	myRoom.card = card
	myRoom.title = Kit.label({
		Size = UDim2.new(1, -250, 0, 28),
		Position = UDim2.fromOffset(14, 8),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Fonts.title,
		MaxTextSize = 21,
		Parent = card,
	})
	myRoom.status = Kit.label({
		Size = UDim2.new(1, -250, 0, 20),
		Position = UDim2.fromOffset(14, 38),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.goldLight,
		MaxTextSize = 16,
		Parent = card,
	})
	myRoom.members = Kit.new("Frame", {
		Size = UDim2.new(1, -250, 0, 40),
		Position = UDim2.fromOffset(14, 66),
		BackgroundTransparency = 1,
		Parent = card,
	})
	Kit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = myRoom.members,
	})
	myRoom.start = Kit.button({
		Text = Locale.t("boss_start"),
		Size = UDim2.fromOffset(110, 52),
		Position = UDim2.new(1, -132, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Color = C.vermilion,
		MaxTextSize = 20,
		Parent = card,
	}, function()
		State.request("raidStart")
	end)
	myRoom.leave = Kit.button({
		Text = Locale.t("boss_leave"),
		Size = UDim2.fromOffset(110, 52),
		Position = UDim2.new(1, -12, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Color = C.panelDark,
		MaxTextSize = 20,
		Parent = card,
	}, function()
		State.request("raidLeave")
	end)

	for i, bs in Config.Bosses do
		local def = Config.FishById[bs.fish]
		local row = Kit.row(page, 140, 10 + i)
		local frame = Kit.new("Frame", {
			Size = UDim2.fromOffset(116, 116),
			Position = UDim2.fromOffset(12, 12),
			BackgroundColor3 = C.panelDark,
			Parent = row,
		})
		Kit.corner(frame, Theme.Corner)
		Kit.stroke(frame, Color3.fromHex(Config.ElementById[def.element].color), 2, 0.2)
		local ok, model = pcall(FishBuilder.build, def, {})
		Kit.viewport(frame, if ok then model else nil)
		Kit.label({
			Size = UDim2.new(1, -330, 0, 30),
			Position = UDim2.fromOffset(142, 8),
			Text = ("%s %s  Lv%d"):format(
				Config.ElementById[def.element].icon,
				if Locale.get() == "ja" then bs.ja else bs.en,
				bs.level
			),
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Theme.Fonts.title,
			MaxTextSize = 22,
			Parent = row,
		})
		Kit.label({
			Size = UDim2.new(1, -330, 0, 34),
			Position = UDim2.fromOffset(142, 38),
			Text = if Locale.get() == "ja" then bs.jaDesc else bs.enDesc,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			TextColor3 = C.textDim,
			Font = Theme.Fonts.body,
			MaxTextSize = 14,
			Parent = row,
		})
		local function line(y: number, color: Color3): TextLabel
			return Kit.label({
				Size = UDim2.new(1, -330, 0, 20),
				Position = UDim2.fromOffset(142, y),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = color,
				MaxTextSize = 15,
				Parent = row,
			})
		end
		local id = bs.id
		bossRows[id] = {
			rec = line(74, C.success),
			reward = line(95, C.goldLight),
			roomLine = line(116, C.success),
			button = Kit.button({
				Size = UDim2.fromOffset(170, 56),
				Position = UDim2.new(1, -14, 0.5, 0),
				AnchorPoint = Vector2.new(1, 0.5),
				Color = C.vermilion,
				MaxTextSize = 20,
				Parent = row,
			}, function()
				local room = Online.roomFor(id)
				if room then
					State.request("raidJoin", room.id)
				else
					State.request("raidCreate", id)
				end
			end),
		}
	end
end

local function renderBoss(p: any)
	bossRules.Text = Locale.t("boss_rules", { max = O.RaidPartyMax, min = math.floor(O.RaidSeconds / 60) })
	local mine = Online.myRoom()
	myRoom.card.Visible = mine ~= nil
	if mine then
		local host = mine.hostId == player.UserId
		myRoom.title.Text = "🐲 " .. Online.bossName(mine.bossId)
		myRoom.status.Text =
			Locale.t("boss_my_room", { n = #mine.members, max = mine.max, s = Online.roomSecondsLeft(mine) })
		myRoom.start.Visible = host
		local key = table.concat(
			(function()
				local ids = {}
				for _, m in mine.members do
					table.insert(ids, tostring(m.userId))
				end
				return ids
			end)(),
			","
		)
		if myRoom.membersKey ~= key then
			myRoom.membersKey = key
			Kit.clear(myRoom.members)
			for i, m in mine.members do
				local chip = Kit.new("Frame", {
					Size = UDim2.fromOffset(150, 36),
					BackgroundColor3 = C.panel,
					BackgroundTransparency = 0.2,
					LayoutOrder = i,
					Parent = myRoom.members,
				})
				Kit.corner(chip, UDim.new(1, 0))
				Online.avatar(chip, m.userId, 32, { Position = UDim2.fromOffset(2, 2) })
				Kit.label({
					Size = UDim2.new(1, -44, 1, -8),
					Position = UDim2.fromOffset(40, 4),
					Text = (if m.userId == mine.hostId then "★ " else "") .. tostring(m.name),
					TextXAlignment = Enum.TextXAlignment.Left,
					MaxTextSize = 15,
					Parent = chip,
				})
			end
		end
	end

	local best = teamMaxLevel(p)
	local day = today()
	local hasTeam = #p.team > 0 and #p.partners > 0
	for _, bs in Config.Bosses do
		local r = bossRows[bs.id]
		if best >= bs.recommend then
			r.rec.Text = Locale.t("boss_team_ok", { lv = bs.recommend })
			r.rec.TextColor3 = C.success
		else
			r.rec.Text = Locale.t("boss_team_low", { lv = bs.recommend, mine = best })
			r.rec.TextColor3 = C.goldLight
		end
		local clears = (p.raid and p.raid.clears[bs.id]) or 0
		local paid = p.raid and p.raid.paid[bs.id] == day
		local reward = if paid
			then Locale.t("boss_paid")
			else Locale.t("boss_reward", { coins = Format.coins(bs.reward.coins, Locale.get()) })
				.. (
					if bs.reward.bait
						then "  + " .. Locale.t("bait_" .. bs.reward.bait.id) .. " ×" .. bs.reward.bait.amount
						else ""
				)
		r.reward.Text = reward
			.. (if clears > 0 then "   · " .. Locale.t("boss_clears", { n = clears }) else "")
		r.reward.TextColor3 = if paid then C.textDim else C.goldLight

		local room = Online.roomFor(bs.id)
		r.roomLine.Visible = room ~= nil and mine == nil
		if room then
			local hostName = "?"
			for _, m in room.members do
				if m.userId == room.hostId then
					hostName = tostring(m.name)
				end
			end
			r.roomLine.Text = Locale.t(
				"boss_room_line",
				{ host = hostName, n = #room.members, max = room.max, s = Online.roomSecondsLeft(room) }
			)
		end
		if mine then
			r.button.Text = Locale.t(if mine.bossId == bs.id then "boss_in_room" else "boss_create")
			Kit.setEnabled(r.button, false)
		elseif room then
			r.button.Text = Locale.t("boss_join_n", { n = #room.members, max = room.max })
			Kit.setEnabled(r.button, hasTeam, C.jade)
		else
			r.button.Text = Locale.t("boss_create")
			Kit.setEnabled(r.button, hasTeam, C.vermilion)
		end
	end
end

-- オンライン対戦のタブ
local onl: any = {}

local function buildOnlinePage()
	local page = pages.online
	local card = Kit.row(page, 116, 1)
	onl.ratingCaption = Kit.label({
		Size = UDim2.fromOffset(180, 22),
		Position = UDim2.fromOffset(20, 10),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.textDim,
		MaxTextSize = 16,
		Parent = card,
	})
	onl.rating = Kit.label({
		Size = UDim2.fromOffset(180, 64),
		Position = UDim2.fromOffset(20, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.goldLight,
		Font = Theme.Fonts.title,
		MaxTextSize = 52,
		Parent = card,
	})
	onl.record = Kit.label({
		Size = UDim2.new(1, -240, 0, 30),
		Position = UDim2.fromOffset(220, 24),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Fonts.title,
		MaxTextSize = 24,
		Parent = card,
	})
	onl.daily = Kit.label({
		Size = UDim2.new(1, -240, 0, 24),
		Position = UDim2.fromOffset(220, 62),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 17,
		Parent = card,
	})

	-- ランダム対戦(押すと「さがしています」に変わる。探している間も釣りはできる)
	local holder = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 70),
		BackgroundTransparency = 1,
		LayoutOrder = 2,
		Parent = page,
	})
	onl.random = Kit.button({
		Size = UDim2.fromScale(1, 1),
		Color = C.vermilion,
		MaxTextSize = 28,
		Parent = holder,
	}, function()
		State.request("pvpQueue")
	end)
	local searching = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.panelDark,
		Visible = false,
		Parent = holder,
	})
	Kit.corner(searching, Theme.CornerSmall)
	Kit.stroke(searching, C.vermilion, 2)
	onl.searching = searching
	onl.searchText = Kit.label({
		Size = UDim2.new(1, -170, 1, -16),
		Position = UDim2.fromOffset(20, 8),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 22,
		Parent = searching,
	})
	onl.cancel = Kit.button({
		Size = UDim2.fromOffset(130, 50),
		Position = UDim2.new(1, -10, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Color = C.panelLight,
		MaxTextSize = 20,
		Parent = searching,
	}, function()
		State.request("pvpCancel")
	end)

	onl.friends = Kit.button({
		Size = UDim2.new(1, 0, 0, 56),
		Color = C.indigo,
		MaxTextSize = 22,
		LayoutOrder = 3,
		Parent = page,
	}, function()
		Root.open("social")
	end)
	onl.pref = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		LayoutOrder = 4,
		Parent = page,
	})
	onl.rules = Kit.label({
		Size = UDim2.new(1, 0, 0, 52),
		TextWrapped = true,
		TextColor3 = C.textDim,
		Font = Theme.Fonts.body,
		MaxTextSize = 15,
		LayoutOrder = 5,
		Parent = page,
	})
end

local function renderOnline(p: any)
	local pv = p.pvp or { rating = O.RatingStart, wins = 0, losses = 0, dailyWinDay = -1 }
	onl.ratingCaption.Text = Locale.t("pvp_rating")
	onl.rating.Text = tostring(pv.rating)
	onl.record.Text = Locale.t("pvp_record", { w = pv.wins, l = pv.losses })
	if pv.dailyWinDay == today() then
		onl.daily.Text = Locale.t("pvp_daily_done")
		onl.daily.TextColor3 = C.textDim
	else
		onl.daily.Text = Locale.t("pvp_daily_ready", { coins = Format.coins(O.DailyWinCoins, Locale.get()) })
		onl.daily.TextColor3 = C.goldLight
	end
	local q = Online.queue
	onl.random.Text = Locale.t("pvp_random")
	onl.random.Visible = q.state == "idle"
	Kit.setEnabled(onl.random, #p.team > 0 and Online.myRoom() == nil, C.vermilion)
	onl.searching.Visible = q.state ~= "idle"
	onl.searchText.Text = if q.state == "ghost"
		then Locale.t("pvp_searching_ghost")
		else Locale.t("pvp_searching", { t = Format.time(os.clock() - q.since) })
	onl.cancel.Text = Locale.t("pvp_cancel")
	onl.friends.Text = Locale.t("pvp_friends")
	onl.rules.Text = Locale.t("pvp_rules")
	if not onl.prefBuilt or onl.prefLang ~= Locale.get() then
		onl.prefBuilt = true
		onl.prefLang = Locale.get()
		Kit.clear(onl.pref)
		Online.prefControl(onl.pref)
	end
end

local function render()
	if not listPanel.root.Visible or not State.profile then
		return
	end
	local p = State.profile
	listPanel.title.Text = Locale.t("hud_battle")
	for _, id in TABS do
		local b = tabButtons[id]
		local on = id == tab
		b.Text = TAB_ICON[id] .. " " .. Locale.t("tab_" .. id)
		b.BackgroundColor3 = if on then C.vermilion else C.panelLight
		b.TextColor3 = if on then C.text else C.textDim
		pages[id].Visible = on
	end
	-- 入れるボス戦の部屋があればタブに点
	roomDot.Visible = tab ~= "boss" and #Online.rooms > 0
	renderTeamBar(p)
	if tab == "trainers" then
		renderTrainers(p)
	elseif tab == "boss" then
		renderBoss(p)
	else
		renderOnline(p)
	end
end

local function selectTab(id: string)
	if table.find(TABS, id) then
		tab = id
	end
	render()
end

-- バトル画面 ---------------------------------------------------------------------
-- 水の中の舞台(BattleScene)の上に、上の左右に体力の札・真ん中に手番/残り時間の丸・下に技のお札を並べる
local PAPER = Color3.fromRGB(246, 238, 220)
local INK = Color3.fromRGB(44, 32, 26)
local PAPER_DIM = Color3.fromRGB(176, 168, 152)
local scene: any = nil

local function hpColor(r: number): Color3
	return if r > 0.5 then C.success elseif r > 0.2 then C.goldLight else C.danger
end

local function elementOf(id: string?): any
	return (id and Config.ElementById[id]) or Config.ElementById.none
end

local function otherSide(side: string): string
	return if side == "player" then "enemy" else "player"
end

-- 体力の札(左 = 自分、右 = 相手。左右対称)
local function makePlate(parent: Instance, side: string)
	local right = side == "enemy"
	local function at(x: number, y: number): UDim2
		return if right then UDim2.new(1, -x, 0, y) else UDim2.fromOffset(x, y)
	end
	local anchor = Vector2.new(if right then 1 else 0, 0)
	local anchorOther = Vector2.new(if right then 0 else 1, 0)
	local near = if right then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left
	local far = if right then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right
	local plate = Kit.new("Frame", {
		Name = side .. "Plate",
		Size = UDim2.fromOffset(440, 86),
		Position = at(24, 16),
		AnchorPoint = anchor,
		BackgroundColor3 = C.panelDark,
		BackgroundTransparency = 0.25,
		ZIndex = 2,
		Parent = parent,
	})
	Kit.corner(plate, UDim.new(0, 16))
	Kit.stroke(plate, C.gold, 2, 0.35)
	local title = Kit.label({
		Size = UDim2.new(1, -130, 0, 30),
		Position = at(16, 8),
		AnchorPoint = anchor,
		TextXAlignment = near,
		Font = Theme.Fonts.title,
		MaxTextSize = 22,
		Parent = plate,
	})
	local level = Kit.label({
		Size = UDim2.fromOffset(90, 26),
		Position = if right then UDim2.fromOffset(16, 10) else UDim2.new(1, -16, 0, 10),
		AnchorPoint = anchorOther,
		TextXAlignment = far,
		TextColor3 = C.goldLight,
		MaxTextSize = 20,
		Parent = plate,
	})
	local bg, fill = Kit.bar(plate, C.success)
	bg.Size = UDim2.new(1, -32, 0, 14)
	bg.Position = UDim2.fromOffset(16, 44)
	if right then -- 相手の体力は右から減る
		fill.AnchorPoint = Vector2.new(1, 0)
		fill.Position = UDim2.fromScale(1, 0)
	end
	local hpText = Kit.label({
		Size = UDim2.fromOffset(180, 20),
		Position = if right then UDim2.fromOffset(16, 62) else UDim2.new(1, -16, 0, 62),
		AnchorPoint = anchorOther,
		TextXAlignment = far,
		TextColor3 = C.textDim,
		MaxTextSize = 16,
		Parent = plate,
	})
	local beads = Kit.new("Frame", {
		Size = UDim2.fromOffset(160, 16),
		Position = at(16, 64),
		AnchorPoint = anchor,
		BackgroundTransparency = 1,
		Parent = plate,
	})
	Kit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = if right then Enum.HorizontalAlignment.Right else Enum.HorizontalAlignment.Left,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = beads,
	})
	return { frame = plate, title = title, level = level, fill = fill, hpText = hpText, beads = beads }
end

local function updatePlate(card: any, side: any)
	local f = side.team[side.active]
	local def = Config.FishById[f.fishId]
	card.title.Text = elementOf(f.element).icon .. " " .. name(def)
	card.level.Text = "Lv " .. f.level
	local r = f.hp / math.max(1, f.maxHp)
	TweenService:Create(
		card.fill,
		TweenInfo.new(0.35),
		{ Size = UDim2.fromScale(math.clamp(r, 0, 1), 1), BackgroundColor3 = hpColor(r) }
	):Play()
	card.hpText.Text = ("%s / %s"):format(
		Format.coins(f.hp, Locale.get()),
		Format.coins(f.maxHp, Locale.get())
	)
	-- チームの玉(属性の色。倒れた子は灰色、今出ている子は金の縁)
	Kit.clear(card.beads)
	for i, m in side.team do
		local d = Kit.new("Frame", {
			Size = UDim2.fromOffset(14, 14),
			BackgroundColor3 = if m.hp > 0 then Color3.fromHex(elementOf(m.element).color) else C.disabled,
			LayoutOrder = i,
			Parent = card.beads,
		})
		Kit.corner(d, UDim.new(1, 0))
		if i == side.active then
			Kit.stroke(d, C.goldLight, 2)
		end
	end
end

-- バトルの速さ(×1 / ×2)と画面の揺れ(設定に保存)
local function battleSpeed(): number
	local p = State.profile
	local v = p and p.settings and p.settings.battleSpeed
	return if v == 2 then 2 else 1
end

local function shakeOn(): boolean
	local p = State.profile
	return not (p and p.settings and p.settings.battleShake == false)
end

-- 演出の待ち時間(2倍速なら半分)
local function pause(t: number)
	task.wait(t / battleSpeed())
end

local autoOn = false -- おまかせ(このバトルの間だけ)
local autoToken = 0
local useCard: (i: number) -> () -- 下で決める(お札を使う)

local function setMessage(text: string)
	if view then
		view.message.Text = text
	end
end

-- 魚が鳴く(場に出た時。倒れた時は低く・ゆっくり)
local function cry(side: string, fishId: string, fainted: boolean?)
	if not scene then
		return
	end
	local opts = if fainted then { pitch = 0.78, volume = 0.6 } else { volume = 0.75 }
	Cry.say(fishId, scene:tag(side), UDim2.new(1, 30, 0, -20), opts)
end

local function runLabel(): string
	return Locale.t(
		if mode == "pvp" then "pvp_forfeit" elseif mode == "raid" then "raid_leave" else "battle_run"
	)
end

-- 技・交代は「選べる時」だけ。ボス戦の「抜ける」は相棒が全員倒れて見守っている間も押せる
local function setCommandsEnabled(on: boolean)
	if not view then
		return
	end
	for _, card in view.cards do
		-- 押せない間は、灰色ではなく「古びた紙」に(演出のたびに暗くならないように)
		local ok = on and card.button:GetAttribute("HasMove") == true
		card.button:SetAttribute("Disabled", not ok)
		card.button.BackgroundColor3 = if ok then PAPER else PAPER_DIM
		card.name.TextTransparency = if ok then 0 else 0.35
	end
	Kit.setEnabled(view.switchButton, on, C.indigo)
	local runOn = on or (mode == "raid" and not busy and current ~= nil and not resultShown)
	if os.clock() >= confirmUntil then
		view.runButton.Text = runLabel()
		Kit.setEnabled(view.runButton, runOn, C.panelDark)
	end
end

-- お札(技)の中身: 属性の帯・技の名前・威力・相手への効き目
local function refreshCommands()
	if not view or not current then
		return
	end
	local me = current.player
	local f = me.team[me.active]
	local foe = current.enemy.team[current.enemy.active]
	for i, card in view.cards do
		local id = me.moves and me.moves[i]
		local mv = id and Config.MoveById[id]
		card.button:SetAttribute("HasMove", mv ~= nil)
		card.button:SetAttribute("Chosen", nil)
		if mv then
			local elId = BattleLib.moveElement(mv, f)
			local el = elementOf(elId)
			local color = Color3.fromHex(el.color)
			card.band.BackgroundColor3 = color
			card.bandLabel.Text = el.icon .. " " .. Locale.t("element_" .. el.id)
			card.name.Text = if Locale.get() == "ja" then mv.ja else mv.en
			card.footer.Text = if mv.power > 0
				then Locale.t("card_power", { n = mv.power })
				else Locale.t("card_support")
			card.stroke.Color = color
			card.stroke.Thickness = 3
			local eff = if mv.power > 0 and foe then BattleLib.effectiveness(elId, foe.element) else 1
			card.eff.Visible = eff ~= 1
			card.eff.Text = Locale.t(if eff > 1 then "card_good" else "card_bad")
			card.eff.BackgroundColor3 = if eff > 1 then C.jade else C.disabled
		else
			-- 空きの札: 次にレベルいくつで技を覚えるかを見せる
			card.band.BackgroundColor3 = C.disabled
			card.bandLabel.Text = ""
			local def = f and Config.FishById[f.fishId]
			local _, at = if def then BattleLib.nextMove(def, f.level) else nil
			local firstEmpty = i == #(me.moves or {}) + 1
			card.name.Text = if at and firstEmpty then "🔒" else "—"
			card.footer.Text = if at and firstEmpty then Locale.t("card_unlock_at", { lv = at }) else ""
			card.stroke.Thickness = 0
			card.eff.Visible = false
		end
	end
	local canAct = not busy and not current.over and not chosen
	setCommandsEnabled(canAct)
	-- ★ おすすめ(おまかせの時は、それを自動で使う)
	local suggested = if canAct then BattleAdvice.suggest(current) else nil
	for i, card in view.cards do
		card.star.Visible = suggested == i and not autoOn
	end
	if autoOn and canAct and suggested then
		autoToken += 1
		local token = autoToken
		task.delay(0.7 / battleSpeed(), function()
			if
				autoOn
				and token == autoToken
				and view
				and not busy
				and not chosen
				and current
				and not current.over
			then
				useCard(suggested)
			end
		end)
	end
end

local function applyState(st: any, noFish: boolean?)
	current = st
	if not view then
		return
	end
	for _, side in { "player", "enemy" } do
		local f = st[side].team[st[side].active]
		-- 演出で出し入れしているはずの魚が、何かの都合でいなければここで出す
		if not noFish and scene and f.hp > 0 and not scene:hasFish(side, f.fishId) then
			scene:setFish(side, f.fishId, f.mutation)
		end
	end
	updatePlate(view.playerPlate, st.player)
	updatePlate(view.enemyPlate, st.enemy)
	refreshCommands()
end

-- バトルの間は、ふだんの画面(小判・メニュー・スタンプなど)を隠す。お知らせと申し込みのカードは残す
local KEEP_DURING_BATTLE = { Toasts = true, OnlineCards = true, Battle = true }
local hiddenForBattle: { GuiObject } = {}

local disabledPrompts: { ProximityPrompt } = {}

-- バトルの間は、キャラクターを動かせないようにする(カメラは舞台にあるので、見えないまま歩いてしまう。
-- スマホでは、スティックとジャンプボタンがバトルのボタンに重ならないように消える)
local function setControls(on: boolean)
	pcall(function()
		local scripts = player:FindFirstChild("PlayerScripts")
		local moduleScript = scripts and scripts:FindFirstChild("PlayerModule")
		if moduleScript and moduleScript:IsA("ModuleScript") then
			local controls = (require :: any)(moduleScript):GetControls()
			if on then
				controls:Enable()
			else
				controls:Disable()
			end
		end
	end)
end

local function hideWorldUi()
	for _, c in gui:GetChildren() do
		if c:IsA("GuiObject") and c.Visible ~= false and not KEEP_DURING_BATTLE[c.Name] then
			c.Visible = false
			table.insert(hiddenForBattle, c)
		end
	end
	-- キャラクターは世界に立ったままなので、近くの「調べる」ボタンがバトルの上に出ないよう止める(この画面だけ)
	for _, p in CollectionService:GetTagged("YokaiPrompt") do
		if p:IsA("ProximityPrompt") and p.Enabled then
			p.Enabled = false
			table.insert(disabledPrompts, p)
		end
	end
	Root.setLocked(true)
	setControls(false)
end

local function showWorldUi()
	Root.setLocked(false)
	if #hiddenForBattle > 0 then
		setControls(true)
	end
	for _, c in hiddenForBattle do
		c.Visible = true
	end
	table.clear(hiddenForBattle)
	for _, p in disabledPrompts do
		p.Enabled = true
	end
	table.clear(disabledPrompts)
end

local function closeScreen()
	showWorldUi()
	if scene then
		scene:destroy()
		scene = nil
	end
	Music.battle(false)
	if screen then
		screen:Destroy()
		screen = nil
	end
	view = nil
	current = nil
	busy = false
	chosen = false
	deadline = nil
	resultShown = false
	autoOn = false
	Input.setEnabled(true)
end

local function send(action: any)
	busy = true
	setCommandsEnabled(false)
	actionRemote:FireServer(action)
end

-- 対戦では、選んだら相手を待つ(コンピューターや写しが相手ならすぐ進む)
local function choose(action: any)
	if mode == "pvp" then
		chosen = true
		setMessage(Locale.t("pvp_waiting"))
	end
	send(action)
end

useCard = function(i: number)
	if not view or busy or chosen or not current or current.over then
		return
	end
	local card = view.cards[i]
	if not card or card.button:GetAttribute("HasMove") ~= true then
		return
	end
	choose({ kind = "move", index = i })
	card.button:SetAttribute("Chosen", true)
	card.stroke.Color = C.goldLight
	card.stroke.Thickness = 4
end

-- 交代: 下に相棒の札を並べて選ぶ
local function showSwitchPicker()
	if not view or not current or busy or chosen then
		return
	end
	local overlay = Kit.new("TextButton", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Text = "",
		ZIndex = 40,
		Parent = screen,
	})
	local box = Kit.new("Frame", {
		Size = UDim2.fromOffset(700, 190),
		Position = UDim2.new(0.5, 0, 1, -24),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = C.panel,
		ZIndex = 41,
		Parent = overlay,
	})
	Kit.corner(box)
	Kit.stroke(box, C.gold, 3)
	Kit.label({
		Size = UDim2.new(1, -24, 0, 30),
		Position = UDim2.fromOffset(12, 10),
		Text = Locale.t("battle_switch_title"),
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Fonts.title,
		MaxTextSize = 20,
		ZIndex = 42,
		Parent = box,
	})
	local row = Kit.new("Frame", {
		Size = UDim2.new(1, -24, 0, 120),
		Position = UDim2.fromOffset(12, 52),
		BackgroundTransparency = 1,
		ZIndex = 42,
		Parent = box,
	})
	Kit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 12),
		Parent = row,
	})
	for i, f in current.player.team do
		local def = Config.FishById[f.fishId]
		local ok = f.hp > 0 and i ~= current.player.active
		local color = Color3.fromHex(elementOf(f.element).color)
		local b = Kit.button({
			Text = ("%s %s\nLv%d   %d/%d"):format(
				elementOf(f.element).icon,
				name(def),
				f.level,
				f.hp,
				f.maxHp
			),
			Size = UDim2.fromOffset(210, 112),
			Color = color:Lerp(C.panel, 0.55),
			StrokeColor = color,
			MaxTextSize = 18,
			Parent = row,
		}, function()
			overlay:Destroy()
			if view and current and not busy and not chosen then
				choose({ kind = "switch", slot = i })
			end
		end)
		b.ZIndex = 43
		Kit.setEnabled(b, ok, color:Lerp(C.panel, 0.55))
	end
	overlay.Activated:Connect(function()
		overlay:Destroy()
	end)
end

-- 降参・抜けるは、間違えて押さないように「もう一度押す」で確定
local function onRun()
	if not view or not current or busy or resultShown then
		return
	end
	if mode ~= "trainer" and os.clock() >= confirmUntil then
		confirmUntil = os.clock() + 2.5
		view.runButton.Text = Locale.t(if mode == "pvp" then "pvp_forfeit_confirm" else "raid_leave_confirm")
		view.runButton.BackgroundColor3 = C.danger
		Sound.play("click", 0.4, 0.7)
		task.delay(2.6, function()
			if view and os.clock() >= confirmUntil then
				refreshCommands()
			end
		end)
		return
	end
	confirmUntil = 0
	if scene and mode ~= "raid" then
		scene:leave("player")
	end
	send({ kind = "run" })
end

-- ボス戦の仲間の札(与えたダメージ・倒れた人)
local function renderRaid()
	if not view or not view.raid or not raidInfo then
		return
	end
	local r = view.raid
	r.rage.Visible = raidInfo.enraged == true
	view.medallionStroke.Color = if raidInfo.enraged then C.danger else C.gold
	Kit.clear(r.party)
	for i, m in raidInfo.members or {} do
		local chip = Kit.new("Frame", {
			Size = UDim2.fromOffset(116, 42),
			BackgroundColor3 = if m.alive then C.panelLight else C.panelDark,
			BackgroundTransparency = 0.15,
			LayoutOrder = i,
			Parent = r.party,
		})
		Kit.corner(chip, UDim.new(0, 10))
		if m.userId == player.UserId then
			Kit.stroke(chip, C.goldLight, 2)
		end
		Online.avatar(
			chip,
			m.userId,
			34,
			{ Position = UDim2.fromOffset(4, 4), ImageTransparency = if m.alive then 0 else 0.6 }
		)
		Kit.label({
			Size = UDim2.new(1, -46, 0, 18),
			Position = UDim2.fromOffset(42, 3),
			Text = (if m.alive then "" else "💤 ") .. tostring(m.name),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = if m.alive then C.text else C.textDim,
			MaxTextSize = 14,
			Parent = chip,
		})
		Kit.label({
			Size = UDim2.new(1, -46, 0, 16),
			Position = UDim2.fromOffset(42, 22),
			Text = "⚔ " .. Format.coins(m.dealt or 0, Locale.get()),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = C.goldLight,
			MaxTextSize = 13,
			Parent = chip,
		})
	end
end

-- ボスの体力は全員で1本。減る一方なので、届いた中で一番新しい値(= 一番少ない値)に合わせる
local function syncBossHp()
	if mode ~= "raid" or not view or not current or not raidInfo or type(raidInfo.hp) ~= "number" then
		return
	end
	local b = current.enemy.team[1]
	if raidInfo.hp < b.hp then
		b.hp = raidInfo.hp
		updatePlate(view.enemyPlate, current.enemy)
	end
end

local function onRaidInfo(info: any)
	local wasEnraged = raidInfo and raidInfo.enraged
	raidInfo = info
	raidInfoAt = os.clock()
	if not view then
		return
	end
	renderRaid()
	-- ほかの人が削ったボスの体力をそろえる(自分の技の演出中は、終わった時にそろえる)
	if not busy then
		syncBossHp()
	end
	if info.enraged and not wasEnraged then
		if scene then
			scene:setEnraged(true)
		end
		Sound.play("fail", 0.6, 0.6)
		if not busy then
			setMessage(Locale.t("raid_enraged", { boss = Online.bossName(info.bossId) }))
		end
	end
end

-- 技のお札(1枚)
local function makeTalisman(parent: Instance, i: number)
	local b = Kit.button({
		Name = "Talisman" .. i,
		Text = "",
		Size = UDim2.fromOffset(168, 128),
		Color = PAPER,
		LayoutOrder = i,
		Corner = UDim.new(0, 10),
		Parent = parent,
	}, function()
		useCard(i)
	end)
	local stroke = b:FindFirstChildOfClass("UIStroke") :: UIStroke
	stroke.Thickness = 3
	stroke.Transparency = 0
	-- 上の帯(属性)。Kit.button の内側の余白(6)の外まで広げる
	local band = Kit.new("Frame", {
		Size = UDim2.new(1, 12, 0, 32),
		Position = UDim2.fromOffset(-6, -6),
		BackgroundColor3 = C.disabled,
		BorderSizePixel = 0,
		Parent = b,
	})
	Kit.corner(band, UDim.new(0, 10))
	local bandLabel = Kit.label({
		Size = UDim2.new(1, -16, 1, -8),
		Position = UDim2.fromOffset(8, 4),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 16,
		Parent = band,
	})
	Kit.new(
		"UIStroke",
		{ Color = Color3.fromRGB(30, 20, 20), Thickness = 1.5, Transparency = 0.4, Parent = bandLabel }
	)
	local nameLabel = Kit.label({
		Size = UDim2.new(1, 0, 0, 50),
		Position = UDim2.fromOffset(0, 32),
		TextColor3 = INK,
		Font = Theme.Fonts.title,
		TextWrapped = true,
		MaxTextSize = 22,
		Parent = b,
	})
	local footer = Kit.label({
		Size = UDim2.new(1, -30, 0, 18),
		Position = UDim2.new(0, 2, 1, -18),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(110, 92, 80),
		MaxTextSize = 14,
		Parent = b,
	})
	-- 判子(キーボードの 1〜4)
	local hanko = Kit.label({
		Size = UDim2.fromOffset(24, 24),
		Position = UDim2.new(1, 2, 1, 2),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 0,
		BackgroundColor3 = C.vermilion,
		Text = tostring(i),
		Font = Theme.Fonts.title,
		MaxTextSize = 14,
		Parent = b,
	})
	Kit.corner(hanko, UDim.new(1, 0))
	-- 相手への効き目(帯の右端)
	local eff = Kit.label({
		Size = UDim2.fromOffset(84, 20),
		Position = UDim2.new(1, 2, 0, -1),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 0,
		BackgroundColor3 = C.jade,
		MaxTextSize = 13,
		Visible = false,
		ZIndex = 3,
		Parent = b,
	})
	Kit.corner(eff, UDim.new(1, 0))
	-- ★ おすすめ(お札の上に小さな札)
	local star = Kit.label({
		Size = UDim2.fromOffset(112, 22),
		Position = UDim2.new(0.5, 0, 0, -34),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 0,
		BackgroundColor3 = C.goldLight,
		TextColor3 = INK,
		Text = Locale.t("card_suggest"),
		Font = Theme.Fonts.title,
		MaxTextSize = 14,
		Visible = false,
		ZIndex = 4,
		Parent = b,
	})
	Kit.corner(star, UDim.new(1, 0))
	return {
		star = star,
		button = b,
		stroke = stroke,
		band = band,
		bandLabel = bandLabel,
		name = nameLabel,
		footer = footer,
		eff = eff,
	}
end

-- 相性表(どの属性が、どの属性に強いか)
local ELEMENTS = { "water", "fire", "earth", "thunder", "spirit" }
local function showChart(parent: Instance)
	local overlay = Kit.new("TextButton", {
		Name = "Chart",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		Text = "",
		ZIndex = 60,
		Parent = parent,
	})
	local box = Kit.new("Frame", {
		Size = UDim2.fromOffset(560, 470),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.panel,
		ZIndex = 61,
		Parent = overlay,
	})
	Kit.corner(box)
	Kit.stroke(box, C.gold, 3)
	Kit.label({
		Size = UDim2.new(1, -24, 0, 30),
		Position = UDim2.fromOffset(12, 10),
		Text = Locale.t("chart_title"),
		Font = Theme.Fonts.title,
		MaxTextSize = 22,
		ZIndex = 62,
		Parent = box,
	})
	local grid = Kit.new("Frame", {
		Size = UDim2.fromOffset(6 * 72, 6 * 50),
		Position = UDim2.new(0.5, 0, 0, 50),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		ZIndex = 62,
		Parent = box,
	})
	Kit.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(68, 46),
		CellPadding = UDim2.fromOffset(4, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	local order = 0
	local function cell(text: string, color: Color3, bg: Color3?, size: number?)
		order += 1
		local l = Kit.label({
			Text = text,
			TextColor3 = color,
			BackgroundTransparency = if bg then 0 else 1,
			BackgroundColor3 = bg or C.panel,
			Font = Theme.Fonts.title,
			MaxTextSize = size or 22,
			LayoutOrder = order,
			ZIndex = 63,
			Parent = grid,
		})
		if bg then
			Kit.corner(l, Theme.CornerSmall)
		end
	end
	-- 1行目: 守る側の属性 / 1列目: 技の属性
	cell(Locale.t("chart_corner"), C.textDim, nil, 13)
	for _, d in ELEMENTS do
		cell(elementOf(d).icon, C.text)
	end
	for _, a in ELEMENTS do
		cell(elementOf(a).icon .. " " .. Locale.t("element_" .. a), C.text, nil, 16)
		for _, d in ELEMENTS do
			local m = BattleLib.effectiveness(a, d)
			if m > 1 then
				cell("◎", C.text, C.jade)
			elseif m < 1 then
				cell("△", C.textDim, C.disabled)
			else
				cell("", C.text, C.panelLight)
			end
		end
	end
	Kit.label({
		Size = UDim2.new(1, -40, 0, 24),
		Position = UDim2.new(0, 20, 1, -70),
		Text = Locale.t("chart_legend"),
		TextColor3 = C.goldLight,
		MaxTextSize = 16,
		ZIndex = 62,
		Parent = box,
	})
	Kit.label({
		Size = UDim2.new(1, -40, 0, 22),
		Position = UDim2.new(0, 20, 1, -40),
		Text = Locale.t("chart_cycle"),
		TextColor3 = C.textDim,
		MaxTextSize = 15,
		ZIndex = 62,
		Parent = box,
	})
	overlay.Activated:Connect(function()
		overlay:Destroy()
	end)
	return overlay
end
BattleUI.showChart = showChart

-- 体力の札の下の小さなボタン: 速さ・おまかせ・相性表
local function makeToolbar(parent: Instance): any
	local row = Kit.new("Frame", {
		Size = UDim2.fromOffset(380, 34),
		Position = UDim2.fromOffset(24, 110),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = parent,
	})
	Kit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	local tools: any = {}
	local function paint()
		tools.speed.Text = Locale.t("battle_speed", { n = battleSpeed() })
		tools.speed.BackgroundColor3 = if battleSpeed() == 2 then C.jade else C.panelDark
		tools.auto.BackgroundColor3 = if autoOn then C.jade else C.panelDark
	end
	tools.speed = Kit.button({
		Size = UDim2.fromOffset(104, 34),
		Color = C.panelDark,
		MaxTextSize = 15,
		LayoutOrder = 1,
		Parent = row,
	}, function()
		local nextSpeed = if battleSpeed() == 2 then 1 else 2
		if State.profile then
			State.profile.settings.battleSpeed = nextSpeed -- すぐ反映(本当の値はサーバーに保存)
		end
		State.request("setBattlePrefs", { speed = nextSpeed })
		if scene then
			scene:setSpeed(nextSpeed)
		end
		paint()
	end)
	tools.auto = Kit.button({
		Text = Locale.t("battle_auto"),
		Size = UDim2.fromOffset(132, 34),
		Color = C.panelDark,
		MaxTextSize = 15,
		LayoutOrder = 2,
		Parent = row,
	}, function()
		autoOn = not autoOn
		paint()
		refreshCommands()
	end)
	tools.chart = Kit.button({
		Text = Locale.t("battle_chart"),
		Size = UDim2.fromOffset(104, 34),
		Color = C.panelDark,
		MaxTextSize = 15,
		LayoutOrder = 3,
		Parent = row,
	}, function()
		if screen then
			showChart(screen)
		end
	end)
	paint()
	return tools
end

local function openScreen()
	closeScreen()
	Root.close()
	Input.setEnabled(false)
	hideWorldUi()
	local s = Kit.new("Frame", {
		Name = "Battle",
		Active = true, -- 下の HUD のボタンを押せないようにする
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1, -- 後ろは3Dの水の中(カメラごと移る)
		ZIndex = 30,
		Parent = gui,
	})
	screen = s
	scene = BattleScene.new(s, { boss = mode == "raid" })
	Music.battle(true, mode == "raid" or (trainer ~= nil and trainer.boss == true))
	scene:setSpeed(battleSpeed())
	scene:setShake(shakeOn())

	local v: any = {}
	-- 上の段(体力の札・丸・名前・仲間)。Roblox の上のバーに重ならないよう、まとめて下げる
	local top = Kit.new("Frame", {
		Name = "Top",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromOffset(0, Root.topShift(10)),
		BackgroundTransparency = 1,
		ZIndex = 2,
		Parent = s,
	})
	v.playerPlate = makePlate(top, "player")
	v.enemyPlate = makePlate(top, "enemy")
	v.tools = makeToolbar(top)

	-- 真ん中の丸(手番 / 対戦の残り秒 / ボス戦の残り時間)
	local medal = Kit.new("Frame", {
		Size = UDim2.fromOffset(96, 96),
		Position = UDim2.new(0.5, 0, 0, 10),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.1,
		ZIndex = 2,
		Parent = top,
	})
	Kit.corner(medal, UDim.new(1, 0))
	v.medallionStroke = Kit.stroke(medal, C.gold, 3, 0.1)
	v.medalCaption = Kit.label({
		Size = UDim2.new(1, -20, 0, 18),
		Position = UDim2.fromOffset(10, 14),
		TextColor3 = C.textDim,
		MaxTextSize = 14,
		Parent = medal,
	})
	v.medalValue = Kit.label({
		Size = UDim2.new(1, -14, 0, 44),
		Position = UDim2.fromOffset(7, 34),
		Font = Theme.Fonts.title,
		MaxTextSize = 36,
		Parent = medal,
	})

	-- 相手の名前(妖怪退治の相手 / 対戦の相手 / ボス)
	local header = ""
	if mode == "pvp" and opponent then
		local oname = if opponent.ghost then Locale.t("pvp_ghost_name") else tostring(opponent.name)
		local otitle = if type(opponent.title) == "string" and opponent.title ~= ""
			then "  「" .. Locale.t("title_" .. opponent.title) .. "」"
			else ""
		header = Locale.t("pvp_vs", { name = oname }) .. "  ⚔" .. tostring(opponent.rating or "") .. otitle
	elseif mode == "raid" and boss then
		header = "🐲 " .. (if Locale.get() == "ja" then boss.ja else boss.en)
	elseif trainer then
		header = if Locale.get() == "ja" then trainer.ja else trainer.en
	end
	local headerLabel = Kit.label({
		Size = UDim2.fromOffset(440, 26),
		Position = UDim2.new(1, -28, 0, 108),
		AnchorPoint = Vector2.new(1, 0),
		Text = header,
		TextColor3 = C.goldLight,
		TextXAlignment = Enum.TextXAlignment.Right,
		MaxTextSize = 20,
		ZIndex = 2,
		Parent = top,
	})
	Kit.new(
		"UIStroke",
		{ Color = Color3.fromRGB(4, 16, 30), Thickness = 2, Transparency = 0.2, Parent = headerLabel }
	)
	-- 「相手は選び終わった!」
	v.foeReady = Kit.label({
		Size = UDim2.fromOffset(240, 30),
		Position = UDim2.new(1, -24, 0, 138),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 0,
		BackgroundColor3 = C.jadeDark,
		Text = "○ " .. Locale.t("pvp_foe_ready"),
		MaxTextSize = 16,
		Visible = false,
		ZIndex = 2,
		Parent = top,
	})
	Kit.corner(v.foeReady, UDim.new(1, 0))

	if mode == "raid" then
		local party = Kit.new("Frame", {
			Size = UDim2.fromOffset(500, 44),
			Position = UDim2.new(1, -24, 0, 138),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 1,
			ZIndex = 2,
			Parent = top,
		})
		Kit.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = party,
		})
		local rage = Kit.label({
			Size = UDim2.fromOffset(120, 26),
			Position = UDim2.new(0.5, 0, 0, 112),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundTransparency = 0,
			BackgroundColor3 = C.vermilionDark,
			Text = Locale.t("raid_rage"),
			MaxTextSize = 15,
			Visible = false,
			ZIndex = 2,
			Parent = top,
		})
		Kit.corner(rage, UDim.new(1, 0))
		v.raid = { rage = rage, party = party }
	end

	-- 字幕(何が起きたか)
	local banner = Kit.new("Frame", {
		Size = UDim2.fromOffset(780, 48),
		Position = UDim2.new(0.5, 0, 1, -166),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = Color3.fromRGB(4, 14, 28),
		BackgroundTransparency = 0.3,
		ZIndex = 2,
		Parent = s,
	})
	Kit.corner(banner, UDim.new(1, 0))
	v.message = Kit.label({
		Size = UDim2.new(1, -40, 1, -10),
		Position = UDim2.fromOffset(20, 5),
		MaxTextSize = 24,
		Parent = banner,
	})

	-- 下: 技のお札と、交代・逃げる
	local dock = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 158),
		Position = UDim2.fromScale(0, 1),
		AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = Color3.fromRGB(4, 14, 28),
		BorderSizePixel = 0,
		ZIndex = 2,
		Parent = s,
	})
	Kit.new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.35, 0.55),
			NumberSequenceKeypoint.new(1, 0.25),
		}),
		Parent = dock,
	})
	local cards = Kit.new("Frame", {
		Size = UDim2.fromOffset(4 * 168 + 3 * 12, 128),
		Position = UDim2.new(0.5, 0, 1, -14),
		AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1,
		Parent = dock,
	})
	Kit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = cards,
	})
	v.cards = {}
	for i = 1, 4 do
		table.insert(v.cards, makeTalisman(cards, i))
	end
	local side = Kit.new("Frame", {
		Size = UDim2.fromOffset(150, 128),
		Position = UDim2.new(1, -24, 1, -14),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundTransparency = 1,
		Parent = dock,
	})
	Kit.new(
		"UIListLayout",
		{ Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder, Parent = side }
	)
	v.switchButton = Kit.button({
		Text = Locale.t("battle_switch"),
		Size = UDim2.fromOffset(150, 58),
		Color = C.indigo,
		MaxTextSize = 20,
		LayoutOrder = 1,
		Parent = side,
	}, showSwitchPicker)
	v.runButton = Kit.button({
		Text = runLabel(),
		Size = UDim2.fromOffset(150, 58),
		Color = C.panelDark,
		MaxTextSize = 20,
		LayoutOrder = 2,
		Parent = side,
	}, onRun)
	view = v

	-- 真ん中の丸と、対戦の残り時間
	local lastTick = -1
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not screen or not view then
			conn:Disconnect()
			return
		end
		local t = os.clock()
		if mode == "pvp" and deadline and current and not current.over then
			local left = math.max(0, deadline - t)
			view.medalCaption.Text = Locale.t("battle_time_caption")
			view.medalValue.Text = if chosen then "⏳" else tostring(math.ceil(left))
			view.medalValue.TextColor3 = if left <= 5 and not chosen then C.danger else C.text
			view.medallionStroke.Color = if left <= 5 and not chosen then C.danger else C.gold
			local whole = math.ceil(left)
			if whole ~= lastTick and whole <= 5 and whole > 0 and not chosen and not busy then
				Sound.play("click", 0.25, 1.6)
			end
			lastTick = whole
			-- 時間切れ: サーバーのコンピューターが代わりに選ぶ
			if left <= 0 and not chosen and not busy then
				chosen = true
				setMessage(Locale.t("pvp_timeout"))
				setCommandsEnabled(false)
			end
		elseif mode == "raid" and raidInfo then
			local left = math.max(0, raidInfo.seconds - (t - raidInfoAt))
			view.medalCaption.Text = Locale.t("battle_time_caption")
			view.medalValue.Text = Format.time(left)
			view.medalValue.TextColor3 = if left <= 30 then C.danger else C.text
		elseif current then
			view.medalCaption.Text = Locale.t("battle_turn_caption")
			view.medalValue.Text = tostring((current.turn or 0) + (if current.over then 0 else 1))
			view.medalValue.TextColor3 = C.text
		end
	end)
	local s2 = Kit.new("UIScale", { Scale = 1.06, Parent = s })
	TweenService:Create(s2, TweenInfo.new(0.3), { Scale = 1 }):Play()
end

-- イベントの再生 -----------------------------------------------------------
local function playEvents(events: { any })
	local lastElement = "none"
	for _, e in events do
		if not view or not scene then
			return
		end
		local side = e.side
		local st = current
		local fishId = if side and st and st[side] then st[side].team[st[side].active].fishId else ""
		local plate = if side == "enemy" then view.enemyPlate else view.playerPlate
		if e.kind == "move" then
			local mv = Config.MoveById[e.move]
			local actor = st and st[side].team[st[side].active]
			lastElement = if mv.element == "self" and actor then actor.element else mv.element
			setMessage(
				Locale.t(
					"battle_used",
					{ name = sideName(side, fishId), move = if Locale.get() == "ja" then mv.ja else mv.en }
				)
			)
			-- 技を出す時に鳴く(短く、少し高く。吹き出しは場に出た時だけ)
			if fishId ~= "" then
				Cry.play(fishId, { volume = 0.6, pitch = 1.12, maxLength = 1.4 })
			end
			if mv.power > 0 then
				-- 相手へ泳いでぶつかる
				scene:attack(side)
				Sound.play("splash", 0.35, 1.5)
				pause(0.3)
			else
				scene:cast(side, Color3.fromHex(elementOf(lastElement).color))
				Sound.play("click", 0.4, 0.8)
				pause(0.55)
			end
		elseif e.kind == "miss" then
			-- e.side は技を出した方。かわしたのは相手
			scene:dodge(otherSide(side))
			setMessage(Locale.t("battle_miss"))
			pause(0.7)
		elseif e.kind == "damage" then
			Sound.play("splash", 0.5, if e.eff > 1 then 0.8 else 1.2)
			scene:hit(side, lastElement, e.eff, e.crit == true)
			scene:float(side, "-" .. e.amount, if e.eff > 1 then C.goldLight else C.text)
			if st then
				st[side].team[st[side].active].hp = e.hp
				updatePlate(plate, st[side])
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
			pause(0.55)
			if #extra > 0 then
				setMessage(table.concat(extra, "  "))
				pause(0.7)
			end
		elseif e.kind == "heal" then
			scene:heal(side)
			scene:float(side, "+" .. e.amount, C.success)
			setMessage(Locale.t("battle_heal", { name = sideName(side, fishId) }))
			if st then
				st[side].team[st[side].active].hp = e.hp
				updatePlate(plate, st[side])
			end
			pause(0.7)
		elseif e.kind == "stat" then
			local key = if e.delta > 0 then "battle_stat_up" else "battle_stat_down"
			setMessage(Locale.t(key, { name = sideName(side, fishId), stat = Locale.t("stat_" .. e.stat) }))
			scene:cast(side, if e.delta > 0 then C.goldLight else C.indigo)
			pause(0.7)
		elseif e.kind == "stun" then
			setMessage(Locale.t("battle_stun", { name = sideName(side, fishId) }))
			scene:stun(side)
			pause(0.7)
		elseif e.kind == "stunned" then
			setMessage(Locale.t("battle_stunned", { name = sideName(side, fishId) }))
			scene:stun(side)
			pause(0.7)
		elseif e.kind == "faint" then
			setMessage(Locale.t("battle_faint", { name = sideName(side, e.fishId) }))
			scene:faint(side)
			Sound.play("fail", 0.5, 0.7)
			cry(side, e.fishId, true)
			if st then
				st[side].team[st[side].active].hp = 0
				updatePlate(plate, st[side])
			end
			pause(1.2)
		elseif e.kind == "switch" then
			-- 前の子が泳ぎ去り、次の子が横から泳いでくる
			if scene:hasFish(side) then
				scene:leave(side)
				pause(0.5)
			end
			if st then
				st[side].active = e.slot
				local f = st[side].team[e.slot]
				scene:setFish(side, f.fishId, f.mutation, "enter")
				updatePlate(plate, st[side])
			end
			local n = name(Config.FishById[e.fishId])
			setMessage(
				if side == "player"
					then Locale.t("battle_go", { name = n })
					else Locale.t("battle_foe_sends", { name = n })
			)
			cry(side, e.fishId)
			pause(0.9)
		elseif e.kind == "run" then
			scene:leave(side)
			if side == "enemy" then
				setMessage(Locale.t("battle_foe_ran"))
			elseif mode == "pvp" then
				setMessage(Locale.t("battle_you_forfeit"))
			else
				setMessage(Locale.t("battle_ran"))
			end
			pause(0.8)
		end
	end
end

local function backToHub()
	local back = if mode == "raid" then "boss" elseif mode == "pvp" then "online" else "trainers"
	closeScreen()
	Root.open("battle", back)
end

local function showResult(r: any)
	if not screen then
		return
	end
	resultShown = true
	-- 勝った子のまわりをカメラが回る
	if scene and not r.retreated then
		local winner = if r.win then "player" else "enemy"
		if scene:hasFish(winner) then
			scene:celebrate(winner)
		end
	end
	setCommandsEnabled(false)
	local overlay = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.4,
		ZIndex = 50,
		Parent = screen,
	})
	local card = Kit.new("Frame", {
		Size = UDim2.fromOffset(500, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
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
	local lang = Locale.get()
	local titleKey = if r.mode == "raid"
		then (if r.retreated then "raid_retreated" elseif r.win then "raid_win" else "raid_lose")
		else (if r.win then "battle_win" else "battle_lose")
	line(Locale.t(titleKey), if r.win then C.goldLight else C.textDim, 40, 1)

	if r.mode == "pvp" then
		if r.ranked and type(r.ratingFrom) == "number" and type(r.ratingTo) == "number" then
			local d = r.ratingTo - r.ratingFrom
			line(
				Locale.t(
					"pvp_rating_change",
					{ from = r.ratingFrom, to = r.ratingTo, d = (if d >= 0 then "+" else "") .. d }
				),
				if d >= 0 then C.success else C.danger,
				24,
				2
			)
		else
			line(Locale.t("pvp_friendly_note"), C.textDim, 18, 2)
		end
		if (r.coins or 0) > 0 then
			line(Locale.t("pvp_daily_coins", { coins = Format.coins(r.coins, lang) }), C.goldLight, 22, 3)
		end
	elseif r.win then
		if (r.coins or 0) > 0 then
			line(
				"¥ "
					.. Format.coins(r.coins, lang)
					.. (if r.firstClear then "  " .. Locale.t("battle_first_clear") else ""),
				C.goldLight,
				22,
				2
			)
		end
		if r.rematchPaidToday then
			line(Locale.t("battle_rematch_paid"), C.textDim, 16, 3)
		end
		if r.rewardPaidToday then
			line(Locale.t("boss_paid"), C.textDim, 16, 3)
		end
		if r.bait then
			line(Locale.t("bait_" .. r.bait.id) .. " ×" .. r.bait.amount, C.text, 18, 4)
		end
		if r.title then
			line(Locale.t("nushi_title_got", { title = Locale.t("title_" .. r.title) }), C.vermilion, 20, 5)
		end
	end
	if r.mode == "raid" and (r.dealt or 0) > 0 then
		line(Locale.t("raid_dealt", { n = Format.coins(r.dealt, lang) }), C.text, 18, 6)
	end
	for i, g in r.gains or {} do
		local def = Config.FishById[g.fishId]
		local text = ("%s  +%d XP"):format(name(def), g.xp)
		if g.levels > 0 then
			text ..= ("   Lv%d → Lv%d ▲"):format(g.from, g.level)
		end
		line(text, if g.levels > 0 then C.success else C.text, 18, 10 + i)
	end

	local buttons = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundTransparency = 1,
		LayoutOrder = 99,
		ZIndex = 52,
		Parent = card,
	})
	Kit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 10),
		Parent = buttons,
	})
	-- ランダム対戦は、続けてもう一度さがせるように
	if r.mode == "pvp" and r.pvpKind ~= "challenge" then
		local again = Kit.button({
			Text = Locale.t("pvp_again"),
			Size = UDim2.fromOffset(200, 50),
			Color = C.vermilion,
			MaxTextSize = 22,
			Parent = buttons,
		}, function()
			State.request("pvpQueue")
			closeScreen()
		end)
		again.ZIndex = 53
	end
	local b = Kit.button({
		Text = Locale.t("close"),
		Size = UDim2.fromOffset(200, 50),
		Color = C.jade,
		MaxTextSize = 22,
		Parent = buttons,
	}, backToHub)
	b.ZIndex = 53
	if r.win then
		Sound.play("rare", 0.7, 1)
	end
	local s = Kit.new("UIScale", { Scale = 0.5, Parent = card })
	TweenService:Create(s, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

-- 戦いの始まり(名乗り → 相手が泳いでくる → 自分の子が泳ぎ出す)
local function intro(msg: any)
	local st = msg.state
	local line = ""
	if mode == "pvp" then
		local oname = if opponent and opponent.ghost
			then Locale.t("pvp_ghost_name")
			else tostring(opponent and opponent.name or "?")
		line = Locale.t("pvp_intro", { name = oname })
	elseif mode == "raid" then
		line = Locale.t("raid_intro", { boss = Online.bossName(msg.bossId) })
	elseif trainer then
		line = if Locale.get() == "ja" then trainer.jaLine else trainer.enLine
	end
	setMessage(line)
	local ef = st.enemy.team[st.enemy.active]
	local pf = st.player.team[st.player.active]
	if scene then
		scene:setFish("enemy", ef.fishId, ef.mutation, "enter")
	end
	if mode == "raid" then
		if scene then
			scene:shotTo("boss", nil, 2.4, 1.5)
		end
		pause(0.8)
		cry("enemy", ef.fishId)
		if scene then
			scene:flash(C.vermilion, 0.35)
			scene:shake(10)
		end
		pause(1.2)
	else
		pause(1.2)
		setMessage(Locale.t("battle_foe_sends", { name = name(Config.FishById[ef.fishId]) }))
		cry("enemy", ef.fishId)
		pause(1.0)
	end
	if scene then
		scene:setFish("player", pf.fishId, pf.mutation, "enter")
	end
	setMessage(Locale.t("battle_go", { name = name(Config.FishById[pf.fishId]) }))
	cry("player", pf.fishId)
	pause(1.0)
end

local queue: { any } = {}
local playing = false

local function handle(msg: any)
	if msg.kind == "start" then
		mode = if msg.mode == "pvp" or msg.mode == "raid" then msg.mode else "trainer"
		trainer = if mode == "trainer" then Config.TrainerById[msg.trainerId] else nil
		opponent = if mode == "pvp" then msg.opponent else nil
		boss = if mode == "raid" then Config.BossById[msg.bossId] else nil
		raidInfo = msg.raid
		raidInfoAt = msg.at
		openScreen()
		deadline = if mode == "pvp" then msg.at + (tonumber(msg.seconds) or O.FirstTurnSeconds) - 0.5 else nil
		applyState(msg.state, true) -- 魚は名乗りの後で泳いでくる
		renderRaid()
		busy = true
		setCommandsEnabled(false)
		intro(msg)
		busy = false
		if not chosen then
			setMessage(Locale.t("battle_choose"))
		end
		refreshCommands()
	elseif msg.kind == "turn" then
		if not view then
			return
		end
		busy = true
		chosen = false
		setCommandsEnabled(false)
		view.foeReady.Visible = false
		playEvents(msg.events or {})
		applyState(msg.state)
		syncBossHp()
		busy = false
		if mode == "pvp" then
			deadline = msg.at + (tonumber(msg.seconds) or O.TurnSeconds) - 0.5
		end
		if mode == "raid" and msg.state.over and msg.state.winner == "enemy" then
			setMessage(Locale.t("raid_down"))
		elseif not msg.state.over then
			setMessage(Locale.t("battle_choose"))
		end
		refreshCommands()
	elseif msg.kind == "result" then
		showResult(msg)
	end
end

-- 待たずにすぐ反映する知らせ(演出の順番に関係ない)
local function handleNow(msg: any)
	if msg.kind == "waiting" then
		if view and chosen then
			setMessage(Locale.t("pvp_waiting"))
		end
	elseif msg.kind == "foeReady" then
		if view then
			view.foeReady.Visible = true
			Sound.play("click", 0.3, 1.2)
		end
	elseif msg.kind == "raid" and type(msg.raid) == "table" then
		onRaidInfo(msg.raid)
	end
end

-- 言語を切り替えた時(ボスの名前や説明は一度だけ作っているので作り直す)
function BattleUI.relabel()
	if not pages.boss then
		return
	end
	Kit.clear(pages.boss)
	table.clear(bossRows)
	myRoom = {}
	buildBossPage()
	teamKey = ""
	render()
end

function BattleUI.init(g: ScreenGui)
	gui = g
	actionRemote = Remotes.event("BattleAction")
	listPanel = Kit.panel(gui, "BattleList", UDim2.fromScale(0.84, 0.84))
	listPanel.close.Activated:Connect(function()
		Root.close()
	end)
	local body = listPanel.body

	-- タブ
	local tabBar =
		Kit.new("Frame", { Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1, Parent = body })
	Kit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = tabBar,
	})
	for i, id in TABS do
		tabButtons[id] = Kit.button({
			Size = UDim2.new(1 / #TABS, -4, 1, 0),
			Color = C.panelLight,
			MaxTextSize = 20,
			LayoutOrder = i,
			Parent = tabBar,
		}, function()
			selectTab(id)
		end)
	end
	roomDot = Kit.new("Frame", {
		Size = UDim2.fromOffset(14, 14),
		Position = UDim2.new(1, -6, 0, 6),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = C.danger,
		Visible = false,
		ZIndex = 5,
		Parent = tabButtons.boss,
	})
	Kit.corner(roomDot, UDim.new(1, 0))

	teamBar = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.fromOffset(0, 54),
		BackgroundTransparency = 1,
		Parent = body,
	})
	Kit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6),
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = teamBar,
	})
	local holder = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 1, -102),
		Position = UDim2.fromOffset(0, 102),
		BackgroundTransparency = 1,
		Parent = body,
	})
	for _, id in TABS do
		pages[id] = Kit.list(holder, 8)
		pages[id].Visible = false
	end
	buildBossPage()
	buildOnlinePage()
	Root.register("battle", listPanel.root, function(arg)
		if type(arg) == "string" and table.find(TABS, arg) then
			tab = arg
		end
		render()
	end)
	State.Changed:Connect(render)
	Online.Changed:Connect(render)
	-- 残り秒(部屋の開始・さがしている時間)を進める
	task.spawn(function()
		while true do
			task.wait(1)
			if listPanel.root.Visible and tab ~= "trainers" then
				render()
			end
		end
	end)

	-- キーボードの 1〜4 でお札を使う
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not view then
			return
		end
		local keys = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four }
		-- ゲームパッド: 十字キーの 左・上・右・下 = お札 1〜4、Y = 交代、B = 逃げる
		local pad =
			{ Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadUp, Enum.KeyCode.DPadRight, Enum.KeyCode.DPadDown }
		local i = table.find(keys, input.KeyCode) or table.find(pad, input.KeyCode)
		if i then
			useCard(i)
		elseif input.KeyCode == Enum.KeyCode.ButtonY then
			showSwitchPicker()
		elseif input.KeyCode == Enum.KeyCode.ButtonB then
			onRun()
		end
	end)

	-- サーバーからのメッセージは届いた順に1つずつ再生する
	Remotes.event("BattleState").OnClientEvent:Connect(function(msg)
		if type(msg) ~= "table" then
			return
		end
		msg.at = os.clock() -- 届いた時刻(対戦の残り時間はここから数える)
		if msg.kind == "waiting" or msg.kind == "foeReady" or msg.kind == "raid" then
			handleNow(msg)
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
