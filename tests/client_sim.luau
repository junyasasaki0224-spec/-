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

local F = require("./fakes")
local fakeTask, fakeOs, advance, Signal = F.task, F.os, F.advance, F.Signal
local methods, fakeNew, walkFind, visible = F.methods, F.new, F.walkFind, F.visible
local button, cardFor, enabled, visibleButtons = F.button, F.cardFor, F.enabled, F.visibleButtons
local click, hasText, snapshot = F.click, F.hasText, F.snapshot

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
	UserInputService = { InputBegan = Signal() },
	-- 世界の「調べる」ボタン(バトルの間は止まる)
	CollectionService = {
		GetTagged = function(_, tag)
			return if tag == "YokaiPrompt" then { rawget(_G, "__shopPrompt") } else {}
		end,
	},
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
	-- 音の置き場(BGM が鳴っているかを調べる)
	SoundService = fakeNew("Folder"),
}
local camera = fakeNew("Camera")
camera.ViewportSize = roblox.Vector2.new(1280, 720)
camera.CameraType = roblox.Enum.CameraType.Custom
camera.FieldOfView = 70
-- 光の設定(バトルの間だけ水の中のものに変わり、終われば戻る)
local lighting = fakeNew("Lighting")
lighting.FogEnd = 100000
lighting.ClockTime = 14
local atmosphere = fakeNew("Atmosphere")
atmosphere.Name = "Atmosphere"
atmosphere.Parent = lighting
local grade = fakeNew("ColorCorrectionEffect")
grade.Name = "Grade"
grade.Parent = lighting
services.Lighting = lighting
local lightingHeld = false
local shopPrompt = fakeNew("ProximityPrompt")
shopPrompt.Enabled = true
rawset(_G, "__shopPrompt", shopPrompt)
local workspace: any = fakeNew("Workspace")
workspace.CurrentCamera = camera
workspace.GetServerTimeNow = function()
	return 1.75e9
end

-- 画面以外の部品は偽物に
local function noop() end
H.override(client.Controllers.Sound, {
	play = noop,
	isMuted = function()
		return false
	end,
})
H.override(client.Controllers.Cry, { say = noop, bubble = noop, play = noop })
H.override(client.Controllers.Input, { setEnabled = noop })
H.override(client.Controllers.Notify, { key = noop, show = noop })
H.override(client.Controllers.LightingFX, {
	hold = function(on)
		lightingHeld = on
	end,
})
H.override(shared.Lib.Remotes, { event = remote })
local RealFishBuilder = H.require(shared.Lib.FishBuilder)
H.override(shared.Lib.FishBuilder, {
	build = function(def)
		local m = fakeNew("Model")
		m.Name = def.id
		return m
	end,
	sizeOf = RealFishBuilder.sizeOf, -- 大きさの計算(レア度)は本物
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
-- ここから先(ゲームのコード)のプロパティの読み書きを、本物の Roblox の定義で確かめる
F.validating = true
local Root = H.require(client.UI.Root)
local Online = H.require(client.Controllers.Online)
local BattleUI = H.require(client.Controllers.BattleUI)
local Social = H.require(client.Controllers.Social)
local HUD = H.require(client.Controllers.HUD)
local gui = Root.init()
rawset(_G, "__gui", gui)
rawset(_G, "__beforeSnapshot", function()
	services.RunService.RenderStepped:Fire()
end)
F.setSnapshotRoot(gui)
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
		-- 技のお札: 名前はお札の中の文字
		local moveButton = cardFor(gui, moveName)
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
		H.assert(hasText(gui, "3:55"), "raid timer missing")
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
	"3Dの水の中: カメラが舞台へ・光が水の中に・2匹が泳ぐ・技で相手へ泳ぐ・倒れると水面へ・終われば元どおり",
	function()
		-- カメラの計算(注目点のまわりを回る): 回転なしなら真後ろ(+Z)から奥を見る
		local Scene = H.require(client.Controllers.BattleScene)
		local focus = roblox.Vector3.new(1, 2, 3)
		local cf = Scene.orbit(focus, 0, 0, 30)
		H.assert((cf.Position - (focus + roblox.Vector3.new(0, 0, 30))).Magnitude < 1e-4, "orbit position")
		H.assert((cf.LookVector - roblox.Vector3.new(0, 0, -1)).Magnitude < 1e-4, "orbit look")
		-- どのカメラも水面より下(水面の板の中や上から写さない)
		local Arena = H.require(client.Controllers.BattleArena)
		local I = Arena.INTRO_SHOT
		local introCam = Arena.orbit(roblox.Vector3.new(0, Arena.FISH_Y + I.up, 0), I.yaw, I.pitch, I.dist)
		H.assert(introCam.Position.Y < Arena.SURFACE_Y - 4, "intro camera breaks the surface")
		local B = Arena.BASE_SHOT
		H.assert(
			Arena.orbit(roblox.Vector3.new(0, Arena.FISH_Y, 0), 0, B.pitch + 0.03, B.bossDist + 1.5).Position.Y
				< Arena.SURFACE_Y - 4,
			"base camera breaks the surface"
		)
		local high = Scene.orbit(focus, 0.4, 0.3, 30)
		H.assert(high.Position.Y > focus.Y + 5, "pitch should raise the camera")
		H.assertNear((high.Position - focus).Magnitude, 30, 1e-3)

		local state = BattleLib.new(fighters({ { fishA.id, 20 } }), fighters({ { fishB.id, 12 } }))
		serverSays({ kind = "start", trainerId = Config.Trainers[1].id, state = BattleLib.publicState(state) })
		-- カメラは舞台へ、光は水の中へ
		H.assert(camera.CameraType == roblox.Enum.CameraType.Scriptable, "camera not taken")
		H.assert(lightingHeld, "day/weather look not paused")
		H.assert(lighting.FogEnd < 1000, "no underwater fog")
		H.assert(atmosphere.Parent == nil, "atmosphere still blocks the fog")
		H.assert(lighting:FindFirstChild("BattleDepth") ~= nil, "no depth of field")
		-- ふだんの画面(小判・メニュー・スタンプ)はバトルの後ろに見えない。お知らせのカードは残す
		H.assert(gui:FindFirstChild("HUD").Visible == false, "world HUD shows through the battle")
		H.assert(gui:FindFirstChild("StampButton").Visible == false, "stamp button shows through the battle")
		H.assert(gui:FindFirstChild("OnlineCards").Visible ~= false, "notice cards hidden in battle")
		-- 世界の「調べる」ボタンは止まり、ほかの画面はバトルの上に開かない
		H.assert(shopPrompt.Enabled == false, "world prompt still active in battle")
		Root.open("shop", "rods")
		H.assert(not Root.isOpen("shop"), "a panel opened over the battle")
		advance(4)
		local arena = workspace:FindFirstChild("BattleArena")
		H.assert(arena, "arena not built")
		local origin = Scene.orbit(roblox.Vector3.new(0, 2000, 0), 0, 0, 0).Position
		local battle = arena:FindFirstChild("Battle")
		local function fishModel(id: string): any
			for _, c in battle:GetChildren() do
				if c.ClassName == "Model" and c.Name == id then
					return c
				end
			end
			return nil
		end
		local mine, foe = fishModel(fishA.id), fishModel(fishB.id)
		H.assert(mine and foe, "fish not in the water")
		-- レアな大物ほど大きく戦う(並 約5 〜 秘伝 約8.7。舞台からはみ出さない)
		local common, legend, secret =
			Scene.lengthFor(Config.FishById.doro_funa),
			Scene.lengthFor(Config.FishById.kyubi_koi),
			Scene.lengthFor(Config.FishById.tsukuyomi_koi)
		H.assert(legend > common * 1.3 and secret > legend, "rarer fish should be bigger in battle")
		H.assert(
			common >= 4.8 and secret <= 8.8,
			("battle sizes out of range %.2f..%.2f"):format(common, secret)
		)
		local function x(m: any): number
			return m.Pivot.Position.X - origin.X
		end
		local step = services.RunService.RenderStepped
		step:Fire()
		H.assert(x(mine) < 0 and x(foe) > 0, "fish on the wrong sides")
		H.assert(math.abs(camera.CFrame.Position.Y - origin.Y) < 60, "camera not at the arena")
		local p1 = mine.Pivot.Position
		advance(0.5)
		step:Fire()
		H.assert((mine.Pivot.Position - p1).Magnitude > 0.01, "fish not swimming")
		-- 舞台の海藻も揺れている
		local kelpPart = nil
		for _, d in arena:FindFirstChild("Moving"):GetChildren() do
			if d.Name == "Block" then
				kelpPart = d
				break
			end
		end
		local k1 = kelpPart.CFrame
		advance(0.7)
		step:Fire()
		H.assert(kelpPart.CFrame ~= k1, "kelp not swaying")
		snapshot("underwater")

		-- キーボードの 1 で1枚目のお札
		local sent = rawget(remote("BattleAction"), "sent")
		local before = #sent
		services.UserInputService.InputBegan:Fire({ KeyCode = roblox.Enum.KeyCode.One }, false)
		H.assertEq(#sent, before + 1, "key 1 did not use a talisman")
		H.assertEq(sent[#sent][1].index, 1)

		-- 攻撃: 自分の魚が相手の方へ泳いでいき、当たった相手は倒れて水面へ
		local power = nil
		for _, id in state.sides.player.team[1].moves do
			if Config.MoveById[id].power > 0 then
				power = id
			end
		end
		local home = x(mine)
		state.sides.enemy.team[1].hp = 0
		state.over = true
		state.winner = "player"
		serverSays({
			kind = "turn",
			events = {
				{ kind = "move", side = "player", move = power },
				{ kind = "damage", side = "enemy", amount = 99, eff = 2, crit = true, hp = 0 },
				{ kind = "faint", side = "enemy", fishId = fishB.id },
				{ kind = "end", winner = "player" },
			},
			state = BattleLib.publicState(state),
		})
		advance(0.25)
		step:Fire()
		H.assert(x(mine) > home + 4, "attacker did not swim at the foe")
		-- 当たった所に3Dの演出(光る粒など)が出ている
		H.assert(#arena:FindFirstChild("Effects"):GetChildren() > 0, "no 3D effects on hit")
		snapshot("underwater_hit")
		advance(4)
		step:Fire()
		H.assert(foe.Parent == nil, "fainted fish still in the water")
		H.assert(mine.Parent ~= nil, "winner left the water")
		serverSays({ kind = "result", win = true, coins = 0, gains = {} })
		advance(2)
		click(button(gui, t("close")))
		-- 元どおり
		H.assert(camera.CameraType == roblox.Enum.CameraType.Custom, "camera not returned")
		H.assertEq(camera.FieldOfView, 70)
		H.assertEq(lighting.FogEnd, 100000)
		H.assert(atmosphere.Parent == lighting, "atmosphere not restored")
		H.assert(lighting:FindFirstChild("BattleDepth") == nil, "depth of field left behind")
		H.assert(not lightingHeld, "day/weather look still paused")
		H.assert(arena.Parent == nil, "arena still in the world")
		H.assert(gui:FindFirstChild("HUD").Visible ~= false, "world HUD not restored")
		H.assert(shopPrompt.Enabled == true, "world prompt not restored")
	end
)

H.test(
	"バトルの便利機能: ★おすすめ・おまかせ・2倍速(保存)・相性表・ゲームパッド",
	function()
		-- 水の技は火の相手によく効く → おすすめは水の技
		local waterFish, fireFish = nil, nil
		for _, f in Config.Fish do
			if f.element == "water" and not waterFish then
				waterFish = f
			elseif f.element == "fire" and not fireFish then
				fireFish = f
			end
		end
		local state = BattleLib.new(fighters({ { waterFish.id, 30 } }), fighters({ { fireFish.id, 30 } }))
		local moves = state.sides.player.team[1].moves
		local Advice = H.require(shared.Lib.BattleAdvice)
		local best = Advice.suggest(BattleLib.publicState(state))
		H.assert(best ~= nil, "no suggestion")
		serverSays({ kind = "start", trainerId = Config.Trainers[1].id, state = BattleLib.publicState(state) })
		advance(5)
		H.assert(hasText(gui, t("card_suggest")), "suggested card not marked")
		snapshot("battle_tools")

		-- 2倍速: サーバーに保存を頼み、すぐ反映
		click(button(gui, t("battle_speed", { n = 1 })))
		local r = lastRequest("setBattlePrefs")
		H.assert(r and r.payload.speed == 2, "speed pref not sent")
		H.assertEq(profile.settings.battleSpeed, 2)
		H.assert(button(gui, t("battle_speed", { n = 2 })) ~= nil, "speed button not updated")

		-- 相性表
		click(button(gui, t("battle_chart")))
		H.assert(hasText(gui, t("chart_title")) and hasText(gui, "◎"), "chart missing")
		snapshot("type_chart")
		click(gui:FindFirstChild("Battle"):FindFirstChild("Chart"))

		-- ゲームパッド: 十字キーの上 = 2枚目
		local sent = rawget(remote("BattleAction"), "sent")
		local before = #sent
		services.UserInputService.InputBegan:Fire({ KeyCode = roblox.Enum.KeyCode.DPadUp }, false)
		H.assertEq(#sent, before + 1, "dpad did not use a talisman")
		H.assertEq(sent[#sent][1].index, 2)
		-- 次の手番: おまかせにすると、おすすめを自動で使う
		serverSays({ kind = "turn", events = {}, state = BattleLib.publicState(state) })
		advance(0.2)
		click(button(gui, t("battle_auto")))
		before = #sent
		advance(1)
		H.assertEq(#sent, before + 1, "auto did not act")
		H.assertEq(sent[#sent][1].index, best, "auto picked something else")
		H.assert(moves[best] ~= nil)
		-- 逃げて終わる(おまかせは次のバトルには持ち越さない)
		serverSays({ kind = "turn", events = {}, state = BattleLib.publicState(state) })
		advance(0.2)
		click(button(gui, t("battle_run")))
		serverSays({ kind = "result", win = false, gains = {} })
		advance(2)
		click(button(gui, t("close")))
		profile.settings.battleSpeed = 1
	end
)

H.test(
	"交代: 「交代」→ 相棒の札を選ぶ → 前の子は泳ぎ去り、次の子が横から泳いでくる",
	function()
		local state =
			BattleLib.new(fighters({ { fishA.id, 20 }, { fishB.id, 12 } }), fighters({ { fishB.id, 9 } }))
		serverSays({ kind = "start", trainerId = Config.Trainers[1].id, state = BattleLib.publicState(state) })
		advance(4)
		click(button(gui, t("battle_switch")))
		H.assert(hasText(gui, t("battle_switch_title")), "switch picker missing")
		snapshot("switch_picker")
		local pick = cardFor(gui, Locale.fishName(fishB) .. "\nLv12")
		H.assert(pick and enabled(pick), "second partner not selectable")
		-- 今出ている子は選べない
		H.assert(not enabled(cardFor(gui, Locale.fishName(fishA) .. "\nLv20")), "active partner selectable")
		click(pick)
		local sent = rawget(remote("BattleAction"), "sent")
		H.assertEq(sent[#sent][1].kind, "switch")
		H.assertEq(sent[#sent][1].slot, 2)
		local events = BattleLib.turn(state, { kind = "switch", slot = 2 }, rng, { kind = "move", index = 1 })
		serverSays({ kind = "turn", events = events, state = BattleLib.publicState(state) })
		local water = workspace:FindFirstChild("BattleArena"):FindFirstChild("Battle")
		advance(0.3)
		services.RunService.RenderStepped:Fire()
		advance(6)
		services.RunService.RenderStepped:Fire()
		local names = {}
		for _, c in water:GetChildren() do
			if c.ClassName == "Model" then
				table.insert(names, c.Name)
			end
		end
		-- 自分は泥鮒→2匹目、相手は1匹: 水の中は2匹だけ
		H.assertEq(#names, 2, "fish count after switch: " .. table.concat(names, ","))
		H.assert(
			hasText(gui, t("battle_go", { name = Locale.fishName(fishB) }))
				or hasText(gui, t("battle_choose")),
			"no go line"
		)
		-- 交代で使ったお札の縁は元に戻る
		for _, c in
			walkFind(gui, function(d)
				return d.ClassName == "TextButton"
					and type(d.Name) == "string"
					and d.Name:find("Talisman", 1, true) == 1
			end)
		do
			H.assert(c:GetAttribute("Chosen") ~= true, "talisman stays chosen")
		end
		click(button(gui, t("battle_run")))
		serverSays({ kind = "result", win = false, gains = {} })
		advance(2)
		click(button(gui, t("close")))
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

H.test(
	"BGM: 場所で曲が変わり、バトル中はバトルの曲。切ると止まる(フェードで切り替え)",
	function()
		local Music = H.require(client.Controllers.Music)
		local M = Config.Music
		local saved = {}
		for name, tr in M.tracks do
			saved[name] = tr.soundId
			tr.soundId = "rbxassetid://1"
		end
		local root = fakeNew("Part")
		root.Name = "HumanoidRootPart"
		local char = fakeNew("Model")
		root.Parent = char
		me.Character = char
		local function at(spotId: string)
			local o = Config.SpotById[spotId].origin
			root.Position = roblox.Vector3.new(o.x + 30, 5, o.z - 20)
		end
		local function bgm(name: string): any
			return services.SoundService:FindFirstChild("BGM_" .. name)
		end
		for _, spotId in { "nushi_lake", "swamp", "river", "sea" } do
			at(spotId)
			Music.step(0.1)
			H.assertEq(Music.current(), M.areaTrack[spotId])
		end
		-- 海の曲がフェードで大きくなる
		for _ = 1, 30 do
			Music.step(0.1)
		end
		H.assertNear(bgm("sea").Volume, M.volume, 1e-6)
		-- バトルが始まるとバトルの曲、前の曲は小さくなって消える
		Music.battle(true)
		for _ = 1, 30 do
			Music.step(0.1)
		end
		H.assertEq(Music.current(), "battle")
		H.assert(bgm("sea") == nil, "sea still playing")
		H.assertNear(bgm("battle").Volume, M.volume, 1e-6)
		Music.battle(false)
		Music.step(0.1)
		H.assertEq(Music.current(), "sea")
		-- 遠く(どの釣り場からも離れた所)は村の曲
		root.Position = roblox.Vector3.new(-5000, 0, -5000)
		Music.step(0.1)
		H.assertEq(Music.current(), "village")
		-- 切ると全部止まる
		Music.setEnabled(false)
		for _ = 1, 30 do
			Music.step(0.1)
		end
		H.assertEq(Music.current(), nil)
		for name in M.tracks do
			H.assert(bgm(name) == nil, name .. " still playing")
		end
		Music.setEnabled(true)
		-- soundId が 0(まだアップロードしていない)なら鳴らさない
		for name, id in saved do
			M.tracks[name].soundId = id
		end
		at("river")
		Music.step(0.1)
		H.assertEq(Music.current(), if saved.river == "rbxassetid://0" then nil else "river")
	end
)

H.test(
	"Roblox の定義: 画面のコードが使うプロパティの名前と型がすべて正しい",
	function()
		local lines = {}
		for _, p in F.problems do
			table.insert(lines, ("%s.%s (%s) %s  @ %s"):format(p.class, p.key, p.kind, p.msg, p.where))
		end
		H.assert(#F.problems == 0, "\n      " .. table.concat(lines, "\n      "))
	end
)

H.globals = nil
local ok = H.summary()
process.exit(if ok then 0 else 1)
