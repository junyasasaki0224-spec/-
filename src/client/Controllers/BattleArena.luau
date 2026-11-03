--!strict
-- バトルの舞台(水の中の3D)。クライアントだけで作る(ほかの人には見えない・サーバーへは送らない)。
-- 砂の海底・砂丘・岩・珊瑚・海藻の林・沈んだ鳥居・石灯籠・海月・小魚の群れ・水面・光の筋・泡・漂う粒。
-- Roblox のサービスは使わない(Lune でも組み立てられる → tools/battle で Blender の絵にして確かめる)。
-- 座標は舞台の中心(海底)からの相対。魚は FISH_Y の高さで、x = ±7 に向かい合う。
local BattleArena = {}

BattleArena.ORIGIN = Vector3.new(0, 2000, 0) -- 地図のはるか上(霧と水面で外は見えない)
BattleArena.FISH_Y = 6
BattleArena.SURFACE_Y = 46

-- 2匹の定位置(舞台の中心から)と、ふだんのカメラ
BattleArena.HOME = {
	player = Vector3.new(-7, BattleArena.FISH_Y, 0),
	enemy = Vector3.new(7, BattleArena.FISH_Y, 0),
}
BattleArena.BASE_SHOT = { yaw = 0, pitch = 0.07, dist = 25, bossDist = 30, fov = 50 }
-- 始まり: 高いところから、すべり降りる(水面より下に収める: 高さ = FISH_Y + up + dist × sin(pitch) < SURFACE_Y)
BattleArena.INTRO_SHOT = { yaw = 0.9, pitch = 0.4, dist = 50, up = 6, fov = 55 }
-- 攻撃の時: 攻める側の後ろへ回りこむ(yaw は攻める向きで左右が変わる。at = 2匹の間のどこを見るか)
BattleArena.ATTACK_SHOT = { yaw = 0.34, pitch = 0.06, dist = 19, fov = 46, at = 0.62 }

-- カメラ: 注目点のまわりを回る(yaw = 横の回転、pitch = 見下ろす角度、dist = 距離)。回転なしは +Z から奥(-Z)を見る
function BattleArena.orbit(focus: Vector3, yaw: number, pitch: number, dist: number): CFrame
	return CFrame.new(focus) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(-pitch, 0, 0) * CFrame.new(0, 0, dist)
end

-- 魚の向き: 頭(-Z)を進む向き(heading = +1 右 / -1 左)へ。少しだけカメラの方へ向けて、顔が見えるように
function BattleArena.fishYaw(heading: number): number
	return if heading > 0 then -math.pi / 2 - 0.3 else math.pi / 2 + 0.3
end

-- ふだんの泳ぎ(定位置のまわりをゆったり。奥行きの方向にも動く)
function BattleArena.idle(home: Vector3, t: number, phase: number): Vector3
	return home
		+ Vector3.new(
			math.sin(t * 0.55 + phase) * 1.4,
			math.sin(t * 0.83 + phase * 1.7) * 0.9,
			math.sin(t * 0.37 + phase) * 2.2
		)
end

local TEX_SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

type Kelp = { segs: { BasePart }, base: CFrame, len: number, phase: number, amp: number }
type Jelly = { parts: { BasePart }, offsets: { CFrame }, home: Vector3, phase: number }
type Fishlet = { part: BasePart, offset: Vector3, phase: number }
type Bubble = { part: BasePart, base: Vector3, speed: number, offset: number, phase: number }
type Glow = { part: BasePart, phase: number }
type Ray = { top: Attachment, bottom: Attachment, x: number, z: number, phase: number }

export type Arena = {
	folder: Folder,
	fx: Folder,
	origin: Vector3,
	kelp: { Kelp },
	jelly: { Jelly },
	school: { Fishlet },
	bubbles: { Bubble },
	caustics: { Glow },
	rays: { Ray },
}

-- 部品 ----------------------------------------------------------------------------
local function part(parent: Instance, props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	-- 形を先に(球・円柱は大きさの扱いが変わる)
	if props.Shape then
		p.Shape = props.Shape
	end
	for k, v in props do
		if k ~= "Shape" and k ~= "Parent" then
			(p :: any)[k] = v
		end
	end
	p.Parent = parent
	return p
end

local function ball(
	parent: Instance,
	cf: CFrame,
	d: number,
	color: Color3,
	material: Enum.Material?
): BasePart
	return part(parent, {
		Name = "Ball",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(d, d, d),
		CFrame = cf,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	})
end

-- 立った円柱(Roblox の円柱は X 軸なので、Z まわりに 90° 回す)
local function pillar(
	parent: Instance,
	base: CFrame,
	h: number,
	d: number,
	color: Color3,
	material: Enum.Material?
): BasePart
	return part(parent, {
		Name = "Pillar",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(h, d, d),
		CFrame = base * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	})
end

local function block(
	parent: Instance,
	cf: CFrame,
	size: Vector3,
	color: Color3,
	material: Enum.Material?
): BasePart
	return part(parent, {
		Name = "Block",
		Size = size,
		CFrame = cf,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
	})
end

-- 景色 ----------------------------------------------------------------------------
local SAND = Color3.fromRGB(186, 166, 124)
local ROCK = { Color3.fromRGB(72, 82, 86), Color3.fromRGB(58, 70, 74), Color3.fromRGB(86, 92, 88) }
local MOSS = Color3.fromRGB(70, 120, 70)
local CORAL = {
	Color3.fromRGB(255, 120, 140),
	Color3.fromRGB(255, 160, 80),
	Color3.fromRGB(176, 112, 232),
	Color3.fromRGB(90, 200, 190),
}

local function rocks(parent: Instance, rng: any, at: Vector3, scale: number, n: number)
	for i = 1, n do
		local d = scale * rng:NextNumber(0.55, 1.2)
		local off = Vector3.new(rng:NextNumber(-1, 1) * scale, -d * 0.3, rng:NextNumber(-1, 1) * scale * 0.7)
		ball(parent, CFrame.new(at + off), d, ROCK[(i % #ROCK) + 1], Enum.Material.Slate)
		-- 苔
		if rng:NextNumber() < 0.5 then
			ball(
				parent,
				CFrame.new(at + off + Vector3.new(0, d * 0.42, 0)),
				d * 0.35,
				MOSS,
				Enum.Material.Grass
			)
		end
	end
end

local function coral(parent: Instance, rng: any, at: Vector3, color: Color3, size: number)
	ball(parent, CFrame.new(at), size * 0.9, color:Lerp(Color3.new(0, 0, 0), 0.25))
	for _ = 1, 7 do
		local len = size * rng:NextNumber(0.9, 1.8)
		local tilt = rng:NextNumber(-0.7, 0.7)
		local yaw = rng:NextNumber(0, math.pi * 2)
		-- 枝: 根元から上へ(円柱の X 軸を上に向けて傾ける)
		local cf = CFrame.new(at) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(tilt, 0, 0)
		part(parent, {
			Name = "Branch",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(len, size * 0.22, size * 0.22),
			CFrame = cf * CFrame.new(0, len / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
			Color = color,
		})
		ball(parent, cf * CFrame.new(0, len, 0), size * 0.36, color:Lerp(Color3.new(1, 1, 1), 0.25))
	end
end

local function seagrass(parent: Instance, rng: any, at: Vector3)
	for _ = 1, 7 do
		local h = rng:NextNumber(1.6, 3.4)
		local cf = CFrame.new(at + Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)))
			* CFrame.Angles(rng:NextNumber(-0.25, 0.25), rng:NextNumber(0, 3), rng:NextNumber(-0.25, 0.25))
		block(
			parent,
			cf * CFrame.new(0, h / 2, 0),
			Vector3.new(0.35, h, 0.08),
			Color3.fromRGB(70, 140, 80):Lerp(Color3.fromRGB(150, 170, 70), rng:NextNumber()),
			Enum.Material.Grass
		)
	end
end

local function kelp(parent: Instance, rng: any, at: Vector3, list: { Kelp })
	local n = rng:NextInteger(6, 9)
	local len = rng:NextNumber(2.6, 3.4)
	local color = Color3.fromRGB(60, 120, 60):Lerp(Color3.fromRGB(120, 140, 50), rng:NextNumber())
	local segs = {}
	local base = CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0)
	for i = 1, n do
		local w = 1.5 - i * 0.07
		table.insert(
			segs,
			block(
				parent,
				base * CFrame.new(0, (i - 0.5) * len, 0),
				Vector3.new(w, len, 0.12),
				color,
				Enum.Material.Grass
			)
		)
		-- ところどころに浮き袋
		if i % 3 == 0 then
			local b =
				ball(parent, base * CFrame.new(0.7, (i - 0.5) * len, 0), 0.55, Color3.fromRGB(160, 150, 60))
			table.insert(segs, b)
		end
	end
	table.insert(
		list,
		{ segs = segs, base = base, len = len, phase = rng:NextNumber(0, 6), amp = rng:NextNumber(0.6, 1) }
	)
end

local function torii(parent: Instance, at: CFrame)
	local red = Color3.fromRGB(168, 62, 46)
	for _, x in { -6, 6 } do
		pillar(parent, at * CFrame.new(x, 0, 0), 15, 1.3, red, Enum.Material.Wood)
		ball(parent, at * CFrame.new(x, 0.3, 0), 2, MOSS, Enum.Material.Grass)
	end
	block(
		parent,
		at * CFrame.new(0, 14.9, 0),
		Vector3.new(17.5, 1.3, 2.2),
		Color3.fromRGB(40, 32, 30),
		Enum.Material.Wood
	)
	block(parent, at * CFrame.new(0, 13.9, 0), Vector3.new(15.5, 0.9, 1.6), red, Enum.Material.Wood)
	block(parent, at * CFrame.new(0, 10.8, 0), Vector3.new(14, 0.8, 1), red, Enum.Material.Wood)
	block(parent, at * CFrame.new(0, 12.3, 0), Vector3.new(1, 2.2, 0.6), red, Enum.Material.Wood)
	-- 苔と、沈んだ年月
	for _, x in { -7, -2, 3, 8 } do
		ball(parent, at * CFrame.new(x, 15.6, 0), 1.2, MOSS, Enum.Material.Grass)
	end
end

local function lantern(parent: Instance, at: CFrame)
	local stone = Color3.fromRGB(120, 128, 126)
	pillar(parent, at, 0.7, 2.6, stone, Enum.Material.Slate)
	pillar(parent, at * CFrame.new(0, 0.7, 0), 3, 0.9, stone, Enum.Material.Slate)
	block(parent, at * CFrame.new(0, 3.9, 0), Vector3.new(2.4, 0.5, 2.4), stone, Enum.Material.Slate)
	block(parent, at * CFrame.new(0, 4.9, 0), Vector3.new(1.7, 1.5, 1.7), stone, Enum.Material.Slate)
	local fire = block(
		parent,
		at * CFrame.new(0, 4.9, 0),
		Vector3.new(1.85, 0.9, 1.1),
		Color3.fromRGB(120, 230, 255),
		Enum.Material.Neon
	)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(120, 230, 255)
	light.Brightness = 1.6
	light.Range = 14
	light.Parent = fire
	block(parent, at * CFrame.new(0, 5.9, 0), Vector3.new(3, 0.45, 3), stone, Enum.Material.Slate)
	ball(parent, at * CFrame.new(0, 6.4, 0), 0.8, stone, Enum.Material.Slate)
	ball(parent, at * CFrame.new(0.9, 6.1, 0.4), 0.9, MOSS, Enum.Material.Grass)
end

local function jellyfish(parent: Instance, rng: any, home: Vector3, color: Color3, list: { Jelly })
	local parts, offsets = {}, {}
	local bell = ball(parent, CFrame.new(home), 3, color, Enum.Material.ForceField)
	table.insert(parts, bell)
	table.insert(offsets, CFrame.new())
	local inner =
		ball(parent, CFrame.new(home), 1.4, color:Lerp(Color3.new(1, 1, 1), 0.4), Enum.Material.Neon)
	inner.Transparency = 0.4
	table.insert(parts, inner)
	table.insert(offsets, CFrame.new(0, -0.2, 0))
	local glow = Instance.new("PointLight")
	glow.Color = color
	glow.Brightness = 1.2
	glow.Range = 10
	glow.Parent = inner
	for j = 1, 6 do
		local a = j / 6 * math.pi * 2
		local len = rng:NextNumber(3, 5.5)
		local t = part(parent, {
			Name = "Tentacle",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(len, 0.16, 0.16),
			Color = color:Lerp(Color3.new(1, 1, 1), 0.2),
			Material = Enum.Material.Neon,
			Transparency = 0.35,
		})
		table.insert(parts, t)
		table.insert(
			offsets,
			CFrame.new(math.cos(a) * 0.8, -0.6 - len / 2, math.sin(a) * 0.8)
				* CFrame.Angles(0, 0, math.pi / 2)
		)
	end
	table.insert(list, { parts = parts, offsets = offsets, home = home, phase = rng:NextNumber(0, 6) })
end

-- 組み立て ----------------------------------------------------------------------------
function BattleArena.build(parent: Instance, origin: Vector3?): Arena
	local o = origin or BattleArena.ORIGIN
	local rng = Random.new(1203)
	local folder = Instance.new("Folder")
	folder.Name = "BattleArena"
	local static = Instance.new("Folder")
	static.Name = "Scenery"
	static.Parent = folder
	local moving = Instance.new("Folder")
	moving.Name = "Moving"
	moving.Parent = folder
	local fx = Instance.new("Folder")
	fx.Name = "Effects"
	fx.Parent = folder
	local at = function(x: number, y: number, z: number): Vector3
		return o + Vector3.new(x, y, z)
	end

	-- 海底(大きな円盤)と砂丘
	part(static, {
		Name = "Seabed",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2, 340, 340),
		CFrame = CFrame.new(at(0, -1, 0)) * CFrame.Angles(0, 0, math.pi / 2),
		Color = SAND,
		Material = Enum.Material.Sand,
	})
	for _, d in
		{
			{ -40, -30, 70, 5 },
			{ 34, -42, 80, 6 },
			{ -8, -60, 90, 7 },
			{ 46, 4, 60, 4 },
			{ -50, 10, 60, 4 },
			{ 10, -20, 46, 2.2 },
			{ -24, 20, 40, 2 },
			{ 26, 22, 40, 2 },
		}
	do
		local size, rise = d[3], d[4]
		ball(
			static,
			CFrame.new(at(d[1], rise - size / 2, d[2])),
			size,
			SAND:Lerp(Color3.fromRGB(150, 130, 96), rng:NextNumber(0, 0.5)),
			Enum.Material.Sand
		)
	end

	-- 岩: 奥に並ぶ岩場、左右の岩の柱、遠くの岩壁(霧に溶ける)
	for _, r in
		{
			{ -30, -26, 3.5, 5 },
			{ -6, -34, 3, 4 },
			{ 18, -28, 3.2, 5 },
			{ 38, -18, 4, 5 },
			{ -40, -6, 4.2, 5 },
			{ 24, 16, 2.4, 3 },
			{ -26, 15, 2.2, 3 },
			{ 4, -16, 1.8, 3 },
		}
	do
		rocks(static, rng, at(r[1], 0, r[2]), r[3], r[4])
	end
	for _, side in { -1, 1 } do
		local x = side * 34
		local y = 0
		for i, d in { 9, 7.5, 6.5, 5, 4 } do
			ball(
				static,
				CFrame.new(at(x + side * (i % 2) * 0.8, y + d * 0.4, -8)),
				d,
				ROCK[(i % 3) + 1],
				Enum.Material.Slate
			)
			y += d * 0.75
		end
		ball(static, CFrame.new(at(x, y + 1, -8)), 2.4, MOSS, Enum.Material.Grass)
	end
	for i = 1, 16 do
		local a = i / 16 * math.pi * 2
		local d = rng:NextNumber(60, 95)
		ball(
			static,
			CFrame.new(at(math.cos(a) * 140, d * 0.25, math.sin(a) * 140)),
			d,
			ROCK[(i % 3) + 1],
			Enum.Material.Slate
		)
	end

	-- 珊瑚・海草
	for i, c in
		{
			{ -12, -18, 2.2 },
			{ 9, -24, 2.6 },
			{ 30, -30, 2 },
			{ -22, 18, 1.8 },
			{ 21, 19, 1.6 },
			{ -34, -22, 2.4 },
			{ 44, -8, 2 },
		}
	do
		coral(static, rng, at(c[1], 0, c[2]), CORAL[(i % #CORAL) + 1], c[3])
	end
	for _, g in
		{ { -16, -10 }, { 14, -8 }, { -4, -22 }, { 28, -14 }, { -30, 6 }, { 32, 8 }, { 0, -40 }, { -18, 22 } }
	do
		seagrass(static, rng, at(g[1], 0, g[2]))
	end

	-- 手前の砂の上(カメラに近いので、立体の手がかりになる): 小石・貝・ヒトデ・海草。魚の通り道(x = ±12 の内側)はあける
	local shells =
		{ Color3.fromRGB(240, 220, 200), Color3.fromRGB(230, 190, 170), Color3.fromRGB(250, 240, 230) }
	for i = 1, 26 do
		local side = if i % 2 == 0 then 1 else -1
		local x = side * rng:NextNumber(4, 30)
		local z = rng:NextNumber(4, 22)
		local d = rng:NextNumber(0.3, 1.1)
		local pebble = SAND:Lerp(ROCK[(i % #ROCK) + 1], rng:NextNumber(0.25, 0.6))
		ball(static, CFrame.new(at(x, d * 0.1, z)), d, pebble, Enum.Material.Slate)
		if i % 3 == 0 then
			-- 貝(平たい円盤を傾けて)
			part(static, {
				Name = "Shell",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.18, 0.9, 0.9),
				CFrame = CFrame.new(at(x + 1.2, 0.12, z - 0.8))
					* CFrame.Angles(0, rng:NextNumber(0, 3), 1.35),
				Color = shells[(i % #shells) + 1],
			})
		end
	end
	for _, st in { { -14, 9 }, { 17, 6 }, { -26, 16 }, { 9, 17 } } do
		-- ヒトデ: 5本の腕
		for k = 1, 5 do
			local cfStar = CFrame.new(at(st[1], 0.1, st[2])) * CFrame.Angles(0, k / 5 * math.pi * 2, 0)
			block(
				static,
				cfStar * CFrame.new(0, 0, -0.45),
				Vector3.new(0.35, 0.18, 0.9),
				Color3.fromRGB(240, 110, 70),
				Enum.Material.SmoothPlastic
			)
		end
	end
	for _, g in { { -16, 6 }, { 18, 9 }, { -30, 10 }, { 30, 4 }, { -8, 19 }, { 12, 21 } } do
		seagrass(static, rng, at(g[1], 0, g[2]))
	end

	-- 沈んだ鳥居と石灯籠(妖怪の海の底)
	torii(static, CFrame.new(at(-17, -0.5, -32)) * CFrame.Angles(0, 0.25, 0.08))
	lantern(static, CFrame.new(at(13, 0, -20)) * CFrame.Angles(0, 0.4, 0.05))
	lantern(static, CFrame.new(at(-31, 0, -12)) * CFrame.Angles(0, -0.3, -0.06))
	lantern(static, CFrame.new(at(27, 0, -36)) * CFrame.Angles(0, 0.2, 0))

	-- 水面(下から見上げる)
	part(static, {
		Name = "Surface",
		Size = Vector3.new(720, 1, 720),
		CFrame = CFrame.new(at(0, BattleArena.SURFACE_Y, 0)),
		Color = Color3.fromRGB(140, 215, 230),
		Material = Enum.Material.Glass,
		Transparency = 0.2,
		CastShadow = false,
	})

	local arena: Arena = {
		folder = folder,
		fx = fx,
		origin = o,
		kelp = {},
		jelly = {},
		school = {},
		bubbles = {},
		caustics = {},
		rays = {},
	}

	-- 海藻の林(奥と、画面の左右の手前)
	for _, k in
		{
			{ -26, -20 },
			{ -23, -22 },
			{ -8, -28 },
			{ -5, -30 },
			{ 16, -32 },
			{ 19, -30 },
			{ 34, -24 },
			{ -42, -16 },
			{ 42, -30 },
			{ -21, 13 },
			{ -24, 11 },
			{ 22, 12 },
			{ 25, 14 },
		}
	do
		kelp(moving, rng, at(k[1], 0, k[2]), arena.kelp)
	end

	-- 海月
	for i, j in { { -22, 20, -18 }, { 20, 24, -28 }, { 4, 28, -46 }, { 34, 15, -10 } } do
		jellyfish(moving, rng, at(j[1], j[2], j[3]), CORAL[((i + 1) % #CORAL) + 1], arena.jelly)
	end

	-- 小魚の群れ(奥をぐるりと回る)
	for _ = 1, 18 do
		local p = part(moving, {
			Name = "Fishlet",
			Size = Vector3.new(0.35, 0.45, 1.1),
			Color = Color3.fromRGB(190, 210, 225),
			Material = Enum.Material.SmoothPlastic,
			Reflectance = 0.25,
			CastShadow = false,
		})
		table.insert(arena.school, {
			part = p,
			offset = Vector3.new(rng:NextNumber(-3, 3), rng:NextNumber(-1.5, 1.5), rng:NextNumber(-3, 3)),
			phase = rng:NextNumber(0, 6),
		})
	end

	-- 泡(海底の割れ目から上る。球のパーツ)
	local vents = { at(-12, 0, -18), at(9, 0, -24), at(-31, 0, -12), at(30, 0, -30), at(2, 0, -40) }
	for i = 1, 36 do
		local d = rng:NextNumber(0.25, 0.7)
		local p = ball(moving, CFrame.new(o), d, Color3.fromRGB(220, 245, 255), Enum.Material.Glass)
		p.Transparency = 0.45
		p.Reflectance = 0.2
		p.CastShadow = false
		table.insert(arena.bubbles, {
			part = p,
			base = vents[(i % #vents) + 1] + Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)),
			speed = rng:NextNumber(2.5, 5),
			offset = rng:NextNumber(0, BattleArena.SURFACE_Y),
			phase = rng:NextNumber(0, 6),
		})
	end

	-- 水面からの光が海底でゆらめく(動く光)
	for i = 1, 5 do
		local p = part(moving, {
			Name = "Caustic",
			Size = Vector3.new(0.2, 0.2, 0.2),
			Transparency = 1,
			CastShadow = false,
		})
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(170, 235, 255)
		light.Brightness = 1.1
		light.Range = 18
		light.Parent = p
		table.insert(arena.caustics, { part = p, phase = i * 1.3 })
	end

	-- 光の筋(水面 → 海底へ斜めに)
	local rayAnchor = part(static, {
		Name = "RayAnchor",
		Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = CFrame.new(o),
		Transparency = 1,
		CastShadow = false,
	})
	for i, x in { -30, -14, 2, 16, 32, 46 } do
		local z = -10 - (i % 3) * 12
		local top = Instance.new("Attachment")
		top.Position = Vector3.new(x, BattleArena.SURFACE_Y, z)
		top.Parent = rayAnchor
		local bottom = Instance.new("Attachment")
		bottom.Position = Vector3.new(x + 9, 0, z + 4)
		bottom.Parent = rayAnchor
		local beam = Instance.new("Beam")
		beam.Attachment0 = top
		beam.Attachment1 = bottom
		beam.Color = ColorSequence.new(Color3.fromRGB(200, 245, 255))
		beam.LightEmission = 1
		beam.LightInfluence = 0
		beam.Width0 = 2.5 + (i % 2) * 1.5
		beam.Width1 = 7 + (i % 3) * 2
		beam.FaceCamera = true
		beam.Segments = 1
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.72),
			NumberSequenceKeypoint.new(0.5, 0.9),
			NumberSequenceKeypoint.new(1, 1),
		})
		beam.Parent = rayAnchor
		table.insert(arena.rays, { top = top, bottom = bottom, x = x, z = z, phase = i * 0.9 })
	end

	-- 漂う粒(マリンスノー)
	local snowBox = part(static, {
		Name = "MarineSnow",
		Size = Vector3.new(90, 36, 70),
		CFrame = CFrame.new(at(0, 18, -10)),
		Transparency = 1,
		CastShadow = false,
	})
	local snow = Instance.new("ParticleEmitter")
	snow.Texture = TEX_SPARKLE
	snow.Shape = Enum.ParticleEmitterShape.Box
	snow.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	snow.Rate = 24
	snow.Lifetime = NumberRange.new(9, 14)
	snow.Speed = NumberRange.new(0.2, 0.6)
	snow.SpreadAngle = Vector2.new(180, 180)
	snow.Size = NumberSequence.new(0.14)
	snow.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.45),
		NumberSequenceKeypoint.new(0.8, 0.45),
		NumberSequenceKeypoint.new(1, 1),
	})
	snow.Color = ColorSequence.new(Color3.fromRGB(220, 245, 255))
	snow.LightEmission = 0.6
	snow.Parent = snowBox

	folder.Parent = parent
	BattleArena.step(arena, 0, nil)
	return arena
end

-- 動き ----------------------------------------------------------------------------
-- 動くものの位置をまとめて計算し、move(parts, cframes) で一度に動かす(ゲームでは workspace:BulkMoveTo)
function BattleArena.step(arena: Arena, t: number, move: ((parts: { BasePart }, cfs: { CFrame }) -> ())?)
	local parts: { BasePart } = {}
	local cfs: { CFrame } = {}
	local o = arena.origin

	-- 海藻: 根元から先へ、少しずつ曲がりながら揺れる
	for _, k in arena.kelp do
		local cf = k.base
		local seg = 0
		for _, p in k.segs do
			if p.Name == "Block" then
				seg += 1
				local bend = math.sin(t * 0.8 + k.phase + seg * 0.55) * 0.09 * k.amp
				local lean = math.cos(t * 0.6 + k.phase + seg * 0.4) * 0.05 * k.amp
				cf = cf * CFrame.Angles(lean, 0.08, bend)
				table.insert(parts, p)
				table.insert(cfs, cf * CFrame.new(0, k.len / 2, 0))
				cf = cf * CFrame.new(0, k.len, 0)
			else
				-- 浮き袋はひとつ前の葉の横
				table.insert(parts, p)
				table.insert(cfs, cf * CFrame.new(0.75, -k.len / 2, 0))
			end
		end
	end

	-- 海月: ふわふわ上下しながら漂う
	for _, j in arena.jelly do
		local pos = j.home
			+ Vector3.new(
				math.sin(t * 0.18 + j.phase) * 3,
				math.sin(t * 0.5 + j.phase) * 1.6,
				math.cos(t * 0.15 + j.phase) * 2
			)
		local sway = math.sin(t * 1.4 + j.phase) * 0.12
		local root = CFrame.new(pos) * CFrame.Angles(sway, t * 0.1, -sway * 0.5)
		for i, p in j.parts do
			table.insert(parts, p)
			table.insert(cfs, root * j.offsets[i])
		end
	end

	-- 小魚の群れ: 奥を大きな輪で回る(頭 = -Z を進む向きへ)
	local th = t * 0.22
	local center = o + Vector3.new(math.cos(th) * 36, 16 + math.sin(th * 2) * 3, -42 + math.sin(th) * 10)
	local dx, dz = -math.sin(th) * 36, math.cos(th) * 10
	local yaw = math.atan2(-dx, -dz)
	for _, f in arena.school do
		local wob = Vector3.new(math.sin(t * 1.3 + f.phase) * 0.5, math.sin(t * 1.7 + f.phase) * 0.3, 0)
		table.insert(parts, f.part)
		table.insert(
			cfs,
			CFrame.new(center + f.offset + wob) * CFrame.Angles(0, yaw + math.sin(t * 6 + f.phase) * 0.15, 0)
		)
	end

	-- 泡: 割れ目から水面まで上って、また下から
	local h = BattleArena.SURFACE_Y
	for _, b in arena.bubbles do
		local y = (b.offset + t * b.speed) % h
		local wob =
			Vector3.new(math.sin(t * 2 + b.phase + y * 0.3) * 0.4, y, math.cos(t * 1.7 + b.phase) * 0.4)
		table.insert(parts, b.part)
		table.insert(cfs, CFrame.new(b.base + wob))
	end

	-- 海底のゆらめく光
	for _, c in arena.caustics do
		local pos = o
			+ Vector3.new(math.sin(t * 0.3 + c.phase) * 20, 3, math.cos(t * 0.23 + c.phase * 1.7) * 14 - 6)
		table.insert(parts, c.part)
		table.insert(cfs, CFrame.new(pos))
	end

	if move then
		move(parts, cfs)
	else
		for i, p in parts do
			p.CFrame = cfs[i]
		end
	end

	-- 光の筋は水面の揺れに合わせて少し動く
	for _, r in arena.rays do
		r.top.Position = Vector3.new(r.x + math.sin(t * 0.2 + r.phase) * 2, h, r.z)
		r.bottom.Position = Vector3.new(r.x + 9 + math.sin(t * 0.25 + r.phase) * 4, 0, r.z + 4)
	end
end

return BattleArena
