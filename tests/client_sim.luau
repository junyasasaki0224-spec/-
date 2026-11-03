-- クライアントの画面(対戦の画面・ボス戦・なかま・申し込みのカード)を、Studio を開かずに動かして確かめる。
-- 本物の Kit / Root / Online / Social / BattleUI を、偽物の Instance と時間を自分で進める task の上で動かし、
-- サーバーから届く知らせを順に流して「押せるボタン」「出る文字」「サーバーへ送る中身」を調べる。
-- 実行: lune run tests/client_sim.luau
local H = require("./harness")
local roblox = require("@lune/roblox")
local process = require("@lune/process")
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local shared = H.root("src/shared")
local client = H.root("src/client")
local Config = H.require(shared.Config)
local Locale = H.require(shared.Locale)
local BattleLib = H.require(shared.Lib.Battle)
local Format = H.require(shared.Lib.Format)

-- 時間(os.clock と task は、この時計で動く) -------------------------------------
local now = 1000
local sleeping: { { co: thread, at: number, args: { any }? } } = {}

local function resume(co: thread, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		error(debug.traceback(co, tostring(err)), 0)
	end
end

local fakeTask = {}
function fakeTask.spawn(fn: any, ...): thread
	local co = if type(fn) == "thread" then fn else coroutine.create(fn)
	resume(co, ...)
	return co
end
function fakeTask.defer(fn: any, ...)
	table.insert(sleeping, { co = coroutine.create(fn), at = now, args = { ... } })
end
function fakeTask.delay(t: number?, fn: any, ...)
	table.insert(sleeping, { co = coroutine.create(fn), at = now + (t or 0), args = { ... } })
end
function fakeTask.wait(t: number?): number
	if not coroutine.isyieldable() then
		return 0
	end
	table.insert(sleeping, { co = coroutine.running(), at = now + (t or 0.03) })
	coroutine.yield()
	return t or 0.03
end

local function advance(dt: number)
	local target = now + dt
	while true do
		local bestI, best = nil, nil
		for i, s in sleeping do
			if s.at <= target and (best == nil or s.at < best.at) then
				bestI, best = i, s
			end
		end
		if not bestI or not best then
			break
		end
		table.remove(sleeping, bestI)
		now = math.max(now, best.at)
		resume(best.co, table.unpack(best.args or {}))
	end
	now = target
end

local fakeOs = table.clone(os)
fakeOs.clock = function()
	return now
end

-- 偽物の Instance ------------------------------------------------------------------
local function Signal()
	local s: any = { handlers = {} }
	function s:Connect(fn)
		local h = { fn = fn, Connected = true }
		table.insert(self.handlers, h)
		function h.Disconnect()
			h.Connected = false
		end
		return h
	end
	s.Once = s.Connect
	function s:Fire(...)
		for _, h in table.clone(self.handlers) do
			if h.Connected then
				fakeTask.spawn(h.fn, ...)
			end
		end
	end
	function s:Wait() end
	return s
end

local EVENTS = {
	Activated = true,
	MouseButton1Down = true,
	MouseButton1Up = true,
	MouseButton1Click = true,
	MouseLeave = true,
	MouseEnter = true,
	Changed = true,
	Destroying = true,
	OnClientEvent = true,
	Event = true,
	Heartbeat = true,
	RenderStepped = true,
	FocusLost = true,
	InputBegan = true,
	InputEnded = true,
	TeleportInitFailed = true,
	FriendStatusChanged = true,
	PlayerAdded = true,
	PlayerRemoving = true,
}
local IS_A = {
	Part = { BasePart = true, Instance = true },
	TextButton = { GuiButton = true, GuiObject = true, TextButton = true },
	ImageButton = { GuiButton = true, GuiObject = true },
	TextLabel = { GuiObject = true },
	ImageLabel = { GuiObject = true },
	Frame = { GuiObject = true },
	ScrollingFrame = { GuiObject = true },
	ViewportFrame = { GuiObject = true },
	BillboardGui = { LayerCollector = true },
	ScreenGui = { LayerCollector = true },
}

local methods: any = {}
local mt: any = {}
local function newInstance(className: string): any
	local self = setmetatable({
		__props = { ClassName = className, Name = className },
		__children = {},
		__attrs = {},
		__signals = {},
		__attrSignals = {},
	}, mt)
	return self
end
mt.__index = function(t, k)
	local props = rawget(t, "__props")
	local v = props[k]
	if v ~= nil then
		return v
	end
	if methods[k] then
		return methods[k]
	end
	if EVENTS[k] then
		local sigs = rawget(t, "__signals")
		sigs[k] = sigs[k] or Signal()
		return sigs[k]
	end
	return nil
end
mt.__newindex = function(t, k, v)
	local props = rawget(t, "__props")
	if k == "Parent" then
		local old = props.Parent
		if old then
			local list = rawget(old, "__children")
			local i = table.find(list, t)
			if i then
				table.remove(list, i)
			end
		end
		if v then
			table.insert(rawget(v, "__children"), t)
		end
	end
	props[k] = v
end
mt.__tostring = function(t)
	return "Fake" .. rawget(t, "__props").ClassName
end

-- BindableEvent
function methods:Fire(...)
	self.Event:Fire(...)
end
function methods:GetChildren()
	return table.clone(rawget(self, "__children"))
end
function methods:GetDescendants()
	local out = {}
	local function walk(n)
		for _, c in rawget(n, "__children") do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function methods:FindFirstChild(name)
	for _, c in rawget(self, "__children") do
		if c.Name == name then
			return c
		end
	end
	return nil
end
function methods:WaitForChild(name)
	return self:FindFirstChild(name)
end
function methods:FindFirstChildOfClass(cls)
	for _, c in rawget(self, "__children") do
		if c.ClassName == cls then
			return c
		end
	end
	return nil
end
function methods:IsA(cls)
	local own = self.ClassName
	return own == cls or (IS_A[own] ~= nil and IS_A[own][cls] == true) or cls == "Instance"
end
function methods:Destroy()
	for _, c in self:GetChildren() do
		c:Destroy()
	end
	self.Destroying:Fire()
	self.Parent = nil
	rawget(self, "__props").Destroyed = true
end
function methods:ClearAllChildren()
	for _, c in self:GetChildren() do
		c:Destroy()
	end
end
function methods:SetAttribute(k, v)
	rawget(self, "__attrs")[k] = v
	local s = rawget(self, "__attrSignals")[k]
	if s then
		s:Fire()
	end
end
function methods:GetAttribute(k)
	return rawget(self, "__attrs")[k]
end
function methods:GetAttributeChangedSignal(k)
	local sigs = rawget(self, "__attrSignals")
	sigs[k] = sigs[k] or Signal()
	return sigs[k]
end
function methods:GetPropertyChangedSignal()
	return Signal()
end
function methods:PivotTo(cf)
	rawget(self, "__props").Pivot = cf
end
function methods:GetBoundingBox()
	return roblox.CFrame.new(), roblox.Vector3.new(4, 2, 1)
end

local created = 0
local function fakeNew(className: string): any
	created += 1
	return newInstance(className)
end

local function walkFind(root: any, pred: (any) -> boolean): { any }
	local out = {}
	for _, d in root:GetDescendants() do
		if pred(d) then
			table.insert(out, d)
		end
	end
	return out
end

local function visible(inst: any): boolean
	local n = inst
	while n do
		if n.Visible == false then
			return false
		end
		n = n.Parent
	end
	return true
end

-- 画面に見えている、その文字のボタン
local function button(root: any, text: string): any
	for _, b in
		walkFind(root, function(d)
			return d.ClassName == "TextButton" and d.Text == text and visible(d)
		end)
	do
		return b
	end
	return nil
end

local function enabled(b: any): boolean
	return b ~= nil and b:GetAttribute("Disabled") ~= true
end

local function visibleButtons(root: any): string
	local names = {}
	for _, d in
		walkFind(root, function(d)
			return d.ClassName == "TextButton" and visible(d) and d.Text ~= ""
		end)
	do
		table.insert(names, d.Text .. (if enabled(d) then "" else "(off)"))
	end
	return table.concat(names, " | ")
end

local function click(b: any)
	if not b then
		error("button not found; visible: " .. visibleButtons(rawget(_G, "__gui")), 2)
	end
	if not enabled(b) then
		error("button disabled: " .. tostring(b.Text), 2)
	end
	b.Activated:Fire()
end

local function hasText(root: any, pattern: string): boolean
	for _, d in
		walkFind(root, function(d)
			return type(d.Text) == "string" and visible(d)
		end)
	do
		if d.Text:find(pattern, 1, true) then
			return true
		end
	end
	return false
end

-- 画面の写し(UI_SNAPSHOTS=フォルダ を付けて実行すると、場面ごとに画面の木を JSON で書き出す。
-- node tools/ui/render_ui.js で PNG にできる)
local snapshotDir = process.env.UI_SNAPSHOTS
local function ser(v: any): any
	local ty = typeof(v)
	if ty == "UDim2" then
		return { xs = v.X.Scale, xo = v.X.Offset, ys = v.Y.Scale, yo = v.Y.Offset }
	elseif ty == "UDim" then
		return { s = v.Scale, o = v.Offset }
	elseif ty == "Vector2" then
		return { x = v.X, y = v.Y }
	elseif ty == "Color3" then
		return { r = v.R, g = v.G, b = v.B }
	elseif ty == "EnumItem" then
		return { name = v.Name }
	elseif ty == "ColorSequence" then
		local k = v.Keypoints
		return { c0 = ser(k[1].Value), c1 = ser(k[#k].Value) }
	elseif ty == "number" or ty == "string" or ty == "boolean" then
		return v
	end
	return nil
end
local function dumpTree(inst: any): any
	local props = {}
	for k, v in rawget(inst, "__props") do
		if k ~= "Parent" then
			local x = ser(v)
			if x ~= nil then
				props[k] = x
			end
		end
	end
	local kids = {}
	for _, c in rawget(inst, "__children") do
		table.insert(kids, dumpTree(c))
	end
	return { c = inst.ClassName, p = props, k = kids }
end
local snapshotGui: any = nil
local function snapshot(name: string)
	if not snapshotDir or not snapshotGui then
		return
	end
	if not fs.isDir(snapshotDir) then
		fs.writeDir(snapshotDir)
	end
	fs.writeFile(snapshotDir .. "/" .. name .. ".json", serde.encode("json", dumpTree(snapshotGui)))
end

-- 偽物のサービス ------------------------------------------------------------------
local requests: { { action: string, payload: any } } = {}
local remotes: { [string]: any } = {}
local function remote(name: string): any
	local r = remotes[name]
	if not r then
		r = fakeNew("RemoteEvent")
		r.Name = name
		rawset(r, "sent", {})
		r.FireServer = function(self, ...)
			table.insert(rawget(self, "sent"), { ... })
		end
		remotes[name] = r
	end
	return r
end

local function makePlayer(userId: number, name: string): any
	local p = fakeNew("Player")
	p.UserId = userId
	p.Name = name
	p.DisplayName = name
	return p
end

local me = makePlayer(1, "Me")
local playerGui = fakeNew("PlayerGui")
playerGui.Name = "PlayerGui"
playerGui.Parent = me
local friends = { [2] = true }
me.IsFriendsWith = function(_, id)
	return friends[id] == true
end
me.GetFriendsOnline = function()
	return {
		{ VisitorId = 9, UserName = "far", DisplayName = "Far", PlaceId = 77, GameId = "job-2" },
		{ VisitorId = 8, UserName = "web", DisplayName = "Web", PlaceId = 0, GameId = nil },
	}
end
local others: { any } = {}
local Players: any = {
	LocalPlayer = me,
	PlayerAdded = Signal(),
	PlayerRemoving = Signal(),
}
function Players:GetPlayers()
	local list = { me }
	for _, p in others do
		table.insert(list, p)
	end
	return list
end
function Players:GetPlayerByUserId(id)
	for _, p in self:GetPlayers() do
		if p.UserId == id then
			return p
		end
	end
	return nil
end

local teleports, invitesPrompted, friendPrompts = {}, 0, 0
local services: { [string]: any } = {
	Players = Players,
	ReplicatedStorage = {
		WaitForChild = function()
			return shared
		end,
	},
	RunService = { Heartbeat = Signal(), RenderStepped = Signal() },
	TweenService = {
		-- 短い動きは一瞬で終わらせる(画面の写しで、動き終わった形を見るため)。長い動き(残り時間の帯)は始めのまま
		Create = function(_, inst, info, goal)
			return {
				Play = function()
					if (info.Time or 0) <= 1 then
						for k, v in goal do
							inst[k] = v
						end
					end
				end,
				Cancel = function() end,
			}
		end,
	},
	StarterGui = {
		SetCore = function(_, name)
			if name == "PromptSendFriendRequest" then
				friendPrompts += 1
			end
		end,
	},
	SocialService = {
		CanSendGameInviteAsync = function()
			return true
		end,
		PromptGameInvite = function()
			invitesPrompted += 1
		end,
	},
	TeleportService = {
		TeleportToPlaceInstance = function(_, placeId, jobId)
			table.insert(teleports, { placeId, jobId })
		end,
		TeleportInitFailed = Signal(),
	},
}
local camera = fakeNew("Camera")
camera.ViewportSize = roblox.Vector2.new(1280, 720)
local workspace: any = fakeNew("Workspace")
workspace.CurrentCamera = camera
workspace.GetServerTimeNow = function()
	return 1.75e9
end

-- 画面以外の部品は偽物に
local function noop() end
H.override(client.Controllers.Sound, { play = noop })
H.override(client.Controllers.Cry, { say = noop, bubble = noop, play = noop })
H.override(client.Controllers.Input, { setEnabled = noop })
H.override(client.Controllers.Notify, { key = noop, show = noop })
H.override(shared.Lib.Remotes, { event = remote })
H.override(shared.Lib.FishBuilder, {
	build = function(def)
		local m = fakeNew("Model")
		m.Name = def.id
		return m
	end,
})

-- 自分のデータ(サーバーから届く写しと同じ形)
local fishA, fishB = Config.Fish[1], Config.Fish[2]
local profile: any = {
	coins = 1000,
	team = { 11, 12 },
	partners = {
		{ uid = 11, fishId = fishA.id, level = 20, grams = 900 },
		{ uid = 12, fishId = fishB.id, level = 12, grams = 900 },
	},
	battle = { cleared = {}, rematchPaid = {} },
	pvp = { rating = 1000, wins = 2, losses = 1, dailyWinDay = -1 },
	raid = { paid = {}, clears = {} },
	settings = { challenges = "all" },
	creel = {},
	equippedBait = "",
	bait = {},
	quests = { list = {} },
	daily = { pending = false },
}
local stateChanged = Signal()
H.override(client.ClientState, {
	profile = profile,
	Changed = stateChanged,
	creelCapacity = function()
		return 20
	end,
	luck = function()
		return 1
	end,
	hasPass = function()
		return false
	end,
	request = function(action, payload)
		table.insert(requests, { action = action, payload = payload })
	end,
})

local function lastRequest(action: string): any
	for i = #requests, 1, -1 do
		if requests[i].action == action then
			return requests[i]
		end
	end
	return nil
end

H.globals = {
	game = {
		PlaceId = 77,
		JobId = "job-1",
		GetService = function(_, name)
			return services[name] or {}
		end,
	},
	workspace = workspace,
	task = fakeTask,
	os = fakeOs,
	TweenInfo = {
		new = function(time)
			return { Time = time or 1 }
		end,
	},
	Instance = { new = fakeNew },
}
Locale.set("ja")
local Root = H.require(client.UI.Root)
local Online = H.require(client.Controllers.Online)
local BattleUI = H.require(client.Controllers.BattleUI)
local Social = H.require(client.Controllers.Social)
local HUD = H.require(client.Controllers.HUD)
local gui = Root.init()
rawset(_G, "__gui", gui)
snapshotGui = gui
Online.init(gui)
HUD.init(gui)
BattleUI.init(gui)
Social.init(gui)

local arena = remote("Arena")
local battleState = remote("BattleState")
local function arenaSay(msg: any)
	arena.OnClientEvent:Fire(msg)
end
local function serverSays(msg: any)
	battleState.OnClientEvent:Fire(msg)
end
local function t(key: string, args: any?): string
	return Locale.t(key, args)
end

-- 戦いの状態を本物のしくみで作る
local function fighters(list: { { any } }): { any }
	local out = {}
	for _, x in list do
		table.insert(out, BattleLib.fighter(Config.FishById[x[1]], 900, nil, x[2]))
	end
	return out
end
local function rng()
	return 0.5
end

print("クライアントの画面")

H.test(
	"対戦の画面: タブ(妖怪退治 / ボス戦 / オンライン対戦)が開き、それぞれの中身が出る",
	function()
		Root.open("battle", "online")
		H.assert(Root.isOpen("battle"), "battle hub not open")
		H.assert(hasText(gui, "1000"), "rating not shown")
		H.assert(hasText(gui, t("pvp_record", { w = 2, l = 1 })), "record not shown")
		H.assert(enabled(button(gui, t("pvp_random"))), "random button disabled")
		snapshot("hub_online")
		click(button(gui, "🐲 " .. t("tab_boss")))
		local name1 = Config.Bosses[1].ja
		H.assert(hasText(gui, name1), "boss row missing")
		-- チームの最高 Lv20 は、Lv18 推奨のボスには足りていて、Lv28 推奨には足りない
		H.assert(hasText(gui, t("boss_team_ok", { lv = Config.Bosses[1].recommend })), "recommend ok missing")
		H.assert(
			hasText(gui, t("boss_team_low", { lv = Config.Bosses[2].recommend, mine = 20 })),
			"recommend warning missing"
		)
		snapshot("hub_boss")
		click(button(gui, "👹 " .. t("tab_trainers")))
		H.assert(hasText(gui, Config.Trainers[1].ja), "trainer list missing")
		snapshot("hub_trainers")
	end
)

H.test(
	"ボス戦の部屋: ほかの人の部屋に「参加」→ 自分の部屋の札 → 部屋主だけ「始める」",
	function()
		Root.open("battle", "boss")
		local bossId = Config.Bosses[1].id
		arenaSay({
			kind = "rooms",
			rooms = {
				{
					id = 5,
					bossId = bossId,
					hostId = 2,
					members = { { userId = 2, name = "Aki" } },
					max = 4,
					startsIn = 30,
				},
			},
		})
		local join = button(gui, t("boss_join_n", { n = 1, max = 4 }))
		H.assert(enabled(join), "join button missing")
		click(join)
		H.assertEq(lastRequest("raidJoin").payload, 5, "join request")
		arenaSay({
			kind = "rooms",
			rooms = {
				{
					id = 5,
					bossId = bossId,
					hostId = 2,
					members = { { userId = 2, name = "Aki" }, { userId = 1, name = "Me" } },
					max = 4,
					startsIn = 30,
				},
			},
		})
		H.assert(hasText(gui, t("boss_my_room", { n = 2, max = 4, s = 30 })), "my room card missing")
		H.assert(button(gui, t("boss_start")) == nil, "non-host sees start")
		-- ほかのボスの「部屋を作る」は、部屋にいる間は押せない
		H.assert(not enabled(button(gui, t("boss_create"))), "create enabled while in a room")
		advance(5)
		services.RunService.Heartbeat:Fire(1)
		H.assert(hasText(gui, t("boss_my_room", { n = 2, max = 4, s = 25 })), "countdown not ticking")
		snapshot("hub_boss_room")
		-- 左の札にも出る(押すと抜ける)
		H.assert(
			hasText(gui, t("pill_room", { boss = Config.Bosses[1].ja, n = 2, max = 4, s = 25 })),
			"room pill missing"
		)
		click(button(gui, t("boss_leave")))
		H.assert(lastRequest("raidLeave"), "leave not sent")
		arenaSay({ kind = "rooms", rooms = {} })
		H.assert(not hasText(gui, t("boss_my_room", { n = 2, max = 4, s = 25 })), "room card stays")
	end
)

H.test("ランダム対戦: 押す → さがしている表示(左の札も) → やめる", function()
	Root.open("battle", "online")
	click(button(gui, t("pvp_random")))
	H.assert(lastRequest("pvpQueue"), "queue not requested")
	arenaSay({ kind = "queue", state = "searching" })
	advance(12)
	services.RunService.Heartbeat:Fire(1)
	H.assert(hasText(gui, t("pvp_searching", { t = "0:12" })), "searching text missing")
	snapshot("hub_online_searching")
	H.assert(button(gui, t("pvp_random")) == nil, "random button still shown")
	arenaSay({ kind = "queue", state = "ghost" })
	H.assert(hasText(gui, t("pvp_searching_ghost")), "ghost text missing")
	click(button(gui, t("pvp_cancel")))
	H.assert(lastRequest("pvpCancel"), "cancel not sent")
	arenaSay({ kind = "queue", state = "idle" })
	H.assert(button(gui, t("pvp_random")) ~= nil, "random button not back")
end)

H.test(
	"申し込みのカード: 受ける/断る、時間切れで消える。仲間募集のカードから参加",
	function()
		Root.close()
		arenaSay({ kind = "invite", from = 2, name = "Aki", rating = 1100, title = "", seconds = 20 })
		H.assertEq(Online.pendingInvites(), 1)
		H.assert(hasText(gui, t("invite_title", { name = "Aki" })), "invite card missing")
		snapshot("invite_card")
		click(button(gui, t("invite_accept")))
		local r = lastRequest("pvpRespond")
		H.assert(r and r.payload.from == 2 and r.payload.accept == true, "accept payload")
		H.assertEq(Online.pendingInvites(), 0)
		arenaSay({ kind = "invite", from = 3, name = "Bo", rating = 900, seconds = 20 })
		advance(21)
		H.assertEq(Online.pendingInvites(), 0, "invite not expired")
		arenaSay({ kind = "recruit", roomId = 9, bossId = Config.Bosses[2].id, hostId = 3, name = "Bo" })
		snapshot("recruit_card")
		click(button(gui, t("boss_join")))
		H.assertEq(lastRequest("raidJoin").payload, 9, "recruit join")
		advance(13)
	end
)

H.test(
	"対戦(人と): 名乗り → 技を選ぶ → 相手待ち → 相手も選んだ → ターン → 時間切れ → 降参は2回押す → 結果",
	function()
		local state = BattleLib.new(
			fighters({ { fishA.id, 20 }, { fishB.id, 12 } }),
			fighters({ { fishB.id, 18 }, { fishA.id, 15 } })
		)
		serverSays({
			kind = "start",
			mode = "pvp",
			pvpKind = "challenge",
			opponent = { name = "Aki", title = "", rating = 1100 },
			state = BattleLib.publicState(state, "player"),
			seconds = 35,
		})
		H.assert(gui:FindFirstChild("Battle"), "battle screen not open")
		H.assert(hasText(gui, t("pvp_vs", { name = "Aki" })), "VS header missing")
		advance(4) -- 名乗りの演出
		H.assert(hasText(gui, t("battle_choose")), "not asking to choose")
		local moveName = Config.MoveById[state.sides.player.team[1].moves[1]].ja
		local moveButton = nil
		for _, b in
			walkFind(gui, function(d)
				return d.ClassName == "TextButton"
					and type(d.Text) == "string"
					and d.Text:find(moveName, 1, true) ~= nil
			end)
		do
			moveButton = b
		end
		H.assert(enabled(moveButton), "move button disabled")
		click(moveButton)
		local sent = rawget(remote("BattleAction"), "sent")
		H.assertEq(sent[#sent][1].kind, "move")
		H.assert(hasText(gui, t("pvp_waiting")), "waiting message missing")
		H.assert(not enabled(moveButton), "can pick twice")
		serverSays({ kind = "foeReady" })
		H.assert(hasText(gui, t("pvp_foe_ready")), "foe ready badge missing")
		snapshot("pvp_waiting")
		local events = BattleLib.turn(state, { kind = "move", index = 1 }, rng, { kind = "move", index = 1 })
		serverSays({
			kind = "turn",
			mode = "pvp",
			events = events,
			state = BattleLib.publicState(state, "player"),
			seconds = 25,
		})
		advance(8) -- 演出
		H.assert(enabled(moveButton) or state.over, "move button not re-enabled")
		-- 時間切れ: 押せなくなり「コンピューターが代わりに」
		advance(25)
		services.RunService.RenderStepped:Fire()
		H.assert(hasText(gui, t("pvp_timeout")), "timeout message missing")
		snapshot("pvp_timeout")
		-- 降参: 1回目は確認だけ
		local before = #sent
		local forfeit = button(gui, t("pvp_forfeit"))
		serverSays({
			kind = "turn",
			mode = "pvp",
			events = {},
			state = BattleLib.publicState(state, "player"),
			seconds = 25,
		})
		advance(1)
		forfeit = button(gui, t("pvp_forfeit"))
		click(forfeit)
		H.assertEq(#sent, before, "forfeit sent without confirm")
		H.assert(hasText(gui, t("pvp_forfeit_confirm")), "confirm text missing")
		click(button(gui, t("pvp_forfeit_confirm")))
		H.assertEq(sent[#sent][1].kind, "run", "forfeit not sent")
		serverSays({
			kind = "turn",
			mode = "pvp",
			events = { { kind = "run", side = "player" }, { kind = "end", winner = "enemy" } },
			state = BattleLib.publicState(state, "player"),
			seconds = 25,
		})
		serverSays({
			kind = "result",
			mode = "pvp",
			pvpKind = "challenge",
			win = false,
			coins = 0,
			ranked = false,
			ratingFrom = 1000,
			ratingTo = 1000,
		})
		advance(3)
		H.assert(hasText(gui, t("battle_lose")), "result missing")
		H.assert(hasText(gui, t("pvp_friendly_note")), "friendly note missing")
		snapshot("pvp_result_friendly")
		H.assert(button(gui, t("pvp_again")) == nil, "again shown for a challenge")
		click(button(gui, t("close")))
		H.assert(gui:FindFirstChild("Battle") == nil, "screen not closed")
		H.assert(Root.isOpen("battle"), "did not return to hub")
	end
)

H.test(
	"ランダム対戦の結果: 点数の変化・初勝利の小判・「もう一度」で続けてさがす",
	function()
		local state = BattleLib.new(fighters({ { fishA.id, 20 } }), fighters({ { fishB.id, 5 } }))
		serverSays({
			kind = "start",
			mode = "pvp",
			pvpKind = "ghost",
			opponent = { ghost = true, title = "", rating = 990 },
			state = BattleLib.publicState(state, "player"),
			seconds = 35,
		})
		H.assert(hasText(gui, t("pvp_vs", { name = t("pvp_ghost_name") })), "ghost header missing")
		serverSays({
			kind = "result",
			mode = "pvp",
			pvpKind = "ghost",
			win = true,
			coins = 1500,
			ranked = true,
			ratingFrom = 1000,
			ratingTo = 1016,
		})
		advance(5)
		H.assert(
			hasText(gui, t("pvp_rating_change", { from = 1000, to = 1016, d = "+16" })),
			"rating change missing"
		)
		H.assert(
			hasText(gui, t("pvp_daily_coins", { coins = Format.coins(1500, "ja") })),
			"daily coins missing"
		)
		snapshot("pvp_result_ranked")
		local n = #requests
		click(button(gui, t("pvp_again")))
		H.assertEq(#requests, n + 1)
		H.assertEq(requests[#requests].action, "pvpQueue")
		H.assert(gui:FindFirstChild("Battle") == nil, "screen not closed")
	end
)

H.test(
	"ボス戦: 仲間の札・怒り・ほかの人が削った体力・倒れたら見守り(抜けるは押せる)→ 結果からボス戦のタブへ",
	function()
		local bs = Config.Bosses[1]
		local foe = BattleLib.fighter(Config.FishById[bs.fish], 9000, nil, bs.level)
		foe.maxHp *= 8
		foe.hp = foe.maxHp
		local state = BattleLib.new(fighters({ { fishA.id, 20 } }), { foe })
		local info = {
			bossId = bs.id,
			hp = foe.maxHp,
			max = foe.maxHp,
			seconds = 240,
			enraged = false,
			members = {
				{ userId = 1, name = "Me", alive = true, dealt = 0 },
				{ userId = 2, name = "Aki", alive = true, dealt = 0 },
			},
		}
		serverSays({
			kind = "start",
			mode = "raid",
			bossId = bs.id,
			state = BattleLib.publicState(state),
			raid = info,
		})
		H.assert(hasText(gui, "🐲 " .. bs.ja), "boss header missing")
		H.assert(hasText(gui, t("raid_leave")), "leave button missing")
		advance(5)
		-- ほかの人が削った
		local info2 = table.clone(info)
		info2.hp = math.floor(foe.maxHp * 0.4)
		info2.enraged = true
		info2.seconds = 235
		info2.members = {
			{ userId = 1, name = "Me", alive = true, dealt = 0 },
			{ userId = 2, name = "Aki", alive = true, dealt = 1234 },
		}
		serverSays({ kind = "raid", raid = info2 })
		H.assert(hasText(gui, t("raid_rage")), "enraged badge missing")
		H.assert(hasText(gui, Format.coins(1234, "ja")), "party damage missing")
		H.assert(hasText(gui, t("raid_enraged", { boss = bs.ja })), "enraged message missing")
		services.RunService.RenderStepped:Fire()
		H.assert(hasText(gui, t("raid_time", { t = "3:55" })), "raid timer missing")
		snapshot("raid")
		-- 自分の相棒が全員倒れた
		state.sides.player.team[1].hp = 0
		state.over = true
		state.winner = "enemy"
		serverSays({
			kind = "turn",
			mode = "raid",
			events = { { kind = "faint", side = "player", fishId = fishA.id } },
			state = BattleLib.publicState(state),
		})
		advance(3)
		H.assert(hasText(gui, t("raid_down")), "down message missing")
		-- 自分のターンの状態が届いても、ほかの人が削った分は戻らない
		H.assert(hasText(gui, Format.coins(info2.hp, "ja") .. " / "), "boss hp jumped back after a turn")
		local leave = button(gui, t("raid_leave"))
		H.assert(enabled(leave), "leave disabled while watching")
		snapshot("raid_down")
		serverSays({
			kind = "result",
			mode = "raid",
			bossId = bs.id,
			win = true,
			coins = 6000,
			bait = { id = "glow_shrimp", amount = 2 },
			gains = { { fishId = fishA.id, xp = 100, level = 21, from = 20, levels = 1 } },
			dealt = 4321,
			rewardPaidToday = false,
		})
		advance(2)
		H.assert(hasText(gui, t("raid_win")), "raid win missing")
		H.assert(hasText(gui, t("raid_dealt", { n = Format.coins(4321, "ja") })), "dealt missing")
		snapshot("raid_result")
		H.assert(not enabled(button(gui, t("raid_leave"))), "leave still enabled after result")
		click(button(gui, t("close")))
		H.assert(Root.isOpen("battle"), "hub not reopened")
		H.assert(hasText(gui, bs.ja), "not on boss tab")
	end
)

H.test(
	"妖怪退治(今まで通り): 逃げるは確認なしですぐ送る。再戦の小判を今日もらった相手は「受け取り済み」",
	function()
		local WorldClock = H.require(shared.Lib.WorldClock)
		local tr = Config.Trainers[1]
		profile.battle.cleared[tr.id] = true
		profile.battle.rematchPaid[tr.id] = WorldClock.dayIndex(1.75e9, Config.Tuning.Quests.dayOffsetSeconds)
		Root.open("battle", "trainers")
		H.assert(hasText(gui, t("battle_rematch_paid")), "rematch paid not shown")
		snapshot("hub_trainers_paid")
		local state = BattleLib.new(fighters({ { fishA.id, 20 } }), fighters({ { fishB.id, 5 } }))
		serverSays({ kind = "start", trainerId = tr.id, state = BattleLib.publicState(state) })
		H.assert(hasText(gui, tr.ja), "trainer header missing")
		advance(4)
		local sent = rawget(remote("BattleAction"), "sent")
		local before = #sent
		snapshot("trainer_battle")
		click(button(gui, t("battle_run")))
		H.assertEq(#sent, before + 1, "run needs no confirm for trainers")
		H.assertEq(sent[#sent][1].kind, "run")
		local runEvents = BattleLib.turn(state, { kind = "run" }, rng)
		serverSays({ kind = "turn", events = runEvents, state = BattleLib.publicState(state) })
		serverSays({ kind = "result", win = false, gains = {} })
		advance(3)
		H.assert(hasText(gui, t("battle_ran")), "ran message missing")
		click(button(gui, t("close")))
		H.assert(Root.isOpen("battle"), "hub not reopened")
	end
)

H.test(
	"なかま: 一覧(友達が上・受付なし・対戦中)、申し込み → 取り消す、水槽、友達申請、招待、ほかのサーバーへ",
	function()
		local aki = makePlayer(2, "Aki")
		aki:SetAttribute("PvpRating", 1100)
		aki:SetAttribute("Codex", 12)
		aki:SetAttribute("TitleId", "")
		aki:SetAttribute("ChallengePref", "friends")
		local bo = makePlayer(3, "Bo")
		bo:SetAttribute("ChallengePref", "off")
		local cy = makePlayer(4, "Cy")
		cy:SetAttribute("InBattle", true)
		others = { bo, cy, aki }
		Root.open("social")
		advance(0.1) -- フレンドの問い合わせ
		advance(1.1)
		H.assert(hasText(gui, t("social_here", { n = 4, max = Config.Online.MaxPlayers })), "count missing")
		H.assert(hasText(gui, t("social_closed")), "closed state missing")
		H.assert(hasText(gui, t("social_in_battle")), "in-battle state missing")
		snapshot("social")
		-- Aki は友達だけ受け付ける。自分は友達なので押せる
		local challenge = nil
		for _, b in
			walkFind(gui, function(d)
				return d.ClassName == "TextButton" and d.Text == t("social_challenge") and visible(d)
			end)
		do
			challenge = b
		end
		H.assert(enabled(challenge), "challenge to friend disabled")
		click(challenge)
		H.assertEq(lastRequest("pvpChallenge").payload, 2)
		arenaSay({ kind = "sent", to = 2, name = "Aki", seconds = 20 })
		advance(2)
		services.RunService.Heartbeat:Fire(1)
		local withdraw = nil
		for _, b in
			walkFind(gui, function(d)
				return d.ClassName == "TextButton"
					and type(d.Text) == "string"
					and d.Text:find(t("social_you_sent", { s = "" }), 1, true) == 1
			end)
		do
			withdraw = b
		end
		H.assert(withdraw, "withdraw button missing: " .. visibleButtons(gui))
		H.assert(hasText(gui, t("pill_sent", { name = "Aki", s = 18 })), "sent pill missing")
		click(withdraw)
		H.assert(lastRequest("pvpCancelChallenge"), "withdraw not sent")
		arenaSay({ kind = "sentGone" })
		-- 友達ではない人にだけ「友達申請」
		H.assertEq(#walkFind(gui, function(d)
			return d.ClassName == "TextButton" and d.Text == t("social_add_friend") and visible(d)
		end), 2, "friend buttons")
		click(button(gui, t("social_add_friend")))
		H.assertEq(friendPrompts, 1)
		click(button(gui, t("social_invite")))
		H.assertEq(invitesPrompted, 1)
		-- ほかのサーバーのフレンド(同じゲームの別サーバーだけ)
		H.assert(hasText(gui, "Far") and not hasText(gui, "Web"), "friends online filter")
		click(button(gui, t("social_join")))
		H.assertEq(teleports[1][2], "job-2")
		click(button(gui, t("social_tank")))
		H.assertEq(type(lastRequest("visitTank").payload), "number")
		H.assert(not Root.isOpen("social"), "panel not closed after visit")
	end
)

H.test(
	"スタンプ: 選んで送る(続けて送れない)・届いたら頭の上に出る・申し込みの受け方を切り替える",
	function()
		local head = fakeNew("Part")
		head.Name = "Head"
		local char = fakeNew("Model")
		head.Parent = char
		me.Character = char
		click(button(gui, "💬"))
		snapshot("stamps")
		click(button(gui, t("stamp_hello")))
		local sent = rawget(remote("Stamp"), "sent")
		H.assertEq(#sent, 1)
		H.assertEq(sent[1][1], "hello")
		H.assert(not enabled(button(gui, "💬")), "stamp button not cooling down")
		advance(2)
		H.assert(enabled(button(gui, "💬")), "stamp button stays off")
		remote("StampShown").OnClientEvent:Fire(1, "hello")
		local bb = playerGui:FindFirstChild("Stamp")
		H.assert(bb and bb.Adornee == head, "bubble not shown")
		remote("StampShown").OnClientEvent:Fire(1, "not_a_stamp")
		advance(4)
		H.assert(playerGui:FindFirstChild("Stamp") == nil, "bubble stays")
		Root.open("battle", "online")
		click(button(gui, t("pref_friends")))
		H.assertEq(lastRequest("setChallengePref").payload, "friends")
	end
)

H.test("言語を切り替えても壊れない(英語で全部の画面を開く)", function()
	Locale.set("en")
	Online.relabel()
	Social.relabel()
	BattleUI.relabel()
	for _, tab in { "trainers", "boss", "online" } do
		Root.open("battle", tab)
	end
	Root.open("battle", "boss")
	H.assert(hasText(gui, Config.Bosses[1].en), "boss names not relabelled")
	Root.open("social")
	H.assert(hasText(gui, Locale.t("social_title")), "social title")
	Locale.set("ja")
end)

H.globals = nil
local ok = H.summary()
process.exit(if ok then 0 else 1)
