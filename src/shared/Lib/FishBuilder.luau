--!strict
-- 妖怪魚の見た目を組み立てる(第3版)。画像やメッシュのアセットは使わず、Roblox の基本パーツだけで作る。
-- 魚の前方は -Z。モデルの PrimaryPart は "Body"。
--
-- 1匹の見た目 = 体の形(6種)× 体つき(body)× 目(eyes)× 口(mouth)× 模様(pattern)× 飾り(deco)× 色(c1/c2/c3)
--             × レア度の格(大きさ・ツヤ・ひれの縁取り・金の飾り・後光 など)
--
-- レア度の格(RARITY_STYLE)はすべての魚に自動でかかる。データ側は「その魚の個性」だけを書けばよい。

local Types = require(script.Parent.Types)

local FishBuilder = {}

export type BuildOptions = {
	mutation: string?,
	scale: number?, -- 全体の大きさ(既定 1)。レア度の大きさに掛け算される
	anchored: boolean?,
	silhouette: boolean?, -- 図鑑の未発見表示
	noRarityScale: boolean?, -- レア度による大きさの差を付けない(図鑑の小さな枠など)
}

-- 体の形ごとの基本(スタッド)
local SHAPES = {
	koi = {
		body = Vector3.new(0.92, 1.0, 2.1),
		stalk = 0.5,
		tail = "forked",
		tailSize = 1.0,
		dorsal = "sail",
		eyes = "normal",
		mouth = "small",
	},
	catfish = {
		body = Vector3.new(1.1, 0.78, 2.3),
		stalk = 0.48,
		tail = "fan",
		tailSize = 0.85,
		dorsal = "small",
		eyes = "normal",
		mouth = "wide",
	},
	puffer = {
		body = Vector3.new(1.5, 1.4, 1.55),
		stalk = 0.3,
		tail = "fan",
		tailSize = 0.6,
		dorsal = "small",
		eyes = "normal",
		mouth = "o",
	},
	eel = {
		body = Vector3.new(0.62, 0.68, 3.4),
		stalk = 0.62,
		tail = "ribbon",
		tailSize = 0.7,
		dorsal = "ribbon",
		eyes = "normal",
		mouth = "small",
	},
	angler = {
		body = Vector3.new(1.45, 1.2, 1.75),
		stalk = 0.42,
		tail = "fan",
		tailSize = 0.75,
		dorsal = "spines",
		eyes = "normal",
		mouth = "grin",
	},
	ray = {
		body = Vector3.new(1.3, 0.38, 1.7),
		stalk = 0,
		tail = "whip",
		tailSize = 1.0,
		dorsal = "none",
		eyes = "normal",
		mouth = "none",
	},
}

-- レア度の格。上に行くほど大きく、派手になる
type Style = {
	scale: number, -- 大きさ
	gloss: number, -- ツヤ(Reflectance)
	fin: number, -- ひれの大きさ
	rim: boolean, -- ひれの縁取り
	frill: boolean, -- ひれの飾り(2枚目)
	gold: boolean, -- 金の縁と額の紋
	aura: number, -- まとう光の粒(毎秒)
	light: boolean, -- 体が光を放つ
	halo: number, -- 後光の輪の数
	glowEyes: boolean, -- 光る瞳
	orbs: number, -- 周りを漂う鬼火
}
local RARITY_STYLE: { [string]: Style } = {
	common = {
		scale = 0.8,
		gloss = 0,
		fin = 1.0,
		rim = false,
		frill = false,
		gold = false,
		aura = 0,
		light = false,
		halo = 0,
		glowEyes = false,
		orbs = 0,
	},
	uncommon = {
		scale = 0.92,
		gloss = 0.03,
		fin = 1.06,
		rim = false,
		frill = false,
		gold = false,
		aura = 0,
		light = false,
		halo = 0,
		glowEyes = false,
		orbs = 0,
	},
	rare = {
		scale = 1.05,
		gloss = 0.07,
		fin = 1.12,
		rim = true,
		frill = false,
		gold = false,
		aura = 0,
		light = false,
		halo = 0,
		glowEyes = false,
		orbs = 0,
	},
	epic = {
		scale = 1.2,
		gloss = 0.1,
		fin = 1.22,
		rim = true,
		frill = true,
		gold = false,
		aura = 6,
		light = false,
		halo = 0,
		glowEyes = false,
		orbs = 0,
	},
	legendary = {
		scale = 1.4,
		gloss = 0.14,
		fin = 1.3,
		rim = true,
		frill = true,
		gold = true,
		aura = 10,
		light = true,
		halo = 0,
		glowEyes = false,
		orbs = 0,
	},
	mythic = {
		scale = 1.65,
		gloss = 0.18,
		fin = 1.38,
		rim = true,
		frill = true,
		gold = true,
		aura = 14,
		light = true,
		halo = 1,
		glowEyes = true,
		orbs = 0,
	},
	secret = {
		scale = 1.9,
		gloss = 0.2,
		fin = 1.45,
		rim = true,
		frill = true,
		gold = true,
		aura = 20,
		light = true,
		halo = 2,
		glowEyes = true,
		orbs = 3,
	},
}
FishBuilder.RarityStyle = RARITY_STYLE

local MUTATION_LOOK = {
	gold = { color = Color3.fromHex("#FFD34D"), material = Enum.Material.Foil, reflectance = 0.25 },
	sakura = { tint = Color3.fromHex("#FFB7D5") },
	thunder = { tint = Color3.fromHex("#FFE34D"), neonPattern = true },
	rainbow = { tag = "RainbowFish" },
	onibi = { tint = Color3.fromHex("#6BE3FF") },
	crystal = { color = Color3.fromHex("#BDF4FF"), material = Enum.Material.Glass, transparency = 0.25 },
	pearl = { color = Color3.fromHex("#FFF4E8"), material = Enum.Material.SmoothPlastic, reflectance = 0.4 },
}

local WHITE = Color3.fromRGB(250, 248, 240)
local INK = Color3.fromRGB(18, 14, 24)
local HORN = Color3.fromHex("#F4EAD2")
local GOLD = Color3.fromHex("#F2C14E")
local PINK = Color3.fromHex("#FF8FA8")
local RED = Color3.fromHex("#D7263D")

local function hashString(s: string): number
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + string.byte(s, i)) % 2147483647
	end
	return h
end

-- 楕円体の表面の点と、外向きの向き(u: 前後 -1..1 / phi: 周方向。90°が背中)
local function surface(half: Vector3, u: number, phi: number): (Vector3, Vector3)
	local r = math.sqrt(math.max(0, 1 - u * u))
	local p = Vector3.new(half.X * r * math.cos(phi), half.Y * r * math.sin(phi), half.Z * u)
	local n = Vector3.new(p.X / (half.X * half.X), p.Y / (half.Y * half.Y), p.Z / (half.Z * half.Z))
	return p, if n.Magnitude > 0 then n.Unit else Vector3.new(0, 1, 0)
end

-- pos から dir の方向へ伸びる CFrame(パーツの Z 軸を dir に向ける)
local function along(pos: Vector3, dir: Vector3, upHint: Vector3?): CFrame
	if dir.Magnitude < 1e-4 then
		return CFrame.new(pos)
	end
	local d = dir.Unit
	local up = upHint or (if math.abs(d.Y) > 0.95 then Vector3.new(1, 0, 0) else Vector3.new(0, 1, 0))
	return CFrame.lookAt(pos, pos + d, up)
end

-- 見た目の全体の大きさ(水槽やぬしの表示で使う)
function FishBuilder.sizeOf(def: Types.FishDef): number
	local style = RARITY_STYLE[def.rarity] or RARITY_STYLE.common
	return style.scale * (def.size or 1)
end

function FishBuilder.build(def: Types.FishDef, opts: BuildOptions?): Model
	local o: BuildOptions = opts or ({} :: BuildOptions)
	local shape = SHAPES[def.shape] or SHAPES.koi
	local style = RARITY_STYLE[def.rarity] or RARITY_STYLE.common
	local scale = (o.scale or 1) * (def.size or 1) * (if o.noRarityScale then 1 else style.scale)
	local rng = Random.new(hashString(def.id))
	local mutLook = if o.mutation then MUTATION_LOOK[o.mutation] else nil
	local deco = def.deco
	local has = function(name: string): boolean
		return table.find(deco, name) ~= nil
	end
	local eyesStyle = def.eyes
		or (if has("noface") then "none" elseif has("big_eye") then "big" else shape.eyes)
	local mouthStyle = def.mouth or (if has("noface") then "none" else shape.mouth)

	-- 色 -------------------------------------------------------------------
	local c1 = Color3.fromHex(def.c1)
	local c2 = Color3.fromHex(def.c2)
	local accent = if def.c3 then Color3.fromHex(def.c3) else c2
	local bodyMaterial = Enum.Material.SmoothPlastic
	local patternMaterial = Enum.Material.SmoothPlastic
	if mutLook then
		if mutLook.color then
			c1 = mutLook.color
			c2 = mutLook.color:Lerp(WHITE, 0.35)
			accent = c2
		elseif mutLook.tint then
			c1 = c1:Lerp(mutLook.tint, 0.55)
			c2 = c2:Lerp(mutLook.tint, 0.35)
			accent = accent:Lerp(mutLook.tint, 0.4)
		end
		if mutLook.material then
			bodyMaterial = mutLook.material
			patternMaterial = mutLook.material
		end
		if mutLook.neonPattern then
			patternMaterial = Enum.Material.Neon
		end
	end
	local glow = has("glow")
	if glow then
		patternMaterial = Enum.Material.Neon
	end
	local finColor = accent:Lerp(WHITE, 0.18)
	local rimColor = if style.gold then GOLD else accent:Lerp(INK, 0.15)
	local rimMaterial = if style.gold then Enum.Material.Foil else Enum.Material.SmoothPlastic
	local mouthColor = c1:Lerp(INK, 0.72)
	local white, ink = WHITE, INK
	local silhouette = o.silhouette == true
	if silhouette then
		c1 = Color3.fromRGB(18, 20, 32)
		c2, accent, finColor, mouthColor, white, ink, rimColor = c1, c1, c1, c1, c1, c1, c1
		bodyMaterial = Enum.Material.SmoothPlastic
		patternMaterial = bodyMaterial
		rimMaterial = bodyMaterial
	end
	local finAlpha = if silhouette or bodyMaterial == Enum.Material.Glass then 0 else 0.12
	local fx = not silhouette -- 光やエフェクトを付けるか

	local model = Instance.new("Model")
	model.Name = def.id
	model:SetAttribute("Shape", def.shape)
	model:SetAttribute("Rarity", def.rarity)

	-- kind: nil/"ellipsoid"(楕円体) / "ball" / "cylinder" / "block" / "wedge"
	local function part(
		name: string,
		size: Vector3,
		cf: CFrame,
		color: Color3,
		kind: string?,
		material: Enum.Material?
	): BasePart
		local p: BasePart
		if kind == "wedge" then
			p = Instance.new("WedgePart")
		else
			local pp = Instance.new("Part")
			if kind == "ball" then
				pp.Shape = Enum.PartType.Ball
			elseif kind == "cylinder" then
				pp.Shape = Enum.PartType.Cylinder
			end
			p = pp
		end
		p.Name = name
		p.Size = Vector3.new(math.max(size.X, 0.05), math.max(size.Y, 0.05), math.max(size.Z, 0.05))
		p.CFrame = cf
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.CastShadow = false
		if kind == nil or kind == "ellipsoid" then
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = p
		end
		p.Parent = model
		return p
	end
	-- 薄いひれ(thinAxis: 薄い方向 "X" か "Y")。レア度が上がると縁取りが付く
	local function fin(name: string, size: Vector3, cf: CFrame, color: Color3?, thinAxis: string?): BasePart
		local s = size
			* Vector3.new(
				if thinAxis == "X" or thinAxis == nil then 1 else style.fin,
				if thinAxis == "Y" then 1 else style.fin,
				style.fin
			)
		local f = part(name, s, cf, color or finColor, nil, patternMaterial)
		f.Transparency = finAlpha
		if style.rim and not silhouette then
			local grow = if thinAxis == "Y" then Vector3.new(1.12, 0.6, 1.1) else Vector3.new(0.6, 1.12, 1.1)
			local r = part(name .. "Rim", s * grow, cf, rimColor, nil, rimMaterial)
			r.Transparency = 0
		end
		return f
	end
	-- 輪(後光・太鼓・火の車など): plane は "YZ"(横から見て丸い)か "XY"(正面から見て丸い)
	local function ring(
		name: string,
		center: Vector3,
		radius: number,
		count: number,
		plane: string,
		ballSize: number,
		color: Color3,
		material: Enum.Material,
		kind: string?
	)
		for i = 1, count do
			local a = (i / count) * math.pi * 2
			local offset = if plane == "YZ"
				then Vector3.new(0, math.sin(a) * radius, math.cos(a) * radius)
				else Vector3.new(math.cos(a) * radius, math.sin(a) * radius, 0)
			local size = if kind == "cylinder"
				then Vector3.new(ballSize * 0.55, ballSize, ballSize) -- 太鼓: 面が横を向く
				else Vector3.new(ballSize, ballSize, ballSize)
			part(name, size, CFrame.new(center + offset), color, kind or "ball", material)
		end
	end

	-- 胴 ------------------------------------------------------------------
	local prop = def.body or { 1, 1, 1 }
	local bodySize = shape.body * Vector3.new(prop[1], prop[2], prop[3]) * scale
	local half = bodySize / 2
	local body = part("Body", bodySize, CFrame.new(), c1, nil, bodyMaterial)
	body.Reflectance = if mutLook and mutLook.reflectance
		then mutLook.reflectance
		else (if silhouette then 0 else style.gloss)
	if mutLook and mutLook.transparency then
		body.Transparency = mutLook.transparency
	end
	model.PrimaryPart = body

	-- 頭の形
	if def.shape == "catfish" then
		part(
			"Head",
			Vector3.new(bodySize.X * 1.12, bodySize.Y * 0.86, bodySize.Z * 0.45),
			CFrame.new(0, -half.Y * 0.06, -half.Z * 0.58),
			c1,
			nil,
			bodyMaterial
		)
	elseif def.shape == "angler" then
		part(
			"Head",
			Vector3.new(bodySize.X * 0.96, bodySize.Y * 0.92, bodySize.Z * 0.62),
			CFrame.new(0, half.Y * 0.02, -half.Z * 0.42),
			c1,
			nil,
			bodyMaterial
		)
	elseif def.shape == "eel" then
		part(
			"Head",
			Vector3.new(bodySize.X * 1.06, bodySize.Y * 1.0, bodySize.Z * 0.32),
			CFrame.new(0, 0, -half.Z * 0.72),
			c1,
			nil,
			bodyMaterial
		)
	end
	if has("bighead") then
		-- ぬらりひょんのような大きな後頭部
		part(
			"Dome",
			Vector3.new(bodySize.X * 0.95, bodySize.Y * 0.95, bodySize.Z * 0.55),
			CFrame.new(0, half.Y * 0.55, -half.Z * 0.5),
			c1:Lerp(WHITE, 0.08),
			nil,
			bodyMaterial
		)
	end

	-- 尾の付け根
	local tailZ = half.Z
	if shape.stalk > 0 then
		local stalkLen = bodySize.Z * (if def.shape == "eel" then 0.55 else 0.42)
		local stalkSize = Vector3.new(bodySize.X * shape.stalk, bodySize.Y * shape.stalk * 1.05, stalkLen)
		local stalkZ = half.Z * 0.78
		part("Stalk", stalkSize, CFrame.new(0, 0, stalkZ), c1, nil, bodyMaterial)
		tailZ = stalkZ + stalkLen * 0.46
	end

	-- 模様 ----------------------------------------------------------------
	local pattern = def.pattern
	if pattern == "belly" then
		part(
			"Belly",
			Vector3.new(bodySize.X * 0.94, bodySize.Y * 0.6, bodySize.Z * 0.9),
			CFrame.new(0, -half.Y * 0.38, 0),
			c2,
			nil,
			patternMaterial
		)
	elseif pattern == "stripes" or pattern == "ribs" then
		local count = if def.shape == "eel" then 5 elseif pattern == "ribs" then 5 else 3
		local thick = if pattern == "ribs" then 0.05 else 0.08
		for i = 1, count do
			local u = -0.5 + (i - 1) * (1.0 / math.max(1, count - 1)) * 0.9
			local r = math.sqrt(1 - u * u) * 1.035
			part(
				"Stripe",
				Vector3.new(bodySize.X * r, bodySize.Y * r, bodySize.Z * thick),
				CFrame.new(0, 0, half.Z * u),
				c2,
				nil,
				patternMaterial
			)
		end
		if pattern == "ribs" then
			-- 背骨
			part(
				"Spine",
				Vector3.new(bodySize.X * 0.18, bodySize.Y * 0.14, bodySize.Z * 0.95),
				CFrame.new(0, half.Y * 0.93, 0),
				c2,
				nil,
				patternMaterial
			)
		end
	elseif pattern == "spots" or pattern == "patches" then
		local big = pattern == "patches"
		local n = if big then 4 elseif def.shape == "eel" then 9 else 7
		for _ = 1, n do
			local u = rng:NextNumber(-0.55, 0.6)
			local phi = rng:NextNumber(math.rad(if big then 50 else 30), math.rad(if big then 130 else 150))
			local side = if rng:NextInteger(0, 1) == 0 then 1 else -1
			local p, nrm = surface(half, u, phi)
			p = Vector3.new(p.X * side, p.Y, p.Z)
			nrm = Vector3.new(nrm.X * side, nrm.Y, nrm.Z)
			local base = math.min(bodySize.X, bodySize.Y)
			local d = base * (if big then rng:NextNumber(0.55, 0.75) else rng:NextNumber(0.2, 0.32))
			part(
				"Spot",
				Vector3.new(d, d * (if big then 0.8 else 1), d * 0.35),
				along(p - nrm * d * 0.08, nrm),
				c2,
				nil,
				patternMaterial
			)
		end
	elseif pattern == "saddle" then
		part(
			"Saddle",
			Vector3.new(bodySize.X * 1.02, bodySize.Y * 0.62, bodySize.Z * 0.42),
			CFrame.new(0, half.Y * 0.42, half.Z * 0.05),
			c2,
			nil,
			patternMaterial
		)
	elseif pattern == "gradient" then
		part(
			"Rear",
			Vector3.new(bodySize.X * 1.015, bodySize.Y * 1.015, bodySize.Z * 0.62),
			CFrame.new(0, 0, half.Z * 0.42),
			c2,
			nil,
			patternMaterial
		)
	elseif pattern == "dango" then
		-- 花見団子の三色
		local cols = { c2, WHITE:Lerp(c1, 0.15), accent }
		for i = 1, 3 do
			local u = -0.45 + (i - 1) * 0.45
			local r = math.sqrt(1 - u * u) * 1.03
			part(
				"Band",
				Vector3.new(bodySize.X * r, bodySize.Y * r, bodySize.Z * 0.22),
				CFrame.new(0, 0, half.Z * u),
				cols[i],
				nil,
				patternMaterial
			)
		end
	end
	if not silhouette and pattern ~= "stripes" and pattern ~= "dango" and pattern ~= "saddle" then
		part(
			"Back",
			Vector3.new(bodySize.X * 0.7, bodySize.Y * 0.35, bodySize.Z * 0.8),
			CFrame.new(0, half.Y * 0.68, half.Z * 0.02),
			c1:Lerp(INK, 0.18),
			nil,
			bodyMaterial
		)
	end

	-- 尾びれ ----------------------------------------------------------------
	local ts = shape.tailSize * scale
	local tails = def.tails or (if has("long_tail") then 3 else 0)
	if tails >= 2 and shape.tail ~= "whip" then
		-- 何本もの長い尾(猫又・九尾)。扇のように広げる
		local len = ts * 1.55
		for i = 1, tails do
			local t = if tails == 1 then 0 else (i - 1) / (tails - 1) * 2 - 1
			local dir = Vector3.new(t * 0.35, t * 0.75, 1)
			local pos = Vector3.new(t * len * 0.12, t * len * 0.28, tailZ + len * 0.4)
			local col = if i % 2 == 0 then accent else finColor
			fin(
				"Tail",
				Vector3.new(0.07 * scale, len * 0.3, len * 0.95),
				along(pos, dir, Vector3.new(0, 1, 0)),
				col
			)
		end
	elseif shape.tail == "forked" then
		local len = ts * 0.95
		for _, s in { 1, -1 } do
			local cf = along(Vector3.new(0, s * len * 0.22, tailZ + len * 0.38), Vector3.new(0, s * 0.55, 1))
			fin("Tail", Vector3.new(0.07 * scale, len * 0.42, len * 0.85), cf)
		end
	elseif shape.tail == "fan" then
		fin("Tail", Vector3.new(0.07 * scale, ts * 0.95, ts * 0.75), CFrame.new(0, 0, tailZ + ts * 0.3))
	elseif shape.tail == "ribbon" then
		fin("Tail", Vector3.new(0.06 * scale, ts * 0.55, ts * 0.9), CFrame.new(0, 0, tailZ + ts * 0.32))
	elseif shape.tail == "whip" then
		local len = bodySize.Z * (if has("cloth") then 2.2 else 0.95)
		if has("cloth") then
			-- 一反木綿: 長くたなびく布の尾
			-- 少しずつ重ねて、波打つ一枚の布に見せる
			for k = 0, 5 do
				local z = half.Z * 0.6 + len * (k * 0.17)
				local y = math.sin(k * 1.1) * 0.22 * scale
				part(
					"Cloth",
					Vector3.new(bodySize.X * (0.75 - k * 0.08), 0.07 * scale, len * 0.26),
					CFrame.new(0, y, z) * CFrame.Angles(math.cos(k * 1.1) * 0.35, 0, 0),
					c1:Lerp(c2, k / 6),
					nil,
					bodyMaterial
				)
			end
		else
			part(
				"Tail",
				Vector3.new(0.14 * scale, 0.14 * scale, len),
				CFrame.new(0, 0, half.Z + len * 0.45),
				c1,
				nil,
				bodyMaterial
			)
			part(
				"TailTip",
				Vector3.new(0.1 * scale, 0.2 * scale, 0.5 * scale),
				CFrame.new(0, 0.05 * scale, half.Z + len * 0.92),
				accent,
				"wedge",
				patternMaterial
			)
		end
	end
	if has("plumes") then
		-- 鳳凰の尾羽: 長い羽を5枚、先に目玉模様
		for i = 1, 5 do
			local t = (i - 3) / 2
			local len = ts * (2.2 - math.abs(t) * 0.5)
			local dir = Vector3.new(t * 0.45, 0.25 + t * 0.15, 1)
			local base = Vector3.new(0, half.Y * 0.1, tailZ)
			local cf = along(base + dir.Unit * len * 0.5, dir)
			fin("Plume", Vector3.new(0.06 * scale, ts * 0.3, len), cf, if i % 2 == 0 then c2 else accent)
			part(
				"PlumeEye",
				Vector3.new(0.18, 0.2, 0.2) * scale,
				CFrame.new(base + dir.Unit * len * 0.92 + Vector3.new(0, 0.02, 0)),
				GOLD,
				"ball",
				if fx then Enum.Material.Neon else Enum.Material.SmoothPlastic
			)
		end
	end

	-- 背びれ ------------------------------------------------------------------
	if has("mane") then
		-- 龍のたてがみ: 頭から尾までとがった毛が並ぶ
		for i = 0, 6 do
			local u = -0.6 + i * 0.22
			local p = surface(half, math.clamp(u, -0.95, 0.95), math.rad(90))
			part(
				"Mane",
				Vector3.new(0.1 * scale, bodySize.Y * 0.42 * (1 - i * 0.07), 0.3 * scale),
				CFrame.new(0, p.Y + bodySize.Y * 0.12, p.Z),
				accent,
				"wedge",
				patternMaterial
			)
		end
	elseif shape.dorsal == "sail" then
		fin(
			"Dorsal",
			Vector3.new(0.07 * scale, bodySize.Y * 0.5, bodySize.Z * 0.5),
			along(Vector3.new(0, half.Y * 0.92, half.Z * 0.05), Vector3.new(0, -0.35, 1))
		)
	elseif shape.dorsal == "small" then
		fin(
			"Dorsal",
			Vector3.new(0.07 * scale, bodySize.Y * 0.36, bodySize.Z * 0.3),
			CFrame.new(0, half.Y * 0.93, half.Z * 0.12)
		)
	elseif shape.dorsal == "ribbon" then
		fin(
			"Dorsal",
			Vector3.new(0.05 * scale, bodySize.Y * 0.42, bodySize.Z * 0.95),
			CFrame.new(0, half.Y * 0.88, half.Z * 0.25)
		)
		fin(
			"Anal",
			Vector3.new(0.05 * scale, bodySize.Y * 0.3, bodySize.Z * 0.6),
			CFrame.new(0, -half.Y * 0.88, half.Z * 0.45)
		)
	elseif shape.dorsal == "spines" then
		for i = 1, 3 do
			local z = -half.Z * 0.1 + (i - 1) * half.Z * 0.25
			part(
				"Spine",
				Vector3.new(0.08 * scale, bodySize.Y * (0.42 - i * 0.07), 0.22 * scale),
				CFrame.new(0, half.Y * 0.95, z),
				accent,
				"wedge",
				patternMaterial
			)
		end
	end
	if style.frill and shape.dorsal ~= "none" and not has("mane") then
		-- 2枚目の背びれ(極以上): 後ろへ長く流れる
		fin(
			"Frill",
			Vector3.new(0.05 * scale, bodySize.Y * 0.35, bodySize.Z * 0.5),
			along(Vector3.new(0, half.Y * 0.8, half.Z * 0.45), Vector3.new(0, -0.5, 1)),
			accent
		)
	end

	-- 胸びれ・腹びれ
	if def.shape == "ray" then
		for _, s in { 1, -1 } do
			part(
				"Wing",
				Vector3.new(bodySize.X * 1.9, bodySize.Y * 0.45, bodySize.Z * 0.78),
				CFrame.new(s * half.X * 1.45, -half.Y * 0.02, half.Z * 0.05)
					* CFrame.Angles(0, s * math.rad(-18), s * math.rad(-8)),
				c1,
				nil,
				bodyMaterial
			)
			fin(
				"WingEdge",
				Vector3.new(bodySize.X * 0.85, bodySize.Y * 0.38, bodySize.Z * 0.36),
				CFrame.new(s * half.X * 2.6, half.Y * 0.12, half.Z * 0.2)
					* CFrame.Angles(0, s * math.rad(-30), s * math.rad(-8)),
				c2,
				"Y"
			)
		end
	else
		local frills = has("frills")
		for _, s in { 1, -1 } do
			local len = bodySize.Z * (if frills then 0.6 else 0.24)
			fin(
				"PecFin",
				Vector3.new(bodySize.X * (if frills then 0.5 else 0.42), 0.06 * scale, len),
				CFrame.new(
					s * half.X * 0.95,
					-half.Y * 0.28,
					-half.Z * 0.18 + (if frills then len * 0.35 else 0)
				) * CFrame.Angles(math.rad(-10), s * math.rad(-25), s * math.rad(28)),
				if frills then accent else nil,
				"Y"
			)
			if def.shape ~= "eel" and def.shape ~= "puffer" then
				fin(
					"PelvicFin",
					Vector3.new(bodySize.X * 0.22, 0.05 * scale, bodySize.Z * 0.16),
					CFrame.new(s * half.X * 0.4, -half.Y * 0.9, half.Z * 0.2)
						* CFrame.Angles(0, 0, s * math.rad(40)),
					nil,
					"Y"
				)
			end
		end
	end

	-- 河豚のトゲ
	if def.shape == "puffer" and not has("smooth") then
		for i = 1, 14 do
			local u = -0.6 + (i % 7) * 0.2
			local phi = math.rad(if i <= 7 then 55 else 125) + rng:NextNumber(-0.2, 0.2)
			local side = if i % 2 == 0 then 1 else -1
			local p, nrm = surface(half, u, phi)
			p = Vector3.new(p.X * side, p.Y, p.Z)
			nrm = Vector3.new(nrm.X * side, nrm.Y, nrm.Z)
			part(
				"Spike",
				Vector3.new(0.07, 0.07, 0.3) * scale,
				along(p + nrm * 0.08 * scale, nrm),
				c2:Lerp(WHITE, 0.25),
				nil,
				patternMaterial
			)
		end
	end

	-- 顔 ----------------------------------------------------------------------
	local frontZ = -half.Z
	if def.shape == "catfish" then
		frontZ = -half.Z * 0.58 - bodySize.Z * 0.45 / 2
	elseif def.shape == "angler" then
		frontZ = -half.Z * 0.42 - bodySize.Z * 0.62 / 2
	elseif def.shape == "eel" then
		frontZ = -half.Z * 0.72 - bodySize.Z * 0.32 / 2
	end
	local eyeBase = math.min(bodySize.X, bodySize.Y)
	local eyePositions: { { pos: Vector3, out: Vector3, d: number } } = {}

	local function eye(pos: Vector3, outward: Vector3, d: number, kind: string)
		local out = outward.Unit
		table.insert(eyePositions, { pos = pos, out = out, d = d })
		if kind == "dot" then
			part("Pupil", Vector3.new(d, d, d) * 0.55, CFrame.new(pos + out * d * 0.1), ink, "ball")
			return
		end
		local scleraColor = if kind == "cat"
			then (if silhouette then c1 else Color3.fromHex("#FFD34D"))
			else white
		part("Eye", Vector3.new(d, d, d), CFrame.new(pos), scleraColor, "ball")
		local pupilPos = pos + out * d * 0.26
		local glowEyes = (style.glowEyes or kind == "glow") and fx
		local pupilColor = if glowEyes then accent:Lerp(WHITE, 0.2) else ink
		local pupilMat = if glowEyes then Enum.Material.Neon else Enum.Material.SmoothPlastic
		if kind == "cat" then
			part(
				"Pupil",
				Vector3.new(d * 0.22, d * 0.7, d * 0.22),
				along(pupilPos, out, Vector3.new(0, 1, 0)) * CFrame.Angles(0, 0, 0),
				ink,
				nil
			)
		else
			local ps = if kind == "cute" then 0.74 else 0.62
			part("Pupil", Vector3.new(d, d, d) * ps, CFrame.new(pupilPos), pupilColor, "ball", pupilMat)
		end
		if fx and not glowEyes then
			local hl = pupilPos + out * d * 0.2 + Vector3.new(0, d * 0.16, -d * 0.1)
			part("Highlight", Vector3.new(d, d, d) * 0.2, CFrame.new(hl), WHITE, "ball", Enum.Material.Neon)
			if kind == "cute" then
				part(
					"Highlight",
					Vector3.new(d, d, d) * 0.11,
					CFrame.new(pupilPos + out * d * 0.22 - Vector3.new(0, d * 0.14, -d * 0.08)),
					WHITE,
					"ball",
					Enum.Material.Neon
				)
			end
		end
		if kind == "sleepy" then
			-- 半分閉じたまぶた
			part(
				"Lid",
				Vector3.new(d, d, d) * 1.08,
				CFrame.new(pos + Vector3.new(0, d * 0.28, 0)) * CFrame.new(out * d * 0.04),
				c1:Lerp(INK, 0.1),
				nil,
				bodyMaterial
			)
		elseif kind == "angry" then
			-- 内側へ下がる眉
			local inward = Vector3.new(-math.sign(pos.X), 0, 0)
			local browPos = pos + Vector3.new(0, d * 0.62, 0) + out * d * 0.15
			part(
				"Brow",
				Vector3.new(d * 1.05, d * 0.22, d * 0.3),
				along(browPos, out, Vector3.new(0, 1, 0))
					* CFrame.Angles(0, 0, math.rad(22) * (if inward.X > 0 then 1 else -1)),
				ink,
				"block"
			)
		end
	end

	if eyesStyle == "big" then
		-- 一つ目
		if def.shape == "ray" then
			eye(Vector3.new(0, half.Y * 1.1, -half.Z * 0.5), Vector3.new(0, 1, -0.4), 0.5 * scale, "normal")
		else
			eye(
				Vector3.new(0, half.Y * 0.45, frontZ * 0.72),
				Vector3.new(0, 0.35, -1),
				eyeBase * 0.55,
				"normal"
			)
		end
	elseif eyesStyle ~= "none" then
		if def.shape == "ray" then
			for _, s in { 1, -1 } do
				eye(
					Vector3.new(s * half.X * 0.35, half.Y * 0.8, -half.Z * 0.55),
					Vector3.new(s * 0.4, 1, -0.3),
					0.26 * scale * (if eyesStyle == "cute" then 1.3 else 1),
					eyesStyle
				)
			end
		else
			local d = eyeBase
				* (if def.shape == "puffer" then 0.3 else 0.27)
				* (if eyesStyle == "cute" then 1.3 elseif eyesStyle == "dot" then 0.8 else 1)
			local ez = frontZ * 0.72
			local ey = half.Y * (if def.shape == "catfish" then 0.38 else 0.28)
			local ex = half.X * (if def.shape == "catfish" then 0.72 else 0.62)
			for _, s in { 1, -1 } do
				eye(Vector3.new(s * ex, ey, ez), Vector3.new(s, 0.15, -0.35), d, eyesStyle)
			end
		end
	end
	if has("third_eye") then
		local d = eyeBase * 0.24
		eye(
			Vector3.new(0, half.Y * 0.82, frontZ * 0.45),
			Vector3.new(0, 1, -0.4),
			d,
			if style.glowEyes then "glow" else "normal"
		)
	end
	if has("blush") and fx then
		for _, e in eyePositions do
			if math.abs(e.pos.X) > 0.01 then
				part(
					"Blush",
					Vector3.new(e.d * 0.75, e.d * 0.4, e.d * 0.2),
					along(e.pos + Vector3.new(0, -e.d * 0.75, -e.d * 0.05), e.out),
					PINK
				)
			end
		end
	end

	-- 口
	local mz = frontZ + 0.05 * scale
	local my = -half.Y * (if def.shape == "catfish" then 0.3 else 0.16)
	if mouthStyle == "small" then
		part(
			"Mouth",
			Vector3.new(bodySize.X * 0.34, bodySize.Y * 0.11, 0.14 * scale),
			CFrame.new(0, my, mz),
			mouthColor
		)
	elseif mouthStyle == "wide" then
		part(
			"Mouth",
			Vector3.new(bodySize.X * 0.78, bodySize.Y * 0.12, 0.18 * scale),
			CFrame.new(0, my, mz + 0.01 * scale),
			mouthColor
		)
	elseif mouthStyle == "o" then
		part(
			"Mouth",
			Vector3.new(0.26, 0.24, 0.12) * scale,
			CFrame.new(0, -half.Y * 0.12, frontZ + 0.03 * scale),
			mouthColor
		)
	elseif mouthStyle == "smile" or mouthStyle == "frown" then
		local dir = if mouthStyle == "smile" then 1 else -1
		for k = -2, 2 do
			local x = k * bodySize.X * 0.07
			local y = my + dir * (k * k) * bodySize.Y * 0.018
			part(
				"Mouth",
				Vector3.new(0.09, 0.07, 0.07) * scale * 1.2,
				CFrame.new(x, y, mz + math.abs(k) * 0.02 * scale),
				mouthColor,
				"ball"
			)
		end
	elseif mouthStyle == "open" or mouthStyle == "tongue" then
		part(
			"Mouth",
			Vector3.new(bodySize.X * 0.4, bodySize.Y * 0.26, 0.16 * scale),
			CFrame.new(0, my, mz),
			mouthColor
		)
		local tongueColor = if silhouette then c1 else RED
		if mouthStyle == "tongue" then
			-- べろりと垂れる長い舌
			part(
				"Tongue",
				Vector3.new(bodySize.X * 0.2, 0.08 * scale, 0.7 * scale),
				CFrame.new(0, my - 0.22 * scale, mz - 0.28 * scale) * CFrame.Angles(math.rad(35), 0, 0),
				tongueColor
			)
		else
			part(
				"Tongue",
				Vector3.new(bodySize.X * 0.22, bodySize.Y * 0.1, 0.1 * scale),
				CFrame.new(0, my - bodySize.Y * 0.06, mz - 0.03 * scale),
				tongueColor
			)
		end
	elseif mouthStyle == "fangs" or mouthStyle == "grin" or mouthStyle == "geta" then
		local w = bodySize.X * (if mouthStyle == "grin" then 0.72 else 0.42)
		part(
			"Mouth",
			Vector3.new(w, bodySize.Y * (if mouthStyle == "grin" then 0.3 else 0.14), 0.24 * scale),
			CFrame.new(0, my, mz + 0.03 * scale),
			mouthColor
		)
		if mouthStyle == "grin" then
			for i = 1, 5 do
				local x = (i - 3) * w * 0.18
				part(
					"Tooth",
					Vector3.new(0.08, 0.2, 0.1) * scale,
					CFrame.new(x, my + bodySize.Y * 0.12, mz - 0.06 * scale)
						* CFrame.Angles(math.rad(180), 0, 0),
					white,
					"wedge"
				)
			end
		elseif mouthStyle == "fangs" then
			for _, s in { 1, -1 } do
				part(
					"Fang",
					Vector3.new(0.08, 0.22, 0.09) * scale,
					CFrame.new(s * w * 0.3, my - bodySize.Y * 0.08, mz - 0.06 * scale)
						* CFrame.Angles(math.rad(180), 0, 0),
					white,
					"wedge"
				)
			end
		else
			-- 下駄の歯のような2本の前歯
			for _, s in { 1, -1 } do
				part(
					"Tooth",
					Vector3.new(0.12, 0.14, 0.06) * scale,
					CFrame.new(s * 0.075 * scale, my - bodySize.Y * 0.1, mz - 0.07 * scale),
					white,
					"block"
				)
			end
		end
	elseif mouthStyle == "beak" then
		part(
			"Beak",
			Vector3.new(0.22, 0.16, 0.4) * scale,
			CFrame.new(0, my + bodySize.Y * 0.05, frontZ - 0.12 * scale) * CFrame.Angles(0, math.rad(180), 0),
			GOLD,
			"wedge"
		)
	end

	-- 飾り --------------------------------------------------------------------
	local headTop = surface(half, -0.4, math.rad(88))
	local hornColor = if silhouette then c1 else HORN
	if has("horns") then
		local tipColor = if silhouette then c1 else accent:Lerp(INK, 0.35)
		local baseP = surface(half, -0.4, math.rad(82))
		local len = 0.62 * scale * math.clamp(bodySize.Y / scale, 0.6, 1.4)
		for _, s in { 1, -1 } do
			local base = Vector3.new(s * half.X * 0.32, baseP.Y * 0.92, baseP.Z)
			for k = 0, 3 do
				local t = k / 3
				local dir = Vector3.new(s * (0.35 + t * 0.35), 1, 0.25 + t * 0.4)
				local pos = base + Vector3.new(s * len * 0.3 * t * t, len * 0.85 * t, len * 0.3 * t * t)
				local w = len * 0.34 * (1 - t * 0.72)
				part(
					"Horn",
					Vector3.new(w, w, len * 0.42),
					along(pos, dir),
					hornColor:Lerp(tipColor, t * 0.8)
				)
			end
		end
	end
	if has("antlers") then
		-- 龍の枝分かれした角
		for _, s in { 1, -1 } do
			local base = Vector3.new(s * half.X * 0.3, headTop.Y * 0.95, headTop.Z)
			local tip = base + Vector3.new(s * 0.35, 0.8, 0.45) * scale
			part(
				"Antler",
				Vector3.new(0.12 * scale, 0.12 * scale, (tip - base).Magnitude),
				along((base + tip) / 2, tip - base),
				hornColor
			)
			local mid = base:Lerp(tip, 0.55)
			local branch = mid + Vector3.new(s * 0.05, 0.25, -0.25) * scale
			part(
				"Antler",
				Vector3.new(0.09 * scale, 0.09 * scale, (branch - mid).Magnitude),
				along((mid + branch) / 2, branch - mid),
				hornColor
			)
		end
	end
	if has("ears") then
		-- 猫の耳
		for _, s in { 1, -1 } do
			local base = Vector3.new(s * half.X * 0.42, headTop.Y * 0.9, headTop.Z)
			part(
				"Ear",
				Vector3.new(0.12, 0.42, 0.34) * scale,
				CFrame.new(base + Vector3.new(0, 0.15 * scale, 0))
					* CFrame.Angles(0, math.rad(180), s * math.rad(-12)),
				c1,
				"wedge",
				bodyMaterial
			)
			part(
				"EarInner",
				Vector3.new(0.13, 0.28, 0.2) * scale,
				CFrame.new(base + Vector3.new(0, 0.11 * scale, -0.05 * scale))
					* CFrame.Angles(0, math.rad(180), s * math.rad(-12)),
				if silhouette then c1 else PINK,
				"wedge"
			)
		end
	end
	if has("crown") then
		local r = bodySize.X * 0.6
		local plateColor = if silhouette then c1 else Color3.fromHex("#E8F4F8")
		part(
			"Crown",
			Vector3.new(0.08 * scale, r, r),
			CFrame.new(0, headTop.Y + 0.03, headTop.Z) * CFrame.Angles(0, 0, math.rad(90)),
			plateColor,
			"cylinder"
		)
		part(
			"CrownRim",
			Vector3.new(0.05 * scale, r * 1.14, r * 1.14),
			CFrame.new(0, headTop.Y, headTop.Z) * CFrame.Angles(0, 0, math.rad(90)),
			accent:Lerp(INK, 0.2),
			"cylinder"
		)
	end
	if has("leaf") then
		-- 化け狸の頭の葉っぱ
		local leafColor = if silhouette then c1 else Color3.fromHex("#5DA444")
		part(
			"Leaf",
			Vector3.new(0.06, 0.62, 0.36) * scale,
			CFrame.new(headTop + Vector3.new(0, 0.3 * scale, 0))
				* CFrame.Angles(math.rad(-20), 0, math.rad(15)),
			leafColor
		)
		part(
			"LeafStem",
			Vector3.new(0.05, 0.25, 0.05) * scale,
			CFrame.new(headTop + Vector3.new(0, 0.05 * scale, 0.05 * scale)),
			leafColor:Lerp(INK, 0.3),
			"block"
		)
	end
	if has("umbrella") then
		-- 唐傘: 赤い傘の屋根と、てっぺんの石突き
		local top = headTop + Vector3.new(0, 0.35 * scale, 0.1 * scale)
		local w = bodySize.X * 1.25
		part("Umbrella", Vector3.new(w, 0.32 * scale, w), CFrame.new(top), accent, nil, patternMaterial)
		part(
			"Umbrella",
			Vector3.new(w * 0.62, 0.32 * scale, w * 0.62),
			CFrame.new(top + Vector3.new(0, 0.16 * scale, 0)),
			c2,
			nil,
			patternMaterial
		)
		part(
			"UmbrellaTip",
			Vector3.new(0.14, 0.14, 0.14) * scale,
			CFrame.new(top + Vector3.new(0, 0.36 * scale, 0)),
			if silhouette then c1 else Color3.fromHex("#2B1B10"),
			"ball"
		)
		part(
			"UmbrellaPole",
			Vector3.new(0.07, 0.4, 0.07) * scale,
			CFrame.new(top - Vector3.new(0, 0.18 * scale, 0)),
			if silhouette then c1 else Color3.fromHex("#C79A4B"),
			"block"
		)
	end
	if has("hat") then
		-- 旅の笠
		local top = headTop + Vector3.new(0, 0.18 * scale, 0)
		local strawColor = if silhouette then c1 else Color3.fromHex("#C9A35C")
		part(
			"Hat",
			Vector3.new(bodySize.X * 1.5, 0.12 * scale, bodySize.X * 1.5),
			CFrame.new(top),
			strawColor
		)
		part(
			"Hat",
			Vector3.new(bodySize.X * 0.7, 0.3 * scale, bodySize.X * 0.7),
			CFrame.new(top + Vector3.new(0, 0.12 * scale, 0)),
			strawColor:Lerp(INK, 0.1)
		)
	end
	if has("okappa") then
		-- 座敷童のおかっぱ頭
		local hairColor = if silhouette then c1 else Color3.fromHex("#1C1820")
		part(
			"Hair",
			Vector3.new(bodySize.X * 1.1, bodySize.Y * 0.95, bodySize.Z * 0.4),
			CFrame.new(0, half.Y * 0.32, frontZ * 0.28),
			hairColor
		)
		part(
			"Bangs",
			Vector3.new(bodySize.X * 0.92, bodySize.Y * 0.2, bodySize.Z * 0.3),
			CFrame.new(0, half.Y * 0.74, frontZ * 0.62),
			hairColor
		)
	end
	if has("hair") then
		-- 長い黒髪(濡れ女・ろくろ首・雪女)
		local hairColor = if silhouette then c1 else (if def.c3 then accent else Color3.fromHex("#1C1820"))
		for i = 1, 4 do
			local x = (i - 2.5) * bodySize.X * 0.16
			local len = bodySize.Z * (0.7 + (i % 2) * 0.15)
			local start = Vector3.new(x, half.Y * 0.75, frontZ * 0.55)
			local dir = Vector3.new(x * 0.4, -0.18, 1)
			part(
				"Hair",
				Vector3.new(0.14 * scale, 0.1 * scale, len),
				along(start + dir.Unit * len * 0.45, dir),
				hairColor
			)
		end
	end
	if has("nose") then
		-- 天狗の長い鼻
		local noseColor = if silhouette then c1 else c1:Lerp(RED, 0.6)
		part(
			"Nose",
			Vector3.new(0.7 * scale, 0.16 * scale, 0.16 * scale),
			CFrame.new(0, half.Y * 0.05, frontZ - 0.32 * scale) * CFrame.Angles(0, math.rad(90), math.rad(-8)),
			noseColor,
			"cylinder"
		)
	end
	if has("crest") then
		-- 頭のとさか
		for i = 1, 4 do
			local p = surface(half, -0.55 + i * 0.12, math.rad(90))
			part(
				"Crest",
				Vector3.new(
					0.08 * scale,
					(0.45 - i * 0.06) * scale * math.max(1, bodySize.Y / scale),
					0.2 * scale
				),
				CFrame.new(0, p.Y + 0.12 * scale, p.Z),
				accent,
				"wedge",
				patternMaterial
			)
		end
	end
	if has("whiskers") then
		for _, s in { 1, -1 } do
			for k = 0, 1 do
				local dir = Vector3.new(s * (0.6 + k * 0.25), -0.25 - k * 0.2, -0.75 + k * 0.4)
				local len = (1.0 - k * 0.25) * scale
				part(
					"Whisker",
					Vector3.new(0.05 * scale, 0.05 * scale, len),
					along(
						Vector3.new(s * half.X * 0.35, -half.Y * 0.22, frontZ + 0.12 * scale)
							+ dir.Unit * len * 0.5,
						dir
					),
					if has("beard") then white else ink,
					nil
				)
			end
		end
	end
	if has("beard") then
		-- 長老のひげ
		part(
			"Beard",
			Vector3.new(bodySize.X * 0.35, bodySize.Y * 0.55, 0.22 * scale),
			CFrame.new(0, -half.Y * 0.7, frontZ * 0.85) * CFrame.Angles(math.rad(-15), 0, 0),
			if silhouette then c1 else WHITE
		)
	end
	if has("bell") then
		-- 猫又の首輪と鈴
		local u = if def.shape == "eel" then -0.55 else -0.4
		local r = math.sqrt(1 - u * u) * 1.06
		part(
			"Collar",
			Vector3.new(bodySize.X * r, bodySize.Y * r, 0.12 * scale),
			CFrame.new(0, 0, half.Z * u),
			if silhouette then c1 else RED
		)
		part(
			"Bell",
			Vector3.new(0.26, 0.26, 0.26) * scale,
			CFrame.new(0, -half.Y * r - 0.08 * scale, half.Z * u - 0.04 * scale),
			if silhouette then c1 else GOLD,
			"ball",
			if silhouette then nil else Enum.Material.Foil
		)
	end
	if has("shimenawa") then
		-- しめ縄と紙垂(しで)。神さまの魚の印
		local u = -0.15
		local r = math.sqrt(1 - u * u) * 1.08
		local ropeColor = if silhouette then c1 else Color3.fromHex("#D9C38A")
		part(
			"Rope",
			Vector3.new(bodySize.X * r, bodySize.Y * r, 0.2 * scale),
			CFrame.new(0, 0, half.Z * u),
			ropeColor
		)
		for _, x in { -0.35, 0, 0.35 } do
			local pos = Vector3.new(x * half.X * 1.6, -half.Y * r * 0.85, half.Z * u - 0.05 * scale)
			part(
				"Shide",
				Vector3.new(0.18, 0.4, 0.04) * scale,
				CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(x * 30)),
				if silhouette then c1 else WHITE,
				"block"
			)
		end
	end
	if has("lotus") then
		-- 頭に咲く蓮の花
		local base = headTop + Vector3.new(0, 0.1 * scale, 0)
		for i = 1, 6 do
			local a = i / 6 * math.pi * 2
			local dir = Vector3.new(math.cos(a) * 0.6, 1, math.sin(a) * 0.6)
			part(
				"Petal",
				Vector3.new(0.12, 0.2, 0.42) * scale,
				along(base + dir.Unit * 0.18 * scale, dir),
				if silhouette then c1 else PINK:Lerp(WHITE, 0.2)
			)
		end
		part(
			"LotusCenter",
			Vector3.new(0.16, 0.16, 0.16) * scale,
			CFrame.new(base + Vector3.new(0, 0.08 * scale, 0)),
			if silhouette then c1 else GOLD,
			"ball"
		)
	end
	if has("kanzashi") then
		-- かんざし: 金の棒と花と下がり飾り
		local base = headTop + Vector3.new(half.X * 0.4, 0.1 * scale, 0.1 * scale)
		part(
			"Kanzashi",
			Vector3.new(0.06, 0.06, 0.8) * scale,
			along(base, Vector3.new(0.5, 0.6, 0.4)),
			if silhouette then c1 else GOLD,
			nil,
			if silhouette then nil else Enum.Material.Foil
		)
		part(
			"KanzashiFlower",
			Vector3.new(0.28, 0.28, 0.28) * scale,
			CFrame.new(base + Vector3.new(0.12, 0.2, 0.1) * scale),
			if silhouette then c1 else accent,
			"ball"
		)
		for k = 1, 3 do
			part(
				"KanzashiBead",
				Vector3.new(0.09, 0.09, 0.09) * scale,
				CFrame.new(base + Vector3.new(0.22, 0.1 - k * 0.11, 0.12) * scale),
				if silhouette then c1 else GOLD,
				"ball"
			)
		end
	end
	if has("coin") then
		-- 額の小判
		local p, nrm = surface(half, -0.62, math.rad(60))
		local coinColor = if silhouette then c1 else GOLD
		part(
			"Coin",
			Vector3.new(0.5, 0.32, 0.06) * scale,
			along(Vector3.new(0, p.Y, p.Z), Vector3.new(0, nrm.Y, nrm.Z)),
			coinColor,
			nil,
			if silhouette then nil else Enum.Material.Foil
		)
	end
	if has("wind_bag") then
		-- 風神の風袋: 体の上にかかる布の輪
		for i = 0, 6 do
			local a = math.pi * (i / 6)
			local arcH = math.max(half.Y * 2.2, half.X * 1.1)
			local pos =
				Vector3.new(math.cos(a) * half.X * 1.6, half.Y * 0.4 + math.sin(a) * arcH, half.Z * 0.15)
			part(
				"WindBag",
				Vector3.new(0.34, 0.34, 0.5) * scale,
				CFrame.new(pos),
				if silhouette then c1 else accent,
				"ball",
				patternMaterial
			)
		end
	end
	if has("drums") then
		-- 雷神の太鼓の輪(体の後ろ)
		local center = Vector3.new(0, half.Y * 0.3, half.Z * 0.1)
		local radius = math.max(half.Y, half.Z) * 1.35
		ring(
			"Drum",
			center,
			radius,
			6,
			"YZ",
			0.42 * scale,
			if silhouette then c1 else Color3.fromHex("#B5322A"),
			Enum.Material.SmoothPlastic,
			"cylinder"
		)
		ring(
			"DrumRing",
			center,
			radius,
			18,
			"YZ",
			0.1 * scale,
			if silhouette then c1 else GOLD,
			if silhouette then Enum.Material.SmoothPlastic else Enum.Material.Foil
		)
	end
	if has("fire_wheel") then
		-- 火車の炎の車輪
		local center = Vector3.new(0, 0, half.Z * 0.2)
		ring(
			"FireWheel",
			center,
			math.max(half.Y, half.Z) * 1.25,
			14,
			"YZ",
			0.26 * scale,
			if silhouette then c1 else Color3.fromHex("#FF7A2E"),
			if fx then Enum.Material.Neon else Enum.Material.SmoothPlastic
		)
	end
	if has("sun_disc") then
		-- 八咫烏の日輪(背負った大きな円盤)
		-- 鱏は正面から見るので円盤も正面向き、ほかの形は横向き
		local r = math.max(half.Z * 0.75, half.Y)
		local sunCF = if def.shape == "ray"
			then CFrame.new(0, half.Y + r * 0.5, half.Z * 0.35) * CFrame.Angles(0, math.rad(90), 0)
			else CFrame.new(-0.05 * scale, half.Y + r * 0.55, half.Z * 0.15)
		part(
			"Sun",
			Vector3.new(0.08 * scale, r * 2, r * 2),
			sunCF,
			if silhouette then c1 else Color3.fromHex("#FF9E3D"),
			"cylinder",
			if fx then Enum.Material.Neon else Enum.Material.SmoothPlastic
		)
	end
	if has("moon") then
		-- 三日月(背中の上に弧を描く光の玉)
		for i = 0, 8 do
			local a = math.rad(-70 + i * 17.5)
			local thick = math.cos(math.rad(-70 + i * 17.5)) * 0.32 + 0.08
			local pos = Vector3.new(0, half.Y * 0.8 + math.cos(a) * half.Z * 0.9, math.sin(a) * half.Z * 0.9)
			part(
				"Moon",
				Vector3.new(thick, thick, thick) * scale * 1.2,
				CFrame.new(pos),
				if silhouette then c1 else Color3.fromHex("#F4F1C8"),
				"ball",
				if fx then Enum.Material.Neon else Enum.Material.SmoothPlastic
			)
		end
	end
	if has("orb") then
		-- 龍の宝珠(あごの下)
		local orb = part(
			"Orb",
			Vector3.new(0.5, 0.5, 0.5) * scale,
			CFrame.new(0, -half.Y * 0.95, frontZ * 0.8),
			if silhouette then c1 else Color3.fromHex("#CFF4FF"),
			"ball",
			if fx then Enum.Material.Neon else Enum.Material.SmoothPlastic
		)
		if fx then
			local l = Instance.new("PointLight")
			l.Color = Color3.fromHex("#9FE8FF")
			l.Range = 8
			l.Parent = orb
		end
	end
	if has("lantern") then
		local root = surface(half, -0.5, math.rad(90))
		local tip = Vector3.new(0, root.Y + 0.75 * scale, root.Z - 0.75 * scale)
		local rootPos = Vector3.new(0, root.Y, root.Z)
		part(
			"Stalk",
			Vector3.new(0.07 * scale, 0.07 * scale, (tip - rootPos).Magnitude),
			along((rootPos + tip) / 2, tip - rootPos),
			c1:Lerp(INK, 0.3),
			nil,
			bodyMaterial
		)
		local bulbColor = if silhouette then c1 else Color3.fromHex("#FFB547")
		local bulb = part(
			"Lantern",
			Vector3.new(0.42, 0.5, 0.42) * scale,
			CFrame.new(tip + Vector3.new(0, -0.05, -0.1) * scale),
			bulbColor,
			nil,
			if silhouette then Enum.Material.SmoothPlastic else Enum.Material.Neon
		)
		part(
			"LanternCap",
			Vector3.new(0.3, 0.08, 0.3) * scale,
			CFrame.new(tip + Vector3.new(0, 0.2, -0.1) * scale),
			ink,
			"cylinder"
		)
		if fx then
			local light = Instance.new("PointLight")
			light.Color = Color3.fromHex("#FFB547")
			light.Range = 8
			light.Brightness = 1.5
			light.Parent = bulb
		end
	end

	-- レア度の格 --------------------------------------------------------------
	if style.gold and not silhouette then
		-- 額の金の紋(伝説以上の証)
		local p, nrm = surface(half, -0.55, math.rad(72))
		if not has("coin") and not has("okappa") then
			part(
				"Kamon",
				Vector3.new(0.26, 0.26, 0.05) * scale,
				along(Vector3.new(0, p.Y, p.Z) + Vector3.new(0, 0, 0), Vector3.new(0, nrm.Y, nrm.Z)),
				GOLD,
				nil,
				Enum.Material.Foil
			)
		end
	end
	if style.halo > 0 and fx then
		-- 後光: 光の玉の輪(神話は1つ、秘伝は2つが交差)
		-- 頭の後ろに背負う(体全体を囲むと、細長い龍が小さく見えてしまうため)
		local radius = math.max(half.Y * 1.5, half.X * 1.4, 0.75 * scale)
		local center = Vector3.new(0, half.Y * 0.85 + radius * 0.35, frontZ * 0.35)
		ring("Halo", center, radius, 16, "YZ", 0.13 * scale, accent:Lerp(WHITE, 0.5), Enum.Material.Neon)
		if style.halo >= 2 then
			ring("Halo", center, radius * 0.72, 12, "YZ", 0.1 * scale, GOLD, Enum.Material.Neon)
		end
	end
	if style.orbs > 0 and fx then
		-- 周りを漂う鬼火
		for i = 1, style.orbs do
			local a = i / style.orbs * math.pi * 2 + 0.4
			local pos = Vector3.new(
				math.cos(a) * half.X * 2.4,
				half.Y * (0.6 + 0.4 * math.sin(a * 2)),
				math.sin(a) * half.Z * 1.2
			)
			local orb = part(
				"Onibi",
				Vector3.new(0.3, 0.38, 0.3) * scale,
				CFrame.new(pos),
				accent:Lerp(WHITE, 0.35),
				nil,
				Enum.Material.Neon
			)
			local l = Instance.new("PointLight")
			l.Color = accent
			l.Range = 6
			l.Parent = orb
		end
	end
	if glow and fx then
		local light = Instance.new("PointLight")
		light.Color = c2
		light.Range = 6
		light.Brightness = 0.8
		light.Parent = body
	end
	if style.light and fx then
		local light = Instance.new("PointLight")
		light.Color = accent
		light.Range = 10 * scale
		light.Brightness = 1
		light.Parent = body
	end
	if style.aura > 0 and fx then
		local pe = Instance.new("ParticleEmitter")
		pe.Name = "Aura"
		pe.Color = ColorSequence.new(accent:Lerp(WHITE, 0.3))
		pe.LightEmission = 1
		pe.Size = NumberSequence.new(0.18 * scale, 0)
		pe.Lifetime = NumberRange.new(0.8, 1.6)
		pe.Rate = style.aura
		pe.Speed = NumberRange.new(0.3, 0.9)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Parent = body
	end
	if has("flame") and fx then
		local fire = Instance.new("Fire")
		fire.Color = accent
		fire.SecondaryColor = c1
		fire.Size = 2 * scale
		fire.Heat = 2
		fire.Parent = body
	end

	-- 変異のエフェクト
	if o.mutation and fx then
		local mutColor = mutLook and (mutLook.color or mutLook.tint)
		if o.mutation == "gold" then
			local s = Instance.new("Sparkles")
			s.SparkleColor = Color3.fromHex("#FFE38A")
			s.Parent = body
		elseif o.mutation == "onibi" then
			local fire = Instance.new("Fire")
			fire.Color = Color3.fromHex("#6BE3FF")
			fire.SecondaryColor = Color3.fromHex("#1F3BFF")
			fire.Size = 3 * scale
			fire.Parent = body
		elseif mutColor then
			local pe = Instance.new("ParticleEmitter")
			pe.Color = ColorSequence.new(mutColor)
			pe.LightEmission = 0.8
			pe.Size = NumberSequence.new(0.25 * scale, 0)
			pe.Lifetime = NumberRange.new(0.6, 1.2)
			pe.Rate = 12
			pe.Speed = NumberRange.new(0.5, 1.5)
			pe.SpreadAngle = Vector2.new(180, 180)
			pe.Parent = body
		end
		if mutLook and mutLook.tag then
			model:AddTag(mutLook.tag)
		end
	end
	if o.mutation then
		model:SetAttribute("Mutation", o.mutation)
	end

	-- すべて Body に溶接
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") then
			d.Anchored = o.anchored == true
			if d ~= body then
				local w = Instance.new("WeldConstraint")
				w.Part0 = body
				w.Part1 = d
				w.Parent = d
			end
		end
	end
	return model
end

return FishBuilder
