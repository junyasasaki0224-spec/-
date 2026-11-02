--!strict
-- 妖怪魚の見た目を、6種類の体の形 + 色 + 模様 + 飾り + 変異 から組み立てる。
-- 画像やメッシュのアセットを使わないので、魚を増やす時はデータの行を足すだけでよい。
-- 魚の前方は -Z。モデルの PrimaryPart は "Body"。
--
-- デザインの方針(2版):
--   * シルエット: 胴 → 尾の付け根(細くくびれる)→ 尾びれ、の3段で「魚らしい流れ」を作る
--   * 顔: 白目 + 黒目 + ハイライト(光の点)で表情を出し、口を付けてキャラクターにする
--   * ひれ: 体色より明るい色で少し透かし、動きと軽さを出す
--   * 形ごとの個性: 鯉=二股の尾 / 鯰=平たい頭と大きな口 / 河豚=トゲ / 鰻=背びれのリボン /
--     提灯=大あごと牙 / 鱏=ひし形の翼と鞭の尾

local Types = require(script.Parent.Types)

local FishBuilder = {}

export type BuildOptions = {
	mutation: string?,
	scale: number?, -- 全体の大きさ(既定 1)
	anchored: boolean?,
	silhouette: boolean?, -- 図鑑の未発見表示
}

-- 体の形ごとの寸法(スタッド)
--   body     : 胴の大きさ
--   stalk    : 尾の付け根(胴に対する比率)と位置
--   tail     : 尾びれの形 forked(二股)/ fan(扇)/ ribbon(細長い)/ whip(鞭)
--   tailSize : 尾びれの大きさ
local SHAPES = {
	koi = {
		body = Vector3.new(0.92, 1.0, 2.1),
		stalk = 0.5,
		tail = "forked",
		tailSize = 1.0,
		dorsal = "sail",
	},
	catfish = {
		body = Vector3.new(1.1, 0.78, 2.3),
		stalk = 0.48,
		tail = "fan",
		tailSize = 0.85,
		dorsal = "small",
	},
	puffer = {
		body = Vector3.new(1.5, 1.4, 1.55),
		stalk = 0.3,
		tail = "fan",
		tailSize = 0.6,
		dorsal = "small",
	},
	eel = {
		body = Vector3.new(0.62, 0.68, 3.4),
		stalk = 0.62,
		tail = "ribbon",
		tailSize = 0.7,
		dorsal = "ribbon",
	},
	angler = {
		body = Vector3.new(1.45, 1.2, 1.75),
		stalk = 0.42,
		tail = "fan",
		tailSize = 0.75,
		dorsal = "spines",
	},
	ray = { body = Vector3.new(1.6, 0.34, 1.9), stalk = 0, tail = "whip", tailSize = 1.0, dorsal = "none" },
}

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

-- 位置 pos から dir の方向へ伸びる CFrame(パーツの Z 軸を dir に向ける)
local function along(pos: Vector3, dir: Vector3): CFrame
	if dir.Magnitude < 1e-4 then
		return CFrame.new(pos)
	end
	local d = dir.Unit
	local up = if math.abs(d.Y) > 0.95 then Vector3.new(1, 0, 0) else Vector3.new(0, 1, 0)
	return CFrame.lookAt(pos, pos + d, up)
end

function FishBuilder.build(def: Types.FishDef, opts: BuildOptions?): Model
	local o: BuildOptions = opts or ({} :: BuildOptions)
	local shape = SHAPES[def.shape] or SHAPES.koi
	local scale = (o.scale or 1) * (def.size or 1)
	local rng = Random.new(hashString(def.id))
	local mutLook = if o.mutation then MUTATION_LOOK[o.mutation] else nil
	local deco = def.deco
	local has = function(name: string): boolean
		return table.find(deco, name) ~= nil
	end

	-- 色
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
	local mouthColor = c1:Lerp(INK, 0.7)
	local white, ink = WHITE, INK
	local silhouette = o.silhouette == true
	if silhouette then
		c1 = Color3.fromRGB(18, 20, 32)
		c2, accent, finColor, mouthColor, white, ink = c1, c1, c1, c1, c1, c1
		bodyMaterial = Enum.Material.SmoothPlastic
		patternMaterial = bodyMaterial
	end
	local finAlpha = if silhouette or bodyMaterial == Enum.Material.Glass then 0 else 0.12

	local model = Instance.new("Model")
	model.Name = def.id

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
	local function fin(name: string, size: Vector3, cf: CFrame, color: Color3?): BasePart
		local f = part(name, size, cf, color or finColor, nil, patternMaterial)
		f.Transparency = finAlpha
		return f
	end

	-- 胴 ------------------------------------------------------------------
	local bodySize = shape.body * scale
	local half = bodySize / 2
	local body = part("Body", bodySize, CFrame.new(), c1, nil, bodyMaterial)
	if mutLook and mutLook.reflectance then
		body.Reflectance = mutLook.reflectance
	end
	if mutLook and mutLook.transparency then
		body.Transparency = mutLook.transparency
	end
	model.PrimaryPart = body

	-- 頭の形(鯰は平たく広い頭、提灯は大きな頭、鰻は少し太い頭)
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

	-- 尾の付け根(くびれ)
	local tailZ = half.Z
	if shape.stalk > 0 then
		local stalkLen = bodySize.Z * (if def.shape == "eel" then 0.55 else 0.42)
		local stalkSize = Vector3.new(bodySize.X * shape.stalk, bodySize.Y * shape.stalk * 1.05, stalkLen)
		local stalkZ = half.Z * 0.78
		part("Stalk", stalkSize, CFrame.new(0, 0, stalkZ), c1, nil, bodyMaterial)
		tailZ = stalkZ + stalkLen * 0.46
	end

	-- 模様(胴の上に重ねる)
	if def.pattern == "belly" then
		part(
			"Belly",
			Vector3.new(bodySize.X * 0.94, bodySize.Y * 0.6, bodySize.Z * 0.9),
			CFrame.new(0, -half.Y * 0.38, 0),
			c2,
			nil,
			patternMaterial
		)
	elseif def.pattern == "stripes" then
		local count = if def.shape == "eel" then 5 else 3
		for i = 1, count do
			local u = -0.5 + (i - 1) * (1.0 / math.max(1, count - 1)) * 0.9
			local r = math.sqrt(1 - u * u) * 1.035
			part(
				"Stripe",
				Vector3.new(bodySize.X * r, bodySize.Y * r, bodySize.Z * 0.08),
				CFrame.new(0, 0, half.Z * u),
				c2,
				nil,
				patternMaterial
			)
		end
	elseif def.pattern == "spots" then
		local n = if def.shape == "eel" then 9 else 7
		for _ = 1, n do
			local u = rng:NextNumber(-0.55, 0.6)
			local phi = rng:NextNumber(math.rad(30), math.rad(150))
			local side = if rng:NextInteger(0, 1) == 0 then 1 else -1
			local p, nrm = surface(half, u, phi)
			p = Vector3.new(p.X * side, p.Y, p.Z)
			nrm = Vector3.new(nrm.X * side, nrm.Y, nrm.Z)
			local d = math.min(bodySize.X, bodySize.Y) * rng:NextNumber(0.2, 0.32)
			part(
				"Spot",
				Vector3.new(d, d, d * 0.35),
				along(p - nrm * d * 0.06, nrm),
				c2,
				nil,
				patternMaterial
			)
		end
	end
	-- 背中の濃い色(上から光が当たっても立体感が出る)
	if not silhouette and def.pattern ~= "stripes" then
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
	local longTail = has("long_tail")
	if shape.tail == "forked" or (longTail and shape.tail ~= "whip") then
		-- 二股の尾(長い尾は猫又・九尾のように大きく流れる)
		local len = ts * (if longTail then 1.5 else 0.95)
		for _, s in { 1, -1 } do
			local dir = Vector3.new(0, s * 0.55, 1)
			local cf = along(Vector3.new(0, s * len * 0.22, tailZ + len * 0.38), dir)
			fin("Tail", Vector3.new(0.07 * scale, len * 0.42, len * 0.85), cf)
		end
		if longTail then
			-- 3本目(九尾らしさ)
			fin(
				"Tail",
				Vector3.new(0.07 * scale, ts * 0.4, ts * 1.2),
				along(Vector3.new(0, 0, tailZ + ts * 0.55), Vector3.new(0, 0, 1)),
				accent
			)
		end
	elseif shape.tail == "fan" then
		fin("Tail", Vector3.new(0.07 * scale, ts * 0.95, ts * 0.75), CFrame.new(0, 0, tailZ + ts * 0.3))
	elseif shape.tail == "ribbon" then
		fin("Tail", Vector3.new(0.06 * scale, ts * 0.55, ts * 0.9), CFrame.new(0, 0, tailZ + ts * 0.32))
	elseif shape.tail == "whip" then
		-- 鱏の鞭のような尾と先端のトゲ
		local len = bodySize.Z * 0.95
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

	-- 背びれ ------------------------------------------------------------------
	if shape.dorsal == "sail" then
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
		-- 鰻: 背中から尾まで続くひれ
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

	-- 胸びれ・腹びれ
	if def.shape == "ray" then
		-- 鱏はひし形の大きな翼
		for _, s in { 1, -1 } do
			part(
				"Wing",
				Vector3.new(bodySize.X * 1.5, bodySize.Y * 0.6, bodySize.Z * 0.95),
				CFrame.new(s * half.X * 1.25, -half.Y * 0.05, half.Z * 0.02)
					* CFrame.Angles(0, s * math.rad(-24), s * math.rad(-5)),
				c1,
				nil,
				bodyMaterial
			)
			-- 翼の縁(模様の色)と、翼の先のとがり
			fin(
				"WingEdge",
				Vector3.new(bodySize.X * 0.7, bodySize.Y * 0.5, bodySize.Z * 0.42),
				CFrame.new(s * half.X * 2.05, -half.Y * 0.04, half.Z * 0.22)
					* CFrame.Angles(0, s * math.rad(-38), 0),
				c2
			)
		end
	else
		for _, s in { 1, -1 } do
			fin(
				"PecFin",
				Vector3.new(bodySize.X * 0.42, 0.06 * scale, bodySize.Z * 0.24),
				CFrame.new(s * half.X * 0.95, -half.Y * 0.28, -half.Z * 0.18)
					* CFrame.Angles(math.rad(-10), s * math.rad(-25), s * math.rad(28))
			)
			if def.shape ~= "eel" and def.shape ~= "puffer" then
				fin(
					"PelvicFin",
					Vector3.new(bodySize.X * 0.22, 0.05 * scale, bodySize.Z * 0.16),
					CFrame.new(s * half.X * 0.4, -half.Y * 0.9, half.Z * 0.2)
						* CFrame.Angles(0, 0, s * math.rad(40))
				)
			end
		end
	end

	-- 河豚のトゲ
	if def.shape == "puffer" then
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
	local noface = has("noface")
	local frontZ = -half.Z
	if def.shape == "catfish" then
		frontZ = -half.Z * 0.58 - bodySize.Z * 0.45 / 2
	elseif def.shape == "angler" then
		frontZ = -half.Z * 0.42 - bodySize.Z * 0.62 / 2
	elseif def.shape == "eel" then
		frontZ = -half.Z * 0.72 - bodySize.Z * 0.32 / 2
	end
	local eyeBase = math.min(bodySize.X, bodySize.Y)

	local function eye(pos: Vector3, outward: Vector3, d: number)
		part("Eye", Vector3.new(d, d, d), CFrame.new(pos), white, "ball")
		local pupilPos = pos + outward.Unit * d * 0.26
		part("Pupil", Vector3.new(d, d, d) * 0.62, CFrame.new(pupilPos), ink, "ball")
		if not silhouette then
			-- 光の点(これがあると生き物らしい表情になる)
			local hl = pupilPos + outward.Unit * d * 0.2 + Vector3.new(0, d * 0.16, -d * 0.1)
			part("Highlight", Vector3.new(d, d, d) * 0.2, CFrame.new(hl), WHITE, "ball", Enum.Material.Neon)
		end
	end

	if not noface then
		if def.shape == "ray" then
			-- 鱏は背中側に目
			for _, s in { 1, -1 } do
				local d = 0.26 * scale
				eye(
					Vector3.new(s * half.X * 0.35, half.Y * 0.8, -half.Z * 0.55),
					Vector3.new(s * 0.4, 1, -0.3),
					d
				)
			end
		elseif has("big_eye") then
			local d = eyeBase * 0.55
			eye(Vector3.new(0, half.Y * 0.45, frontZ * 0.72), Vector3.new(0, 0.35, -1), d)
		else
			local d = eyeBase * (if def.shape == "puffer" then 0.3 else 0.27)
			local ez = frontZ * 0.72
			local ey = half.Y * (if def.shape == "catfish" then 0.38 else 0.28)
			local ex = half.X * (if def.shape == "catfish" then 0.72 else 0.62)
			for _, s in { 1, -1 } do
				eye(Vector3.new(s * ex, ey, ez), Vector3.new(s, 0.15, -0.35), d)
			end
		end
		if has("third_eye") then
			local d = eyeBase * 0.24
			eye(Vector3.new(0, half.Y * 0.82, frontZ * 0.45), Vector3.new(0, 1, -0.4), d)
		end

		-- 口
		if def.shape == "angler" then
			-- 大きなあごと牙
			local jawW = bodySize.X * 0.72
			part(
				"Mouth",
				Vector3.new(jawW, bodySize.Y * 0.3, 0.3 * scale),
				CFrame.new(0, -half.Y * 0.18, frontZ + 0.08 * scale),
				mouthColor
			)
			for i = 1, 5 do
				local x = (i - 3) * jawW * 0.18
				part(
					"Tooth",
					Vector3.new(0.08, 0.2, 0.1) * scale,
					CFrame.new(x, -half.Y * 0.06, frontZ - 0.02 * scale) * CFrame.Angles(math.rad(180), 0, 0),
					white,
					"wedge"
				)
			end
		elseif def.shape == "catfish" then
			part(
				"Mouth",
				Vector3.new(bodySize.X * 0.78, bodySize.Y * 0.12, 0.18 * scale),
				CFrame.new(0, -half.Y * 0.3, frontZ + 0.06 * scale),
				mouthColor
			)
		elseif def.shape == "puffer" then
			part(
				"Mouth",
				Vector3.new(0.26, 0.2, 0.12) * scale,
				CFrame.new(0, -half.Y * 0.12, frontZ + 0.03 * scale),
				mouthColor
			)
		elseif def.shape ~= "ray" then
			part(
				"Mouth",
				Vector3.new(bodySize.X * 0.34, bodySize.Y * 0.11, 0.14 * scale),
				CFrame.new(0, -half.Y * 0.16, frontZ + 0.05 * scale),
				mouthColor
			)
		end
	end

	-- 飾り --------------------------------------------------------------------
	if has("horns") then
		-- 鬼の角: 細長い楕円を4つ重ねて、外へ反りながら細くなる円錐にする
		local hornColor = if silhouette then c1 else HORN
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
	if has("crown") then
		-- 河童の皿: 縁つきの白い円盤
		local top = surface(half, -0.3, math.rad(90))
		local r = bodySize.X * 0.6
		local plateColor = if silhouette then c1 else Color3.fromHex("#E8F4F8")
		part(
			"Crown",
			Vector3.new(0.08 * scale, r, r),
			CFrame.new(0, top.Y + 0.03, top.Z) * CFrame.Angles(0, 0, math.rad(90)),
			plateColor,
			"cylinder"
		)
		part(
			"CrownRim",
			Vector3.new(0.05 * scale, r * 1.14, r * 1.14),
			CFrame.new(0, top.Y, top.Z) * CFrame.Angles(0, 0, math.rad(90)),
			accent:Lerp(INK, 0.2),
			"cylinder"
		)
	end
	if has("whiskers") then
		for _, s in { 1, -1 } do
			for k = 0, 1 do
				local dir = Vector3.new(s * (0.6 + k * 0.25), -0.25 - k * 0.2, -0.75 + k * 0.4)
				local len = (1.0 - k * 0.25) * scale
				part(
					"Whisker",
					Vector3.new(0.05, 0.05, len) * scale,
					along(
						Vector3.new(s * half.X * 0.35, -half.Y * 0.22, frontZ + 0.12 * scale)
							+ dir.Unit * len * 0.5,
						dir
					),
					ink,
					nil
				)
			end
		end
	end
	if has("lantern") then
		local root, _ = surface(half, -0.5, math.rad(90))
		local tip = Vector3.new(0, root.Y + 0.75 * scale, root.Z - 0.75 * scale)
		local mid = (Vector3.new(0, root.Y, root.Z) + tip) / 2
		part(
			"Stalk",
			Vector3.new(0.07 * scale, 0.07 * scale, (tip - Vector3.new(0, root.Y, root.Z)).Magnitude),
			along(mid, tip - Vector3.new(0, root.Y, root.Z)),
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
		-- 提灯の上下の枠
		part(
			"LanternCap",
			Vector3.new(0.3, 0.08, 0.3) * scale,
			CFrame.new(tip + Vector3.new(0, 0.2, -0.1) * scale),
			ink,
			"cylinder"
		)
		if not silhouette then
			local light = Instance.new("PointLight")
			light.Color = Color3.fromHex("#FFB547")
			light.Range = 8
			light.Brightness = 1.5
			light.Parent = bulb
		end
	end
	if glow and not silhouette then
		local light = Instance.new("PointLight")
		light.Color = c2
		light.Range = 6
		light.Brightness = 0.8
		light.Parent = body
	end
	if has("flame") and not silhouette then
		local fire = Instance.new("Fire")
		fire.Color = accent
		fire.SecondaryColor = c1
		fire.Size = 2 * scale
		fire.Heat = 2
		fire.Parent = body
	end

	-- 変異のエフェクト
	if o.mutation and not silhouette then
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
