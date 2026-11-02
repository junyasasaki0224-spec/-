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
			-- 水槽に収まる大きさに縮める
			local scale = math.clamp(1.4 / (def.size or 1), 0.4, 1.2)
			local model =
				FishBuilder.build(def, { mutation = caught.mutation, scale = scale, anchored = true })
			local half = tank.Size / 2 - Vector3.new(1.2, 1, 1.2)
			local offset = Vector3.new(
				rng:NextNumber(-half.X, half.X),
				rng:NextNumber(-half.Y, half.Y),
				rng:NextNumber(-half.Z, half.Z)
			)
			model:PivotTo(
				tank.CFrame * CFrame.new(offset) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
			)
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
