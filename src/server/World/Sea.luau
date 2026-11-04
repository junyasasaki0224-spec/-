--!strict
-- 三つ目の釣り場「海」。南の砂浜から北へ開けた入り江。沖は外海で、水平線まで水が続く(山は南側だけ)。
-- 長い桟橋、海に立つ大鳥居、東の岬の灯台、岩礁、浜の黒松、小舟、干物の棚、狸の行商、村への鳥居。
-- 大きくてレアな魚(鮫・鯱・鯨・大鱏・大蛇)はここで釣れる。パーツは約600に抑える(スマホ向け)。
local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Build = require(script.Parent.Build)
local Scenery = require(script.Parent.Scenery)
local Terrain = require(script.Parent.Terrain)

local M = {}

local ROCK = Color3.fromRGB(92, 88, 84)
local DARK_WOOD = Color3.fromRGB(70, 52, 38)

-- 外海(入り江の北)。真ん中ほど岸に近く、横へ行くほど岬が北へ伸びる。岸の線は少し揺らす(まっすぐだと人工的)
-- 正なら海の中(値は岸からのおおよその距離)
function M.oceanMargin(center: Vector3, x: number, z: number): number
	local dz = center.Z - z -- 北(-Z)が正
	local dx = math.abs(x - center.X)
	return dz - (22 + math.max(0, dx - 70) * 0.35) + math.noise(x / 34, z / 34, 7.3) * 10
end
function M.isOcean(center: Vector3, x: number, z: number): boolean
	return M.oceanMargin(center, x, z) > 0
end

function M.build()
	local spot = Config.SpotById.sea
	local o = Vector3.new(spot.origin.x, spot.origin.y, spot.origin.z)
	local center = o + Vector3.new(spot.water.x, spot.water.y, spot.water.z)
	local rx, rz = spot.water.rx, spot.water.rz
	local basin: Terrain.Basin = {
		center = center,
		rx = rx,
		rz = rz,
		half = 130,
		groundY = 2,
		hills = 8,
		seed = 53,
		ring = 150,
		ringHeight = 60,
		extent = 230,
	}
	Terrain.build(basin)

	-- 外海: 北側の山と陸を消して、深い海にする(水平線まで続くように広く)。入り江の底は砂に
	local terrain = workspace.Terrain
	local y0 = center.Y
	local function sea(x: number, z: number, step: number)
		local dz = center.Z - z
		local depth = 8 + math.min(22, dz * 0.08)
		-- 海の底から上をいったん空にして(山・陸を消す)、水を張る
		terrain:FillBlock(
			CFrame.new(x, y0 + (90 - depth) / 2, z),
			Vector3.new(step, 90 + depth, step),
			Enum.Material.Air
		)
		terrain:FillBlock(
			CFrame.new(x, y0 - depth / 2, z),
			Vector3.new(step, depth, step),
			Enum.Material.Water
		)
		terrain:FillBlock(CFrame.new(x, y0 - depth - 8, z), Vector3.new(step, 16, step), Enum.Material.Sand)
	end
	-- 沖は 8 スタッドの升で、岸の近くだけ 4 スタッドの升で細かく(岸の線が階段に見えないように)
	for x = center.X - 264, center.X + 264, 8 do
		for z = center.Z - 336, center.Z + 40, 8 do
			local m = M.oceanMargin(center, x, z)
			if m > 10 then
				sea(x, z, 8)
			elseif m > -10 then
				for _, off in
					{ Vector2.new(-2, -2), Vector2.new(2, -2), Vector2.new(-2, 2), Vector2.new(2, 2) }
				do
					if M.isOcean(center, x + off.X, z + off.Y) then
						sea(x + off.X, z + off.Y, 4)
					end
				end
			end
		end
	end
	for x = center.X - rx, center.X + rx, 4 do
		for z = center.Z - rz, center.Z + rz, 4 do
			local d = Terrain.shape(basin, x, z)
			if d <= 1 and not M.isOcean(center, x, z) then
				local depth = 4 + (1 - d) * 8
				terrain:FillBlock(CFrame.new(x, y0 - depth - 1, z), Vector3.new(4, 2, 4), Enum.Material.Sand)
			end
		end
	end

	local world = workspace:FindFirstChild("World") or Build.folder("World", workspace)
	local root = Build.folder("Sea", world)
	local deco = Build.folder("Deco", root)
	local rng = Random.new(20261105)

	local function ground(x: number, z: number): number
		return Terrain.heightAt(basin, x, z)
	end
	local function at(x: number, z: number): Vector3
		return Vector3.new(x, ground(x, z), z)
	end
	local function onShore(deg: number, k: number): Vector3
		local a = math.rad(deg)
		return Vector3.new(center.X + math.cos(a) * rx * k, 0, center.Z + math.sin(a) * rz * k)
	end
	local spawnPos = o + Vector3.new(spot.spawn.x, 0, spot.spawn.z)
	local stallPos = at(spawnPos.X - 22, spawnPos.Z + 2)
	local toriiPos = at(spawnPos.X + 22, spawnPos.Z + 8)
	local lighthousePos = at(center.X + 104, center.Z - 12)
	local function busy(x: number, z: number): boolean
		local p = Vector3.new(x, 0, z)
		if math.abs(x - spawnPos.X) < 8 and z < spawnPos.Z + 4 then
			return true -- 桟橋
		end
		for _, q in { spawnPos, stallPos, toriiPos, lighthousePos } do
			if (p - Vector3.new(q.X, 0, q.Z)).Magnitude < 16 then
				return true
			end
		end
		return false
	end

	-- 砂浜(南の岸ぞいを砂に塗る)
	for _, k in { 1.1, 1.28, 1.46 } do
		local pts = {}
		for deg = 8, 172, 12 do
			table.insert(pts, onShore(deg, k))
		end
		Terrain.paintPath(basin, pts, 10, Enum.Material.Sand)
	end

	-- 出現地点(浜の上)と、海の名前の看板
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "SeaSpawn"
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.CFrame = CFrame.new(spawnPos.X, ground(spawnPos.X, spawnPos.Z) + 0.5, spawnPos.Z)
	spawn.Anchored = true
	spawn.Neutral = false -- 最初は沼に出現させる(ここへは鳥居・お店の「釣り場」で移動)
	spawn.Enabled = false
	spawn.Material = Enum.Material.WoodPlanks
	spawn.Color = Color3.fromRGB(150, 118, 84)
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = root
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end
	local signPost = at(spawnPos.X + 7, spawnPos.Z + 4)
	Build.part({
		name = "SignPost",
		size = Vector3.new(0.5, 5, 0.5),
		cframe = CFrame.new(signPost + Vector3.new(0, 2.5, 0)),
		color = DARK_WOOD,
		material = Enum.Material.Wood,
		parent = deco,
	})
	Build.sign(
		deco,
		CFrame.lookAt(signPost + Vector3.new(0, 5.4, 0), signPost + Vector3.new(0, 5.4, 1)),
		Vector2.new(3.2, 1.3),
		"spot_sea",
		Color3.fromRGB(30, 60, 96)
	)

	-- 長い桟橋(浜から入り江へ)と、先の広い釣り台
	local pier = Build.folder("Pier", root)
	local shoreZ = center.Z + rz
	local pierStart, pierEnd = spawnPos.Z - 6, shoreZ - 26
	local deckY = center.Y + 1.8
	local z = pierStart
	local i = 0
	while z > pierEnd do
		i += 1
		Build.part({
			name = "Plank",
			size = Vector3.new(7, 0.35, 1.8),
			cframe = CFrame.new(o.X, deckY, z) * CFrame.Angles(0, math.rad(rng:NextNumber(-1.5, 1.5)), 0),
			color = Color3.fromRGB(128 + rng:NextInteger(-10, 10), 98, 70),
			material = Enum.Material.WoodPlanks,
			parent = pier,
		})
		if i % 3 == 0 then
			for _, px in { -3.3, 3.3 } do
				Build.part({
					name = "Post",
					size = Vector3.new(0.7, 9, 0.7),
					cframe = CFrame.new(o.X + px, deckY - 1.1, z),
					color = DARK_WOOD,
					material = Enum.Material.Wood,
					parent = pier,
				})
			end
		end
		z -= 2
	end
	local landY = ground(o.X, pierStart + 4)
	Build.part({
		name = "Ramp",
		size = Vector3.new(7, 0.35, 6),
		cframe = CFrame.lookAt(
			Vector3.new(o.X, (landY + deckY) / 2, pierStart + 2),
			Vector3.new(o.X, deckY, pierStart - 1)
		),
		color = Color3.fromRGB(128, 98, 70),
		material = Enum.Material.WoodPlanks,
		parent = pier,
	})
	for _, px in { -3.3, 3.3 } do
		Scenery.rod(
			pier,
			Vector3.new(o.X + px, deckY + 3.4, pierStart),
			Vector3.new(o.X + px, deckY + 3.4, pierEnd + 2),
			0.22,
			Color3.fromRGB(214, 190, 140),
			Enum.Material.Fabric,
			"Rope"
		)
	end
	Build.part({
		name = "Platform",
		size = Vector3.new(20, 0.4, 10),
		cframe = CFrame.new(o.X, deckY, pierEnd - 4),
		color = Color3.fromRGB(132, 100, 70),
		material = Enum.Material.WoodPlanks,
		parent = pier,
	})
	for _, px in { -9.6, 9.6 } do
		for _, dz in { -8.6, 0.6 } do
			Build.part({
				name = "Post",
				size = Vector3.new(0.7, 8, 0.7),
				cframe = CFrame.new(o.X + px, deckY - 3, pierEnd + dz),
				color = DARK_WOOD,
				material = Enum.Material.Wood,
				parent = pier,
			})
		end
	end
	Build.lantern(pier, Vector3.new(o.X - 9, deckY, pierEnd - 8.2))
	Build.lantern(pier, Vector3.new(o.X + 9, deckY, pierEnd - 8.2))
	Scenery.boat(
		deco,
		CFrame.new(o.X + 7, center.Y + 0.15, pierStart - 18) * CFrame.Angles(0, math.rad(-6), 0)
	)
	Scenery.boat(
		deco,
		CFrame.new(o.X - 7.5, center.Y + 0.15, pierStart - 30) * CFrame.Angles(0, math.rad(10), 0)
	)

	-- 海に立つ大鳥居(浜から見える。足は海の中)
	local seaTorii = Vector3.new(center.X - 34, center.Y - 3, center.Z - 6)
	Build.torii(deco, CFrame.lookAt(seaTorii, Vector3.new(spawnPos.X - 10, seaTorii.Y, spawnPos.Z)), 1.6)

	-- 東の岬の灯台
	local lh = Build.folder("Lighthouse", deco)
	local base = lighthousePos
	Terrain.flatten(CFrame.new(base), 12, 12, Enum.Material.Rock)
	Build.part({
		name = "Tower",
		size = Vector3.new(16, 6, 6),
		cframe = CFrame.new(base + Vector3.new(0, 8, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		color = Color3.fromRGB(240, 238, 230),
		material = Enum.Material.SmoothPlastic,
		shape = Enum.PartType.Cylinder,
		parent = lh,
	})
	for _, h in { 5, 11 } do
		Build.part({
			name = "Band",
			size = Vector3.new(1.4, 6.2, 6.2),
			cframe = CFrame.new(base + Vector3.new(0, h, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			color = Color3.fromRGB(196, 46, 36),
			material = Enum.Material.SmoothPlastic,
			shape = Enum.PartType.Cylinder,
			parent = lh,
		})
	end
	local lamp = Build.part({
		name = "Lamp",
		size = Vector3.new(3, 4.4, 4.4),
		cframe = CFrame.new(base + Vector3.new(0, 17.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		color = Color3.fromRGB(255, 236, 170),
		material = Enum.Material.Neon,
		shape = Enum.PartType.Cylinder,
		parent = lh,
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 226, 160)
	light.Range = 40
	light.Brightness = 1.4
	light.Parent = lamp
	Build.part({
		name = "Cap",
		size = Vector3.new(5.6, 2.4, 5.6),
		cframe = CFrame.new(base + Vector3.new(0, 20.2, 0)),
		color = Color3.fromRGB(196, 46, 36),
		material = Enum.Material.SmoothPlastic,
		shape = Enum.PartType.Ball,
		parent = lh,
	})

	-- 岩礁(入り江の両側。桟橋の正面はあける)
	local rocks, tries = 0, 0
	while rocks < 16 and tries < 300 do
		tries += 1
		local side = if rng:NextNumber() < 0.5 then 1 else -1
		local a = math.rad(rng:NextNumber(-80, 20))
		local px = center.X + side * math.cos(a) * rx * rng:NextNumber(0.75, 1.15)
		local pz = center.Z + math.sin(a) * rz * rng:NextNumber(0.6, 1.1)
		if math.abs(px - o.X) < 40 then
			continue
		end
		rocks += 1
		local s = rng:NextNumber(3, 7)
		Build.part({
			name = "SeaRock",
			size = Vector3.new(s * 1.2, s * rng:NextNumber(1, 1.8), s),
			cframe = CFrame.new(px, center.Y + s * 0.15, pz) * CFrame.Angles(
				rng:NextNumber(-0.2, 0.2),
				rng:NextNumber(0, math.pi),
				rng:NextNumber(-0.2, 0.2)
			),
			color = ROCK:Lerp(Color3.fromRGB(64, 62, 60), rng:NextNumber()),
			material = Enum.Material.Slate,
			parent = deco,
		})
	end

	-- 狸の行商(魚を売れる)と、干物の棚
	local stallCF = CFrame.lookAt(stallPos, Vector3.new(spawnPos.X, stallPos.Y, spawnPos.Z - 6))
	Terrain.flatten(stallCF, 16, 12, Enum.Material.Sand)
	local counter =
		Build.stall(root, stallCF, "sign_fish_shop", "open:shop:sell", Color3.fromRGB(36, 72, 120))
	CollectionService:AddTag(counter, "Merchant")
	Build.tanuki(root, stallCF * CFrame.new(0, 0, 3.4))
	local rackCF = stallCF * CFrame.new(-9, 0, 2)
	for _, dx in { -3, 3 } do
		Build.part({
			name = "RackPole",
			size = Vector3.new(0.4, 4, 0.4),
			cframe = rackCF * CFrame.new(dx, 2, 0),
			color = DARK_WOOD,
			material = Enum.Material.Wood,
			parent = deco,
		})
	end
	Scenery.rod(
		deco,
		(rackCF * CFrame.new(-3, 3.8, 0)).Position,
		(rackCF * CFrame.new(3, 3.8, 0)).Position,
		0.15,
		Color3.fromRGB(214, 190, 140),
		Enum.Material.Fabric,
		"RackRope"
	)
	for k = 0, 4 do
		Build.part({
			name = "DriedFish",
			size = Vector3.new(0.5, 1.3, 0.25),
			cframe = rackCF * CFrame.new(-2.4 + k * 1.2, 3, 0),
			color = Color3.fromRGB(196, 150, 96),
			material = Enum.Material.SmoothPlastic,
			parent = deco,
		})
	end

	-- 村への鳥居
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

	-- 浜の黒松と、貝・ヒトデ
	local placed, tries2 = 0, 0
	while placed < 24 and tries2 < 600 do
		tries2 += 1
		local p = onShore(rng:NextNumber(-10, 190), rng:NextNumber(1.55, 2.3))
		if busy(p.X, p.Z) or M.isOcean(center, p.X, p.Z) then
			continue
		end
		if Vector3.new(p.X - center.X, 0, p.Z - center.Z).Magnitude > basin.ring :: number - 6 then
			continue
		end
		Build.tree(deco, at(p.X, p.Z) - Vector3.new(0, 0.4, 0), rng, "pine")
		placed += 1
	end
	for _ = 1, 10 do
		local p = onShore(rng:NextNumber(20, 160), rng:NextNumber(1.1, 1.4))
		if busy(p.X, p.Z) then
			continue
		end
		local star = rng:NextNumber() < 0.4
		Build.part({
			name = if star then "Starfish" else "Shell",
			size = if star then Vector3.new(1.2, 0.2, 1.2) else Vector3.new(0.7, 0.35, 0.9),
			cframe = CFrame.new(at(p.X, p.Z) + Vector3.new(0, 0.15, 0))
				* CFrame.Angles(0, rng:NextNumber(0, 6), 0),
			color = if star then Color3.fromRGB(230, 110, 70) else Color3.fromRGB(244, 230, 214),
			material = Enum.Material.SmoothPlastic,
			shape = if star then Enum.PartType.Block else Enum.PartType.Ball,
			collide = false,
			parent = deco,
		})
	end

	-- 道(行商・鳥居・桟橋へ)。砂浜の上の板の道
	for _, pts in
		{ { spawnPos, stallPos }, { spawnPos, toriiPos }, { spawnPos, Vector3.new(o.X, 0, pierStart) } }
	do
		Terrain.paintPath(basin, pts, 5, Enum.Material.WoodPlanks)
	end

	-- 南の山の松林と、見えない壁(北の外海にも)
	Scenery.mountainForest(deco, basin, 30, rng, function(px: number, pz: number): boolean
		return M.isOcean(center, px, pz) or pz < center.Z - 10
	end)
	Scenery.boundary(root, Vector3.new(center.X, center.Y, center.Z), basin.ring :: number + 8, 160)

	return root
end

return M
