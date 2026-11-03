--!strict
-- 対戦: 相手を選ぶ画面(妖怪退治 / ボス戦 / オンライン対戦 のタブ)と、ポケモンのようなバトル画面。
-- 画面はサーバーから届いたイベントを順番に再生するだけ(ダメージや勝敗はサーバーが決める)。
-- バトル画面は3種類で共通: 妖怪退治(コンピューター)・対戦(人 / ほかのサーバーのチームの写し)・ボス戦(協力)
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Locale = require(Shared.Locale)
local Format = require(Shared.Lib.Format)
local Remotes = require(Shared.Lib.Remotes)
local FishBuilder = require(Shared.Lib.FishBuilder)
local WorldClock = require(Shared.Lib.WorldClock)

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local Root = require(script.Parent.Parent.UI.Root)
local State = require(script.Parent.Parent.ClientState)
local Input = require(script.Parent.Input)
local Sound = require(script.Parent.Sound)
local Cry = require(script.Parent.Cry)
local Online = require(script.Parent.Online)
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
	card.hpText.Text = ("%s / %s"):format(
		Format.coins(f.hp, Locale.get()),
		Format.coins(f.maxHp, Locale.get())
	)
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
	for _, b in view.moveButtons do
		Kit.setEnabled(b, on and b:GetAttribute("HasMove") == true, b:GetAttribute("Color") :: any)
	end
	Kit.setEnabled(view.switchButton, on, C.indigo)
	local runOn = on or (mode == "raid" and not busy and current ~= nil and not resultShown)
	if os.clock() >= confirmUntil then
		view.runButton.Text = runLabel()
		Kit.setEnabled(view.runButton, runOn, C.panelDark)
	end
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
	setCommandsEnabled(not busy and not current.over and not chosen)
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
	chosen = false
	deadline = nil
	resultShown = false
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

local function showSwitchPicker()
	if not view or not current or busy or chosen then
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
			if view and current and not busy and not chosen then
				choose({ kind = "switch", slot = i })
			end
		end)
		b.ZIndex = 42
		Kit.setEnabled(b, ok, C.indigo)
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
	send({ kind = "run" })
end

-- ボス戦の上の札(残り時間・怒り・仲間)
local function renderRaid()
	if not view or not view.raid or not raidInfo then
		return
	end
	local r = view.raid
	r.rage.Visible = raidInfo.enraged == true
	Kit.clear(r.party)
	for i, m in raidInfo.members or {} do
		local chip = Kit.new("Frame", {
			Size = UDim2.fromOffset(116, 42),
			BackgroundColor3 = if m.alive then C.panelLight else C.panelDark,
			BackgroundTransparency = 0.1,
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
		updateCard(view.enemyCard, current.enemy)
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
		flash(view.enemyStage, C.danger)
		task.spawn(shake, view.enemyStage)
		Sound.play("fail", 0.6, 0.6)
		if not busy then
			setMessage(Locale.t("raid_enraged", { boss = Online.bossName(info.bossId) }))
		end
	end
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
	if mode == "raid" then
		Kit.gradient(s, Color3.fromRGB(70, 24, 40), Color3.fromRGB(20, 30, 60))
	else
		Kit.gradient(s, Color3.fromRGB(40, 34, 78), Color3.fromRGB(24, 64, 70))
	end
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
	local enemySize = if mode == "raid" then Vector2.new(380, 270) else Vector2.new(300, 220)
	v.enemyStage = makeStage(s, UDim2.new(0.72, 0, 0.3, 0), Vector2.new(0.5, 0.5), enemySize)
	v.playerStage = makeStage(s, UDim2.new(0.28, 0, 0.58, 0), Vector2.new(0.5, 0.5), Vector2.new(340, 240))
	v.enemyCard = makeCard(s, UDim2.new(0.05, 0, 0, 80), Vector2.new(0, 0))
	-- 自分の札は相手の足元の波紋と重ならない高さに
	v.playerCard = makeCard(s, UDim2.new(0.95, 0, 0.56, 0), Vector2.new(1, 0.5))

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
	Kit.label({
		Size = UDim2.fromOffset(420, 26),
		Position = UDim2.new(0.05, 0, 0, 176),
		Text = header,
		TextColor3 = C.goldLight,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 20,
		Parent = s,
	})
	-- 「相手は選び終わった!」
	v.foeReady = Kit.label({
		Size = UDim2.fromOffset(240, 30),
		Position = UDim2.new(0.05, 0, 0, 206),
		BackgroundTransparency = 0,
		BackgroundColor3 = C.jadeDark,
		Text = "✓ " .. Locale.t("pvp_foe_ready"),
		MaxTextSize = 16,
		Visible = false,
		Parent = s,
	})
	Kit.corner(v.foeReady, UDim.new(1, 0))

	if mode == "raid" then
		local panel = Kit.new("Frame", {
			Size = UDim2.fromOffset(500, 90),
			Position = UDim2.new(0.5, 0, 0, 12),
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = C.panel,
			BackgroundTransparency = 0.1,
			Parent = s,
		})
		Kit.corner(panel)
		Kit.stroke(panel, C.vermilion, 2)
		local time = Kit.label({
			Size = UDim2.fromOffset(120, 28),
			Position = UDim2.fromOffset(12, 4),
			TextXAlignment = Enum.TextXAlignment.Left,
			Font = Theme.Fonts.title,
			MaxTextSize = 20,
			Parent = panel,
		})
		Kit.label({
			Size = UDim2.fromOffset(120, 28),
			Position = UDim2.fromOffset(140, 4),
			Text = Locale.t("raid_party"),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = C.textDim,
			MaxTextSize = 15,
			Parent = panel,
		})
		local rage = Kit.label({
			Size = UDim2.fromOffset(110, 26),
			Position = UDim2.new(1, -10, 0, 5),
			AnchorPoint = Vector2.new(1, 0),
			BackgroundTransparency = 0,
			BackgroundColor3 = C.vermilionDark,
			Text = Locale.t("raid_rage"),
			MaxTextSize = 15,
			Visible = false,
			Parent = panel,
		})
		Kit.corner(rage, UDim.new(1, 0))
		local party = Kit.new("Frame", {
			Size = UDim2.new(1, -20, 0, 42),
			Position = UDim2.fromOffset(10, 38),
			BackgroundTransparency = 1,
			Parent = panel,
		})
		Kit.new("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding = UDim.new(0, 6),
			SortOrder = Enum.SortOrder.LayoutOrder,
			Parent = party,
		})
		v.raid = { time = time, rage = rage, party = party }
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
	-- 対戦の残り時間(下の枠の上の帯)
	local tbg, tfill = Kit.bar(bottom, C.goldLight)
	tbg.Size = UDim2.new(1, -28, 0, 6)
	tbg.Position = UDim2.fromOffset(14, -12)
	tbg.Visible = mode == "pvp"
	v.timerBar = tbg
	v.timerFill = tfill
	v.timerText = Kit.label({
		Size = UDim2.fromOffset(60, 26),
		Position = UDim2.new(1, -14, 0, -42),
		AnchorPoint = Vector2.new(1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		Font = Theme.Fonts.title,
		MaxTextSize = 22,
		Visible = false,
		Parent = bottom,
	})
	Kit.new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1.5, Parent = v.timerText })
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
				if busy or chosen or not current or current.over then
					return
				end
				choose({ kind = "move", index = i })
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
		Text = runLabel(),
		Size = UDim2.new(0.5, -3, 1, 0),
		Color = C.panelDark,
		MaxTextSize = 18,
		Parent = row,
	}, onRun)
	view = v

	-- 魚をゆらゆら動かす・残り時間を進める
	local lastTick = -1
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
		if mode == "pvp" and deadline and current and not current.over then
			local total = math.max(1, O.TurnSeconds)
			local left = math.max(0, deadline - t)
			view.timerFill.Size = UDim2.fromScale(math.clamp(left / total, 0, 1), 1)
			view.timerFill.BackgroundColor3 = if left <= 5 then C.danger else C.goldLight
			view.timerText.Visible = not chosen and not busy
			view.timerText.Text = tostring(math.ceil(left))
			view.timerText.TextColor3 = if left <= 5 then C.danger else C.text
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
		else
			view.timerText.Visible = false
		end
		if mode == "raid" and view.raid and raidInfo then
			local left = math.max(0, raidInfo.seconds - (t - raidInfoAt))
			view.raid.time.Text = Locale.t("raid_time", { t = Format.time(left) })
			view.raid.time.TextColor3 = if left <= 30 then C.danger else C.text
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
			if side == "enemy" then
				setMessage(Locale.t("battle_foe_ran"))
			elseif mode == "pvp" then
				setMessage(Locale.t("battle_you_forfeit"))
			else
				setMessage(Locale.t("battle_ran"))
			end
			task.wait(0.7)
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

-- 戦いの始まり(名乗り → お互いに魚を出す)
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
	if mode == "raid" and view then
		local ef = st.enemy.team[st.enemy.active]
		cry(view.enemyStage, ef.fishId)
		flash(view.enemyStage, C.vermilion)
		task.spawn(shake, view.enemyStage)
		task.wait(1.6)
	else
		task.wait(1.4)
		local ef = st.enemy.team[st.enemy.active]
		setMessage(Locale.t("battle_foe_sends", { name = name(Config.FishById[ef.fishId]) }))
		if view then
			cry(view.enemyStage, ef.fishId)
		end
		task.wait(1.1)
	end
	local pf = st.player.team[st.player.active]
	setMessage(Locale.t("battle_go", { name = name(Config.FishById[pf.fishId]) }))
	if view then
		cry(view.playerStage, pf.fishId)
	end
	task.wait(0.9)
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
		applyState(msg.state)
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
