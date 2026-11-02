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

local okAll = H.summary()
process.exit(if okAll then 0 else 1)
