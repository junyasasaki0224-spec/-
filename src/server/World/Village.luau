--!strict
-- 釣り村(拠点)。山に囲まれた「ぬしの湖」のほとり。
-- 鳥居から湖へ続く表通り(石畳・提灯の列)の両側に魚屋・竿屋・エサ屋・道場、通りの先に見物台と依頼板。
-- 湖の北に釣り小屋が並び、湖のまわりを石の道がめぐる。北西の山には五重塔。
local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Build = require(script.Parent.Build)
local Scenery = require(script.Parent.Scenery)
local Terrain = require(script.Parent.Terrain)

local HUT_COUNT = Config.Online.MaxPlayers -- 1人1軒(サーバーの最大人数と揃える)

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
	-- 水槽(大物の鮫・鯱も横向きで入る奥行き。前に5スタッドの通路が残る)
	local tank = Build.part({
		name = "Tank",
		size = Vector3.new(10, 5, 4.2),
		cframe = cf * CFrame.new(0, 3.5, 2.35),
		color = Color3.fromRGB(140, 210, 230),
		material = Enum.Material.Glass,
		transparency = 0.72,
		parent = model,
	})
	Build.part({
		name = "TankStand",
		size = Vector3.new(10.4, 1, 4.6),
		cframe = cf * CFrame.new(0, 0.9, 2.35),
		color = darkWood,
		material = Enum.Material.Wood,
		parent = model,
	})
	Build.part({
		name = "TankSand",
		size = Vector3.new(9.8, 0.3, 4),
		cframe = cf * CFrame.new(0, 1.15, 2.35),
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
		half = 100,
		groundY = 2,
		hills = 10,
		seed = 29,
		ring = 104, -- この先は山(村を囲む)
		ringHeight = 58,
		extent = 182,
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
	-- 通りの方(x = 中心)を向く
	local function facingStreet(pos: Vector3): CFrame
		return CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, pos.Z))
	end

	-- 出現地点は表通りのまん中(鳥居 → 通り → 湖の見物台 と一本道)
	local spawnPos = o + Vector3.new(spot.spawn.x, 0, spot.spawn.z)
	local plazaY = ground(spawnPos.X, spawnPos.Z)
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

	-- お店: 表通りの両側に向かい合わせ(魚屋・竿屋 / エサ屋・道場)
	type Shop = { pos: Vector3, sign: string, action: string, roof: Color3 }
	local shops: { Shop } = {
		{
			pos = at(-15, 46),
			sign = "sign_fish_shop",
			action = "open:shop:sell",
			roof = Color3.fromRGB(40, 70, 120),
		},
		{
			pos = at(-15, 64),
			sign = "sign_rod_shop",
			action = "open:shop:rods",
			roof = Color3.fromRGB(120, 40, 40),
		},
		{
			pos = at(15, 46),
			sign = "sign_bait_shop",
			action = "open:shop:bait",
			roof = Color3.fromRGB(60, 110, 60),
		},
		{
			pos = at(15, 64),
			sign = "sign_battle_dojo",
			action = "open:battle",
			roof = Color3.fromRGB(90, 50, 130),
		},
	}
	for _, sh in shops do
		Terrain.flatten(facingStreet(sh.pos), 12, 16)
	end
	for i, sh in shops do
		local cf = facingStreet(sh.pos)
		local counter = Build.stall(root, cf, sh.sign, sh.action, sh.roof)
		if i == 1 then
			CollectionService:AddTag(counter, "Merchant")
			Build.tanuki(root, cf * CFrame.new(0, 0, 3.4))
		end
	end

	-- 依頼板(通りの湖側の端、見物台の脇)
	local qPos = at(16, 36)
	local qcf = facingStreet(qPos)
	Terrain.flatten(qcf, 12, 6)
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

	-- ランキング看板(湖の向こう側、出現地点と見物台から見える位置)
	local rPos = at(0, -50)
	rankingBoard(root, facing(rPos))
	Build.sign(root, facing(rPos) * CFrame.new(0, 15.2, -0.2), Vector2.new(8, 1.8), "sign_ranking")

	-- 沼への鳥居(表通りの入口)
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
	-- 川・海への鳥居(沼の鳥居の両脇。まだ開いていない時は、押すと条件が出る)
	for _, g in { { x = -26, to = "river" }, { x = 26, to = "sea" } } do
		local p = at(g.x, 78)
		local cf = CFrame.lookAt(p, Vector3.new(spawnPos.X, p.Y, spawnPos.Z))
		Build.torii(root, cf, 0.85)
		local side = Build.part({
			name = "Gate",
			size = Vector3.new(7, 9, 1),
			cframe = cf * CFrame.new(0, 4.5, 0),
			transparency = 1,
			collide = false,
			parent = root,
		})
		Build.prompt(side, "prompt_travel", "travel:" .. g.to, 14)
		Build.sign(
			root,
			cf * CFrame.new(0, 10.4, -0.45),
			Vector2.new(3.4, 1.4),
			"sign_torii_" .. g.to,
			Color3.fromRGB(28, 22, 22)
		)
		Terrain.paintPath(basin, { at(0, 80), p }, 5, Enum.Material.Cobblestone)
	end

	-- 湖の見物台(ぬし釣りの時はここに集まる)
	Scenery.deck(deco, CFrame.new(center.X, center.Y + 1.4, center.Z + spot.water.rz + 1), 18, 12)
	Build.lantern(deco, Vector3.new(center.X - 8.2, center.Y + 1.65, center.Z + spot.water.rz + 6))
	Build.lantern(deco, Vector3.new(center.X + 8.2, center.Y + 1.65, center.Z + spot.water.rz + 6))

	-- 表通りの提灯の列(両側の柱に渡す)
	for k = 0, 3 do
		-- 提灯は頭より上(カメラの高さ)に来るように、柱は高め
		local left = Scenery.pole(deco, at(-7, 42 + k * 12), 15)
		local right = Scenery.pole(deco, at(7, 42 + k * 12), 15)
		Scenery.lanternLine(deco, left, right, 3)
	end

	-- 釣り小屋(湖の北側に半円状)
	local hutsFolder = Build.folder("Huts", root)
	local hutAngles = {}
	for k = 1, HUT_COUNT do
		local a = math.rad(195 + (k - 1) * (150 / (HUT_COUNT - 1)))
		table.insert(hutAngles, a)
		local r = 66
		local pos = at(math.cos(a) * r, math.sin(a) * r)
		-- 小屋の正面(-Z)を湖へ向ける
		hut(hutsFolder, facing(pos), k)
	end

	-- 石灯籠(湖のまわり。表通りの前はあける)
	for k = 0, 11 do
		local a = (k / 12) * math.pi * 2
		if math.abs(math.deg(a) - 90) < 20 then
			continue
		end
		local p = at(math.cos(a) * spot.water.rx * 1.2, math.sin(a) * spot.water.rz * 1.2)
		Build.lantern(deco, p)
	end

	-- 桜と松(表通りと鳥居の前はあける)
	local placed, tries = 0, 0
	while placed < 30 and tries < 400 do
		tries += 1
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(80, 94)
		local p = at(math.cos(a) * r, math.sin(a) * r)
		if math.abs(p.X - center.X) < 18 and p.Z > center.Z then
			continue
		end
		placed += 1
		Build.tree(
			deco,
			p - Vector3.new(0, 0.5, 0),
			rng,
			if rng:NextNumber() < 0.55 then "sakura" else "pine"
		)
	end
	-- 表通りの入口の桜(鳥居の両脇)
	for _, x in { -14, 14 } do
		local p = at(x, 74)
		Build.tree(deco, p - Vector3.new(0, 0.5, 0), rng, "sakura")
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

	-- 五重塔(北西の山の中腹。村のどこからでも見える目印)
	local pa = math.rad(232)
	local pagodaPos = at(math.cos(pa) * 126, math.sin(pa) * 126)
	local pagodaCF = CFrame.lookAt(pagodaPos, Vector3.new(center.X, pagodaPos.Y, center.Z))
	Terrain.flatten(pagodaCF, 26, 26, Enum.Material.Slate)
	Scenery.pagoda(deco, pagodaCF, 1.15)
	Build.lantern(deco, (pagodaCF * CFrame.new(-11, 0, -11)).Position)
	Build.lantern(deco, (pagodaCF * CFrame.new(11, 0, -11)).Position)

	-- 道: 鳥居 → 表通り → 見物台 の石畳、湖をめぐる石の道と、小屋への小道
	local street = { at(0, 84), at(0, 40) }
	Terrain.paintPath(basin, street, 12, Enum.Material.Cobblestone)
	Terrain.paintPath(basin, { at(-20, 38), at(20, 38) }, 8, Enum.Material.Cobblestone)
	local ring = {}
	for k = 0, 24 do
		local a = (k / 24) * math.pi * 2
		table.insert(ring, at(math.cos(a) * 47, math.sin(a) * 47))
	end
	Terrain.paintPath(basin, ring, 6, Enum.Material.Cobblestone)
	for _, a in hutAngles do
		Terrain.paintPath(
			basin,
			{ at(math.cos(a) * 49, math.sin(a) * 49), at(math.cos(a) * 59, math.sin(a) * 59) },
			4,
			Enum.Material.Ground
		)
	end

	-- 村を囲む山の杉林と、山の手前の見えない壁(五重塔のまわりはあける)
	Scenery.mountainForest(deco, basin, 48, rng, function(x: number, z: number): boolean
		return (Vector3.new(x, 0, z) - Vector3.new(pagodaPos.X, 0, pagodaPos.Z)).Magnitude < 20
	end)
	Scenery.boundary(root, Vector3.new(center.X, center.Y, center.Z), basin.ring :: number + 8, 160)

	return root
end

return M
