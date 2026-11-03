-- サーバーの結合テスト(Lune): lune run tests/server_sim.luau
-- 本物のサーバー起動スクリプトとサービスを、偽の Roblox サービス(DataStore・Players・通信)の上で動かし、
-- 「参加 → 投げる → アタリ → 合わせる → 引き上げ → 売る → 竿を買う → 課金」までを通しで確認する。
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local task = require("@lune/task")
local H = require("./harness")

-- 偽のイベント ---------------------------------------------------------------
local function Signal()
	local handlers = {}
	local sig = {}
	function sig:Connect(fn)
		table.insert(handlers, fn)
		return {
			Disconnect = function()
				local i = table.find(handlers, fn)
				if i then
					table.remove(handlers, i)
				end
			end,
		}
	end
	function sig:Fire(...)
		for _, fn in table.clone(handlers) do
			task.spawn(fn, ...)
		end
	end
	function sig:Wait()
		local thread = coroutine.running()
		local c
		c = sig:Connect(function(...)
			c.Disconnect()
			task.spawn(thread, ...)
		end)
		return coroutine.yield()
	end
	return sig
end

-- 実際の Roblox Instance(Lune)で足りないものを補う
local dm = roblox.Instance.new("DataModel")
local workspace = dm:GetService("Workspace")
local terrain = roblox.Instance.new("Terrain")
terrain.Parent = workspace
for _, m in { "FillBlock", "FillBall", "FillCylinder", "SetMaterialColor" } do
	roblox.implementMethod("Terrain", m, function() end)
end
local serverTime = 1700000000 + 600 -- ぬしの時間外
roblox.implementMethod("Workspace", "GetServerTimeNow", function()
	return serverTime + os.clock()
end)
roblox.implementMethod("Workspace", "Raycast", function()
	return nil
end)
roblox.implementMethod("Instance", "WaitForChild", function(inst, name)
	return inst:FindFirstChild(name)
end)
roblox.implementMethod("Model", "PivotTo", function(model, cf)
	local root = model:FindFirstChild("HumanoidRootPart")
	if root then
		root.CFrame = cf
		root.Position = cf.Position
	end
end)
roblox.implementMethod("Model", "GetPivot", function(model)
	local p = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	return if p then p.CFrame else roblox.CFrame.new()
end)
roblox.implementProperty("Humanoid", "Health", function()
	return 100
end)
local diedSignals = {}
roblox.implementProperty("Humanoid", "Died", function(hum)
	diedSignals[hum] = diedSignals[hum] or Signal()
	return diedSignals[hum]
end)

-- タグ
local tagged: { [string]: { any } } = {}
local CollectionService = {}
function CollectionService:AddTag(inst, tag)
	tagged[tag] = tagged[tag] or {}
	table.insert(tagged[tag], inst)
end
function CollectionService:HasTag(inst, tag)
	return table.find(tagged[tag] or {}, inst) ~= nil
end
function CollectionService:GetTagged(tag)
	return tagged[tag] or {}
end
roblox.implementMethod("Instance", "AddTag", function(inst, tag)
	CollectionService:AddTag(inst, tag)
end)

-- 偽の DataStore(保存時にコピーして、テーブルの共有による誤魔化しを防ぐ)
local function deepCopy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = deepCopy(x)
	end
	return out
end
local stores: { [string]: { [string]: any } } = {}
local updateCalls = 0
local DataStoreService = {}
function DataStoreService:GetDataStore(name)
	stores[name] = stores[name] or {}
	local data = stores[name]
	return {
		UpdateAsync = function(_, key, fn)
			updateCalls += 1
			local new, userIds = fn(deepCopy(data[key]))
			if new ~= nil then
				assert(type(userIds) == "table" and #userIds == 1, "UpdateAsync must pass userIds for GDPR")
				data[key] = deepCopy(new)
			end
			return new
		end,
		RemoveAsync = function(_, key)
			data[key] = nil
		end,
	}
end
function DataStoreService:GetOrderedDataStore(name)
	stores[name] = stores[name] or {}
	local data = stores[name]
	return {
		SetAsync = function(_, key, v)
			data[key] = v
		end,
		UpdateAsync = function(_, key, fn)
			local new = fn(data[key])
			if new ~= nil then
				data[key] = new
			end
		end,
		RemoveAsync = function(_, key)
			data[key] = nil
		end,
		GetSortedAsync = function()
			return {
				GetCurrentPage = function()
					local list = {}
					for k, v in data do
						table.insert(list, { key = k, value = v })
					end
					table.sort(list, function(a, b)
						return a.value > b.value
					end)
					return list
				end,
			}
		end,
	}
end

-- 偽の MemoryStore(ほかのサーバーの対戦チームの写し)。sortKey で並べて範囲で取り出せる
local memory: { [string]: { [string]: { value: any, sortKey: number? } } } = {}
local MemoryStoreService = {}
function MemoryStoreService:GetSortedMap(name)
	memory[name] = memory[name] or {}
	local data = memory[name]
	return {
		SetAsync = function(_, key, value, _ttl, sortKey)
			data[key] = { value = deepCopy(value), sortKey = sortKey }
			return true
		end,
		RemoveAsync = function(_, key)
			data[key] = nil
		end,
		GetRangeAsync = function(_, _dir, count, lower, upper)
			local list = {}
			for k, v in data do
				local sk = v.sortKey or 0
				if (not lower or sk > lower.sortKey) and (not upper or sk < upper.sortKey) then
					table.insert(list, { key = k, value = deepCopy(v.value), sortKey = sk })
				end
			end
			table.sort(list, function(a, b)
				return a.sortKey < b.sortKey
			end)
			while #list > count do
				table.remove(list)
			end
			return list
		end,
	}
end

-- 偽の Players
local Players = { PlayerAdded = Signal(), PlayerRemoving = Signal(), RespawnTime = 0, LocalPlayer = nil }
local playerList = {}
function Players:GetPlayers()
	return table.clone(playerList)
end
function Players:GetPlayerByUserId(id)
	for _, p in playerList do
		if p.UserId == id then
			return p
		end
	end
	return nil
end
function Players:GetNameFromUserIdAsync(id)
	return "user" .. id
end

-- Lune では CFrame から Position が自動で決まらないので、両方を設定する
local function place(part, cf)
	part.CFrame = cf
	part.Position = cf.Position
end

local function makeCharacter(pos)
	local char = roblox.Instance.new("Model")
	char.Name = "Character"
	local hum = roblox.Instance.new("Humanoid")
	hum.Health = 100
	hum.Parent = char
	local root = roblox.Instance.new("Part")
	root.Name = "HumanoidRootPart"
	place(root, roblox.CFrame.lookAt(pos, pos + roblox.Vector3.new(0, 0, -1)))
	root.Parent = char
	local hand = roblox.Instance.new("Part")
	hand.Name = "RightHand"
	place(hand, roblox.CFrame.new(pos))
	hand.Parent = char
	local head = roblox.Instance.new("Part")
	head.Name = "Head"
	head.Parent = char
	char.Parent = workspace
	return char
end

local kicked: { [number]: string } = {}
local friendships: { [string]: boolean } = {}
local function makePlayer(userId: number)
	local attrs = {}
	local attrSignals = {}
	local p
	p = {
		__fake = true,
		UserId = userId,
		Name = "user" .. userId,
		DisplayName = "Tester" .. userId,
		Parent = Players,
		Character = nil,
		CharacterAdded = Signal(),
		IsA = function(_, c)
			return c == "Player" or c == "Instance"
		end,
		SetAttribute = function(_, k, v)
			attrs[k] = v
			if attrSignals[k] then
				attrSignals[k]:Fire()
			end
		end,
		GetAttribute = function(_, k)
			return attrs[k]
		end,
		GetAttributeChangedSignal = function(_, k)
			attrSignals[k] = attrSignals[k] or Signal()
			return attrSignals[k]
		end,
		FindFirstChild = function(_, name)
			return p.__children[name]
		end,
		Kick = function(_, msg)
			kicked[userId] = msg
		end,
		IsFriendsWith = function(_, other)
			return friendships[userId .. ":" .. other] == true or friendships[other .. ":" .. userId] == true
		end,
		LoadCharacter = function()
			p.Character = makeCharacter(roblox.Vector3.new(0, 3, 17))
			p.CharacterAdded:Fire(p.Character)
		end,
		__children = {},
	}
	return p
end

-- 偽の通信(サーバーから送った内容を記録)
local sent: { [any]: { { name: string, args: { any } } } } = {}
local announced = {}
local remoteEvents = {}
local remoteFuncs = {}
local FakeRemotes = { Events = {}, Functions = {} }
local function event(name)
	if not remoteEvents[name] then
		remoteEvents[name] = {
			Name = name,
			OnServerEvent = Signal(),
			FireClient = function(_, player, ...)
				sent[player] = sent[player] or {}
				table.insert(sent[player], { name = name, args = { ... } })
			end,
			FireAllClients = function(_, ...)
				table.insert(announced, { name = name, args = { ... } })
			end,
		}
	end
	return remoteEvents[name]
end
function FakeRemotes.setupServer() end
function FakeRemotes.event(name)
	return event(name)
end
function FakeRemotes.func(name)
	remoteFuncs[name] = remoteFuncs[name] or { Name = name }
	return remoteFuncs[name]
end

local function lastSent(player, name)
	local list = sent[player] or {}
	for i = #list, 1, -1 do
		if list[i].name == name then
			return list[i].args
		end
	end
	return nil
end
local function countSent(player, name)
	local n = 0
	for _, e in sent[player] or {} do
		if e.name == name then
			n += 1
		end
	end
	return n
end
local function clientSend(player, name, ...)
	event(name).OnServerEvent:Fire(player, ...)
	task.wait(0.05)
end

-- 偽のサービス
local MarketplaceService = { PromptGamePassPurchaseFinished = Signal(), ProcessReceipt = nil }
function MarketplaceService:UserOwnsGamePassAsync(userId, passId)
	return userId == 5005 and passId == 222
end
local analyticsLog = {}
local AnalyticsService = setmetatable({}, {
	__index = function(_, method)
		return function(_, _player, ...)
			table.insert(analyticsLog, { method = method, args = { ... } })
		end
	end,
})
local RunService = {
	IsStudio = function()
		return false
	end,
	IsServer = function()
		return true
	end,
}
local ProximityPromptService = { PromptTriggered = Signal() }

local shared = H.root("src/shared")
local services = {
	Workspace = workspace,
	Lighting = dm:GetService("Lighting"),
	Players = Players,
	DataStoreService = DataStoreService,
	MemoryStoreService = MemoryStoreService,
	CollectionService = CollectionService,
	MarketplaceService = MarketplaceService,
	AnalyticsService = AnalyticsService,
	RunService = RunService,
	ProximityPromptService = ProximityPromptService,
	ReplicatedStorage = {
		WaitForChild = function()
			return shared
		end,
	},
}
local closeHandlers = {}
local fakeGame = {
	JobId = "server-A",
	GetService = function(_, name)
		return services[name] or error("no fake service " .. name)
	end,
	BindToClose = function(_, fn)
		table.insert(closeHandlers, fn)
	end,
}

-- BindableEvent は Lune にイベントが無いので偽物にする
local FakeInstance = {
	new = function(className, ...)
		if className == "BindableEvent" then
			local sig = Signal()
			return {
				Event = sig,
				Fire = function(_, ...)
					sig:Fire(...)
				end,
			}
		end
		return roblox.Instance.new(className, ...)
	end,
}

H.globals = {
	Instance = FakeInstance,
	game = fakeGame,
	workspace = workspace,
	task = task,
	typeof = function(v)
		if type(v) == "table" and v.__fake then
			return "Instance"
		end
		return typeof(v)
	end,
}
H.override(shared.Lib.Remotes, FakeRemotes)

-- テストを速くするための調整(本番の値は変えない)
local Config = H.require(shared.Config)
Config.Tuning.Fishing.biteMinSeconds = 0.2
Config.Tuning.Fishing.biteMaxSeconds = 0.3
Config.Tuning.FirstCatch.biteSeconds = 0.2
Config.Tuning.Data.loadRetries = 2
Config.Tuning.Nushi.baseRequired = 2
Config.Tuning.Nushi.perPlayerRequired = 1
Config.Tuning.Nushi.minContribution = 0.5
Config.Products.DevProducts[1].id = 111 -- 運のお札
Config.Products.DevProducts[3].id = 333 -- 高級エサ10個
Config.Products.GamePasses[2].id = 222 -- 自動釣り

-- サーバー起動(本物の init.server.luau)
local server = H.root("src/server")
local ok, err = pcall(H.require, server)
if not ok then
	print("server boot failed: " .. tostring(err))
	process.exit(1)
end
for _, d in workspace:GetDescendants() do
	if d:IsA("BasePart") then
		d.Position = d.CFrame.Position
	end
end
local DataService = H.require(server.Services.DataService)
local Shop = H.require(server.Services.ShopService)

local function data(p)
	return DataService.get(p)
end

print("Server simulation")
local alice = makePlayer(1001)
table.insert(playerList, alice)
Players.PlayerAdded:Fire(alice)
task.wait(0.3)

H.test(
	"参加するとデータが読み込まれ、キャラクターが出現し、竿が付く",
	function()
		H.assert(DataService.isLoaded(alice), "profile not loaded")
		H.assert(alice.Character ~= nil, "no character")
		task.wait(0.6)
		H.assert(alice.Character:FindFirstChild("YokaiRod") ~= nil, "no rod")
		H.assert(lastSent(alice, "Profile") ~= nil, "profile not replicated")
		local stored = stores[Config.Tuning.Data.storeName]["u_1001"]
		H.assert(stored and stored._lock and stored._lock.job == "server-A", "session lock not written")
	end
)

H.test(
	"クライアントに送るデータに内部情報(ロック・購入履歴)が含まれない",
	function()
		local snap = lastSent(alice, "Profile")[1]
		H.assert(
			snap._lock == nil and snap.purchases == nil and snap.uidCounter == nil,
			"hidden fields leaked"
		)
	end
)

H.test("不正な値(NaN・範囲外・文字列)で投げても何も起きない", function()
	local before = countSent(alice, "FishingState")
	clientSend(alice, "Cast", 0 / 0)
	clientSend(alice, "Cast", 5)
	clientSend(alice, "Cast", "hello")
	H.assertEq(countSent(alice, "FishingState"), before, "state changed on bad input")
end)

H.test("連打は回数制限で止まる(直前の3回で枠を使い切っている)", function()
	local before = countSent(alice, "FishingState")
	clientSend(alice, "Cast", 0.8, 0, -1)
	H.assertEq(countSent(alice, "FishingState"), before, "rate limit did not apply")
	task.wait(1.6) -- 回復を待つ
end)

H.test(
	"最初の1匹: 投げる → アタリ → 合わせ → 引き上げ成功 → 上以上の魚が手に入る",
	function()
		clientSend(alice, "Cast", 0.8, 0, -1)
		H.assertEq(lastSent(alice, "FishingState")[1], "waiting", "not waiting")
		task.wait(0.4)
		H.assertEq(lastSent(alice, "FishingState")[1], "bite", "no bite")
		clientSend(alice, "Hook")
		local st = lastSent(alice, "FishingState")
		H.assertEq(st[1], "reel", "no reel")
		local params = st[2]
		H.assert(params.rarity ~= "common", "first catch must be uncommon+")
		-- 完璧に操作した時間だけ待ってから成功を報告
		task.wait((1 - params.startProgress) * params.duration / params.reelSpeed + 0.1)
		clientSend(alice, "ReelResult", true)
		local r = lastSent(alice, "CatchResult")
		H.assert(r ~= nil, "no catch result")
		r = r[1]
		H.assert(r.isNew and r.firstEver, "first catch flags")
		H.assertEq(#data(alice).creel, 1, "creel")
		H.assert(data(alice).codex[r.fishId] ~= nil, "codex")
		H.assertEq(data(alice).stats.caught, 1)
	end
)

H.test("引き上げが人間に不可能な速さなら無効になる", function()
	clientSend(alice, "Cast", 0.5, 0, -1)
	task.wait(0.45)
	clientSend(alice, "Hook")
	H.assertEq(lastSent(alice, "FishingState")[1], "reel", "no reel")
	clientSend(alice, "ReelResult", true) -- すぐ成功を報告
	H.assertEq(#data(alice).creel, 1, "too-fast reel was accepted")
	H.assertEq(lastSent(alice, "FishingState")[2].reason, "escaped")
end)

H.test(
	"引き上げに失敗すると逃げられ、分析に「逃げた」をレア度つきで記録する(難しさの見直し用)",
	function()
		clientSend(alice, "Cast", 0.5, 0, -1)
		task.wait(0.45)
		clientSend(alice, "Hook")
		H.assertEq(lastSent(alice, "FishingState")[1], "reel", "no reel")
		local before = #data(alice).creel
		clientSend(alice, "ReelResult", false)
		H.assertEq(#data(alice).creel, before, "escaped fish was kept")
		H.assertEq(lastSent(alice, "FishingState")[2].reason, "broke")
		local logged = nil
		for i = #analyticsLog, 1, -1 do
			local e = analyticsLog[i]
			if
				e.method == "LogCustomEvent"
				and type(e.args[1]) == "string"
				and e.args[1]:sub(1, 7) == "Escape_"
			then
				logged = e.args[1]
				break
			end
		end
		H.assert(logged and Config.RarityById[logged:sub(8)] ~= nil, "no Escape_<rarity> event")
	end
)

H.test("合わせが遅すぎると逃げられる", function()
	clientSend(alice, "Cast", 0.5, 0, -1)
	task.wait(0.45)
	H.assertEq(lastSent(alice, "FishingState")[1], "bite", "no bite")
	task.wait(Config.Tuning.Fishing.hookWindow + Config.Tuning.Fishing.latencyAllowance + 0.3)
	H.assertEq(lastSent(alice, "FishingState")[2].reason, "escaped")
	clientSend(alice, "Hook")
	H.assertEq(lastSent(alice, "FishingState")[1], "idle", "late hook accepted")
end)

H.test("水辺から遠いと投げられない", function()
	local root = alice.Character.HumanoidRootPart
	local old = root.CFrame
	place(root, roblox.CFrame.new(0, 3, 200))
	local before = countSent(alice, "FishingState")
	clientSend(alice, "Cast", 0.5, 0, -1)
	H.assertEq(countSent(alice, "FishingState"), before, "cast from far away")
	H.assertEq(lastSent(alice, "Notify")[1], "fish_too_far")
	place(root, old)
end)

H.test("ぬしの湖は3段目の竿から釣れる(1段目では断られ、理由が出る)", function()
	local root = alice.Character.HumanoidRootPart
	local old = root.CFrame
	local d = data(alice)
	local lake = Config.SpotById.nushi_lake
	H.assertEq(lake.unlockRodTier, 3)
	local oldTier = d.rodTier
	d.rodTier = 1
	place(root, roblox.CFrame.new(lake.origin.x, 3, lake.origin.z + lake.water.rz + 4))
	local before = countSent(alice, "FishingState")
	clientSend(alice, "Cast", 0.5, 0, -1)
	H.assertEq(countSent(alice, "FishingState"), before, "cast at the lake with rod 1")
	local n = lastSent(alice, "Notify")
	H.assertEq(n[1], "fish_need_rod")
	H.assertEq(n[2].tier, 3)
	d.rodTier = 3
	clientSend(alice, "Cast", 0.5, 0, -1)
	H.assertEq(countSent(alice, "FishingState"), before + 1, "rod 3 could not cast at the lake")
	clientSend(alice, "CancelFishing")
	task.wait(1.5) -- 投げる回数の制限(2回/秒・最大3回)を戻してから次のテストへ
	d.rodTier = oldTier
	place(root, old)
end)

H.test("魚屋から離れていると売れない / 近づくと売れて小判が増える", function()
	local uid = data(alice).creel[1].uid
	Shop.handleRequest(alice, "sell", uid)
	H.assertEq(#data(alice).creel, 1, "sold far from merchant")
	local merchant = CollectionService:GetTagged("Merchant")[1]
	local root = alice.Character.HumanoidRootPart
	place(root, roblox.CFrame.new(merchant.Position + roblox.Vector3.new(0, 0, -4)))
	Shop.handleRequest(alice, "sell", uid)
	H.assertEq(#data(alice).creel, 0, "not sold")
	H.assert(data(alice).coins > 0, "no coins")
	place(root, roblox.CFrame.new(0, 3, 17))
end)

H.test("小判が足りないと竿は買えない / 足りれば買えて竿が付け替わる", function()
	data(alice).coins = 100
	Shop.handleRequest(alice, "buyRod", 2)
	H.assertEq(data(alice).rodTier, 1, "bought without coins")
	data(alice).coins = 600
	Shop.handleRequest(alice, "buyRod", 3)
	H.assertEq(data(alice).rodTier, 1, "skipped a tier")
	Shop.handleRequest(alice, "buyRod", 2)
	H.assertEq(data(alice).rodTier, 2)
	H.assertEq(data(alice).coins, 100)
end)

H.test("エサ: 買う → 装備 → 投げると1個減る", function()
	data(alice).coins = 1000
	Shop.handleRequest(alice, "buyBait", { id = "worm", amount = 3 })
	H.assertEq(data(alice).bait.worm, 3)
	H.assertEq(data(alice).equippedBait, "worm")
	Shop.handleRequest(alice, "buyBait", { id = "premium", amount = 1 })
	H.assert(data(alice).bait.premium == nil, "bought shop-forbidden bait")
	Shop.handleRequest(alice, "buyBait", { id = "worm", amount = -5 })
	H.assertEq(data(alice).bait.worm, 3, "negative amount")
	clientSend(alice, "Cast", 0.5, 0, -1)
	H.assertEq(data(alice).bait.worm, 2)
	clientSend(alice, "CancelFishing")
end)

H.test("解放していない・存在しない釣り場には行けない", function()
	Shop.handleRequest(alice, "travel", "river")
	Shop.handleRequest(alice, "unlockSpot", "river")
	H.assert(data(alice).spots.river == nil, "unlocked an unavailable spot")
	Shop.handleRequest(alice, "travel", "../../etc")
end)

H.test(
	"課金(運のお札): 付与 → 同じ購入IDが再送されても二重に付与しない",
	function()
		local receipt = { PlayerId = 1001, ProductId = 111, PurchaseId = "p-1", CurrencySpent = 79 }
		local Enum = roblox.Enum
		local r1 = MarketplaceService.ProcessReceipt(receipt)
		H.assertEq(r1, Enum.ProductPurchaseDecision.PurchaseGranted, "first")
		local until1 = data(alice).boosts.luckUntil
		H.assert(until1 > os.time(), "boost not applied")
		local r2 = MarketplaceService.ProcessReceipt(receipt)
		H.assertEq(r2, Enum.ProductPurchaseDecision.PurchaseGranted, "second")
		H.assertEq(data(alice).boosts.luckUntil, until1, "granted twice")
		-- 保存済みのデータにも購入IDが残っている
		local stored = stores[Config.Tuning.Data.storeName]["u_1001"]
		H.assert(table.find(stored.purchases, "p-1"), "purchase id not saved")
	end
)

H.test(
	"課金: 参加していないプレイヤー・不明な商品は後で再処理(NotProcessedYet)",
	function()
		local Enum = roblox.Enum
		H.assertEq(
			MarketplaceService.ProcessReceipt({ PlayerId = 9999, ProductId = 111, PurchaseId = "x" }),
			Enum.ProductPurchaseDecision.NotProcessedYet
		)
		H.assertEq(
			MarketplaceService.ProcessReceipt({ PlayerId = 1001, ProductId = 42, PurchaseId = "y" }),
			Enum.ProductPurchaseDecision.NotProcessedYet
		)
	end
)

H.test("運のお札で運の倍率が2倍になる", function()
	local Fishing = H.require(server.Services.FishingService)
	local luck = Fishing.luckFor(alice, 0, "")
	local rod = Config.RodByTier[data(alice).rodTier]
	H.assert(math.abs(luck - (1 + rod.luck) * 2) < 1e-6, "luck " .. luck)
end)

H.test("依頼: 魚を釣ると進み、達成で受け取れる(二重受け取り不可)", function()
	local d = data(alice)
	H.assertEq(#d.quests.list, 3, "3 quests")
	local entry = d.quests.list[1]
	local q = Config.QuestById[entry.id]
	entry.p = q.count
	entry.done = true
	local before = d.coins
	local Quest = H.require(server.Services.QuestService)
	Quest.handleRequest(alice, "claimQuest", 1)
	H.assertEq(d.coins, before + q.reward.coins, "reward")
	Quest.handleRequest(alice, "claimQuest", 1)
	H.assertEq(d.coins, before + q.reward.coins, "claimed twice")
end)

H.test("デイリー報酬は1日1回", function()
	local d = data(alice)
	H.assert(d.daily.pending, "daily not pending for new player")
	local Quest = H.require(server.Services.QuestService)
	local before = d.coins
	Quest.handleRequest(alice, "claimDaily")
	H.assertEq(d.coins, before + Config.Tuning.DailyRewards[1].coins)
	Quest.handleRequest(alice, "claimDaily")
	H.assertEq(d.coins, before + Config.Tuning.DailyRewards[1].coins, "claimed twice")
end)

H.test("水槽: 飾ると小屋に魚が出る、戻すと消える", function()
	local d = data(alice)
	d.creel = {}
	table.insert(d.creel, { uid = "t1", fishId = "kappa_koi", grams = 2000, spot = "swamp", at = 0 })
	Shop.handleRequest(alice, "toTank", "t1")
	H.assertEq(#d.tank, 1)
	local Aquarium = H.require(server.Services.AquariumService)
	local hut = Aquarium.hutOf(alice)
	H.assert(hut ~= nil, "no hut assigned")
	H.assertEq(#hut.TankFish:GetChildren(), 1, "fish not displayed")
	Shop.handleRequest(alice, "fromTank", "t1")
	H.assertEq(#hut.TankFish:GetChildren(), 0)
end)

H.test("相棒: 魚籠の魚を相棒にして、魚を食べさせるとレベルが上がる", function()
	local d = data(alice)
	d.creel = {
		{ uid = "pa", fishId = "kappa_koi", grams = 2000, spot = "swamp", at = 0 },
		{ uid = "f1", fishId = "kyubi_koi", grams = 9000, spot = "swamp", at = 0 },
		{ uid = "f2", fishId = "doro_funa", grams = 800, spot = "swamp", at = 0, locked = true },
	}
	Shop.handleRequest(alice, "addPartner", "pa") -- Shop ではなく Partner の操作 → 何も起きない
	H.assertEq(#d.partners, 0, "wrong service handled addPartner")
	local Partner = H.require(server.Services.PartnerService)
	Partner.handleRequest(alice, "addPartner", "pa")
	H.assertEq(#d.partners, 1, "partner not added")
	H.assertEq(d.team[1], "pa", "not added to team")
	H.assertEq(d.partners[1].level, 1)
	Partner.handleRequest(alice, "feed", { partner = "pa", food = "f2" })
	H.assertEq(#d.creel, 2, "ate a locked fish")
	Partner.handleRequest(alice, "feed", { partner = "pa", food = "f1" })
	H.assertEq(#d.creel, 1, "food not consumed")
	H.assert(d.partners[1].level > 5, "legendary food should give many levels, got Lv" .. d.partners[1].level)
	Partner.handleRequest(alice, "setTeam", { "pa", "nope" })
	H.assertEq(#d.team, 1, "team accepted unknown uid")
	Partner.handleRequest(alice, "setTeam", { "pa", "pa" })
	H.assertEq(#d.team, 1, "team accepted duplicate")
end)

H.test(
	"妖怪退治: 順番を飛ばせない / 勝つと小判・経験値・依頼が進む / 戦闘中は釣れない",
	function()
		local d = data(alice)
		local Partner = H.require(server.Services.PartnerService)
		local Battle = H.require(server.Services.BattleService)
		d.partners[1].level = 20
		d.quests.list[2] = { id = "battle2", p = 0, done = false, claimed = false }
		Battle.handleRequest(alice, "startBattle", "kitsune_bride")
		H.assert(not Battle.inBattle(alice), "skipped ahead")
		Battle.handleRequest(alice, "startBattle", "kappa_kid")
		H.assert(Battle.inBattle(alice), "battle not started")
		H.assertEq(lastSent(alice, "BattleState")[1].kind, "start")
		-- 戦闘中は投げられず、相棒もいじれない
		task.wait(0.6)
		local before = countSent(alice, "FishingState")
		clientSend(alice, "Cast", 0.5, 0, -1)
		H.assertEq(countSent(alice, "FishingState"), before, "cast during battle")
		Partner.handleRequest(alice, "removePartner", "pa")
		H.assertEq(#d.partners, 1, "partner removed during battle")
		-- 不正な行動は無視される
		local turns = countSent(alice, "BattleState")
		clientSend(alice, "BattleAction", { kind = "move", index = 9 })
		clientSend(alice, "BattleAction", { kind = "hack" })
		clientSend(alice, "BattleAction", "move")
		H.assertEq(countSent(alice, "BattleState"), turns, "invalid action processed")
		task.wait(1)
		local coinsBefore = d.coins
		local xpLevelBefore = d.partners[1].level
		local guard = 0
		while Battle.inBattle(alice) and guard < 40 do
			guard += 1
			clientSend(alice, "BattleAction", { kind = "move", index = 1 })
			task.wait(0.3)
		end
		local r = lastSent(alice, "BattleState")[1]
		H.assertEq(r.kind, "result", "no result")
		H.assert(r.win, "Lv20 partner lost to Lv3 kappa")
		H.assert(r.firstClear, "first clear flag")
		H.assertEq(d.coins, coinsBefore + Config.TrainerById.kappa_kid.reward.coins, "reward coins")
		H.assert(d.battle.cleared.kappa_kid, "not marked cleared")
		H.assert(d.partners[1].level > xpLevelBefore or d.partners[1].xp > 0, "no xp")
		H.assertEq(d.quests.list[2].p, 1, "battle quest progress")
	end
)

H.test(
	"妖怪退治: 2回目は小判が減る / 次の相手に挑めるようになる / 逃げると負け",
	function()
		local d = data(alice)
		local Battle = H.require(server.Services.BattleService)
		local coinsBefore = d.coins
		Battle.handleRequest(alice, "startBattle", "kappa_kid")
		task.wait(1)
		local guard = 0
		while Battle.inBattle(alice) and guard < 40 do
			guard += 1
			clientSend(alice, "BattleAction", { kind = "move", index = 1 })
			task.wait(0.3)
		end
		local expected = math.floor(Config.TrainerById.kappa_kid.reward.coins * Config.Battle.RematchCoinRate)
		H.assertEq(d.coins, coinsBefore + expected, "rematch coins")
		-- 同じ日の3回目: 小判は無し(経験値はもらえる)
		local xpBefore = d.partners[1].xp + d.partners[1].level * 1e6
		Battle.handleRequest(alice, "startBattle", "kappa_kid")
		task.wait(1)
		guard = 0
		while Battle.inBattle(alice) and guard < 40 do
			guard += 1
			clientSend(alice, "BattleAction", { kind = "move", index = 1 })
			task.wait(0.3)
		end
		local r3 = lastSent(alice, "BattleState")[1]
		H.assert(r3.win, "third battle lost")
		H.assertEq(r3.coins, 0, "rematch coins paid twice in a day")
		H.assert(r3.rematchPaidToday, "no note about today's coins")
		H.assertEq(d.coins, coinsBefore + expected, "coins changed on the 3rd battle")
		H.assert(d.partners[1].xp + d.partners[1].level * 1e6 > xpBefore, "no xp on the 3rd battle")
		-- 次の日はまた小判がもらえる
		d.battle.rematchPaid.kappa_kid -= 1
		Battle.handleRequest(alice, "startBattle", "kappa_kid")
		task.wait(1)
		guard = 0
		while Battle.inBattle(alice) and guard < 40 do
			guard += 1
			clientSend(alice, "BattleAction", { kind = "move", index = 1 })
			task.wait(0.3)
		end
		H.assertEq(d.coins, coinsBefore + expected * 2, "next day's rematch coins")
		Battle.handleRequest(alice, "startBattle", "tanuki")
		H.assert(Battle.inBattle(alice), "next trainer not unlocked")
		task.wait(0.6)
		clientSend(alice, "BattleAction", { kind = "run" })
		local r = lastSent(alice, "BattleState")[1]
		H.assertEq(r.kind, "result")
		H.assert(not r.win, "run counted as win")
		H.assert(not d.battle.cleared.tanuki, "cleared by running")
	end
)

H.test("退出時に保存され、セッションロックが外れる", function()
	data(alice).coins = 12345
	table.remove(playerList, table.find(playerList, alice))
	alice.Parent = nil
	Players.PlayerRemoving:Fire(alice)
	task.wait(0.3)
	local stored = stores[Config.Tuning.Data.storeName]["u_1001"]
	H.assertEq(stored.coins, 12345, "not saved")
	H.assert(stored._lock == nil, "lock not released")
end)

H.test(
	"別サーバーがロック中なら待ち、古いロックは引き継いで読み込む",
	function()
		local store = stores[Config.Tuning.Data.storeName]
		store["u_2002"] = { coins = 777, _lock = { job = "server-B", t = os.time() } }
		local bob = makePlayer(2002)
		table.insert(playerList, bob)
		local t0 = os.clock()
		Players.PlayerAdded:Fire(bob)
		task.wait(0.5)
		H.assert(not DataService.isLoaded(bob), "loaded while another server holds the lock")
		while not DataService.isLoaded(bob) and os.clock() - t0 < 8 do
			task.wait(0.2)
		end
		H.assert(DataService.isLoaded(bob), "never loaded")
		H.assertEq(data(bob).coins, 777, "data lost")
		H.assertEq(store["u_2002"]._lock.job, "server-A")
		-- 古いサーバーがロックを取り返したら、こちらは保存をやめてキックする
		store["u_2002"]._lock = { job = "server-C", t = os.time() }
		data(bob).coins = 1
		H.assert(not DataService.saveNow(bob), "saved without lock")
		H.assertEq(store["u_2002"].coins, 777, "overwrote other server's data")
		H.assert(kicked[2002] ~= nil, "not kicked")
	end
)

H.test("ぬし釣り: 出現 → 湖の近くで巻く → 成功で極以上の魚と称号", function()
	local carol = makePlayer(3003)
	table.insert(playerList, carol)
	Players.PlayerAdded:Fire(carol)
	task.wait(0.5)
	H.assert(DataService.isLoaded(carol), "carol not loaded")
	place(carol.Character.HumanoidRootPart, roblox.CFrame.new(0, 3, 640))
	-- サーバー時刻を「毎時30分」に進める
	local NT = Config.Tuning.Nushi
	local now = serverTime + os.clock()
	local cycleStart = math.floor((now - NT.offsetSeconds) / NT.periodSeconds + 1) * NT.periodSeconds
		+ NT.offsetSeconds
	serverTime += cycleStart - now + 1
	task.wait(1.3)
	local appeared = false
	for _, a in announced do
		if a.args[1] == "nushi_appear" then
			appeared = true
		end
	end
	H.assert(appeared, "nushi did not appear")
	H.assert(workspace:FindFirstChild("Nushi") ~= nil, "nushi model missing")
	-- 遠くからの報告は無効
	local far = makePlayer(4004)
	table.insert(playerList, far)
	Players.PlayerAdded:Fire(far)
	task.wait(0.5)
	for _ = 1, 3 do
		clientSend(far, "NushiReel", 5)
		task.wait(0.4)
	end
	for _ = 1, 8 do
		clientSend(carol, "NushiReel", 0.5)
		task.wait(0.35)
	end
	task.wait(1.2)
	local r = lastSent(carol, "CatchResult")
	H.assert(r ~= nil and r[1].source == "nushi", "no nushi reward")
	local fish = Config.FishById[r[1].fishId]
	H.assert(Config.RarityById[fish.rarity].order >= 4, "reward below epic: " .. fish.rarity)
	H.assert(table.find(data(carol).titles, "nushi_hunter"), "no title")
	H.assert(lastSent(far, "CatchResult") == nil, "far player rewarded")
end)

H.test("自動釣り: パスが無いと使えない / あれば操作なしで釣れる", function()
	local noPass = makePlayer(6006)
	table.insert(playerList, noPass)
	Players.PlayerAdded:Fire(noPass)
	task.wait(0.5)
	Shop.handleRequest(noPass, "setAuto", true)
	H.assert(noPass:GetAttribute("AutoFishing") ~= true, "auto enabled without pass")

	local dave = makePlayer(5005)
	table.insert(playerList, dave)
	Players.PlayerAdded:Fire(dave)
	task.wait(0.8)
	Shop.handleRequest(dave, "setAuto", true)
	H.assertEq(dave:GetAttribute("AutoFishing"), true, "auto not enabled with pass")
	local t0 = os.clock()
	while #data(dave).creel == 0 and data(dave).stats.caught == 0 and os.clock() - t0 < 20 do
		task.wait(0.5)
	end
	H.assert(data(dave).stats.caught >= 1, "auto fishing caught nothing")
	-- 手動で投げると自動は止まる
	task.wait(1.5)
	clientSend(dave, "Cast", 0.5, 0, -1)
	H.assert(dave:GetAttribute("AutoFishing") ~= true, "manual cast did not stop auto")
end)

H.test("個人データ削除(eraseUser)でプレイヤーデータが消える", function()
	H.assert(DataService.eraseUser(1001), "erase failed")
	H.assert(stores[Config.Tuning.Data.storeName]["u_1001"] == nil, "still stored")
end)

-- オンライン(対戦・ボス戦・なかま) ------------------------------------------------
local O = Config.Online
local Pvp = H.require(server.Services.PvpService)
local function onlinePlayer(userId: number, level: number)
	local p = makePlayer(userId)
	table.insert(playerList, p)
	Players.PlayerAdded:Fire(p)
	local t0 = os.clock()
	while not data(p) and os.clock() - t0 < 5 do
		task.wait(0.1)
	end
	local d = data(p)
	d.partners = {}
	d.team = {}
	for i, fishId in { "hasu_koi", "kappa_koi", "bake_fugu" } do
		local uid = ("u%d_%d"):format(userId, i)
		table.insert(
			d.partners,
			{ uid = uid, fishId = fishId, grams = 1500, level = level, xp = 0, caughtAt = 0 }
		)
		table.insert(d.team, uid)
	end
	return p
end
local function request(p, action, payload)
	clientSend(p, "Request", action, payload)
end
local function lastArena(p, kind)
	for i = #(sent[p] or {}), 1, -1 do
		local e = sent[p][i]
		if e.name == "Arena" and e.args[1].kind == kind then
			return e.args[1]
		end
	end
	return nil
end
local function lastBattle(p, kind)
	for i = #(sent[p] or {}), 1, -1 do
		local e = sent[p][i]
		if e.name == "BattleState" and e.args[1].kind == kind then
			return e.args[1]
		end
	end
	return nil
end
-- 結果が出るまで、両方(b は nil なら片方だけ)が行動を選び続ける
local function playOut(a, actA, b, actB)
	local guard = 0
	while (Pvp.busy(a) or (b and Pvp.busy(b))) and guard < 80 do
		guard += 1
		clientSend(a, "BattleAction", actA)
		if b then
			clientSend(b, "BattleAction", actB)
		end
		task.wait(0.15)
	end
end
local pA = onlinePlayer(7001, 20)
local pB = onlinePlayer(7002, 20)

H.test(
	"対戦の申し込み: 受け取らない・友達だけの設定を守る / 受けると始まり、相手の画面は自分が手前になる",
	function()
		request(pB, "setChallengePref", "off")
		request(pA, "pvpChallenge", 7002)
		H.assertEq(lastSent(pA, "Notify")[1], "pvp_target_closed", "off")
		request(pB, "setChallengePref", "friends")
		request(pA, "pvpChallenge", 7002)
		H.assertEq(lastSent(pA, "Notify")[1], "pvp_target_closed", "friends only, not friends")
		friendships["7001:7002"] = true
		request(pA, "pvpChallenge", 7002)
		local inv = lastArena(pB, "invite")
		H.assert(inv ~= nil and inv.from == 7001, "no invite")
		H.assertEq(inv.name, pA.DisplayName)
		request(pA, "pvpChallenge", 7002)
		H.assertEq(lastSent(pA, "Notify")[1], "pvp_wait", "cooldown")
		-- 知らない人からの「受ける」は無視
		request(pB, "pvpRespond", { from = 9999, accept = true })
		H.assert(not Pvp.busy(pB), "accepted a challenge nobody sent")
		request(pB, "pvpRespond", { from = 7001, accept = true })
		H.assert(Pvp.busy(pA) and Pvp.busy(pB), "match not started")
		local sa, sb = lastBattle(pA, "start"), lastBattle(pB, "start")
		H.assertEq(sa.mode, "pvp")
		H.assertEq(sa.opponent.name, pB.DisplayName)
		H.assertEq(sa.state.player.team[1].fishId, "hasu_koi")
		H.assert(
			sb.state.player.moves ~= nil and sa.state.enemy.moves == nil,
			"each side sees only its own moves"
		)
		-- 戦っている間は釣れない・相棒をいじれない
		local before = countSent(pA, "FishingState")
		clientSend(pA, "Cast", 0.5, 0, -1)
		H.assertEq(countSent(pA, "FishingState"), before, "cast during pvp")
		-- 片方が選ぶと「待っています」、両方そろうとターンが進む
		clientSend(pA, "BattleAction", { kind = "move", index = 1 })
		H.assertEq(lastSent(pA, "BattleState")[1].kind, "waiting")
		H.assertEq(lastSent(pB, "BattleState")[1].kind, "foeReady")
		clientSend(pB, "BattleAction", { kind = "move", index = 1 })
		local ta, tb = lastBattle(pA, "turn"), lastBattle(pB, "turn")
		H.assert(ta ~= nil and tb ~= nil, "turn not sent to both")
		H.assertEq(tb.state.player.team[1].fishId, ta.state.enemy.team[1].fishId, "mirrored view")
		local wA, lA, rA = data(pA).pvp.wins, data(pA).pvp.losses, data(pA).pvp.rating
		local coinsA = data(pA).coins
		playOut(pA, { kind = "move", index = 1 }, pB, { kind = "move", index = 1 })
		local ra, rb = lastBattle(pA, "result"), lastBattle(pB, "result")
		H.assert(ra and rb and ra.win ~= rb.win, "exactly one winner")
		H.assertEq(data(pA).pvp.wins + data(pA).pvp.losses, wA + lA + 1, "record")
		H.assertEq(data(pA).pvp.rating, rA, "friendly match changed the rating")
		H.assertEq(data(pA).coins, coinsA, "friendly match paid coins")
	end
)

H.test(
	"ランダム対戦: 同じサーバーで待つ2人が組まれ、点数が動き、小判は1日の最初の勝利だけ",
	function()
		request(pA, "pvpQueue")
		H.assertEq(lastArena(pA, "queue").state, "searching")
		request(pB, "pvpQueue")
		H.assert(Pvp.busy(pA) and Pvp.busy(pB), "not paired")
		H.assertEq(lastBattle(pA, "start").pvpKind, "random")
		local coinsA, rA = data(pA).coins, data(pA).pvp.rating
		data(pA).pvp.dailyWinDay = -1
		playOut(pA, { kind = "move", index = 1 }, pB, { kind = "run" }) -- B は降参
		H.assert(lastBattle(pA, "result").win, "A should win")
		H.assert(data(pA).pvp.rating > rA and data(pB).pvp.rating < 1000 + 100, "rating did not move")
		H.assertEq(data(pA).coins, coinsA + O.DailyWinCoins, "daily first win coins")
		-- 同じ日の2勝目は小判なし
		request(pA, "pvpQueue")
		request(pB, "pvpQueue")
		playOut(pA, { kind = "move", index = 1 }, pB, { kind = "run" })
		H.assert(lastBattle(pA, "result").win, "A should win again")
		H.assertEq(data(pA).coins, coinsA + O.DailyWinCoins, "paid twice in a day")
	end
)

H.test(
	"ランダム対戦: 相手がいなければ ほかのサーバーのチームの写しと戦う(名前は出さない・壊れた写しは使わない)",
	function()
		local oldAfter = O.QueueGhostAfter
		O.QueueGhostAfter = 1
		local pC = onlinePlayer(7003, 20)
		local BattleLib = H.require(shared.Lib.Battle)
		local Battle = H.require(server.Services.BattleService)
		local power = BattleLib.power(Battle.fighters(Battle.teamFor(data(pC))))
		local map = memory[O.GhostStore] or {}
		memory[O.GhostStore] = map
		map["8888"] = {
			value = { team = { { f = "doro_funa", g = 900, l = 999 } }, power = power, rating = 1100 },
			sortKey = power,
		}
		map["8889"] = {
			value = {
				team = { { f = "doro_funa", g = 900, l = 18 }, { f = "kappa_haze", g = 500, l = 18 } },
				power = power,
				rating = 1100,
				title = "angler_novice",
			},
			sortKey = power,
		}
		request(pC, "pvpQueue")
		local t0 = os.clock()
		while not Pvp.busy(pC) and os.clock() - t0 < 6 do
			task.wait(0.2)
		end
		O.QueueGhostAfter = oldAfter
		H.assert(Pvp.busy(pC), "no ghost match")
		local st = lastBattle(pC, "start")
		H.assert(st.opponent.ghost == true and st.opponent.name == nil, "ghost owner's name was shown")
		H.assertEq(st.state.enemy.team[1].fishId, "doro_funa")
		H.assertEq(st.state.enemy.team[1].level, 18, "broken ghost used")
		playOut(pC, { kind = "move", index = 1 })
		H.assert(lastBattle(pC, "result") ~= nil, "no result vs ghost")
		H.assert(data(pC).pvp.rating ~= 1000, "ghost match is ranked")
	end
)

H.test(
	"対戦: 選ばない人はコンピューターが代わりに選び、続けて選ばないと降参 / 抜けると負け",
	function()
		local oldTurn, oldFirst = O.TurnSeconds, O.FirstTurnSeconds
		O.TurnSeconds, O.FirstTurnSeconds = 0.6, 0.6
		request(pA, "pvpChallenge", 7002)
		task.wait(O.ChallengeCooldown) -- 前の申し込みからの待ち
		request(pA, "pvpChallenge", 7002)
		request(pB, "pvpRespond", { from = 7001, accept = true })
		H.assert(Pvp.busy(pA), "match not started")
		local t0 = os.clock()
		while Pvp.busy(pA) and os.clock() - t0 < 12 do
			clientSend(pA, "BattleAction", { kind = "move", index = 1 })
			task.wait(0.4)
		end
		O.TurnSeconds, O.FirstTurnSeconds = oldTurn, oldFirst
		H.assert(not Pvp.busy(pA), "afk match never ended")
		H.assert(lastBattle(pA, "result").win, "afk player should lose")
		-- 抜けると相手の勝ち(抜けた人のデータは片付くので、別の人で試す)
		local pL = onlinePlayer(7006, 20)
		friendships["7006:7002"] = true -- B は「友達だけ」受け取る設定
		request(pL, "pvpChallenge", 7002)
		request(pB, "pvpRespond", { from = 7006, accept = true })
		H.assert(Pvp.busy(pB), "second match not started")
		table.remove(playerList, table.find(playerList, pL))
		Players.PlayerRemoving:Fire(pL)
		H.assert(not Pvp.busy(pB), "match kept after leaving")
		H.assert(lastBattle(pB, "result").win, "remaining player should win")
		-- 抜けた人の負けも保存されている(抜ければ負けが付かない、という抜け道を作らない)
		local saved = stores[Config.Tuning.Data.storeName]["u_7006"]
		H.assert(saved and saved.pvp.losses == 1, "leaver's loss not saved")
		-- 降参は相手を待たずにすぐ決まる
		local pF = onlinePlayer(7007, 20)
		request(pF, "pvpChallenge", 7001)
		request(pA, "pvpRespond", { from = 7007, accept = true })
		H.assert(Pvp.busy(pA), "third match not started")
		clientSend(pF, "BattleAction", { kind = "run" })
		H.assert(not Pvp.busy(pA) and not Pvp.busy(pF), "forfeit did not end the match at once")
		H.assert(lastBattle(pA, "result").win and not lastBattle(pF, "result").win, "forfeit winner wrong")
	end
)

H.test(
	"ボス戦: 部屋 → 参加 → 開始 → みんなで1本の体力を削る → 小判は1日1回・経験値は毎回 / 部屋の数に上限",
	function()
		local boss = Config.Bosses[1]
		local oldHp = boss.hpMult
		boss.hpMult = 0.15
		local Raid = H.require(server.Services.RaidService)
		request(pA, "raidCreate", boss.id)
		H.assert(Raid.inRoom(pA), "room not created")
		local rooms = nil
		for i = #announced, 1, -1 do
			if announced[i].name == "Arena" and announced[i].args[1].kind == "rooms" then
				rooms = announced[i].args[1].rooms
				break
			end
		end
		H.assert(rooms and #rooms == 1 and rooms[1].bossId == boss.id, "room list not broadcast")
		request(pB, "raidJoin", rooms[1].id)
		H.assert(Raid.inRoom(pB), "join failed")
		request(pB, "raidStart") -- ホストではないので始まらない
		H.assert(not Raid.fighting(pA), "non-host started the raid")
		request(pA, "raidStart")
		H.assert(Raid.fighting(pA) and Raid.fighting(pB), "raid not started")
		local sa = lastBattle(pA, "start")
		H.assertEq(sa.mode, "raid")
		local max = sa.raid.max
		H.assertEq(sa.state.enemy.team[1].maxHp, max, "boss hp is the shared pool")
		clientSend(pA, "BattleAction", { kind = "move", index = 1 })
		local afterA = lastBattle(pB, "raid").raid.hp
		H.assert(afterA < max or lastBattle(pA, "result"), "A's damage did not reach the shared pool")
		local coinsA, coinsB = data(pA).coins, data(pB).coins
		local paidB = data(pB).raid.paid[boss.id]
		local guard = 0
		while (Raid.fighting(pA) or Raid.fighting(pB)) and guard < 60 do
			guard += 1
			clientSend(pA, "BattleAction", { kind = "move", index = 1 })
			clientSend(pB, "BattleAction", { kind = "move", index = 1 })
			task.wait(0.1)
		end
		local ra, rb = lastBattle(pA, "result"), lastBattle(pB, "result")
		H.assert(ra.win and rb.win, "both should win")
		H.assertEq(data(pA).coins, coinsA + boss.reward.coins, "A reward")
		H.assertEq(data(pB).coins, coinsB + (if paidB then 0 else boss.reward.coins), "B reward")
		H.assert(#ra.gains > 0 and ra.gains[1].xp > 0, "no xp")
		-- 同じ日の2回目: 経験値はもらえて、小判は無し
		request(pA, "raidCreate", boss.id)
		request(pA, "raidStart")
		guard = 0
		while Raid.fighting(pA) and guard < 60 do
			guard += 1
			clientSend(pA, "BattleAction", { kind = "move", index = 1 })
			task.wait(0.1)
		end
		local r2 = lastBattle(pA, "result")
		H.assert(r2.win and r2.coins == 0 and r2.rewardPaidToday, "second clear paid coins")
		H.assert(#r2.gains > 0, "no xp on the second clear")
		boss.hpMult = oldHp
		-- 部屋は同時に2つまで
		local pD = onlinePlayer(7004, 10)
		local pE = onlinePlayer(7005, 10)
		request(pA, "raidCreate", boss.id)
		request(pD, "raidCreate", boss.id)
		request(pE, "raidCreate", boss.id)
		H.assertEq(lastSent(pE, "Notify")[1], "raid_rooms_full")
		request(pA, "raidLeave")
		request(pD, "raidLeave")
		H.assert(not Raid.inRoom(pA) and not Raid.inRoom(pD), "leave failed")
	end
)

H.test(
	"なかま: スタンプは決まったものだけ全員に届く / 公開する情報は進み具合だけ / 水槽を見に行ける",
	function()
		local n = #announced
		clientSend(pA, "Stamp", "hello")
		local last = announced[#announced]
		H.assert(#announced == n + 1 and last.name == "StampShown", "stamp not broadcast")
		H.assertEq(last.args[1], 7001)
		H.assertEq(last.args[2], "hello")
		clientSend(pA, "Stamp", "<font>free text</font>")
		H.assertEq(#announced, n + 1, "unknown stamp broadcast")
		task.wait(3.2)
		H.assert(type(pA:GetAttribute("PvpRating")) == "number", "rating attribute")
		H.assert(type(pA:GetAttribute("Codex")) == "number", "codex attribute")
		-- 水槽を見に行く
		local Aquarium = H.require(server.Services.AquariumService)
		local hut = Aquarium.hutOf(pB)
		H.assert(hut ~= nil, "B has no hut")
		request(pA, "visitTank", 7002)
		local floor = hut:FindFirstChild("Floor")
		local pos = pA.Character.HumanoidRootPart.Position
		H.assert((pos - floor.CFrame.Position).Magnitude < 16, "not moved to the hut")
	end
)

H.test("バトルの好み(速さ・画面の揺れ): 決まった値だけ保存する", function()
	local data = DataService.get(pA)
	H.assertEq(data.settings.battleSpeed, 1, "default speed")
	H.assertEq(data.settings.battleShake, true, "default shake")
	request(pA, "setBattlePrefs", { speed = 2, shake = false })
	H.assertEq(data.settings.battleSpeed, 2)
	H.assertEq(data.settings.battleShake, false)
	-- おかしな値は無視
	request(pA, "setBattlePrefs", { speed = 99, shake = "yes" })
	request(pA, "setBattlePrefs", { speed = 0 / 0 })
	request(pA, "setBattlePrefs", "fast")
	H.assertEq(data.settings.battleSpeed, 2)
	H.assertEq(data.settings.battleShake, false)
	request(pA, "setBattlePrefs", { speed = 1, shake = true })
	H.assertEq(data.settings.battleSpeed, 1)
end)

-- RECORD_MESSAGES=ファイル を付けると、サーバーが送った本物の知らせと、遊んだ後の本物のデータを書き出す。
-- tests/client_boot.luau が、それを本物のクライアントへ流し込んで画面を全部動かす(形の食い違いを見つける)
local recordPath = process.env.RECORD_MESSAGES
if recordPath then
	local fs = require("@lune/fs")
	local serde = require("@lune/serde")
	-- 輪になった表(人 → キャラ → 親 …)は1度だけたどる。人の偽物は名前だけにする
	local onPath: { [any]: boolean } = {}
	local function enc(v: any, depth: number?): any
		local d = depth or 0
		local ty = typeof(v)
		if d > 20 then
			return nil
		elseif ty == "table" and v.UserId ~= nil then
			return { __t = "Instance", v = { tostring(v.Name or v.UserId) } }
		elseif ty == "table" then
			if onPath[v] then
				return nil
			end
			onPath[v] = true
			local out = {}
			for k, x in v do
				if type(k) == "string" or type(k) == "number" then
					out[if type(k) == "number" then "#" .. k else k] = enc(x, d + 1)
				end
			end
			onPath[v] = nil
			return out
		elseif ty == "Vector3" then
			return { __t = "Vector3", v = { v.X, v.Y, v.Z } }
		elseif ty == "Vector2" then
			return { __t = "Vector2", v = { v.X, v.Y } }
		elseif ty == "Color3" then
			return { __t = "Color3", v = { v.R, v.G, v.B } }
		elseif ty == "CFrame" then
			return { __t = "CFrame", v = { v:GetComponents() } }
		elseif ty == "EnumItem" then
			return { __t = "Enum", v = { tostring(v.EnumType), v.Name } }
		elseif ty == "Instance" then
			return { __t = "Instance", v = { tostring(v) } }
		elseif ty == "number" or ty == "string" or ty == "boolean" then
			return v
		end
		return nil
	end
	local function messages(p): { any }
		local out = {}
		for _, m in sent[p] or {} do
			table.insert(out, { name = m.name, args = enc(m.args) })
		end
		return out
	end
	local function profileOf(p): any
		local d = DataService.get(p)
		if not d then
			-- 抜けた人は、最後に送ったデータ
			for i = #(sent[p] or {}), 1, -1 do
				local m = sent[p][i]
				if m.name == "Profile" then
					return enc(m.args[1])
				end
			end
			return nil
		end
		local copy = {}
		for k, v in d do
			if k ~= "_lock" and k ~= "purchases" and k ~= "uidCounter" then
				copy[k] = v
			end
		end
		return enc(copy)
	end
	fs.writeFile(
		recordPath,
		serde.encode("json", {
			fishing = messages(alice),
			fishingProfile = profileOf(alice),
			online = messages(pA),
			onlineProfile = profileOf(pA),
			announced = enc(announced),
		})
	)
	print("recorded server messages → " .. recordPath)
end

local okAll = H.summary()
process.exit(if okAll then 0 else 1)
