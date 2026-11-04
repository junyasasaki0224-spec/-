--!strict
-- 二つ目の釣り場「川」。山あいの清流: 南北に長い淵、両岸の河原(小石)、木の橋、飛び石、東岸の釣り台、
-- 西岸の水車小屋と竹林、北の山から段になって落ちる沢と滝、もみじと杉、夜の蛍。
-- 東岸の出現地点のそばに狸の行商(魚を売れる)と村への鳥居。パーツは約800に抑える(スマホ向け)。
local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Build = require(script.Parent.Build)
local Scenery = require(script.Parent.Scenery)
local Terrain = require(script.Parent.Terrain)

local M = {}

local WOOD = Color3.fromRGB(118, 84, 56)
local DARK_WOOD = Color3.fromRGB(72, 52, 38)
local STONE = Color3.fromRGB(118, 120, 116)

function M.build()
	local spot = Config.SpotById.river
	local o = Vector3.new(spot.origin.x, spot.origin.y, spot.origin.z)
	local center = o + Vector3.new(spot.water.x, spot.water.y, spot.water.z)
	local rx, rz = spot.water.rx, spot.water.rz
	local basin: Terrain.Basin = {
		center = center,
		rx = rx,
		rz = rz,
		half = 110,
		groundY = 2.5,
		hills = 9,
		seed = 37,
		ring = 128,
		ringHeight = 72,
		extent = 206,
	}
	Terrain.build(basin)

	local world = workspace:FindFirstChild("World") or Build.folder("World", workspace)
	local root = Build.folder("River", world)
	local deco = Build.folder("Deco", root)
	local rng = Random.new(20261104)

	local function ground(x: number, z: number): number
		return Terrain.heightAt(basin, x, z)
	end
	local function at(x: number, z: number): Vector3
		return Vector3.new(x, ground(x, z), z)
	end
	-- 川岸の x(中心からの距離 dz のところ)
	local function bankX(dz: number): number
		return rx * math.sqrt(math.max(0, 1 - (dz / rz) ^ 2))
	end
	local spawnPos = o + Vector3.new(spot.spawn.x, 0, spot.spawn.z)
	local bridgeZ = center.Z - 34
	local stonesZ = center.Z + 50
	local deckZ = center.Z + 24
	local millPos = Vector3.new(center.X - 40, 0, center.Z + 8)

	-- 北の山から川へ落ちる沢(上流 → 下流)
	local creekPts = {
		Vector3.new(center.X + 8, 0, center.Z - 150),
		Vector3.new(center.X + 5, 0, center.Z - 130),
		Vector3.new(center.X + 3, 0, center.Z - 110),
		Vector3.new(center.X + 1, 0, center.Z - 90),
		Vector3.new(center.X, 0, center.Z - 64),
	}
	local function distToLine(pts: { Vector3 }, x: number, z: number): number
		local best = math.huge
		local p = Vector3.new(x, 0, z)
		for i = 1, #pts - 1 do
			local a, b = Vector3.new(pts[i].X, 0, pts[i].Z), Vector3.new(pts[i + 1].X, 0, pts[i + 1].Z)
			local ab = b - a
			local t = math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1)
			best = math.min(best, (p - (a + ab * t)).Magnitude)
		end
		return best
	end
	-- 物を置かない場所(道・橋・建物のまわり)
	local function busy(x: number, z: number): boolean
		local p = Vector3.new(x, 0, z)
		if (p - Vector3.new(spawnPos.X, 0, spawnPos.Z)).Magnitude < 22 then
			return true
		end
		if math.abs(z - bridgeZ) < 8 or math.abs(z - stonesZ) < 6 or math.abs(z - deckZ) < 8 then
			return true
		end
		if (p - Vector3.new(millPos.X, 0, millPos.Z)).Magnitude < 14 then
			return true
		end
		return distToLine(creekPts, x, z) < 10
	end

	-- 出現地点(東の河原)と、川の名前の看板
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "RiverSpawn"
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.CFrame = CFrame.new(spawnPos.X, ground(spawnPos.X, spawnPos.Z) + 0.5, spawnPos.Z)
	spawn.Anchored = true
	spawn.Neutral = false -- 最初は沼に出現させる(ここへは鳥居・お店の「釣り場」で移動)
	spawn.Enabled = false
	spawn.Material = Enum.Material.Cobblestone
	spawn.Color = Color3.fromRGB(140, 136, 128)
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = root
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end
	local signPost = at(spawnPos.X - 7, spawnPos.Z + 5)
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
		CFrame.lookAt(signPost + Vector3.new(0, 5.4, 0), signPost + Vector3.new(-1, 5.4, 0)),
		Vector2.new(3.2, 1.3),
		"spot_river",
		Color3.fromRGB(40, 70, 60)
	)

	-- 河原: 両岸に小石を敷く(地形の材質だけ塗る)
	for _, side in { 1, -1 } do
		local pts = {}
		for k = -10, 10 do
			local dz = rz * 0.96 * k / 10
			table.insert(pts, Vector3.new(center.X + side * (bankX(dz) + 4), 0, center.Z + dz))
		end
		Terrain.paintPath(basin, pts, 8, Enum.Material.Pebble)
	end

	-- 木の橋(少し反った板の橋。橋の上からも釣れる)
	local bridge = Build.folder("Bridge", root)
	local half = bankX(bridgeZ - center.Z) + 9
	local n = 22
	for i = 0, n do
		local t = i / n
		local x = center.X - half + t * half * 2
		local y = center.Y + 3.2 + math.sin(t * math.pi) * 1.4
		Build.part({
			name = "Plank",
			size = Vector3.new(half * 2 / n + 0.15, 0.35, 6),
			cframe = CFrame.new(x, y, bridgeZ) * CFrame.Angles(0, 0, math.cos(t * math.pi) * -0.2),
			color = Color3.fromRGB(122 + rng:NextInteger(-8, 8), 88, 58),
			material = Enum.Material.WoodPlanks,
			parent = bridge,
		})
		if i % 4 == 0 then
			-- 川底から手すりまでの柱
			local bottom, top = center.Y - 2, y + 2.2
			for _, dz in { -2.9, 2.9 } do
				Build.part({
					name = "Post",
					size = Vector3.new(0.5, top - bottom, 0.5),
					cframe = CFrame.new(x, (top + bottom) / 2, bridgeZ + dz),
					color = DARK_WOOD,
					material = Enum.Material.Wood,
					parent = bridge,
				})
			end
		end
	end
	-- 手すり(朱塗り)
	for _, dz in { -2.9, 2.9 } do
		local prev = nil
		for i = 0, 4 do
			local t = i / 4
			local p = Vector3.new(
				center.X - half + t * half * 2,
				center.Y + 3.2 + math.sin(t * math.pi) * 1.4 + 2.2,
				bridgeZ + dz
			)
			if prev then
				Scenery.rod(bridge, prev, p, 0.3, Color3.fromRGB(190, 52, 40), Enum.Material.Wood, "Rail")
			end
			prev = p
		end
	end
	Build.lantern(bridge, Vector3.new(center.X - half + 1, center.Y + 3.4, bridgeZ - 4.2))
	Build.lantern(bridge, Vector3.new(center.X + half - 1, center.Y + 3.4, bridgeZ + 4.2))

	-- 飛び石(下流。西岸へ渡れる)
	local stones = Build.folder("SteppingStones", root)
	local sHalf = bankX(stonesZ - center.Z) + 2
	local x = center.X - sHalf
	while x <= center.X + sHalf do
		-- 平たい円柱(円柱の長さは X 軸なので、立てて上を平らに)
		Build.part({
			name = "Stone",
			size = Vector3.new(1.6, 2.8, 2.8),
			cframe = CFrame.new(x, center.Y - 0.1, stonesZ + rng:NextNumber(-0.6, 0.6))
				* CFrame.Angles(0, 0, math.rad(90)),
			color = STONE:Lerp(Color3.fromRGB(150, 146, 136), rng:NextNumber()),
			material = Enum.Material.Slate,
			shape = Enum.PartType.Cylinder,
			parent = stones,
		})
		x += 3.1
	end

	-- 東岸の釣り台(川へ張り出す)
	local deckBank = center.X + bankX(deckZ - center.Z)
	Scenery.deck(
		root,
		CFrame.new(deckBank - 3, center.Y + 1.4, deckZ) * CFrame.Angles(0, math.rad(90), 0),
		8,
		12
	)
	Build.lantern(root, Vector3.new(deckBank - 8, center.Y + 1.65, deckZ - 3.4))

	-- 川の中の岩と、白く泡立つ瀬
	local rocks = 0
	local tries = 0
	while rocks < 14 and tries < 200 do
		tries += 1
		local dz = rng:NextNumber(-rz * 0.85, rz * 0.85)
		local px = center.X + rng:NextNumber(-0.75, 0.75) * bankX(dz)
		local pz = center.Z + dz
		if math.abs(pz - bridgeZ) < 6 or math.abs(pz - stonesZ) < 5 or math.abs(pz - deckZ) < 7 then
			continue
		end
		-- 釣り台・出現地点の正面(投げる先)はあける
		if px > center.X + 4 and math.abs(pz - spawnPos.Z) < 14 then
			continue
		end
		rocks += 1
		local s = rng:NextNumber(2, 4.2)
		Build.part({
			name = "Rock",
			size = Vector3.new(s * 1.3, s, s),
			cframe = CFrame.new(px, center.Y + s * 0.18, pz)
				* CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
			color = STONE:Lerp(Color3.fromRGB(86, 92, 84), rng:NextNumber()),
			material = Enum.Material.Slate,
			shape = Enum.PartType.Ball,
			parent = deco,
		})
		local foam = Build.part({
			name = "Foam",
			size = Vector3.new(0.2, s * 2.2, s * 1.6),
			-- 川は段ごとに水面の高さが違うので、本当の水面を測って泡を乗せる
			cframe = CFrame.new(
				px,
				(Build.waterY(px, pz + s * 0.5, center.Y) or center.Y) - 0.03,
				pz + s * 0.5
			) * CFrame.Angles(0, 0, math.rad(90)),
			color = Color3.fromRGB(240, 248, 255),
			material = Enum.Material.SmoothPlastic,
			transparency = 0.45,
			shape = Enum.PartType.Cylinder,
			collide = false,
			parent = deco,
		})
		foam.CanQuery = false
		foam.CastShadow = false
	end

	-- 西岸の水車小屋
	local mill = Build.folder("WaterMill", root)
	local millGround = ground(millPos.X, millPos.Z)
	local millCF = CFrame.lookAt(
		Vector3.new(millPos.X, millGround, millPos.Z),
		Vector3.new(center.X, millGround, millPos.Z)
	)
	Terrain.flatten(millCF, 14, 12)
	local walls: { { size: Vector3, at: CFrame } } = {
		{ size = Vector3.new(9, 6, 0.5), at = CFrame.new(0, 3, -3.75) },
		{ size = Vector3.new(9, 6, 0.5), at = CFrame.new(0, 3, 3.75) },
		{ size = Vector3.new(0.5, 6, 8), at = CFrame.new(-4.25, 3, 0) },
		{ size = Vector3.new(0.5, 6, 8), at = CFrame.new(4.25, 3, 0) },
	}
	for _, w in walls do
		Build.part({
			name = "Wall",
			size = w.size,
			cframe = millCF * w.at,
			color = Color3.fromRGB(150, 116, 82),
			material = Enum.Material.WoodPlanks,
			parent = mill,
		})
	end
	for _, side in { 1, -1 } do
		Build.part({
			name = "Roof",
			size = Vector3.new(10.5, 0.5, 5.6),
			cframe = millCF * CFrame.new(0, 7.2, side * 2.3) * CFrame.Angles(side * math.rad(28), 0, 0),
			color = Color3.fromRGB(122, 104, 70),
			material = Enum.Material.Fabric, -- かやぶき
			parent = mill,
		})
	end
	-- 水車(輪と羽根)。川の方の壁の外
	local wheelC = millCF * CFrame.new(0, 3.2, -6.4)
	Build.part({
		name = "WheelRim",
		size = Vector3.new(1.2, 7.6, 7.6),
		cframe = wheelC * CFrame.Angles(0, math.rad(90), 0),
		color = DARK_WOOD,
		material = Enum.Material.Wood,
		shape = Enum.PartType.Cylinder,
		parent = mill,
	})
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		Build.part({
			name = "Paddle",
			size = Vector3.new(0.3, 2.2, 1.6),
			cframe = wheelC * CFrame.Angles(a, 0, 0) * CFrame.new(0, 3.9, 0),
			color = WOOD,
			material = Enum.Material.WoodPlanks,
			parent = mill,
		})
	end
	Scenery.rod(
		mill,
		(wheelC * CFrame.new(0, 0, 1.6)).Position,
		(millCF * CFrame.new(0, 3.2, -3.4)).Position,
		0.5,
		DARK_WOOD,
		Enum.Material.Wood,
		"Axle"
	)

	-- 狸の行商(魚を売れる)
	local stallPos = at(spawnPos.X + 2, spawnPos.Z - 18)
	local stallCF = CFrame.lookAt(stallPos, Vector3.new(spawnPos.X - 6, stallPos.Y, spawnPos.Z))
	Terrain.flatten(stallCF, 16, 12)
	local counter = Build.stall(root, stallCF, "sign_fish_shop", "open:shop:sell", Color3.fromRGB(46, 96, 70))
	CollectionService:AddTag(counter, "Merchant")
	Build.tanuki(root, stallCF * CFrame.new(0, 0, 3.4))

	-- 村への鳥居
	local toriiPos = at(spawnPos.X + 12, spawnPos.Z + 16)
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
	-- 鳥居への道ばたのお地蔵さま
	for k = 1, 2 do
		local p = spawnPos:Lerp(toriiPos, 0.35 + k * 0.2) + Vector3.new(3.2, 0, -1.2)
		Scenery.jizo(deco, CFrame.lookAt(at(p.X, p.Z), Vector3.new(spawnPos.X, ground(p.X, p.Z), spawnPos.Z)))
	end

	-- 北の山から段になって落ちる沢と滝
	local levels = {}
	for seg = #creekPts - 1, 1, -1 do
		local a, b = creekPts[seg], creekPts[seg + 1]
		local m = math.huge
		for k = 0, 6 do
			local p = a:Lerp(b, k / 6)
			m = math.min(m, ground(p.X, p.Z))
		end
		local level = if seg == #creekPts - 1
			then center.Y
			else math.max(math.floor(m - 1.5), levels[seg + 1] + 3)
		levels[seg] = level
	end
	local falls = Terrain.creek(basin, creekPts, levels, 7)
	for _, f in falls do
		Scenery.spray(deco, f, 7)
		for _ = 1, 3 do
			local s = rng:NextNumber(1.6, 3)
			Build.part({
				name = "Rock",
				size = Vector3.new(s * 1.2, s, s),
				cframe = CFrame.new(f + Vector3.new(rng:NextNumber(-5, 5), 0.4, rng:NextNumber(-3, 3))),
				color = Color3.fromRGB(96, 100, 96),
				material = Enum.Material.Slate,
				shape = Enum.PartType.Ball,
				parent = deco,
			})
		end
	end

	-- 木: 西岸の北は竹林、東岸と橋のまわりはもみじ、そのほかは杉と広葉樹
	local placed, tries2 = 0, 0
	while placed < 46 and tries2 < 900 do
		tries2 += 1
		local dz = rng:NextNumber(-rz * 1.25, rz * 1.25)
		local side = if rng:NextNumber() < 0.5 then 1 else -1
		local px = center.X + side * (bankX(math.clamp(dz, -rz, rz)) + rng:NextNumber(12, 70))
		local pz = center.Z + dz
		if busy(px, pz) then
			continue
		end
		local r = Vector3.new(px - center.X, 0, pz - center.Z).Magnitude
		if r > basin.ring :: number - 8 then
			continue
		end
		local y = ground(px, pz)
		local pos = Vector3.new(px, y - 0.4, pz)
		if side < 0 and dz < -10 then
			Scenery.bamboo(deco, pos, rng)
		elseif math.abs(pz - bridgeZ) < 30 or (side > 0 and rng:NextNumber() < 0.4) then
			Build.tree(deco, pos, rng, "maple")
		elseif rng:NextNumber() < 0.5 then
			Scenery.cedar(deco, pos, rng)
		else
			Build.tree(deco, pos, rng)
		end
		placed += 1
	end
	-- 岸の葦(ところどころ)
	for _ = 1, 10 do
		local dz = rng:NextNumber(-rz * 0.9, rz * 0.9)
		local side = if rng:NextNumber() < 0.5 then 1 else -1
		local px = center.X + side * (bankX(dz) + 1.5)
		local pz = center.Z + dz
		if not busy(px, pz) then
			Build.reeds(deco, Vector3.new(px, center.Y, pz), rng)
		end
	end

	-- 夜の蛍と、朝の川霧
	Build.fireflies(deco, center + Vector3.new(0, 2, 18), Vector3.new(rx * 2.4, 4, rz * 1.2))
	local mistPart = Build.part({
		name = "Mist",
		size = Vector3.new(rx * 2, 1, rz * 2),
		cframe = CFrame.new(center + Vector3.new(0, 0.6, 0)),
		transparency = 1,
		collide = false,
		parent = deco,
	})
	mistPart.CanQuery = false
	local mist = Instance.new("ParticleEmitter")
	mist.Color = ColorSequence.new(Color3.fromRGB(232, 240, 244))
	mist.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0.9),
		NumberSequenceKeypoint.new(1, 1),
	})
	mist.Size = NumberSequence.new(12)
	mist.Lifetime = NumberRange.new(10, 16)
	mist.Rate = 2
	mist.Speed = NumberRange.new(0.3, 0.8)
	mist.SpreadAngle = Vector2.new(180, 0)
	mist.LightInfluence = 1
	mist.Parent = mistPart
	CollectionService:AddTag(mist, "MistFX")

	-- 道(行商・鳥居・橋・釣り台へ)と、西岸の小道(橋 → 水車小屋 → 飛び石)
	local bridgeE = Vector3.new(center.X + half + 2, 0, bridgeZ)
	local bridgeW = Vector3.new(center.X - half - 2, 0, bridgeZ)
	local paths = {
		{ spawnPos, stallPos },
		{ spawnPos, toriiPos },
		{ spawnPos, spawnPos:Lerp(bridgeE, 0.5) + Vector3.new(6, 0, 0), bridgeE },
		{ spawnPos, Vector3.new(deckBank + 5, 0, deckZ) },
		{ spawnPos, Vector3.new(center.X + sHalf + 3, 0, stonesZ) },
		{ bridgeW, Vector3.new(millPos.X - 2, 0, millPos.Z - 10), Vector3.new(millPos.X, 0, millPos.Z + 6) },
		{ Vector3.new(millPos.X, 0, millPos.Z + 6), Vector3.new(center.X - sHalf - 3, 0, stonesZ) },
	}
	for _, pts in paths do
		Terrain.paintPath(basin, pts, 5, Enum.Material.Ground)
	end
	Terrain.paintPath(
		basin,
		{ spawnPos + Vector3.new(-5, 0, 0), spawnPos + Vector3.new(5, 0, 0) },
		10,
		Enum.Material.Cobblestone
	)

	-- 谷を囲む山の杉林と、山の手前の見えない壁
	Scenery.mountainForest(deco, basin, 44, rng, function(px: number, pz: number): boolean
		return distToLine(creekPts, px, pz) < 10
	end)
	Scenery.boundary(root, Vector3.new(center.X, center.Y, center.Z), basin.ring :: number + 8, 160)

	return root
end

return M
