--!strict
-- 最初の釣り場「沼」。見た目の完成度を最優先で作り込む。
-- 霧のかかる水面、葦、蓮、石灯籠、蛍、島の祠、桟橋、狸の行商、村への鳥居。
local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Build = require(script.Parent.Build)
local Terrain = require(script.Parent.Terrain)

local M = {}

function M.build()
	local spot = Config.SpotById.swamp
	local o = Vector3.new(spot.origin.x, spot.origin.y, spot.origin.z)
	local center = o + Vector3.new(spot.water.x, spot.water.y, spot.water.z)
	local basin: Terrain.Basin = {
		center = center,
		rx = spot.water.rx,
		rz = spot.water.rz,
		half = 88,
		groundY = 2,
		hills = 12,
		seed = 11,
	}
	Terrain.build(basin)

	local world = workspace:FindFirstChild("World") or Build.folder("World", workspace)
	local root = Build.folder("Swamp", world)
	local deco = Build.folder("Deco", root)
	local rng = Random.new(20261101)

	local spawnPos = o + Vector3.new(spot.spawn.x, 0, spot.spawn.z)
	local function ground(x: number, z: number): number
		return Terrain.heightAt(basin, x, z)
	end
	-- 桟橋や施設の周りは木を置かない
	local function clear(x: number, z: number): boolean
		if math.abs(x - o.X) < 12 and z > center.Z + 10 then
			return false
		end
		if (Vector3.new(x, 0, z) - Vector3.new(spawnPos.X, 0, spawnPos.Z)).Magnitude < 26 then
			return false
		end
		return true
	end

	-- 出現地点(桟橋の根元)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "SwampSpawn"
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.CFrame = CFrame.new(spawnPos.X, ground(spawnPos.X, spawnPos.Z) + 0.5, spawnPos.Z)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Material = Enum.Material.WoodPlanks
	spawn.Color = Color3.fromRGB(120, 88, 60)
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = root
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end

	-- 桟橋(水面へ突き出す)
	local pier = Build.folder("Pier", root)
	local shoreZ = center.Z + spot.water.rz
	local pierStart, pierEnd = spawnPos.Z - 4, shoreZ - 12
	local deckY = center.Y + 1.4
	local z = pierStart
	local i = 0
	while z > pierEnd do
		i += 1
		Build.part({
			name = "Plank",
			size = Vector3.new(7, 0.35, 1.8),
			cframe = CFrame.new(o.X, deckY, z) * CFrame.Angles(0, math.rad(rng:NextNumber(-1.5, 1.5)), 0),
			color = Color3.fromRGB(110 + rng:NextInteger(-10, 10), 80, 54),
			material = Enum.Material.WoodPlanks,
			parent = pier,
		})
		if i % 3 == 0 then
			for _, x in { -3.3, 3.3 } do
				Build.part({
					name = "Post",
					size = Vector3.new(0.7, 6, 0.7),
					cframe = CFrame.new(o.X + x, deckY - 2.2, z),
					color = Color3.fromRGB(70, 52, 38),
					material = Enum.Material.Wood,
					parent = pier,
				})
			end
		end
		z -= 2
	end
	-- 桟橋の坂(地面 → 桟橋)
	local landY = ground(o.X, pierStart + 4)
	Build.part({
		name = "Ramp",
		size = Vector3.new(7, 0.35, 6),
		cframe = CFrame.lookAt(
			Vector3.new(o.X, (landY + deckY) / 2, pierStart + 2),
			Vector3.new(o.X, deckY, pierStart - 1)
		),
		color = Color3.fromRGB(110, 80, 54),
		material = Enum.Material.WoodPlanks,
		parent = pier,
	})
	Build.lantern(pier, Vector3.new(o.X - 3.2, deckY, pierEnd + 1))
	Build.lantern(pier, Vector3.new(o.X + 3.2, deckY, pierEnd + 1))

	-- 木
	local placed = 0
	local tries = 0
	while placed < 48 and tries < 600 do
		tries += 1
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(1.3, 2.05)
		local x = center.X + math.cos(a) * spot.water.rx * r
		local zz = center.Z + math.sin(a) * spot.water.rz * r
		if clear(x, zz) and math.abs(x) < 84 and math.abs(zz - center.Z) < 84 then
			local kind = if rng:NextNumber() < 0.15
				then "maple"
				elseif rng:NextNumber() < 0.3 then "pine"
				else nil
			Build.tree(deco, Vector3.new(x, ground(x, zz) - 0.5, zz), rng, kind)
			placed += 1
		end
	end

	-- 葦(岸辺)
	for _ = 1, 80 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(0.93, 1.06)
		local x = center.X + math.cos(a) * spot.water.rx * r
		local zz = center.Z + math.sin(a) * spot.water.rz * r
		if clear(x, zz) then
			Build.reeds(deco, Vector3.new(x, center.Y, zz), rng)
		end
	end

	-- 蓮
	for _ = 1, 34 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = math.sqrt(rng:NextNumber(0.05, 0.75))
		local x = center.X + math.cos(a) * spot.water.rx * r
		local zz = center.Z + math.sin(a) * spot.water.rz * r
		Build.lotus(deco, Vector3.new(x, center.Y + 0.08, zz), rng)
	end

	-- 石灯籠
	for k = 0, 7 do
		local a = (k / 8) * math.pi * 2 + 0.3
		local x = center.X + math.cos(a) * spot.water.rx * 1.14
		local zz = center.Z + math.sin(a) * spot.water.rz * 1.14
		if clear(x, zz) then
			Build.lantern(deco, Vector3.new(x, ground(x, zz), zz))
		end
	end

	-- 岸の岩
	for _ = 1, 24 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(1.0, 1.25)
		local x = center.X + math.cos(a) * spot.water.rx * r
		local zz = center.Z + math.sin(a) * spot.water.rz * r
		if clear(x, zz) then
			local s = rng:NextNumber(1.5, 4)
			Build.part({
				name = "Rock",
				size = Vector3.new(s * 1.3, s, s),
				cframe = CFrame.new(x, ground(x, zz), zz)
					* CFrame.Angles(rng:NextNumber(0, 1), rng:NextNumber(0, 6), 0),
				color = Color3.fromRGB(100, 104, 98),
				material = Enum.Material.Slate,
				shape = Enum.PartType.Ball,
				parent = deco,
			})
		end
	end

	-- 島と祠(遠くの目印)
	local island = center + Vector3.new(-16, 0, -18)
	workspace.Terrain:FillBall(island + Vector3.new(0, -3.5, 0), 7, Enum.Material.LeafyGrass)
	Build.tree(deco, island + Vector3.new(2, 1.8, 2), rng, "maple")
	local shrine = Instance.new("Model")
	shrine.Name = "Hokora"
	local wood = Color3.fromRGB(150, 60, 40)
	Build.part({
		name = "Base",
		size = Vector3.new(3, 0.6, 3),
		cframe = CFrame.new(island + Vector3.new(-2, 2.6, -1)),
		color = Color3.fromRGB(140, 140, 130),
		material = Enum.Material.Slate,
		parent = shrine,
	})
	Build.part({
		name = "Box",
		size = Vector3.new(2.2, 2.4, 2.2),
		cframe = CFrame.new(island + Vector3.new(-2, 4.1, -1)),
		color = wood,
		material = Enum.Material.Wood,
		parent = shrine,
	})
	Build.part({
		name = "Roof",
		size = Vector3.new(3.2, 0.5, 3.2),
		cframe = CFrame.new(island + Vector3.new(-2, 5.5, -1)) * CFrame.Angles(0, math.rad(45), 0),
		color = Color3.fromRGB(40, 40, 46),
		material = Enum.Material.Slate,
		parent = shrine,
	})
	local candle = Build.part({
		name = "Candle",
		size = Vector3.new(0.5, 0.5, 0.5),
		cframe = CFrame.new(island + Vector3.new(-2, 4.2, -2.2)),
		color = Color3.fromRGB(120, 220, 255),
		material = Enum.Material.Neon,
		shape = Enum.PartType.Ball,
		collide = false,
		parent = shrine,
	})
	local cl = Instance.new("PointLight")
	cl.Color = Color3.fromRGB(110, 210, 255)
	cl.Range = 14
	cl.Brightness = 2
	cl.Parent = candle
	shrine.Parent = deco
	Build.torii(deco, CFrame.new(island + Vector3.new(-2, 1.8, 3.5)), 0.35)

	-- 蛍(夜)
	Build.fireflies(
		deco,
		center + Vector3.new(0, 3, 0),
		Vector3.new(spot.water.rx * 1.6, 4, spot.water.rz * 1.6)
	)
	Build.fireflies(deco, center + Vector3.new(-30, 4, 30), Vector3.new(30, 6, 20))

	-- 霧の粒(低く漂う)
	local mistPart = Build.part({
		name = "Mist",
		size = Vector3.new(spot.water.rx * 2, 1, spot.water.rz * 2),
		cframe = CFrame.new(center + Vector3.new(0, 0.6, 0)),
		transparency = 1,
		collide = false,
		parent = deco,
	})
	mistPart.CanQuery = false
	local mist = Instance.new("ParticleEmitter")
	mist.Color = ColorSequence.new(Color3.fromRGB(230, 236, 240))
	mist.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.88),
		NumberSequenceKeypoint.new(1, 1),
	})
	mist.Size = NumberSequence.new(14)
	mist.Lifetime = NumberRange.new(10, 16)
	mist.Rate = 3
	mist.Speed = NumberRange.new(0.3, 0.8)
	mist.SpreadAngle = Vector2.new(180, 0)
	mist.LightInfluence = 1
	mist.Parent = mistPart
	CollectionService:AddTag(mist, "MistFX")

	-- 狸の行商(魚を売れる)
	local stallPos = spawnPos + Vector3.new(-20, 0, 2)
	stallPos = Vector3.new(stallPos.X, ground(stallPos.X, stallPos.Z), stallPos.Z)
	local stallCF = CFrame.lookAt(stallPos, Vector3.new(spawnPos.X, stallPos.Y, spawnPos.Z - 6))
	Terrain.flatten(stallCF, 16, 12)
	local counter =
		Build.stall(root, stallCF, "sign_fish_shop", "open:shop:sell", Color3.fromRGB(40, 70, 120))
	CollectionService:AddTag(counter, "Merchant")
	counter:SetAttribute("TutorialTarget", "sell")
	Build.tanuki(root, stallCF * CFrame.new(0, 0, 3.4))

	-- 村への鳥居
	local toriiPos = spawnPos + Vector3.new(22, 0, 10)
	toriiPos = Vector3.new(toriiPos.X, ground(toriiPos.X, toriiPos.Z), toriiPos.Z)
	local toriiCF = CFrame.lookAt(toriiPos, Vector3.new(spawnPos.X, toriiPos.Y, spawnPos.Z))
	Build.torii(root, toriiCF)
	local gate = Build.part({
		name = "Gate",
		size = Vector3.new(8, 10, 1),
		cframe = toriiCF * CFrame.new(0, 5, 0),
		transparency = 1,
		collide = false,
		parent = root,
	})
	Build.prompt(gate, "prompt_travel", "travel:nushi_lake", 14)
	Build.sign(
		root,
		toriiCF * CFrame.new(0, 12.1, -0.45),
		Vector2.new(4, 1.6),
		"sign_torii_village",
		Color3.fromRGB(28, 22, 22)
	)

	return root
end

return M
