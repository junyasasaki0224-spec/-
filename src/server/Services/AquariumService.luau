--!strict
-- 釣り小屋と水槽。参加すると村の小屋が1軒割り当てられ、水槽に飾った魚が他のプレイヤーにも見える。
-- 小屋の看板には Roblox の表示名(Roblox 側でフィルタ済みの公開情報)だけを出す。
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local FishBuilder = require(Shared.Lib.FishBuilder)

local AquariumService = {}
local S: any

local assigned: { [Player]: Model } = {}

local function huts(): { Model }
	local folder = workspace:FindFirstChild("World")
	folder = folder and folder:FindFirstChild("Village")
	folder = folder and folder:FindFirstChild("Huts")
	if not folder then
		return {}
	end
	local list = {}
	for _, h in folder:GetChildren() do
		if h:IsA("Model") then
			table.insert(list, h)
		end
	end
	table.sort(list, function(a, b)
		return a.Name < b.Name
	end)
	return list
end

-- 水槽の中に魚を置く。レアほど大きく、でもガラスからはみ出さない。
-- 体の長さが奥行きに収まる魚は、ぐるりと泳いで向きを変える。収まらない大物(鮫・鯱など)は横向きのまま、その場でゆったり漂う。
-- 泳ぐ範囲(SwimX / SwimZ)と水槽の向き(TankX / TankZ)は属性で渡し、動きはクライアント(WorldFX)が付ける
local GLASS = Vector3.new(1.0, 0.8, 0.7) -- ガラスと底からのすき間(合計)
function AquariumService.place(model: Model, tank: BasePart, rng: Random)
	model:PivotTo(CFrame.new())
	local _, box = model:GetBoundingBox()
	local inner = tank.Size - GLASS
	local L, H, W = box.Z, box.Y, box.X
	local k = math.min(1, inner.X * 0.85 / L, inner.Y * 0.8 / H, inner.Z * 0.95 / W)
	if k < 1 then
		model:ScaleTo(model:GetScale() * k)
		L, H, W = L * k, H * k, W * k
	end
	local hover = L > inner.Z * 0.95
	-- 向きを変える魚は、どの向きでもはみ出さない半径で考える
	local reach = if hover then L / 2 else math.max(L, W) / 2
	local swimX = math.clamp(inner.X / 2 - reach - 0.2, 0, if hover then 0.6 else 1.9)
	local swimZ = if hover then 0 else math.clamp(inner.Z / 2 - reach, 0, 0.5)
	local roomX = math.max(0, inner.X / 2 - reach - swimX)
	local roomY = math.max(0, inner.Y / 2 - H / 2 - 0.2)
	local yaw = if hover
		then (if rng:NextInteger(0, 1) == 0 then math.pi / 2 else -math.pi / 2)
		else rng:NextNumber(0, math.pi * 2)
	model:PivotTo(
		tank.CFrame
			* CFrame.new(rng:NextNumber(-roomX, roomX), rng:NextNumber(-roomY, roomY), 0)
			* CFrame.Angles(0, yaw, 0)
	)
	model:SetAttribute("Hover", hover)
	model:SetAttribute("SwimX", swimX)
	model:SetAttribute("SwimZ", swimZ)
	model:SetAttribute("TankX", tank.CFrame.RightVector)
	model:SetAttribute("TankZ", tank.CFrame.LookVector)
end

local function clearTank(hut: Model)
	local f = hut:FindFirstChild("TankFish")
	if f then
		f:ClearAllChildren()
	end
end

function AquariumService.refresh(player: Player)
	local hut = assigned[player]
	local data = S.Data.get(player)
	if not hut or not data then
		return
	end
	clearTank(hut)
	local tank = hut:FindFirstChild("Tank") :: BasePart?
	local folder = hut:FindFirstChild("TankFish")
	if not tank or not folder then
		return
	end
	local rng = Random.new(player.UserId)
	for i, caught in data.tank do
		local def = Config.FishById[caught.fishId]
		if def then
			-- レアほど大きく(差はゆるめて残す: 並 ≒ 0.82 〜 秘伝 ≒ 1.53 倍)。大物はガラスに当たる分だけ place で縮める
			local size = FishBuilder.sizeOf(def)
			local scale = math.clamp(0.95 / math.sqrt(size), 0.4, 1.2)
			local model =
				FishBuilder.build(def, { mutation = caught.mutation, scale = scale, anchored = true })
			AquariumService.place(model, tank :: BasePart, rng)
			model:SetAttribute("Index", i)
			model.Parent = folder
			CollectionService:AddTag(model, "TankFish")
		end
	end
end

local function assign(player: Player)
	for _, hut in huts() do
		if hut:GetAttribute("OwnerId") == nil or hut:GetAttribute("OwnerId") == 0 then
			hut:SetAttribute("OwnerId", player.UserId)
			hut:SetAttribute("OwnerName", player.DisplayName)
			assigned[player] = hut
			AquariumService.refresh(player)
			return
		end
	end
end

local function release(player: Player)
	local hut = assigned[player]
	if hut then
		clearTank(hut)
		hut:SetAttribute("OwnerId", 0)
		hut:SetAttribute("OwnerName", "")
	end
	assigned[player] = nil
end

function AquariumService.hutOf(player: Player): Model?
	return assigned[player]
end

function AquariumService.init(registry: any)
	S = registry
end

function AquariumService.start()
	S.Data.Loaded:Connect(assign)
	Players.PlayerRemoving:Connect(release)
end

return AquariumService
