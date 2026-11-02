--!strict
-- 釣りの流れ(投げる→待つ→合わせる→引き上げる)をサーバーで管理する。
-- 不正対策の考え方:
--  * どの魚が釣れるか・重さ・変異・売値は、すべてサーバーが抽選する。クライアントは結果を受け取るだけ。
--  * クライアントが送れるのは「投げる強さ(0〜1)」「合わせた」「引き上げ成功/失敗」だけ。
--  * 合わせは「!」を出した時刻からの経過時間をサーバーで測る。
--  * 引き上げ成功の報告は、完璧に操作しても不可能な速さなら却下する(最短時間チェック)。
--  * 1人につき同時に1回しか釣れない(状態とトークンで管理)。
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Lib.Remotes)
local Roll = require(Shared.Lib.Roll)
local Types = require(Shared.Lib.Types)
local RemoteGuard = require(script.Parent.RemoteGuard)

local FT = Config.Tuning.Fishing
local FirstCatch = Config.Tuning.FirstCatch

local FishingService = {}
local S: any

type Session = {
	state: string, -- idle | waiting | bite | reeling
	token: number,
	spot: string?,
	power: number,
	baitId: string,
	biteAt: number,
	reelStart: number,
	reelMin: number,
	fish: Types.FishDef?,
	grams: number,
	mutation: string?,
	auto: boolean,
	autoBusy: boolean,
	bobber: BasePart?,
	easy: boolean,
}

local sessions: { [Player]: Session } = {}
local rng = Random.new()
local function rand(): number
	return rng:NextNumber()
end

local stateRemote: RemoteEvent
local catchRemote: RemoteEvent
local bobberFolder: Folder

local function getSession(player: Player): Session
	local s = sessions[player]
	if not s then
		s = {
			state = "idle",
			token = 0,
			spot = nil,
			power = 0,
			baitId = "",
			biteAt = 0,
			reelStart = 0,
			reelMin = 0,
			fish = nil,
			grams = 0,
			mutation = nil,
			auto = false,
			autoBusy = false,
			bobber = nil,
			easy = false,
		}
		sessions[player] = s
	end
	return s
end

local function rootPart(player: Player): BasePart?
	local char = player.Character
	if not char then
		return nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then
		return nil
	end
	return char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- 水面の中心(ワールド座標)
local function waterCenter(spot: any): Vector3
	return Vector3.new(
		spot.origin.x + spot.water.x,
		spot.origin.y + spot.water.y,
		spot.origin.z + spot.water.z
	)
end
FishingService.waterCenter = waterCenter

-- 楕円の水面までのおおよその距離(内側なら 0)
local function distanceToWater(spot: any, pos: Vector3): number
	local c = waterCenter(spot)
	local dx, dz = pos.X - c.X, pos.Z - c.Z
	local d = math.sqrt((dx / spot.water.rx) ^ 2 + (dz / spot.water.rz) ^ 2)
	if d <= 1 then
		return 0
	end
	return math.sqrt(dx * dx + dz * dz) * (1 - 1 / d)
end

-- 立っている場所から一番近い、遊べる釣り場
function FishingService.spotAt(pos: Vector3): any?
	local best, bestD = nil, math.huge
	for _, spot in Config.Spots do
		if spot.available then
			local d = distanceToWater(spot, pos)
			if d < bestD then
				best, bestD = spot, d
			end
		end
	end
	if best and bestD <= FT.shoreDistance then
		return best
	end
	return nil
end

local function landingPoint(spot: any, root: BasePart, power: number, aim: Vector3?): Vector3
	local c = waterCenter(spot)
	local look = aim or root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.01 then
		flat = Vector3.new(0, 0, -1)
	end
	local dist = FT.castMinDistance + (FT.castMaxDistance - FT.castMinDistance) * power
	local target = root.Position + flat.Unit * dist
	local dx, dz = target.X - c.X, target.Z - c.Z
	local d = math.sqrt((dx / spot.water.rx) ^ 2 + (dz / spot.water.rz) ^ 2)
	local limit = 0.9
	if d > limit then
		dx, dz = dx * limit / d, dz * limit / d
	end
	return Vector3.new(c.X + dx, c.Y + 0.15, c.Z + dz)
end

-- 竿(キャラクターの右手に付ける)。他のプレイヤーにも見える
local function attachRod(player: Player)
	local char = player.Character
	local data = S.Data.get(player)
	if not char or not data then
		return
	end
	local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") then
		return
	end
	local old = char:FindFirstChild("YokaiRod")
	if old then
		old:Destroy()
	end
	local rodDef = Config.RodByTier[data.rodTier] or Config.Rods[1]
	local model = Instance.new("Model")
	model.Name = "YokaiRod"
	local function part(name: string, size: Vector3, color: string, material: Enum.Material?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = Color3.fromHex(color)
		p.Material = material or Enum.Material.Wood
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.Parent = model
		return p
	end
	local handle = part("Handle", Vector3.new(0.25, 0.25, 1.2), rodDef.accent, Enum.Material.Fabric)
	local shaft = part("Shaft", Vector3.new(0.12, 0.12, 6), rodDef.color)
	local tipCF = CFrame.new(0, 0, -3)
	handle.CFrame = (hand :: BasePart).CFrame * CFrame.new(0, -0.9, 0) * CFrame.Angles(math.rad(50), 0, 0)
	shaft.CFrame = handle.CFrame * CFrame.new(0, 0, -3.4)
	local tip = Instance.new("Attachment")
	tip.Name = "Tip"
	tip.CFrame = tipCF
	tip.Parent = shaft
	local w1 = Instance.new("WeldConstraint")
	w1.Part0 = hand :: BasePart
	w1.Part1 = handle
	w1.Parent = handle
	local w2 = Instance.new("WeldConstraint")
	w2.Part0 = handle
	w2.Part1 = shaft
	w2.Parent = shaft
	model.Parent = char
end
FishingService.attachRod = attachRod

local function clearBobber(s: Session)
	if s.bobber then
		s.bobber:Destroy()
		s.bobber = nil
	end
end

local function makeBobber(player: Player, pos: Vector3): BasePart
	local b = Instance.new("Part")
	b.Name = "Bobber_" .. player.UserId
	b.Shape = Enum.PartType.Ball
	b.Size = Vector3.new(0.6, 0.6, 0.6)
	b.Color = Color3.fromRGB(230, 60, 60)
	b.Material = Enum.Material.SmoothPlastic
	b.Anchored = true
	b.CanCollide = false
	b.CanQuery = false
	b.CanTouch = false
	b.Position = pos
	b:SetAttribute("Owner", player.UserId)
	b:SetAttribute("State", "waiting")
	local att = Instance.new("Attachment")
	att.Name = "Line"
	att.Parent = b
	-- 釣り糸(竿の先端 → ウキ)
	local char = player.Character
	local rod = char and char:FindFirstChild("YokaiRod")
	local shaft = rod and rod:FindFirstChild("Shaft")
	local tip = shaft and shaft:FindFirstChild("Tip")
	if tip and tip:IsA("Attachment") then
		local beam = Instance.new("Beam")
		beam.Attachment0 = tip
		beam.Attachment1 = att
		beam.Width0 = 0.04
		beam.Width1 = 0.04
		beam.Color = ColorSequence.new(Color3.fromRGB(235, 235, 235))
		beam.Transparency = NumberSequence.new(0.2)
		beam.FaceCamera = true
		beam.CurveSize0 = -1.5
		beam.Segments = 12
		beam.Parent = b
	end
	b.Parent = bobberFolder
	CollectionService:AddTag(b, "Bobber")
	return b
end

local function setIdle(player: Player, s: Session, reason: string?)
	s.token += 1
	s.state = "idle"
	s.fish = nil
	s.mutation = nil
	clearBobber(s)
	if reason and player.Parent == Players then
		stateRemote:FireClient(player, "idle", { reason = reason })
	end
end

-- 運の倍率を計算
function FishingService.luckFor(player: Player, power: number, baitId: string): number
	local data = S.Data.get(player)
	local rod = Config.RodByTier[data and data.rodTier or 1] or Config.Rods[1]
	local bait = Config.BaitById[baitId]
	return Roll.luck({
		rodLuck = rod.luck,
		baitLuck = if bait then bait.luck else 0,
		power = power,
		distanceBonus = FT.distanceLuckBonus,
		multipliers = S.Monetization.luckMultipliers(player),
		maxLuck = FT.maxLuck,
	})
end

-- 魚を抽選する(ぬし釣りの報酬でも使う)
function FishingService.rollCatch(
	player: Player,
	spotId: string,
	luck: number,
	minOrder: number?
): (Types.FishDef?, number, string?)
	local spot = Config.SpotById[spotId]
	local poolId = spot.fishPool or spot.id
	local cond = S.World.conditions(spotId)
	local rarityId = Roll.rarity(rand, Config.Rarities, luck, minOrder)
	local fish = Roll.fish(rand, Config.Fish, Config.Rarities, poolId, cond, rarityId)
	if not fish then
		return nil, 0, nil
	end
	local grams = Roll.grams(rand, fish, FT.weightSkew)
	local mutation = Roll.mutation(rand, Config.Mutations, spot.mutations)
	return fish, grams, mutation
end

-- 投げる
local function startCast(player: Player, power: number, isAuto: boolean, aim: Vector3?): boolean
	local s = getSession(player)
	local data = S.Data.get(player)
	if not data or s.state ~= "idle" then
		return false
	end
	local root = rootPart(player)
	if not root then
		return false
	end
	local spot = FishingService.spotAt(root.Position)
	if not spot then
		if not isAuto then
			S.notify(player, "fish_too_far")
		end
		return false
	end
	if not data.spots[spot.id] then
		return false
	end
	if
		#data.creel >= S.Monetization.creelCapacity(player) and not S.Monetization.hasPass(player, "autoSell")
	then
		if not isAuto then
			S.notify(player, "fish_creel_full")
		end
		return false
	end

	-- エサを1個使う
	local baitId = data.equippedBait
	if baitId ~= "" then
		if (data.bait[baitId] or 0) > 0 then
			data.bait[baitId] -= 1
			if data.bait[baitId] <= 0 then
				data.bait[baitId] = nil
			end
		else
			baitId = ""
			data.equippedBait = ""
		end
		S.Data.changed(player)
	end

	s.token += 1
	local token = s.token
	s.state = "waiting"
	s.spot = spot.id
	s.power = power
	s.baitId = baitId
	s.easy = not data.firstCatch
	clearBobber(s)
	local pos = landingPoint(spot, root, power, aim)
	s.bobber = makeBobber(player, pos)

	local bait = Config.BaitById[baitId]
	local wait
	if not data.firstCatch then
		wait = FirstCatch.biteSeconds
	else
		wait = Roll.biteSeconds(rand, FT.biteMinSeconds, FT.biteMaxSeconds, if bait then bait.biteTime else 1)
	end
	if isAuto then
		wait /= FT.autoFishSpeed
	end
	stateRemote:FireClient(player, "waiting", { position = pos, auto = isAuto })
	if data.tutorial < 1 then
		S.Analytics.onboarding(player, S.Analytics.Onboarding.FirstCast)
	end

	task.delay(wait, function()
		if s.token ~= token or s.state ~= "waiting" or player.Parent ~= Players then
			return
		end
		s.state = "bite"
		s.biteAt = os.clock()
		if s.bobber then
			s.bobber:SetAttribute("State", "bite")
		end
		stateRemote:FireClient(player, "bite", {})
		if isAuto then
			return -- 自動釣りは autoLoop が合わせる
		end
		task.delay(FT.hookWindow + FT.latencyAllowance + 0.1, function()
			if s.token == token and s.state == "bite" then
				setIdle(player, s, "escaped")
			end
		end)
	end)
	return true
end

-- 合わせる → 魚を抽選して引き上げ開始
local function startReel(player: Player, s: Session): boolean
	local data = S.Data.get(player)
	if not data or not s.spot then
		return false
	end
	local minOrder = nil
	if s.easy then
		minOrder = (Config.RarityById[FirstCatch.minRarity] :: any).order
	end
	local luck = FishingService.luckFor(player, s.power, s.baitId)
	local fish, grams, mutation = FishingService.rollCatch(player, s.spot, luck, minOrder)
	if not fish then
		setIdle(player, s, "escaped")
		return false
	end
	s.fish = fish
	s.grams = grams
	s.mutation = mutation
	s.state = "reeling"
	s.reelStart = os.clock()

	local rarity = Config.RarityById[fish.rarity]
	local rod = Config.RodByTier[data.rodTier] or Config.Rods[1]
	local easy = s.easy and FirstCatch.easy
	local duration = rarity.reelSeconds
	local params = {
		rarity = fish.rarity,
		duration = duration,
		fishSpeed = rarity.fishSpeed * (if easy then 0.5 else 1),
		jitter = rarity.jitter * (if easy then 0.5 else 1),
		tensionRate = rarity.tensionRate * (if easy then 0.5 else 1),
		tensionDecay = FT.tensionDecay,
		netSize = math.clamp(FT.netBaseSize * rod.netSize * (if easy then 1.5 else 1), 0.1, 0.6),
		reelSpeed = rod.reelSpeed,
		startProgress = FT.startProgress,
		seed = rng:NextInteger(1, 2 ^ 30),
		mutationHint = mutation ~= nil,
	}
	-- 完璧に操作した場合の最短時間(これより明らかに速い成功報告は不正)
	s.reelMin = math.max(
		0,
		(1 - FT.startProgress) * duration / rod.reelSpeed * FT.minReelFactor - FT.latencyAllowance
	)
	local token = s.token
	stateRemote:FireClient(player, "reel", params)
	task.delay(FT.reelTimeoutSeconds, function()
		if s.token == token and s.state == "reeling" then
			setIdle(player, s, "escaped")
		end
	end)
	return true
end

-- 釣果を記録する(図鑑・依頼・ランキング・自動売却)。ぬし釣りの報酬でも使う
function FishingService.grantCatch(
	player: Player,
	fish: Types.FishDef,
	grams: number,
	mutation: string?,
	spotId: string,
	source: string
)
	local data = S.Data.get(player)
	if not data then
		return
	end
	local entry = data.codex[fish.id]
	local isNew = entry == nil
	local isRecord = false
	if not entry then
		entry = { n = 0, best = 0, muts = {} }
		data.codex[fish.id] = entry
	end
	entry.n += 1
	if grams > entry.best then
		isRecord = not isNew
		entry.best = grams
	end
	if mutation then
		entry.muts[mutation] = true
	end
	data.stats.caught += 1

	local cond = S.World.conditions(spotId)
	local caught: Types.CaughtFish = {
		uid = S.Data.nextUid(player),
		fishId = fish.id,
		grams = grams,
		mutation = mutation,
		spot = spotId,
		at = os.time(),
	}
	local price = S.Shop.priceOf(player, caught)

	-- 自動売却: パス所持 + 設定したレア度以下 + 新種でも変異でもない
	local rarity = Config.RarityById[fish.rarity]
	local autoSold = false
	local autoSellOrder = data.settings.autoSell
	local hasAutoSell = S.Monetization.hasPass(player, "autoSell")
	if hasAutoSell and autoSellOrder > 0 and rarity.order <= autoSellOrder and not isNew and not mutation then
		autoSold = true
	elseif #data.creel >= S.Monetization.creelCapacity(player) then
		autoSold = true -- 魚籠が満杯なら失わないよう売る
	end
	if autoSold then
		S.Shop.addCoins(player, price, "AutoSell", fish.id)
		S.Quest.onSell(player, price)
	else
		table.insert(data.creel, caught)
	end

	local firstEver = not data.firstCatch
	data.firstCatch = true
	S.Quest.onCatch(player, fish, grams, mutation, cond)
	S.Leaderboard.onCatch(player, fish, grams)
	S.Data.changed(player)

	catchRemote:FireClient(player, {
		fishId = fish.id,
		grams = grams,
		mutation = mutation,
		isNew = isNew,
		isRecord = isRecord,
		price = price,
		autoSold = autoSold,
		firstEver = firstEver,
		source = source,
	})
	if firstEver then
		S.Analytics.onboarding(player, S.Analytics.Onboarding.FirstCatch)
	end
	if rarity.order >= 5 then
		S.Analytics.custom(player, "Catch_" .. fish.rarity)
	end

	-- 図鑑の完成報酬
	if isNew then
		S.Shop.checkCodexCompletion(player, fish.spot)
	end
end

local function finishReel(player: Player, s: Session, success: boolean)
	local fish = s.fish
	if not fish or not s.spot then
		setIdle(player, s, "escaped")
		return
	end
	local elapsed = os.clock() - s.reelStart
	if success and elapsed < s.reelMin then
		-- 人間には不可能な速さ。結果は無効
		warn(
			("[Fishing] rejected too-fast reel from %d (%.2fs < %.2fs)"):format(
				player.UserId,
				elapsed,
				s.reelMin
			)
		)
		S.Analytics.custom(player, "SuspiciousReel")
		setIdle(player, s, "escaped")
		return
	end
	if not success then
		setIdle(player, s, "broke")
		return
	end
	local spotId = s.spot
	local grams, mutation = s.grams, s.mutation
	setIdle(player, s, nil)
	stateRemote:FireClient(player, "idle", { reason = "caught" })
	FishingService.grantCatch(player, fish, grams, mutation, spotId, "fishing")
end

-- 自動釣り(ゲームパス)。すべてサーバー側で完結し、クライアントの操作は不要
local function autoStep(player: Player, s: Session)
	if s.autoBusy then
		return
	end
	s.autoBusy = true
	if s.state == "idle" then
		startCast(player, 0.6, true)
	elseif s.state == "bite" then
		if startReel(player, s) then
			local fish = s.fish :: Types.FishDef
			local rarity = Config.RarityById[fish.rarity]
			local token = s.token
			local reelTime = (FT.autoFishReelSeconds + rarity.reelSeconds * 0.5) / FT.autoFishSpeed
			task.delay(reelTime, function()
				if s.token == token and s.state == "reeling" then
					s.reelMin = 0
					finishReel(player, s, rand() < rarity.autoSuccess)
				end
			end)
		end
	end
	s.autoBusy = false
end

function FishingService.setAuto(player: Player, on: boolean)
	local s = getSession(player)
	if on and not S.Monetization.hasPass(player, "autoFish") then
		on = false
	end
	s.auto = on
	player:SetAttribute("AutoFishing", on)
	if not on and s.state ~= "reeling" then
		setIdle(player, s, "cancel")
	end
end

function FishingService.cancel(player: Player)
	local s = sessions[player]
	if s then
		setIdle(player, s, "cancel")
	end
end

function FishingService.state(player: Player): string
	local s = sessions[player]
	return if s then s.state else "idle"
end

function FishingService.init(registry: any)
	S = registry
end

function FishingService.start()
	stateRemote = Remotes.event("FishingState")
	catchRemote = Remotes.event("CatchResult")
	bobberFolder = Instance.new("Folder")
	bobberFolder.Name = "Bobbers"
	bobberFolder.Parent = workspace

	-- power: 0..1, dx/dz: 狙う向き(カメラの向き)。向きは着水点を決めるだけなので不正の余地はない
	RemoteGuard.connect(Remotes.event("Cast"), 2, 3, function(player, power, dx, dz)
		if not RemoteGuard.isNumber(power, 0, 1) then
			return
		end
		local aim: Vector3? = nil
		if RemoteGuard.isNumber(dx, -1, 1) and RemoteGuard.isNumber(dz, -1, 1) then
			local v = Vector3.new(dx, 0, dz)
			if v.Magnitude > 0.1 then
				aim = v.Unit
			end
		end
		local s = getSession(player)
		if s.auto then
			FishingService.setAuto(player, false)
		end
		startCast(player, power, false, aim)
	end)

	RemoteGuard.connect(Remotes.event("Hook"), 4, 4, function(player)
		local s = getSession(player)
		if s.auto or s.state ~= "bite" then
			return
		end
		if os.clock() - s.biteAt > FT.hookWindow + FT.latencyAllowance then
			setIdle(player, s, "escaped")
			return
		end
		local data = S.Data.get(player)
		if data and data.tutorial < 2 then
			S.Analytics.onboarding(player, S.Analytics.Onboarding.FirstHook)
		end
		startReel(player, s)
	end)

	RemoteGuard.connect(Remotes.event("ReelResult"), 2, 3, function(player, success)
		if type(success) ~= "boolean" then
			return
		end
		local s = getSession(player)
		if s.auto or s.state ~= "reeling" then
			return
		end
		finishReel(player, s, success)
	end)

	RemoteGuard.connect(Remotes.event("CancelFishing"), 3, 3, function(player)
		local s = getSession(player)
		if s.state ~= "reeling" then
			setIdle(player, s, "cancel")
		end
	end)

	local function onCharacter(player: Player, char: Model)
		FishingService.cancel(player)
		task.wait(0.5)
		if char.Parent then
			attachRod(player)
		end
		local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
		if hum then
			hum.Died:Connect(function()
				FishingService.cancel(player)
			end)
		end
	end
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(char)
			onCharacter(player, char)
		end)
		if player.Character then
			task.spawn(onCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
	S.Data.Loaded:Connect(function(player)
		attachRod(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		local s = sessions[player]
		if s then
			s.token += 1
			clearBobber(s)
		end
		sessions[player] = nil
	end)

	-- 自動釣りのループ + 遠くへ行ったら仕掛けを回収
	task.spawn(function()
		while true do
			task.wait(0.5)
			for player, s in sessions do
				if s.auto then
					task.spawn(autoStep, player, s)
				end
				if s.state == "waiting" or s.state == "bite" then
					local root = rootPart(player)
					if
						not root
						or (
							s.bobber
							and (root.Position - s.bobber.Position).Magnitude > FT.castMaxDistance + 25
						)
					then
						setIdle(player, s, "cancel")
					end
				end
			end
		end
	end)
end

return FishingService
