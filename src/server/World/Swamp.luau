--!strict
-- 最初の釣り場「沼」。見た目の完成度を最優先で作り込む。
-- 山に囲まれた谷の沼: 霧のかかる水面、葦、蓮、枯れ木、石灯籠、蛍、島の祠、桟橋と小舟、狸の行商、村への鳥居。
-- 西の岸に神木(しめ縄の大樹)、東に竹林、北は杉の森と、山から段になって落ちる沢と滝。
-- 出現地点から店・鳥居・VIP の釣り座・神木へは土の道が通っている(地形の材質を塗るだけなのでパーツは増えない)。
local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Build = require(script.Parent.Build)
local Scenery = require(script.Parent.Scenery)
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
		half = 100,
		groundY = 2,
		hills = 12,
		seed = 11,
		ring = 106, -- この先は山(地形の端が見えないように谷を囲む)
		ringHeight = 62,
		extent = 184,
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
	-- VIP の釣り座の位置(下で作る)
	local vipDir = Vector3.new(math.cos(math.rad(25)), 0, math.sin(math.rad(25)))
	local vipShore = center + Vector3.new(vipDir.X * spot.water.rx * 1.12, 0, vipDir.Z * spot.water.rz * 1.12)
	local vipEnd = center + Vector3.new(vipDir.X * spot.water.rx * 0.78, 0, vipDir.Z * spot.water.rz * 0.78)
	local function nearVip(x: number, z: number): boolean
		local p = Vector3.new(x, 0, z)
		local a, b = Vector3.new(vipShore.X, 0, vipShore.Z), Vector3.new(vipEnd.X, 0, vipEnd.Z)
		local ab = b - a
		local t = math.clamp((p - a):Dot(ab) / ab:Dot(ab), -0.4, 1)
		return (p - (a + ab * t)).Magnitude < 9
	end

	-- 景色の目印の場所
	local function onShore(deg: number, k: number): Vector3
		local a = math.rad(deg)
		return Vector3.new(
			center.X + math.cos(a) * spot.water.rx * k,
			0,
			center.Z + math.sin(a) * spot.water.rz * k
		)
	end
	local sacredPos = onShore(236, 1.42) -- 北西の杉林の神木(出現地点から池と島の祠の向こうに見える)
	local shopPos = spawnPos + Vector3.new(-20, 0, 2)
	local toriiPos2 = spawnPos + Vector3.new(22, 0, 10)
	-- 北東の山から池へ落ちる沢(上流 → 下流)
	local creekPts = {
		Vector3.new(44, 0, -122),
		Vector3.new(37, 0, -104),
		Vector3.new(30, 0, -88),
		Vector3.new(24, 0, -73),
		Vector3.new(19, 0, -59),
		Vector3.new(14, 0, -40),
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
	-- 道(出現地点 → 店 / 鳥居 / VIP の釣り座 / 神木)
	local paths = {
		{ spawnPos + Vector3.new(0, 0, 2), shopPos + Vector3.new(6, 0, -2) },
		{
			spawnPos + Vector3.new(2, 0, 2),
			spawnPos + Vector3.new(11, 0, 7),
			toriiPos2 + Vector3.new(0, 0, -3),
		},
		{
			spawnPos + Vector3.new(3, 0, -3),
			Vector3.new(18, 0, 37),
			Vector3.new(32, 0, 28),
			Vector3.new(41, 0, 17),
		},
		{
			shopPos + Vector3.new(-4, 0, -4),
			Vector3.new(-36, 0, 38),
			Vector3.new(-52, 0, 24),
			Vector3.new(-60, 0, 6),
			Vector3.new(-59, 0, -16),
			Vector3.new(-50, 0, -36),
			sacredPos + Vector3.new(-2, 0, 8),
		},
	}
	local function nearPath(x: number, z: number, w: number): boolean
		for _, pts in paths do
			if distToLine(pts, x, z) < w then
				return true
			end
		end
		return false
	end
	local function bambooZone(x: number, z: number): boolean
		local a = math.deg(math.atan2(z - center.Z, x - center.X))
		return a > -62
			and a < -8
			and (Vector3.new(x - center.X, 0, (z - center.Z) * spot.water.rx / spot.water.rz)).Magnitude
				> spot.water.rx * 1.3
	end
	local function cedarZone(x: number, z: number): boolean
		local a = math.deg(math.atan2(z - center.Z, x - center.X))
		return a > -150 and a <= -62
	end

	-- 桟橋や施設の周りは木を置かない
	local function clear(x: number, z: number): boolean
		if nearVip(x, z) then
			return false
		end
		if (Vector3.new(x, 0, z) - Vector3.new(sacredPos.X, 0, sacredPos.Z)).Magnitude < 15 then
			return false
		end
		if distToLine(creekPts, x, z) < 9 or nearPath(x, z, 4.5) then
			return false
		end
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
	local pierStart, pierEnd = spawnPos.Z - 4, shoreZ - 22
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
				-- 水の中の杭と、手すりの柱を1本で(上に少し出す)
				Build.part({
					name = "Post",
					size = Vector3.new(0.7, 8.6, 0.7),
					cframe = CFrame.new(o.X + x, deckY - 0.9, z),
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
	-- 手すりの綱(杭の上をつなぐ)
	for _, x in { -3.3, 3.3 } do
		Scenery.rod(
			pier,
			Vector3.new(o.X + x, deckY + 3.2, pierStart),
			Vector3.new(o.X + x, deckY + 3.2, pierEnd + 2),
			0.22,
			Color3.fromRGB(214, 190, 140),
			Enum.Material.Fabric,
			"Rope"
		)
	end
	-- 先の広い釣り台(何人かで並んで釣れる)
	Build.part({
		name = "Platform",
		size = Vector3.new(16, 0.4, 8),
		cframe = CFrame.new(o.X, deckY, pierEnd - 3),
		color = Color3.fromRGB(116, 84, 58),
		material = Enum.Material.WoodPlanks,
		parent = pier,
	})
	for _, x in { -7.6, 7.6 } do
		for _, dz in { -6.6, 0.6 } do
			Build.part({
				name = "Post",
				size = Vector3.new(0.7, 7, 0.7),
				cframe = CFrame.new(o.X + x, deckY - 2.6, pierEnd + dz),
				color = Color3.fromRGB(70, 52, 38),
				material = Enum.Material.Wood,
				parent = pier,
			})
		end
	end
	Build.lantern(pier, Vector3.new(o.X - 7, deckY, pierEnd - 6.2))
	Build.lantern(pier, Vector3.new(o.X + 7, deckY, pierEnd - 6.2))
	-- つないである小舟
	Scenery.boat(
		deco,
		CFrame.new(o.X + 6.4, center.Y + 0.15, pierStart - 14) * CFrame.Angles(0, math.rad(8), 0)
	)

	-- 木: 北は杉の森、東は竹林(下で作る)、そのほかは広葉樹ともみじ
	local placed = 0
	local tries = 0
	while placed < 58 and tries < 900 do
		tries += 1
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(1.3, 2.15)
		local x = center.X + math.cos(a) * spot.water.rx * r
		local zz = center.Z + math.sin(a) * spot.water.rz * r
		if
			clear(x, zz)
			and not bambooZone(x, zz)
			and Vector3.new(x - center.X, 0, zz - center.Z).Magnitude < 98
		then
			local y = ground(x, zz) - 0.5
			if cedarZone(x, zz) then
				Scenery.cedar(deco, Vector3.new(x, y, zz), rng)
			else
				local kind = if rng:NextNumber() < 0.22
					then "maple"
					elseif rng:NextNumber() < 0.2 then "pine"
					else nil
				Build.tree(deco, Vector3.new(x, y, zz), rng, kind)
			end
			placed += 1
		end
	end
	-- 竹林(北東の岸の向こう)
	for k, deg in { -56, -46, -36, -26, -17 } do
		local p = onShore(deg, 1.5 + (k % 2) * 0.28)
		if clear(p.X, p.Z) then
			Scenery.bamboo(deco, Vector3.new(p.X, ground(p.X, p.Z), p.Z), rng)
		end
	end
	-- 神木(西の岸)
	Scenery.sacredTree(deco, Vector3.new(sacredPos.X, ground(sacredPos.X, sacredPos.Z) - 0.4, sacredPos.Z))
	-- 水から突き出た枯れ木
	for _, deg in { 148, 206, 312 } do
		local p = onShore(deg, 0.86)
		Scenery.snag(deco, Vector3.new(p.X, center.Y, p.Z), rng)
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
		if not nearVip(x, zz) then
			Build.lotus(deco, Vector3.new(x, center.Y + 0.08, zz), rng)
		end
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

	-- VIP の釣り座: 池に張り出した金色の台。入口の光の幕は VIP だけ通れる(クライアント側で当たり判定を切る)
	local vipFolder = Build.folder("VipSeat", root)
	local deckCF =
		CFrame.lookAt((vipShore + vipEnd) / 2 + Vector3.new(0, 1.4, 0), vipEnd + Vector3.new(0, 1.4, 0))
	local len = (vipShore - vipEnd).Magnitude
	Build.part({
		name = "VipDeck",
		size = Vector3.new(9, 0.4, len),
		cframe = deckCF,
		color = Color3.fromRGB(150, 40, 34),
		material = Enum.Material.WoodPlanks,
		parent = vipFolder,
	})
	for _, x in { -4.6, 4.6 } do
		Build.part({
			name = "VipRail",
			size = Vector3.new(0.3, 0.3, len),
			cframe = deckCF * CFrame.new(x, 1.6, 0),
			color = Color3.fromRGB(232, 194, 106),
			material = Enum.Material.Foil,
			parent = vipFolder,
		})
	end
	local tip = deckCF * CFrame.new(0, 0, -len / 2 + 3)
	Build.part({
		name = "VipCarpet",
		size = Vector3.new(6, 0.1, 5),
		cframe = tip * CFrame.new(0, 0.25, 0),
		color = Color3.fromRGB(232, 194, 106),
		material = Enum.Material.Fabric,
		collide = false,
		parent = vipFolder,
	})
	Build.lantern(vipFolder, (tip * CFrame.new(-3.8, 0.2, -1)).Position)
	Build.lantern(vipFolder, (tip * CFrame.new(3.8, 0.2, -1)).Position)
	local gate = Build.part({
		name = "VipGate",
		size = Vector3.new(9, 8, 0.4),
		cframe = deckCF * CFrame.new(0, 4, len / 2 - 0.5),
		color = Color3.fromRGB(255, 214, 120),
		material = Enum.Material.ForceField,
		transparency = 0.2,
		parent = vipFolder,
	})
	CollectionService:AddTag(gate, "VipGate")
	Build.sign(
		vipFolder,
		deckCF * CFrame.new(0, 9, len / 2 - 0.5) * CFrame.Angles(0, math.rad(180), 0),
		Vector2.new(5, 1.4),
		"sign_vip_seat",
		Color3.fromRGB(120, 30, 26)
	)
	Terrain.flatten(CFrame.new(vipShore + vipDir * 6), 12, 12, Enum.Material.Grass)

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

	-- 北東の山から段になって池へ落ちる沢(水面の高さは、道すじの地面に合わせて下流ほど低く)
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
	local falls = Terrain.creek(basin, creekPts, levels, 6)
	for _, f in falls do
		Scenery.spray(deco, f, 6)
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

	-- お地蔵さま(鳥居への道ばた)
	for k = 1, 3 do
		local t = 0.3 + k * 0.14
		local a, b = spawnPos + Vector3.new(2, 0, 2), toriiPos2
		local p = a:Lerp(b, t) + Vector3.new(-1.6, 0, 3.6)
		Scenery.jizo(
			deco,
			CFrame.lookAt(
				Vector3.new(p.X, ground(p.X, p.Z), p.Z),
				Vector3.new(a.X, ground(p.X, p.Z), a.Z + 6)
			)
		)
	end

	-- 道(店・鳥居・VIP の釣り座・神木へ)と、出現地点の石畳
	for _, pts in paths do
		Terrain.paintPath(basin, pts, 6, Enum.Material.Ground)
	end
	Terrain.paintPath(
		basin,
		{ spawnPos + Vector3.new(-5, 0, 0), spawnPos + Vector3.new(5, 0, 0) },
		10,
		Enum.Material.Cobblestone
	)

	-- 谷を囲む山の杉林と、山の手前の見えない壁
	Scenery.mountainForest(deco, basin, 48, rng, function(x: number, z: number): boolean
		return distToLine(creekPts, x, z) < 10
	end)
	Scenery.boundary(root, Vector3.new(center.X, center.Y, center.Z), basin.ring :: number + 8, 160)

	return root
end

return M
