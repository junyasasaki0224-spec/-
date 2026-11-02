--!strict
-- 釣り村(拠点)。中央に「ぬしの湖」、周りに魚屋・竿屋・エサ屋・依頼板・ランキング看板・釣り小屋。
local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Build = require(script.Parent.Build)
local Terrain = require(script.Parent.Terrain)

local HUT_COUNT = 10 -- 最大人数に合わせる(サーバー人数の設定と揃える)

local M = {}

local function hut(parent: Instance, cf: CFrame, index: number)
	Terrain.flatten(cf, 16, 14)
	local model = Instance.new("Model")
	model.Name = ("Hut_%02d"):format(index)
	local wood = Color3.fromRGB(138, 100, 66)
	local darkWood = Color3.fromRGB(84, 60, 42)
	Build.part({
		name = "Floor",
		size = Vector3.new(12, 0.6, 10),
		cframe = cf * CFrame.new(0, 0.3, 0),
		color = darkWood,
		material = Enum.Material.WoodPlanks,
		parent = model,
	})
	Build.part({
		name = "Back",
		size = Vector3.new(12, 8, 0.5),
		cframe = cf * CFrame.new(0, 4.3, 4.75),
		color = wood,
		material = Enum.Material.Wood,
		parent = model,
	})
	for _, x in { -5.75, 5.75 } do
		Build.part({
			name = "Side",
			size = Vector3.new(0.5, 8, 10),
			cframe = cf * CFrame.new(x, 4.3, 0),
			color = wood,
			material = Enum.Material.Wood,
			parent = model,
		})
	end
	for _, side in { 1, -1 } do
		Build.part({
			name = "Roof",
			size = Vector3.new(7.2, 0.5, 12),
			cframe = cf * CFrame.new(side * 3.2, 9.6, 0) * CFrame.Angles(0, 0, side * math.rad(-28)),
			color = Color3.fromRGB(52, 56, 70),
			material = Enum.Material.Slate,
			parent = model,
		})
	end
	-- 水槽
	local tank = Build.part({
		name = "Tank",
		size = Vector3.new(9, 4.4, 3.2),
		cframe = cf * CFrame.new(0, 3.2, 2.6),
		color = Color3.fromRGB(140, 210, 230),
		material = Enum.Material.Glass,
		transparency = 0.72,
		parent = model,
	})
	Build.part({
		name = "TankStand",
		size = Vector3.new(9.4, 1, 3.6),
		cframe = cf * CFrame.new(0, 0.9, 2.6),
		color = darkWood,
		material = Enum.Material.Wood,
		parent = model,
	})
	Build.part({
		name = "TankSand",
		size = Vector3.new(8.8, 0.3, 3),
		cframe = cf * CFrame.new(0, 1.15, 2.6),
		color = Color3.fromRGB(214, 196, 150),
		material = Enum.Material.Sand,
		collide = false,
		parent = model,
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(150, 220, 255)
	light.Range = 10
	light.Brightness = 1
	light.Parent = tank
	local tf = Instance.new("Folder")
	tf.Name = "TankFish"
	tf.Parent = model
	Build.prompt(tank, "prompt_view_tank", "open:tank", 10)
	local sign = Build.sign(model, cf * CFrame.new(0, 8.8, -5.1), Vector2.new(8, 1.6), "tank_owner")
	sign.Name = "OwnerSign"
	model:SetAttribute("OwnerId", 0)
	model:SetAttribute("OwnerName", "")
	CollectionService:AddTag(model, "Hut")
	model.Parent = parent
end

local function rankingBoard(parent: Instance, cf: CFrame)
	local board = Build.part({
		name = "RankingBoard",
		size = Vector3.new(18, 11, 0.6),
		cframe = cf * CFrame.new(0, 8, 0),
		color = Color3.fromRGB(46, 32, 24),
		material = Enum.Material.Wood,
		parent = parent,
	})
	for _, x in { -8.5, 8.5 } do
		Build.part({
			name = "Leg",
			size = Vector3.new(0.8, 14, 0.8),
			cframe = cf * CFrame.new(x, 6, 0.5),
			color = Color3.fromRGB(70, 50, 36),
			material = Enum.Material.Wood,
			parent = parent,
		})
	end
	Build.part({
		name = "BoardRoof",
		size = Vector3.new(20, 0.6, 2.4),
		cframe = cf * CFrame.new(0, 13.9, 0),
		color = Color3.fromRGB(52, 56, 70),
		material = Enum.Material.Slate,
		parent = parent,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Name = "RankingGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0.1
	gui.Parent = board
	CollectionService:AddTag(board, "RankingBoard")
end

function M.build()
	local spot = Config.SpotById.nushi_lake
	local o = Vector3.new(spot.origin.x, spot.origin.y, spot.origin.z)
	local center = o + Vector3.new(spot.water.x, spot.water.y, spot.water.z)
	local basin: Terrain.Basin = {
		center = center,
		rx = spot.water.rx,
		rz = spot.water.rz,
		half = 92,
		groundY = 2,
		hills = 10,
		seed = 29,
	}
	Terrain.build(basin)
	local function ground(x: number, z: number): number
		return Terrain.heightAt(basin, x, z)
	end

	local world = workspace:FindFirstChild("World") or Build.folder("World", workspace)
	local root = Build.folder("Village", world)
	local deco = Build.folder("Deco", root)
	local rng = Random.new(777)

	local function at(dx: number, dz: number): Vector3
		local x, z = center.X + dx, center.Z + dz
		return Vector3.new(x, ground(x, z), z)
	end
	local function facing(pos: Vector3): CFrame
		return CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z))
	end

	-- 石畳の広場(湖の南側)
	local spawnPos = o + Vector3.new(spot.spawn.x, 0, spot.spawn.z)
	local plazaY = ground(spawnPos.X, spawnPos.Z)
	for k = -3, 3 do
		Build.part({
			name = "Path",
			size = Vector3.new(10, 0.4, 8),
			cframe = CFrame.new(spawnPos.X, plazaY + 0.1, spawnPos.Z - 6 + k * 8),
			color = Color3.fromRGB(150, 146, 136),
			material = Enum.Material.Cobblestone,
			parent = root,
		})
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "VillageSpawn"
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.CFrame = CFrame.new(spawnPos.X, plazaY + 0.5, spawnPos.Z)
	spawn.Anchored = true
	spawn.Neutral = false -- 最初は沼に出現させる(村は鳥居で移動)
	spawn.Enabled = false
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Parent = root

	-- 湖畔の桟橋(ぬし釣りの見物席)
	for k = 0, 5 do
		Build.part({
			name = "Plank",
			size = Vector3.new(8, 0.35, 1.8),
			cframe = CFrame.new(center.X, center.Y + 1.4, center.Z + spot.water.rz + 2 - k * 2),
			color = Color3.fromRGB(116, 84, 56),
			material = Enum.Material.WoodPlanks,
			parent = root,
		})
	end

	-- お店
	for _, p in { at(-26, 46), at(-50, 22), at(50, 22), at(26, 46), at(0, -50) } do
		Terrain.flatten(facing(p), 16, 12)
	end
	local fishShop = Build.stall(
		root,
		facing(at(-26, 46)),
		"sign_fish_shop",
		"open:shop:sell",
		Color3.fromRGB(40, 70, 120)
	)
	CollectionService:AddTag(fishShop, "Merchant")
	Build.tanuki(root, facing(at(-26, 46)) * CFrame.new(0, 0, 3.4))
	Build.stall(root, facing(at(-50, 22)), "sign_rod_shop", "open:shop:rods", Color3.fromRGB(120, 40, 40))
	Build.stall(root, facing(at(50, 22)), "sign_bait_shop", "open:shop:bait", Color3.fromRGB(60, 110, 60))

	-- 依頼板
	local qPos = at(26, 46)
	local qcf = facing(qPos)
	local qBoard = Build.part({
		name = "QuestBoard",
		size = Vector3.new(9, 6, 0.5),
		cframe = qcf * CFrame.new(0, 4.5, 0),
		color = Color3.fromRGB(150, 110, 70),
		material = Enum.Material.WoodPlanks,
		parent = root,
	})
	for _, x in { -4, 4 } do
		Build.part({
			name = "Leg",
			size = Vector3.new(0.6, 8, 0.6),
			cframe = qcf * CFrame.new(x, 4, 0.4),
			color = Color3.fromRGB(80, 56, 40),
			material = Enum.Material.Wood,
			parent = root,
		})
	end
	Build.sign(root, qcf * CFrame.new(0, 8.4, -0.1), Vector2.new(6, 1.4), "sign_quest_board")
	for k = 1, 3 do
		Build.part({
			name = "Paper",
			size = Vector3.new(2.2, 3, 0.05),
			cframe = qcf
				* CFrame.new(-3 + (k - 1) * 3, 4.5, -0.3)
				* CFrame.Angles(0, 0, math.rad(rng:NextNumber(-5, 5))),
			color = Color3.fromRGB(245, 236, 210),
			material = Enum.Material.Fabric,
			collide = false,
			parent = root,
		})
	end
	Build.prompt(qBoard, "prompt_open", "open:quests", 12)

	-- ランキング看板(湖の向こう側、出現地点から見える位置)
	local rPos = at(0, -50)
	rankingBoard(root, facing(rPos))
	Build.sign(root, facing(rPos) * CFrame.new(0, 15.2, -0.2), Vector2.new(8, 1.8), "sign_ranking")

	-- 沼への鳥居
	local tPos = at(0, 80)
	local tcf = CFrame.lookAt(tPos, Vector3.new(spawnPos.X, tPos.Y, spawnPos.Z))
	Build.torii(root, tcf)
	local gate = Build.part({
		name = "Gate",
		size = Vector3.new(8, 10, 1),
		cframe = tcf * CFrame.new(0, 5, 0),
		transparency = 1,
		collide = false,
		parent = root,
	})
	Build.prompt(gate, "prompt_travel", "travel:swamp", 14)
	Build.sign(
		root,
		tcf * CFrame.new(0, 12.1, -0.45),
		Vector2.new(4, 1.6),
		"sign_torii_swamp",
		Color3.fromRGB(28, 22, 22)
	)

	-- 釣り小屋(湖の北側に半円状)
	local hutsFolder = Build.folder("Huts", root)
	for k = 1, HUT_COUNT do
		local a = math.rad(195 + (k - 1) * (150 / (HUT_COUNT - 1)))
		local r = 66
		local pos = at(math.cos(a) * r, math.sin(a) * r)
		-- 小屋の正面(-Z)を湖へ向ける
		hut(hutsFolder, facing(pos), k)
	end

	-- 灯籠と桜
	for k = 0, 11 do
		local a = (k / 12) * math.pi * 2
		local p = at(math.cos(a) * spot.water.rx * 1.2, math.sin(a) * spot.water.rz * 1.2)
		Build.lantern(deco, p)
	end
	local placed, tries = 0, 0
	while placed < 30 and tries < 400 do
		tries += 1
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(80, 90)
		local p = at(math.cos(a) * r, math.sin(a) * r)
		placed += 1
		Build.tree(deco, p - Vector3.new(0, 0.5, 0), rng, if rng:NextNumber() < 0.5 then "sakura" else "pine")
	end
	for _ = 1, 30 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = math.sqrt(rng:NextNumber(0.1, 0.7))
		Build.lotus(
			deco,
			Vector3.new(
				center.X + math.cos(a) * spot.water.rx * r,
				center.Y + 0.08,
				center.Z + math.sin(a) * spot.water.rz * r
			),
			rng
		)
	end
	Build.fireflies(
		deco,
		center + Vector3.new(0, 3, 0),
		Vector3.new(spot.water.rx * 1.8, 4, spot.water.rz * 1.8)
	)

	return root
end

return M
