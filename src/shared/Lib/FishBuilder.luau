--!strict
-- 妖怪魚の見た目を、6種類の体の形 + 色 + 模様 + 飾り + 変異 から組み立てる。
-- 画像やメッシュのアセットを使わないので、魚を増やす時はデータの行を足すだけでよい。
-- 魚の前方は -Z。モデルの PrimaryPart は "Body"。

local Types = require(script.Parent.Types)

local FishBuilder = {}

export type BuildOptions = {
	mutation: string?,
	scale: number?, -- 全体の大きさ(既定 1)
	anchored: boolean?,
	silhouette: boolean?, -- 図鑑の未発見表示
}

-- 体の形ごとの基本寸法(スタッド)
local SHAPES = {
	koi = { body = Vector3.new(0.9, 1.0, 2.2), tail = 0.9, fin = true },
	catfish = { body = Vector3.new(1.15, 0.8, 2.4), tail = 0.7, fin = false },
	puffer = { body = Vector3.new(1.5, 1.4, 1.6), tail = 0.55, fin = true },
	eel = { body = Vector3.new(0.5, 0.55, 3.6), tail = 0.45, fin = false },
	angler = { body = Vector3.new(1.4, 1.2, 1.8), tail = 0.7, fin = true },
	ray = { body = Vector3.new(2.6, 0.35, 2.0), tail = 0.3, fin = false },
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

local function hashString(s: string): number
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + string.byte(s, i)) % 2147483647
	end
	return h
end

local function makePart(
	model: Model,
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	sphere: boolean,
	material: Enum.Material?
): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
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
	if sphere then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	p.Parent = model
	return p
end

local function makeWedge(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3): BasePart
	local p = Instance.new("WedgePart")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.Parent = model
	return p
end

local function lerpColor(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, t)
end

-- 楕円体の表面の点(u: 前後 -1..1, phi: 周方向)
local function surfacePoint(half: Vector3, u: number, phi: number): Vector3
	local r = math.sqrt(math.max(0, 1 - u * u))
	return Vector3.new(half.X * r * math.cos(phi), half.Y * r * math.sin(phi), half.Z * u)
end

function FishBuilder.build(def: Types.FishDef, opts: BuildOptions?): Model
	local o: BuildOptions = opts or ({} :: BuildOptions)
	local shape = SHAPES[def.shape] or SHAPES.koi
	local scale = (o.scale or 1) * (def.size or 1)
	local rng = Random.new(hashString(def.id))
	local mutLook = if o.mutation then MUTATION_LOOK[o.mutation] else nil

	local c1 = Color3.fromHex(def.c1)
	local c2 = Color3.fromHex(def.c2)
	local bodyMaterial = Enum.Material.SmoothPlastic
	local patternMaterial = Enum.Material.SmoothPlastic
	if mutLook then
		if mutLook.color then
			c1 = mutLook.color
			c2 = lerpColor(mutLook.color, Color3.new(1, 1, 1), 0.35)
		elseif mutLook.tint then
			c1 = lerpColor(c1, mutLook.tint, 0.55)
			c2 = lerpColor(c2, mutLook.tint, 0.35)
		end
		if mutLook.material then
			bodyMaterial = mutLook.material
			patternMaterial = mutLook.material
		end
		if mutLook.neonPattern then
			patternMaterial = Enum.Material.Neon
		end
	end
	local glow = table.find(def.deco, "glow") ~= nil
	if glow then
		patternMaterial = Enum.Material.Neon
	end
	if o.silhouette then
		c1 = Color3.fromRGB(18, 20, 32)
		c2 = c1
		bodyMaterial = Enum.Material.SmoothPlastic
		patternMaterial = bodyMaterial
	end

	local model = Instance.new("Model")
	model.Name = def.id

	local bodySize = shape.body * scale
	local half = bodySize / 2
	local body = makePart(model, "Body", bodySize, CFrame.new(), c1, true, bodyMaterial)
	if mutLook and mutLook.reflectance then
		body.Reflectance = mutLook.reflectance
	end
	if mutLook and mutLook.transparency then
		body.Transparency = mutLook.transparency
	end
	model.PrimaryPart = body

	-- 模様
	if def.pattern == "belly" then
		makePart(
			model,
			"Belly",
			Vector3.new(bodySize.X * 0.92, bodySize.Y * 0.62, bodySize.Z * 0.9),
			CFrame.new(0, -half.Y * 0.36, 0),
			c2,
			true,
			patternMaterial
		)
	elseif def.pattern == "stripes" then
		for i = 1, 3 do
			local u = -0.45 + (i - 1) * 0.4
			local r = math.sqrt(1 - u * u) * 1.04
			makePart(
				model,
				"Stripe",
				Vector3.new(bodySize.X * r, bodySize.Y * r, bodySize.Z * 0.09),
				CFrame.new(0, 0, half.Z * u),
				c2,
				true,
				patternMaterial
			)
		end
	elseif def.pattern == "spots" then
		for _ = 1, 7 do
			local u = rng:NextNumber(-0.65, 0.65)
			local phi = rng:NextNumber(math.rad(25), math.rad(155))
			local side = if rng:NextInteger(0, 1) == 0 then 1 else -1
			local p = surfacePoint(half, u, phi)
			local d = math.min(bodySize.X, bodySize.Y) * rng:NextNumber(0.18, 0.3)
			makePart(
				model,
				"Spot",
				Vector3.new(d, d, d),
				CFrame.new(p.X * side * 0.97, p.Y * 0.97, p.Z),
				c2,
				true,
				patternMaterial
			)
		end
	end

	-- 尾びれ(後ろ = +Z)
	local tailLen = shape.tail * scale
	local longTail = table.find(def.deco, "long_tail") ~= nil
	if def.shape == "ray" then
		makePart(
			model,
			"Tail",
			Vector3.new(0.12 * scale, 0.12 * scale, bodySize.Z * 1.1),
			CFrame.new(0, 0, half.Z + bodySize.Z * 0.5),
			c2,
			false
		)
	else
		local lobes = if longTail then 2 else 1
		for i = 1, lobes do
			local spread = if lobes == 1 then 0 else (i == 1 and 0.35 or -0.35)
			local len = tailLen * (if longTail then 1.9 else 1)
			local cf = CFrame.new(0, spread * tailLen * 0.6, half.Z + len * 0.42)
				* CFrame.Angles(spread, 0, 0)
			makePart(
				model,
				"Tail",
				Vector3.new(0.1 * scale, tailLen * 1.1, len),
				cf,
				c2,
				true,
				patternMaterial
			)
		end
	end

	-- 背びれ
	if shape.fin then
		makePart(
			model,
			"Fin",
			Vector3.new(0.08 * scale, bodySize.Y * 0.45, bodySize.Z * 0.45),
			CFrame.new(0, half.Y * 0.95, half.Z * 0.05),
			c2,
			true,
			patternMaterial
		)
	end
	-- 胸びれ
	for _, side in { 1, -1 } do
		makePart(
			model,
			"PecFin",
			Vector3.new(bodySize.X * 0.35, 0.06 * scale, bodySize.Z * 0.22),
			CFrame.new(side * half.X * 0.9, -half.Y * 0.25, -half.Z * 0.2) * CFrame.Angles(0, 0, side * 0.5),
			c2,
			true
		)
	end

	-- 目
	local white = if o.silhouette then c1 else Color3.fromRGB(250, 248, 240)
	local black = if o.silhouette then c1 else Color3.fromRGB(15, 12, 20)
	local function eye(pos: Vector3, d: number)
		makePart(model, "Eye", Vector3.new(d, d, d), CFrame.new(pos), white, true)
		local outward = Vector3.new(pos.X, pos.Y * 0.3, pos.Z)
		local dir = if outward.Magnitude > 0 then outward.Unit else Vector3.new(0, 0, -1)
		makePart(model, "Pupil", Vector3.new(d, d, d) * 0.55, CFrame.new(pos + dir * d * 0.28), black, true)
	end
	if not table.find(def.deco, "noface") then
		local eyeD = math.min(bodySize.X, bodySize.Y) * 0.28
		if table.find(def.deco, "big_eye") then
			local p = surfacePoint(half, -0.62, math.rad(70))
			eye(Vector3.new(0, p.Y * 0.85, p.Z), eyeD * 1.9)
		else
			local p = surfacePoint(half, -0.68, math.rad(35))
			for _, side in { 1, -1 } do
				eye(Vector3.new(p.X * side * 0.95, p.Y, p.Z), eyeD)
			end
		end
		if table.find(def.deco, "third_eye") then
			local p = surfacePoint(half, -0.45, math.rad(85))
			eye(Vector3.new(0, p.Y * 0.98, p.Z), eyeD * 0.9)
		end
	end

	-- 飾り
	if table.find(def.deco, "horns") then
		for _, side in { 1, -1 } do
			local p = surfacePoint(half, -0.45, math.rad(75))
			makeWedge(
				model,
				"Horn",
				Vector3.new(0.12 * scale, 0.55 * scale, 0.3 * scale),
				CFrame.new(side * half.X * 0.35, p.Y + 0.2 * scale, p.Z) * CFrame.Angles(0, 0, -side * 0.35),
				if o.silhouette then c1 else Color3.fromHex("#F2E6C9")
			)
		end
	end
	if table.find(def.deco, "crown") then
		local p = surfacePoint(half, -0.3, math.rad(90))
		local disc = makePart(
			model,
			"Crown",
			Vector3.new(0.08 * scale, bodySize.X * 0.55, bodySize.X * 0.55),
			CFrame.new(0, p.Y + 0.02, p.Z) * CFrame.Angles(0, 0, math.rad(90)),
			if o.silhouette then c1 else Color3.fromHex("#E8F4F8"),
			false
		)
		local discPart = disc :: Part
		discPart.Shape = Enum.PartType.Cylinder
	end
	if table.find(def.deco, "whiskers") then
		for _, side in { 1, -1 } do
			makePart(
				model,
				"Whisker",
				Vector3.new(0.05 * scale, 0.05 * scale, 1.1 * scale),
				CFrame.new(side * half.X * 0.45, -half.Y * 0.25, -half.Z - 0.25 * scale)
					* CFrame.Angles(0.25, side * 0.6, 0),
				black,
				false
			)
		end
	end
	if table.find(def.deco, "lantern") then
		local stalkBase = surfacePoint(half, -0.55, math.rad(90))
		makePart(
			model,
			"Stalk",
			Vector3.new(0.06 * scale, 0.06 * scale, 0.9 * scale),
			CFrame.new(0, stalkBase.Y + 0.35 * scale, stalkBase.Z - 0.3 * scale)
				* CFrame.Angles(math.rad(-50), 0, 0),
			c1,
			false
		)
		local bulb = makePart(
			model,
			"Lantern",
			Vector3.new(0.38, 0.45, 0.38) * scale,
			CFrame.new(0, stalkBase.Y + 0.7 * scale, stalkBase.Z - 0.75 * scale),
			if o.silhouette then c1 else Color3.fromHex("#FFB547"),
			true,
			if o.silhouette then Enum.Material.SmoothPlastic else Enum.Material.Neon
		)
		if not o.silhouette then
			local light = Instance.new("PointLight")
			light.Color = Color3.fromHex("#FFB547")
			light.Range = 8
			light.Brightness = 1.5
			light.Parent = bulb
		end
	end
	if glow and not o.silhouette then
		local light = Instance.new("PointLight")
		light.Color = c2
		light.Range = 6
		light.Brightness = 0.8
		light.Parent = body
	end
	if table.find(def.deco, "flame") and not o.silhouette then
		local fire = Instance.new("Fire")
		fire.Color = c2
		fire.SecondaryColor = c1
		fire.Size = 2 * scale
		fire.Heat = 2
		fire.Parent = body
	end

	-- 変異のエフェクト
	if o.mutation and not o.silhouette then
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
