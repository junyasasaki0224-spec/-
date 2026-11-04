-- クライアントを丸ごと起動する(本物の init.client.luau と、すべての画面・すべての部品)。
-- 1. サーバーが本当に送った知らせ(tests/fixtures/server_messages.json。server_sim が書き出す)を順に流し込む
-- 2. すべての画面を開き、見えているボタンを全部押してみる(エラーが出たら失敗)
-- 3. 釣り(投げる → アタリ → 合わせる → 引く)を、本物の操作の流れで通す
-- プロパティの読み書きは、本物の Roblox の定義(Lune の反射データ)で確かめる。
--   lune run tests/client_boot.luau [知らせのファイル]
--   知らせを作り直す: RECORD_MESSAGES=tests/fixtures/server_messages.json lune run tests/server_sim.luau
local H = require("./harness")
local F = require("./fakes")
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local fixturePath = process.args[1] or "tests/fixtures/server_messages.json"
-- DEVICE=phone: スマホ(横向き 844×390・タッチ)として起動する
local PHONE = process.env.DEVICE == "phone"
local SCREEN = if PHONE then { 844, 390 } else { 1280, 720 }
local rec = serde.decode("json", fs.readFile(fixturePath))

-- 書き出した形 → Lune の値
local function dec(v: any): any
	if type(v) ~= "table" then
		return v
	end
	if v.__t then
		local a = v.v
		if v.__t == "Vector3" then
			return roblox.Vector3.new(a[1], a[2], a[3])
		elseif v.__t == "Vector2" then
			return roblox.Vector2.new(a[1], a[2])
		elseif v.__t == "Color3" then
			return roblox.Color3.new(a[1], a[2], a[3])
		elseif v.__t == "CFrame" then
			return roblox.CFrame.new(table.unpack(a))
		elseif v.__t == "Enum" then
			return (roblox.Enum :: any)[a[1]][a[2]]
		end
		return nil
	end
	local out = {}
	for k, x in v do
		if type(k) == "string" and k:sub(1, 1) == "#" then
			out[tonumber(k:sub(2)) :: number] = dec(x)
		else
			out[k] = dec(x)
		end
	end
	return out
end

local shared = H.root("src/shared")
local client = H.root("src/client")
local Config = H.require(shared.Config)
local Locale = H.require(shared.Locale)

local fakeNew, Signal = F.new, F.Signal
local frameSignals: any = nil
-- 時間を進める: ゲームと同じく、1フレーム(1/30秒)ごとに Heartbeat / RenderStepped を鳴らす
local function advance(dt: number)
	local step = 1 / 30
	local left = dt
	while left > 1e-9 do
		local d = math.min(step, left)
		F.advance(d)
		if frameSignals then
			frameSignals.Stepped:Fire(F.now(), d)
			frameSignals.Heartbeat:Fire(d)
			frameSignals.RenderStepped:Fire(d)
		end
		left -= d
	end
end
local walkFind, visible, click = F.walkFind, F.visible, F.click

-- 偽物のサービス(足りないものを使われたら、何が足りないかが分かるように止める)
local function service(name: string, members: { [string]: any }): any
	return setmetatable(members, {
		__index = function(_, k)
			error(("fake service %s has no member %s"):format(name, tostring(k)), 2)
		end,
	})
end

-- 自分(LocalPlayer)とキャラクター
local me = fakeNew("Player")
local meProps = rawget(me, "__props")
meProps.UserId = 1001
meProps.Name = "Tester"
meProps.DisplayName = "Tester"
meProps.LocaleId = "ja-jp"
meProps.IsFriendsWith = function()
	return false
end
meProps.GetFriendsOnline = function()
	return {}
end
local playerGui = fakeNew("PlayerGui")
playerGui.Name = "PlayerGui"
playerGui.Parent = me
local char = fakeNew("Model")
char.Name = "Tester"
for _, n in { "Head", "HumanoidRootPart" } do
	local p = fakeNew("Part")
	p.Name = n
	p.CFrame = roblox.CFrame.new(0, 5, 0)
	p.Position = roblox.Vector3.new(0, 5, 0)
	p.Parent = char
end
local hum = fakeNew("Humanoid")
hum.Name = "Humanoid"
hum.Parent = char
meProps.Character = char

local Players = service("Players", {
	LocalPlayer = me,
	PlayerAdded = Signal(),
	PlayerRemoving = Signal(),
	GetPlayers = function()
		return { me }
	end,
	GetPlayerByUserId = function(_, id)
		return if id == 1001 then me else nil
	end,
})

local remotesFolder: any = nil
local fired: { { name: string, args: { any } } } = {}
local function remote(name: string): any
	return remotesFolder:FindFirstChild(name)
end
local function serverSays(name: string, args: { any })
	remote(name).OnClientEvent:Fire(table.unpack(args))
end

local camera = fakeNew("Camera")
camera.ViewportSize = roblox.Vector2.new(SCREEN[1], SCREEN[2])
camera.CameraType = roblox.Enum.CameraType.Custom
camera.FieldOfView = 70
camera.CFrame = roblox.CFrame.new(0, 10, 20)
local workspace: any = fakeNew("Workspace")
workspace.CurrentCamera = camera
rawget(workspace, "__props").GetServerTimeNow = function()
	return 1.75e9 + F.now()
end
rawget(workspace, "__props").Raycast = function()
	return nil
end
local lighting = fakeNew("Lighting")
for _, c in
	{ { "Atmosphere", "Atmosphere" }, { "ColorCorrectionEffect", "Grade" }, { "BloomEffect", "Bloom" } }
do
	local e = fakeNew(c[1])
	e.Name = c[2]
	e.Parent = lighting
end
local soundService = fakeNew("SoundService")

local services: { [string]: any } = {
	Players = Players,
	ReplicatedStorage = service("ReplicatedStorage", {
		WaitForChild = function(_, name)
			return if name == "Shared" then shared elseif name == "Remotes" then remotesFolder else nil
		end,
		FindFirstChild = function(_, name)
			return if name == "Remotes" then remotesFolder else nil
		end,
	}),
	RunService = service("RunService", {
		Heartbeat = Signal(),
		RenderStepped = Signal(),
		Stepped = Signal(),
		IsClient = function()
			return true
		end,
		IsServer = function()
			return false
		end,
		IsStudio = function()
			return false
		end,
	}),
	TweenService = service("TweenService", {
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
				Pause = function() end,
				Completed = Signal(),
			}
		end,
	}),
	UserInputService = service("UserInputService", {
		InputBegan = Signal(),
		InputEnded = Signal(),
		InputChanged = Signal(),
		WindowFocusReleased = Signal(),
		TouchEnabled = PHONE,
		KeyboardEnabled = not PHONE,
		GamepadEnabled = false,
		GetMouseLocation = function()
			return roblox.Vector2.new(640, 360)
		end,
	}),
	CollectionService = service("CollectionService", {
		GetTagged = function()
			return {}
		end,
		HasTag = function()
			return false
		end,
		GetInstanceAddedSignal = function()
			return Signal()
		end,
		GetInstanceRemovedSignal = function()
			return Signal()
		end,
	}),
	StarterGui = service("StarterGui", {
		SetCoreGuiEnabled = function() end,
		SetCore = function() end,
	}),
	SoundService = soundService,
	MarketplaceService = service("MarketplaceService", {
		PromptGamePassPurchase = function() end,
		PromptProductPurchase = function() end,
		PromptGamePassPurchaseFinished = Signal(),
	}),
	Lighting = lighting,
	TextChatService = service("TextChatService", {
		FindFirstChild = function()
			return nil
		end,
	}),
	TeleportService = service("TeleportService", {
		TeleportToPlaceInstance = function() end,
		TeleportInitFailed = Signal(),
	}),
	SocialService = service("SocialService", {
		CanSendGameInviteAsync = function()
			return false
		end,
		PromptGameInvite = function() end,
	}),
	ProximityPromptService = service("ProximityPromptService", { PromptTriggered = Signal() }),
	ContentProvider = service("ContentProvider", { PreloadAsync = function() end }),
	-- Roblox の上のバーの高さ(PC は 58px、スマホは 36px)
	GuiService = service("GuiService", {
		GetGuiInset = function()
			return roblox.Vector2.new(0, if PHONE then 36 else 58), roblox.Vector2.new(0, 0)
		end,
	}),
}

H.globals = {
	game = {
		PlaceId = 77,
		JobId = "job-1",
		GetService = function(_, name)
			local s = services[name]
			if not s then
				error("no fake service " .. tostring(name), 2)
			end
			return s
		end,
	},
	workspace = workspace,
	task = F.task,
	os = F.os,
	TweenInfo = {
		new = function(time)
			return { Time = time or 1 }
		end,
	},
	Instance = { new = fakeNew },
}

-- 通信: ReplicatedStorage.Remotes に、本物と同じ名前の偽物を並べる
local Remotes = H.require(shared.Lib.Remotes)
remotesFolder = fakeNew("Folder")
remotesFolder.Name = "Remotes"
for _, name in Remotes.Events do
	local r = fakeNew("RemoteEvent")
	r.Name = name
	rawget(r, "__props").FireServer = function(_, ...)
		table.insert(fired, { name = name, args = { ... } })
	end
	r.Parent = remotesFolder
end
for _, name in Remotes.Functions do
	local r = fakeNew("RemoteFunction")
	r.Name = name
	rawget(r, "__props").InvokeServer = function()
		return {}
	end
	r.Parent = remotesFolder
end

frameSignals = services.RunService
print("クライアントを丸ごと起動" .. (if PHONE then "(スマホ)" else ""))
F.validating = true
local gui: any = nil

H.test("起動: 本物の init.client.luau がエラーなく動き、画面ができる", function()
	H.require(client)
	advance(1)
	gui = playerGui:FindFirstChild("YokaiUI")
	H.assert(gui, "no ScreenGui")
	rawset(_G, "__gui", gui)
	F.setSnapshotRoot(gui)
	H.assert(gui:FindFirstChild("HUD"), "no HUD")
end)

local Root = H.require(client.UI.Root)

H.test(
	"サーバーの本物の知らせ(釣り・データ・お知らせ・ぬし・対戦)を順に流しても壊れない",
	function()
		-- 最初に、遊んだ後の本物のデータ(図鑑・相棒・依頼・水槽…がそろっている)
		serverSays("Profile", { dec(rec.onlineProfile) })
		advance(0.5)
		for _, group in { rec.fishing, rec.online } do
			for _, m in group do
				serverSays(m.name, dec(m.args))
				advance(0.4)
			end
			advance(5)
		end
		serverSays("Profile", { dec(rec.fishingProfile) })
		-- バトルの知らせは演出つきで1つずつ再生される(1回の戦いに数秒)。全部再生し終わるまで時間を進める
		local results = 0
		for _ = 1, 120 do
			advance(3)
			local battle = gui:FindFirstChild("Battle")
			local close = battle and (F.button(battle, "閉じる") or F.button(battle, "Close"))
			if close then
				results += 1
				click(close)
				advance(0.5)
				Root.close()
			end
			if not gui:FindFirstChild("Battle") and results > 0 then
				break
			end
		end
		print(("      再生したバトルの結果: %d"):format(results))
		H.assert(results >= 1, "battle results were not shown")
		H.assert(gui:FindFirstChild("Battle") == nil, "battle playback never finished")
		F.snapshot("boot_after_messages")
	end
)

-- 画面の上の四角(レイアウトの単位。親が並べ方を持たない部品だけ)
local function scaleOf(): number
	local s = gui:FindFirstChildOfClass("UIScale")
	return if s then s.Scale else 1
end
local function rect(inst: any): { number }
	local sc = scaleOf()
	local W, H = SCREEN[1] / sc, SCREEN[2] / sc
	local px, py, pw, ph = 0, 0, W, H
	if inst.Parent and inst.Parent ~= gui then
		local r = rect(inst.Parent)
		px, py, pw, ph = r[1], r[2], r[3] - r[1], r[4] - r[2]
	end
	local s, pos, a = inst.Size, inst.Position, inst.AnchorPoint
	local w = s.X.Scale * pw + s.X.Offset
	local h = s.Y.Scale * ph + s.Y.Offset
	local x = px + pos.X.Scale * pw + pos.X.Offset - a.X * w
	local y = py + pos.Y.Scale * ph + pos.Y.Offset - a.Y * h
	return { x, y, x + w, y + h }
end
local function overlaps(a: { number }, b: { number }): boolean
	return a[1] < b[3] and b[1] < a[3] and a[2] < b[4] and b[2] < a[4]
end
local function fmt(r: { number }): string
	return ("(%d,%d)-(%d,%d)"):format(r[1], r[2], r[3], r[4])
end
-- 右のメニュー(見えているボタンの分だけの高さ)
local function menuRect(): { number }
	local hud = gui:FindFirstChild("HUD")
	for _, c in hud:GetChildren() do
		if c:FindFirstChildOfClass("UIListLayout") and c:FindFirstChild("hud_codex") then
			local r = rect(c)
			local n = 0
			for _, b in c:GetChildren() do
				if b.ClassName == "TextButton" and b.Visible ~= false then
					n += 1
				end
			end
			r[4] = r[2] + n * 72 - 8
			return r
		end
	end
	error("menu not found")
end
-- Roblox のジャンプボタン(タッチの時、右下)。小さい画面は 70px、大きい画面は 120px
local function jumpRect(): { number }
	local sc = scaleOf()
	local small = math.min(SCREEN[1], SCREEN[2]) <= 500
	local size, right, bottom =
		if small then 70 else 120, if small then 95 else 170, if small then 90 else 210
	local x0, y0 = SCREEN[1] - right, SCREEN[2] - bottom
	return { x0 / sc, y0 / sc, (x0 + size) / sc, (y0 + size) / sc }
end

-- 流し込んだ知らせで開いたままのバトル(結果の画面)を閉じる
local function closeBattle()
	local battle = gui:FindFirstChild("Battle")
	if not battle then
		return
	end
	for _, label in { "閉じる", "Close" } do
		local b = F.button(battle, label)
		if b then
			click(b)
			advance(0.5)
			return
		end
	end
end

-- 画面を開いて、見えているボタンを全部押す(押すたびに元の画面へ戻す)
local function monkey(panel: string, arg: any?)
	Root.open(panel, arg)
	advance(0.3)
	local root = nil
	for _, c in gui:GetChildren() do
		if
			c.ClassName == "Frame"
			and c.Visible ~= false
			and c.Name ~= "HUD"
			and c:FindFirstChild("Header")
		then
			root = c
		end
	end
	H.assert(root, "panel " .. panel .. " did not open")
	F.snapshot("panel_" .. panel .. (if arg then "_" .. tostring(arg) else ""))
	local buttons = walkFind(root, function(d)
		return d.ClassName == "TextButton" and visible(d) and d.Name ~= "Close"
	end)
	local pressed = 0
	for _, b in buttons do
		if b.Parent and visible(b) and b:GetAttribute("Disabled") ~= true then
			b.Activated:Fire()
			pressed += 1
			advance(0.2)
			-- 押したことで閉じた/別の画面になったら、開き直す
			if not Root.isOpen(panel) then
				Root.open(panel, arg)
				advance(0.2)
			end
		end
	end
	return pressed
end

H.test("すべての画面を開いて、見えているボタンを全部押す", function()
	closeBattle()
	H.assert(gui:FindFirstChild("Battle") == nil, "battle screen still open")
	Root.close()
	local total = 0
	for _, p in
		{
			{ "shop", "rods" },
			{ "shop", "bait" },
			{ "shop", "sell" },
			{ "shop", "tank" },
			{ "shop", "passes" },
			{ "codex" },
			{ "quests" },
			{ "daily" },
			{ "partners" },
			{ "settings" },
			{ "help" },
			{ "battle", "trainers" },
			{ "battle", "boss" },
			{ "battle", "online" },
			{ "social" },
		}
	do
		total += monkey(p[1], p[2])
		Root.close()
		advance(0.5)
	end
	print(("      押したボタン: %d"):format(total))
	closeBattle() -- ボタンでバトルが始まっていたら片付ける
	H.assert(total > 50, "too few buttons pressed")
end)

H.test(
	"釣り: 投げる → 待つ → アタリ → 合わせる → 引く → 釣果(本物の操作の流れ)",
	function()
		local Input = H.require(client.Controllers.Input)
		Root.close()
		advance(0.5)
		local before = #fired
		-- 押して離すと投げる
		Input.press("test")
		advance(0.8)
		Input.release("test")
		advance(0.3)
		local cast = nil
		for i = before + 1, #fired do
			if fired[i].name == "Cast" then
				cast = fired[i]
			end
		end
		H.assert(cast, "no Cast sent")
		local power = cast.args[1]
		H.assert(type(power) == "number" and power >= 0 and power <= 1, "bad cast power")
		-- サーバーの返事(本物の知らせの形)
		local waiting, bite, reel = nil, nil, nil
		for _, m in rec.fishing do
			if m.name == "FishingState" then
				local st = m.args["#1"]
				if st == "waiting" and not waiting then
					waiting = m
				elseif st == "bite" and not bite then
					bite = m
				elseif st == "reel" and not reel then
					reel = m
				end
			end
		end
		H.assert(waiting and bite and reel, "fixture lacks fishing states")
		serverSays("FishingState", dec(waiting.args))
		advance(1)
		serverSays("FishingState", dec(bite.args))
		advance(0.2)
		-- アタリで押す → 合わせる
		before = #fired
		Input.press("test")
		advance(0.1)
		Input.release("test")
		advance(0.2)
		local hooked = false
		for i = before + 1, #fired do
			hooked = hooked or fired[i].name == "Hook"
		end
		H.assert(hooked, "no Hook sent on bite")
		serverSays("FishingState", dec(reel.args))
		F.snapshot("boot_reel")
		-- 引く画面: 網のゲージ・「釣る」ボタン・右のメニュー(・スマホのジャンプボタン)が重ならない
		local reelPanel = gui:FindFirstChild("ReelGame")
		local action = gui:FindFirstChild("Action")
		H.assert(reelPanel and action, "reel panel or action button missing")
		local rr, ar, mr = rect(reelPanel), rect(action), menuRect()
		H.assert(not overlaps(rr, mr), "reel gauge covers the menu " .. fmt(rr) .. " vs " .. fmt(mr))
		H.assert(not overlaps(ar, mr), "action button covers the menu " .. fmt(ar) .. " vs " .. fmt(mr))
		H.assert(not overlaps(rr, ar), "reel gauge covers the action button " .. fmt(rr) .. " vs " .. fmt(ar))
		if PHONE then
			H.assert(
				not overlaps(ar, jumpRect()),
				"action button under the jump button " .. fmt(ar) .. " vs " .. fmt(jumpRect())
			)
		end
		-- 画面の外にはみ出さない
		local sc = scaleOf()
		for _, r in { rr, ar, mr } do
			H.assert(
				r[1] >= 0 and r[2] >= 0 and r[3] <= SCREEN[1] / sc + 0.5 and r[4] <= SCREEN[2] / sc + 0.5,
				"off screen " .. fmt(r)
			)
		end
		-- 引くゲーム: 人のように、画面の魚が網より上なら押す・下なら離す(終われば結果を送る)
		before = #fired
		local function named(name: string): any
			return F.walkFind(reelPanel, function(d)
				return d.Name == name
			end)[1]
		end
		local netF, fishF = named("Net"), named("Fish")
		H.assert(netF and fishF, "reel gauge has no net / fish")
		local netSize = dec(reel.args)[2].netSize
		local result = nil
		local t = 0
		while not result and t < Config.Tuning.Fishing.reelTimeoutSeconds do
			local net = 1 - netF.Position.Y.Scale
			local fish = 1 - fishF.Position.Y.Scale
			if fish > net + netSize / 2 then
				Input.press("test")
			else
				Input.release("test")
			end
			advance(0.1)
			t += 0.1
			for i = before + 1, #fired do
				if fired[i].name == "ReelResult" then
					result = fired[i]
				end
			end
		end
		Input.release("test")
		H.assert(result and type(result.args[1]) == "boolean", "no ReelResult sent")
		-- 釣果の画面(本物の CatchResult)。名前はカタカナのあだ名、その横に種類(もとの魚と妖怪)が出る
		local caught = nil
		for _, m in rec.fishing do
			if m.name == "CatchResult" then
				local args = dec(m.args)
				caught = args[1]
				serverSays("CatchResult", args)
			end
		end
		advance(1)
		F.snapshot("boot_catch")
		local def = caught and Config.FishById[caught.fishId]
		H.assert(def ~= nil, "no catch result in the fixture")
		local name, kind = Locale.fishName(def), Locale.fishKind(def)
		H.assert(F.hasText(gui, name), "nickname not shown: " .. name)
		H.assert(kind ~= name and F.hasText(gui, kind), "kind not shown: " .. kind)
		advance(8)
	end
)

H.test(
	"Roblox の上のバー(メニュー・チャット)に、ふだんの画面とバトルの上の段が重ならない",
	function()
		local inset = (if PHONE then 36 else 58) / scaleOf()
		local function checkTops(container: any, label: string)
			for _, c in container:GetChildren() do
				if c.Visible ~= false and c.Size and c.Position and c.Size.Y.Scale < 1 then
					local r = rect(c)
					H.assert(
						r[2] >= inset - 0.5,
						("%s %s is under the top bar: top %.1f < %.1f"):format(label, c.Name, r[2], inset)
					)
				end
			end
		end
		checkTops(gui:FindFirstChild("HUD"), "HUD")
		-- バトルを1つ始めて、上の段を確かめる
		local start = nil
		for _, m in rec.fishing do
			if m.name == "BattleState" and m.args["#1"].kind == "start" then
				start = m
				break
			end
		end
		serverSays("BattleState", dec(start.args))
		advance(1)
		local battle = gui:FindFirstChild("Battle")
		H.assert(battle and battle:FindFirstChild("Top"), "battle top row missing")
		checkTops(battle:FindFirstChild("Top"), "battle")
		F.snapshot("boot_battle_layout")
		serverSays("BattleState", { { kind = "result", win = false, gains = {} } })
		advance(6)
		closeBattle()
	end
)

H.test("言語を英語に切り替えて、もう一度すべての画面を開く", function()
	Locale.set("en")
	for _, p in
		{
			{ "shop", "rods" },
			{ "codex" },
			{ "quests" },
			{ "partners" },
			{ "settings" },
			{ "battle", "boss" },
		}
	do
		Root.open(p[1], p[2])
		advance(0.3)
	end
	Root.close()
	Locale.set("ja")
end)

H.test(
	"Roblox の定義: クライアント全体で使うプロパティの名前と型がすべて正しい",
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
