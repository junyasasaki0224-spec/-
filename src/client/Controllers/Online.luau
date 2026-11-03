--!strict
-- オンラインの状態(ボス戦の部屋・ランダム対戦の待ち・出した申し込み・届いた申し込み)と、
-- 画面の右上に出る「申し込み」「仲間募集」のカード、左に出る「今やっていること」の札。
-- 表示するだけ。受ける/断る/参加などはサーバーに頼み、決めるのはサーバー。
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Locale = require(Shared.Locale)
local Format = require(Shared.Lib.Format)
local Remotes = require(Shared.Lib.Remotes)

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local Root = require(script.Parent.Parent.UI.Root)
local State = require(script.Parent.Parent.ClientState)
local Sound = require(script.Parent.Sound)
local C = Theme.Colors

local O = Config.Online
local player = Players.LocalPlayer

local Online = {}

export type Room = {
	id: number,
	bossId: string,
	hostId: number,
	members: { { userId: number, name: string } },
	max: number,
	startsIn: number,
}

Online.rooms = {} :: { Room }
Online.queue = { state = "idle", since = 0 } :: { state: string, since: number }
Online.sent = nil :: { to: number, name: string, expires: number }?
Online.invites = {} :: { [number]: { name: string, expires: number } }

local roomsAt = 0
local changed = Instance.new("BindableEvent")
Online.Changed = changed.Event

local gui: ScreenGui? = nil
local cardStack: Frame
local pillStack: Frame
local cards: { [string]: Frame } = {}

-- 共通の小物 -------------------------------------------------------------------
function Online.headshot(userId: number): string
	return ("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150"):format(userId)
end

-- 丸い顔写真
function Online.avatar(parent: Instance, userId: number, size: number, props: { [string]: any }?): ImageLabel
	local img = Kit.new("ImageLabel", {
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = C.panelDark,
		Image = Online.headshot(userId),
		Parent = parent,
	})
	if props then
		for k, v in props do
			(img :: any)[k] = v
		end
	end
	Kit.corner(img, UDim.new(1, 0))
	Kit.stroke(img, C.gold, 2, 0.2)
	return img
end

function Online.bossName(bossId: string): string
	local b = Config.BossById[bossId]
	return if not b then "?" elseif Locale.get() == "ja" then b.ja else b.en
end

function Online.inBattle(): boolean
	local g = gui
	return g ~= nil and g:FindFirstChild("Battle") ~= nil
end

-- 部屋の開始までの残り秒(届いた時刻からの経過を引く)
function Online.roomSecondsLeft(room: Room): number
	return math.max(0, math.ceil(room.startsIn - (os.clock() - roomsAt)))
end

function Online.myRoom(): Room?
	for _, r in Online.rooms do
		for _, m in r.members do
			if m.userId == player.UserId then
				return r
			end
		end
	end
	return nil
end

-- そのボスの、入れる部屋(人が多い方)
function Online.roomFor(bossId: string): Room?
	local best: Room? = nil
	for _, r in Online.rooms do
		if r.bossId == bossId and #r.members < r.max then
			if not best or #r.members > #best.members then
				best = r
			end
		end
	end
	return best
end

function Online.challenge(userId: number)
	State.request("pvpChallenge", userId)
end

function Online.withdraw()
	State.request("pvpCancelChallenge")
end

-- 「申し込みを受け取る: 全員 / 友達だけ / 受け取らない」の切り替え
function Online.prefControl(parent: Instance, order: number?): Frame
	local row = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		LayoutOrder = order or 0,
		Parent = parent,
	})
	Kit.label({
		Size = UDim2.new(0.34, -8, 1, 0),
		Text = Locale.t("pvp_receive"),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.textDim,
		MaxTextSize = 17,
		Parent = row,
	})
	local seg = Kit.new("Frame", {
		Size = UDim2.new(0.66, 0, 1, 0),
		Position = UDim2.fromScale(0.34, 0),
		BackgroundColor3 = C.panelDark,
		Parent = row,
	})
	Kit.corner(seg, UDim.new(1, 0))
	Kit.padding(seg, 3)
	Kit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 3),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = seg,
	})
	local buttons: { [string]: TextButton } = {}
	local function paint()
		local cur = State.profile and State.profile.settings.challenges or "all"
		for key, b in buttons do
			local on = key == cur
			b.BackgroundColor3 = if on then C.jade else C.panelLight
			b.TextColor3 = if on then C.text else C.textDim
		end
	end
	for i, key in { "all", "friends", "off" } do
		local b = Kit.new("TextButton", {
			Size = UDim2.new(1 / 3, -2, 1, 0),
			BackgroundColor3 = C.panelLight,
			AutoButtonColor = true,
			Font = Theme.Fonts.bold,
			Text = Locale.t("pref_" .. key),
			TextColor3 = C.textDim,
			TextScaled = true,
			LayoutOrder = i,
			Parent = seg,
		})
		Kit.new("UITextSizeConstraint", { MaxTextSize = 16, MinTextSize = 8, Parent = b })
		Kit.corner(b, UDim.new(1, 0))
		b.Activated:Connect(function()
			if State.profile then
				State.profile.settings.challenges = key -- すぐ見た目に反映(本当の値はサーバーから届く)
			end
			paint()
			State.request("setChallengePref", key)
		end)
		buttons[key] = b
	end
	paint()
	local conn = State.Changed:Connect(paint)
	row.Destroying:Connect(function()
		conn:Disconnect()
	end)
	return row
end

-- 右上のカード(申し込み・仲間募集) --------------------------------------------
local function dismiss(key: string)
	local card = cards[key]
	if not card then
		return
	end
	cards[key] = nil
	local s = card:FindFirstChildOfClass("UIScale")
	if s then
		TweenService:Create(s, TweenInfo.new(0.18), { Scale = 0.6 }):Play()
	end
	task.delay(0.18, function()
		card:Destroy()
	end)
end

local function makeCard(key: string, userId: number, title: string, sub: string, seconds: number?): Frame
	dismiss(key)
	local card = Kit.new("Frame", {
		Name = key,
		Size = UDim2.fromOffset(340, 118),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.03,
		LayoutOrder = math.floor(os.clock() * 10),
		Parent = cardStack,
	})
	Kit.corner(card)
	Kit.stroke(card, C.goldLight, 2)
	Online.avatar(card, userId, 56, { Position = UDim2.fromOffset(12, 12) })
	Kit.label({
		Size = UDim2.new(1, -92, 0, 26),
		Position = UDim2.fromOffset(80, 10),
		Text = title,
		TextXAlignment = Enum.TextXAlignment.Left,
		Font = Theme.Fonts.title,
		MaxTextSize = 18,
		Parent = card,
	})
	Kit.label({
		Size = UDim2.new(1, -92, 0, 20),
		Position = UDim2.fromOffset(80, 38),
		Text = sub,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.textDim,
		MaxTextSize = 15,
		Parent = card,
	})
	if seconds then
		-- 残り時間の帯
		local bg, fill = Kit.bar(card, C.goldLight)
		bg.Size = UDim2.new(1, -24, 0, 5)
		bg.Position = UDim2.new(0, 12, 1, -10)
		fill.Size = UDim2.fromScale(1, 1)
		TweenService
			:Create(fill, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) })
			:Play()
	end
	local s = Kit.new("UIScale", { Scale = 0.6, Parent = card })
	TweenService:Create(s, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	cards[key] = card
	return card
end

local function cardButtons(card: Frame, items: { { text: string, color: Color3, fn: () -> () } })
	local row = Kit.new("Frame", {
		Size = UDim2.new(1, -92, 0, 38),
		Position = UDim2.fromOffset(80, 64),
		BackgroundTransparency = 1,
		Parent = card,
	})
	Kit.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = row,
	})
	for i, it in items do
		Kit.button({
			Text = it.text,
			Size = UDim2.new(1 / #items, -8, 1, 0),
			Color = it.color,
			MaxTextSize = 17,
			LayoutOrder = i,
			Parent = row,
		}, it.fn)
	end
end

local function showInvite(msg: any)
	local from = msg.from
	local seconds = math.clamp(tonumber(msg.seconds) or O.ChallengeSeconds, 1, 60)
	Online.invites[from] = { name = tostring(msg.name), expires = os.clock() + seconds }
	local title = if msg.title and msg.title ~= ""
		then Locale.t("title_" .. msg.title)
		else Locale.t("title_none")
	local card = makeCard(
		"invite" .. from,
		from,
		Locale.t("invite_title", { name = tostring(msg.name):sub(1, 40) }),
		Locale.t("invite_info", { rating = tonumber(msg.rating) or 0, title = title }),
		seconds
	)
	cardButtons(card, {
		{
			text = Locale.t("invite_accept"),
			color = C.jade,
			fn = function()
				State.request("pvpRespond", { from = from, accept = true })
				Online.invites[from] = nil
				dismiss("invite" .. from)
				changed:Fire()
			end,
		},
		{
			text = Locale.t("invite_decline"),
			color = C.panelDark,
			fn = function()
				State.request("pvpRespond", { from = from, accept = false })
				Online.invites[from] = nil
				dismiss("invite" .. from)
				changed:Fire()
			end,
		},
	})
	Sound.play("rare", 0.6, 1.25)
	task.delay(seconds, function()
		if Online.invites[from] and Online.invites[from].expires <= os.clock() + 0.1 then
			Online.invites[from] = nil
			dismiss("invite" .. from)
			changed:Fire()
		end
	end)
end

local function recruitInfo(bossId: string): string
	local b = Config.BossById[bossId]
	if not b then
		return ""
	end
	return Locale.t("recruit_info", { lv = b.recommend, coins = Format.coins(b.reward.coins, Locale.get()) })
end

local function showRecruit(msg: any)
	if msg.hostId == player.UserId or Online.inBattle() or Online.myRoom() then
		return
	end
	local key = "recruit" .. tostring(msg.roomId)
	local card = makeCard(
		key,
		msg.hostId,
		Locale.t(
			"recruit_title",
			{ name = tostring(msg.name):sub(1, 40), boss = Online.bossName(msg.bossId) }
		),
		recruitInfo(msg.bossId),
		12
	)
	cardButtons(card, {
		{
			text = Locale.t("boss_join"),
			color = C.jade,
			fn = function()
				State.request("raidJoin", msg.roomId)
				dismiss(key)
				Root.open("battle", "boss")
			end,
		},
		{
			text = "✕",
			color = C.panelDark,
			fn = function()
				dismiss(key)
			end,
		},
	})
	task.delay(12, function()
		dismiss(key)
	end)
end

-- 左の「今やっていること」の札 ---------------------------------------------------
type Pill = { frame: Frame, label: TextLabel, action: TextButton, close: TextButton }
local pills: { [string]: Pill } = {}

local function makePill(key: string, order: number, color: Color3, onTap: () -> (), onClose: () -> ()): Pill
	local f = Kit.new("TextButton", {
		Name = key,
		Size = UDim2.fromOffset(330, 42),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.08,
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = order,
		Visible = false,
		Parent = pillStack,
	})
	Kit.corner(f, UDim.new(1, 0))
	Kit.stroke(f, color, 2)
	f.Activated:Connect(onTap)
	local label = Kit.label({
		Size = UDim2.new(1, -150, 1, -10),
		Position = UDim2.fromOffset(14, 5),
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 16,
		Parent = f,
	})
	local action = Kit.button({
		Size = UDim2.fromOffset(84, 32),
		Position = UDim2.new(1, -46, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Color = C.jade,
		MaxTextSize = 15,
		Parent = f,
	}, function() end)
	action.Visible = false
	local close = Kit.button({
		Text = "✕",
		Size = UDim2.fromOffset(32, 32),
		Position = UDim2.new(1, -6, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		Color = C.panelDark,
		MaxTextSize = 16,
		Parent = f,
	}, onClose)
	local p = { frame = f :: any, label = label, action = action, close = close }
	pills[key] = p
	return p
end

local function refreshPills()
	local q = Online.queue
	local queuePill = pills.queue
	queuePill.frame.Visible = q.state ~= "idle"
	if q.state == "searching" then
		queuePill.label.Text = Locale.t("pill_queue", { t = Format.time(os.clock() - q.since) })
	elseif q.state == "ghost" then
		queuePill.label.Text = Locale.t("pill_ghost")
	end

	local sent = Online.sent
	pills.sent.frame.Visible = sent ~= nil
	if sent then
		local left = math.max(0, math.ceil(sent.expires - os.clock()))
		pills.sent.label.Text = Locale.t("pill_sent", { name = sent.name, s = left })
	end

	local room = Online.myRoom()
	local roomPill = pills.room
	roomPill.frame.Visible = room ~= nil
	if room then
		roomPill.label.Text = Locale.t("pill_room", {
			boss = Online.bossName(room.bossId),
			n = #room.members,
			max = room.max,
			s = Online.roomSecondsLeft(room),
		})
		roomPill.action.Visible = room.hostId == player.UserId
	end
	-- 右のボタンが無い札は、文字を広く
	for _, p in pills do
		p.label.Size = UDim2.new(1, if p.action.Visible then -146 else -58, 1, -10)
	end
end

-- サーバーからの知らせ ---------------------------------------------------------
local function onArena(msg: any)
	if type(msg) ~= "table" then
		return
	end
	local kind = msg.kind
	if kind == "rooms" and type(msg.rooms) == "table" then
		Online.rooms = msg.rooms
		roomsAt = os.clock()
		-- 消えた部屋の募集カードを片付ける
		for key in cards do
			local id = tonumber(key:match("^recruit(%d+)$"))
			if id then
				local still = false
				for _, r in Online.rooms do
					if r.id == id and #r.members < r.max then
						still = true
					end
				end
				if not still then
					dismiss(key)
				end
			end
		end
	elseif kind == "recruit" then
		showRecruit(msg)
	elseif kind == "queue" then
		local prev = Online.queue.state
		local nextState: string = if msg.state == "searching" or msg.state == "ghost"
			then msg.state
			else "idle"
		Online.queue = {
			state = nextState,
			since = if prev == "idle" then os.clock() else Online.queue.since,
		}
	elseif kind == "invite" and type(msg.from) == "number" then
		showInvite(msg)
	elseif kind == "inviteGone" and type(msg.from) == "number" then
		Online.invites[msg.from] = nil
		dismiss("invite" .. msg.from)
	elseif kind == "sent" and type(msg.to) == "number" then
		Online.sent = {
			to = msg.to,
			name = tostring(msg.name):sub(1, 40),
			expires = os.clock() + (tonumber(msg.seconds) or O.ChallengeSeconds),
		}
	elseif kind == "sentGone" then
		Online.sent = nil
	end
	refreshPills()
	changed:Fire()
end

function Online.pendingInvites(): number
	local n = 0
	for _ in Online.invites do
		n += 1
	end
	return n
end

function Online.init(g: ScreenGui)
	gui = g
	cardStack = Kit.new("Frame", {
		Name = "OnlineCards",
		Size = UDim2.fromOffset(340, 400),
		Position = UDim2.new(1, -92, 0, 70 + Root.topShift(64)), -- 右のメニューと、上の時計の間
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 1,
		ZIndex = 20,
		Parent = gui,
	})
	Kit.new("UIListLayout", {
		Padding = UDim.new(0, 8),
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = cardStack,
	})
	pillStack = Kit.new("Frame", {
		Name = "OnlinePills",
		Size = UDim2.fromOffset(330, 150),
		Position = UDim2.fromOffset(20, 300),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	Kit.new("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = pillStack,
	})
	makePill("queue", 1, C.vermilion, function()
		Root.open("battle", "online")
	end, function()
		State.request("pvpCancel")
	end)
	makePill("sent", 2, C.goldLight, function()
		Root.open("social")
	end, Online.withdraw)
	local room = makePill("room", 3, C.jade, function()
		Root.open("battle", "boss")
	end, function()
		State.request("raidLeave")
	end)
	room.action.Text = Locale.t("boss_start")
	room.action.Activated:Connect(function()
		State.request("raidStart")
	end)

	Remotes.event("Arena").OnClientEvent:Connect(onArena)
	-- 秒の表示を進める
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.5 then
			return
		end
		acc = 0
		if Online.sent and Online.sent.expires < os.clock() - 2 then
			Online.sent = nil -- 返事が来なかった(サーバーからも知らせが来るはず)
			changed:Fire()
		end
		refreshPills()
	end)
end

-- 言語を切り替えた時
function Online.relabel()
	if pills.room then
		pills.room.action.Text = Locale.t("boss_start")
	end
	refreshPills()
end

return Online
