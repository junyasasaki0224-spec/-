--!strict
-- 景色の部品: 山の見えない壁・杉・竹林・神木・お地蔵さま・枯れ木・小舟・五重塔・提灯の列・見物台・山の森・滝しぶき。
-- どれもパーツ数を抑えて作る(スマホでも軽く)。
local CollectionService = game:GetService("CollectionService")

local Build = require(script.Parent.Build)
local Terrain = require(script.Parent.Terrain)

local M = {}

local CEDAR = Color3.fromRGB(38, 72, 48)
local CEDAR_DARK = Color3.fromRGB(28, 56, 40)
local BARK = Color3.fromRGB(86, 58, 42)
local STONE = Color3.fromRGB(150, 150, 140)
local ROPE = Color3.fromRGB(214, 190, 140)
local WOOD = Color3.fromRGB(122, 86, 56)
local DARK_WOOD = Color3.fromRGB(70, 50, 36)

local function upright(pos: Vector3, h: number, tilt: Vector2?): CFrame
	-- Roblox の円柱は X 軸が長さなので、立てるには Z 軸まわりに 90 度回す
	local t = tilt or Vector2.zero
	return CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(t.X, 0, math.rad(90) + t.Y)
end

local function rod(
	parent: Instance,
	a: Vector3,
	b: Vector3,
	thick: number,
	color: Color3,
	material: Enum.Material?,
	name: string?
): BasePart
	local mid = (a + b) / 2
	local len = (b - a).Magnitude
	-- 円柱の長さの向き(X 軸)を a → b に合わせる
	local cf = CFrame.lookAt(mid, b) * CFrame.Angles(0, math.rad(90), 0)
	return Build.part({
		name = name or "Rod",
		size = Vector3.new(len, thick, thick),
		cframe = cf,
		color = color,
		material = material or Enum.Material.Wood,
		shape = Enum.PartType.Cylinder,
		collide = false,
		parent = parent,
	})
end
M.rod = rod

-- 山の手前の見えない壁(地形の外へ歩いて落ちないように)。カメラや当たり判定の調べには引っかからない
function M.boundary(parent: Instance, center: Vector3, radius: number, height: number)
	local folder = Build.folder("Boundary", parent)
	local n = 36
	local seg = 2 * math.pi * radius / n + 2
	for i = 0, n - 1 do
		local a = (i + 0.5) / n * math.pi * 2
		local pos = center + Vector3.new(math.cos(a) * radius, height / 2 - 10, math.sin(a) * radius)
		local wall = Build.part({
			name = "Wall",
			size = Vector3.new(seg, height, 2),
			cframe = CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z)),
			transparency = 1,
			collide = true,
			parent = folder,
		})
		wall.CanQuery = false
		wall.CanTouch = false
		wall.CastShadow = false
	end
	return folder
end

-- 杉(細い幹に、上ほど小さい3段の葉。遠くからも針葉樹の形に見える)
function M.cedar(parent: Instance, pos: Vector3, rng: Random, scale: number?)
	local s = (scale or 1) * rng:NextNumber(0.85, 1.2)
	local h = 18 * s
	Build.part({
		name = "CedarTrunk",
		size = Vector3.new(h, 1.3 * s, 1.3 * s),
		cframe = upright(pos, h),
		color = BARK,
		material = Enum.Material.Wood,
		shape = Enum.PartType.Cylinder,
		parent = parent,
	})
	local leaf = if rng:NextNumber() < 0.5 then CEDAR else CEDAR_DARK
	for k, spec in { { 0.42, 7.5, 8 }, { 0.66, 5.6, 7 }, { 0.88, 3.4, 5.5 } } do
		local w = spec[2] * s
		Build.part({
			name = "CedarLeaves",
			size = Vector3.new(w, spec[3] * s, w),
			cframe = CFrame.new(pos + Vector3.new(rng:NextNumber(-0.4, 0.4), h * spec[1] + (k - 1) * 0.6, 0)),
			color = leaf,
			material = Enum.Material.LeafyGrass,
			shape = Enum.PartType.Ball,
			collide = false,
			parent = parent,
		})
	end
end

-- 竹林(ひとかたまり)
function M.bamboo(parent: Instance, pos: Vector3, rng: Random)
	local n = rng:NextInteger(7, 10)
	for _ = 1, n do
		local h = rng:NextNumber(15, 24)
		local off = Vector3.new(rng:NextNumber(-3.5, 3.5), -0.5, rng:NextNumber(-3.5, 3.5))
		local green = Color3.fromRGB(118 + rng:NextInteger(0, 30), 160 + rng:NextInteger(0, 25), 78)
		Build.part({
			name = "Bamboo",
			size = Vector3.new(h, 0.45, 0.45),
			cframe = upright(
				pos + off,
				h,
				Vector2.new(rng:NextNumber(-0.05, 0.05), rng:NextNumber(-0.06, 0.06))
			),
			color = green,
			material = Enum.Material.SmoothPlastic,
			shape = Enum.PartType.Cylinder,
			collide = false,
			parent = parent,
		})
	end
	for _ = 1, 3 do
		Build.part({
			name = "BambooLeaves",
			size = Vector3.new(rng:NextNumber(5, 8), rng:NextNumber(1.6, 2.6), rng:NextNumber(5, 8)),
			cframe = CFrame.new(
				pos + Vector3.new(rng:NextNumber(-3, 3), rng:NextNumber(13, 20), rng:NextNumber(-3, 3))
			),
			color = Color3.fromRGB(122, 168, 82),
			material = Enum.Material.LeafyGrass,
			shape = Enum.PartType.Ball,
			collide = false,
			parent = parent,
		})
	end
end

-- 神木: 太い幹にしめ縄と紙垂、まわりに石の玉垣。釣り場の目印になる大樹
function M.sacredTree(parent: Instance, pos: Vector3)
	local model = Instance.new("Model")
	model.Name = "Shinboku"
	local h = 26
	Build.part({
		name = "Trunk",
		size = Vector3.new(h, 5, 5),
		cframe = upright(pos, h),
		color = Color3.fromRGB(92, 66, 48),
		material = Enum.Material.Wood,
		shape = Enum.PartType.Cylinder,
		parent = model,
	})
	Build.part({
		name = "Roots",
		size = Vector3.new(9, 3.2, 9),
		cframe = CFrame.new(pos + Vector3.new(0, 0.6, 0)),
		color = Color3.fromRGB(86, 62, 46),
		material = Enum.Material.Wood,
		shape = Enum.PartType.Ball,
		parent = model,
	})
	local canopy: { { at: Vector3, size: number } } = {
		{ at = Vector3.new(0, 27, 0), size = 18 },
		{ at = Vector3.new(6, 24, 3), size = 13 },
		{ at = Vector3.new(-6, 24, -2), size = 13 },
		{ at = Vector3.new(2, 23, -7), size = 12 },
		{ at = Vector3.new(-3, 23, 7), size = 12 },
		{ at = Vector3.new(0, 31, 0), size = 11 },
	}
	for i, c in canopy do
		Build.part({
			name = "Canopy",
			size = Vector3.new(c.size, c.size * 0.62, c.size),
			cframe = CFrame.new(pos + c.at),
			color = if i % 2 == 0 then Color3.fromRGB(46, 92, 52) else Color3.fromRGB(58, 106, 58),
			material = Enum.Material.LeafyGrass,
			shape = Enum.PartType.Ball,
			collide = false,
			parent = model,
		})
	end
	-- しめ縄(幹を一周)と紙垂
	local ropeY, r = 7, 2.85
	local n = 12
	for i = 0, n - 1 do
		local a1, a2 = i / n * math.pi * 2, (i + 1) / n * math.pi * 2
		local p1 = pos + Vector3.new(math.cos(a1) * r, ropeY + math.sin(a1 * 2) * 0.15, math.sin(a1) * r)
		local p2 = pos + Vector3.new(math.cos(a2) * r, ropeY + math.sin(a2 * 2) * 0.15, math.sin(a2) * r)
		rod(model, p1, p2, 0.7, ROPE, Enum.Material.Fabric, "Shimenawa")
	end
	for i = 0, 3 do
		local a = (i / 4) * math.pi * 2 + 0.4
		local p = pos + Vector3.new(math.cos(a) * (r + 0.35), ropeY - 1.1, math.sin(a) * (r + 0.35))
		Build.part({
			name = "Shide",
			size = Vector3.new(0.7, 1.6, 0.08),
			cframe = CFrame.lookAt(p, p + Vector3.new(math.cos(a), 0, math.sin(a)))
				* CFrame.Angles(0, 0, math.rad(8)),
			color = Color3.new(1, 1, 1),
			material = Enum.Material.Fabric,
			collide = false,
			parent = model,
		})
	end
	-- 玉垣(石の柱の囲い)
	for i = 0, 9 do
		local a = (i / 10) * math.pi * 2
		Build.part({
			name = "Tamagaki",
			size = Vector3.new(0.7, 2.2, 0.7),
			cframe = CFrame.new(pos + Vector3.new(math.cos(a) * 7.5, 1.1, math.sin(a) * 7.5)),
			color = STONE,
			material = Enum.Material.Slate,
			parent = model,
		})
	end
	model.Parent = parent
	return model
end

-- お地蔵さま(赤い前掛けと帽子)
function M.jizo(parent: Instance, cf: CFrame)
	local model = Instance.new("Model")
	model.Name = "Jizo"
	local grey = Color3.fromRGB(140, 140, 132)
	local red = Color3.fromRGB(200, 40, 36)
	Build.part({
		name = "Base",
		size = Vector3.new(1.8, 0.6, 1.8),
		cframe = cf * CFrame.new(0, 0.3, 0),
		color = grey,
		material = Enum.Material.Slate,
		parent = model,
	})
	Build.part({
		name = "Body",
		size = Vector3.new(1.3, 2, 1.1),
		cframe = cf * CFrame.new(0, 1.55, 0),
		color = grey,
		material = Enum.Material.Slate,
		shape = Enum.PartType.Ball,
		parent = model,
	})
	Build.part({
		name = "Head",
		size = Vector3.new(1.05, 1.05, 1.05),
		cframe = cf * CFrame.new(0, 2.85, 0),
		color = grey,
		material = Enum.Material.Slate,
		shape = Enum.PartType.Ball,
		parent = model,
	})
	Build.part({
		name = "Bib",
		size = Vector3.new(1.1, 0.8, 0.15),
		cframe = cf * CFrame.new(0, 2.05, -0.5) * CFrame.Angles(math.rad(-12), 0, 0),
		color = red,
		material = Enum.Material.Fabric,
		collide = false,
		parent = model,
	})
	Build.part({
		name = "Cap",
		size = Vector3.new(1.1, 0.45, 1.1),
		cframe = cf * CFrame.new(0, 3.3, 0),
		color = red,
		material = Enum.Material.Fabric,
		shape = Enum.PartType.Ball,
		collide = false,
		parent = model,
	})
	model.Parent = parent
	return model
end

-- 水から突き出た枯れ木(沼らしさ)
function M.snag(parent: Instance, pos: Vector3, rng: Random)
	local grey = Color3.fromRGB(104, 92, 80)
	local h = rng:NextNumber(6, 9)
	local lean = Vector3.new(rng:NextNumber(-1.2, 1.2), h, rng:NextNumber(-1.2, 1.2))
	local top = pos + lean
	rod(parent, pos - Vector3.new(0, 2, 0), top, 0.9, grey, Enum.Material.Wood, "Snag")
	for _ = 1, 2 do
		local from = pos + lean * rng:NextNumber(0.5, 0.8)
		local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.4, 1), rng:NextNumber(-1, 1)).Unit
		rod(parent, from, from + dir * rng:NextNumber(2, 3.5), 0.4, grey, Enum.Material.Wood, "SnagBranch")
	end
end

-- 小舟(桟橋につないである)
function M.boat(parent: Instance, cf: CFrame)
	local model = Instance.new("Model")
	model.Name = "Boat"
	local hull = Color3.fromRGB(110, 78, 52)
	Build.part({
		name = "Hull",
		size = Vector3.new(3.4, 1.1, 7),
		cframe = cf * CFrame.new(0, 0.2, 0),
		color = hull,
		material = Enum.Material.WoodPlanks,
		parent = model,
	})
	Build.part({
		name = "Bow",
		size = Vector3.new(3.4, 1.1, 2.4),
		cframe = cf * CFrame.new(0, 0.2, -4.7) * CFrame.Angles(0, math.rad(180), 0),
		color = hull,
		material = Enum.Material.WoodPlanks,
		wedge = true,
		parent = model,
	})
	Build.part({
		name = "Inside",
		size = Vector3.new(2.8, 0.2, 6.4),
		cframe = cf * CFrame.new(0, 0.7, 0),
		color = DARK_WOOD,
		material = Enum.Material.WoodPlanks,
		collide = false,
		parent = model,
	})
	for _, z in { -1.6, 1.8 } do
		Build.part({
			name = "Seat",
			size = Vector3.new(3, 0.25, 0.8),
			cframe = cf * CFrame.new(0, 1, z),
			color = WOOD,
			material = Enum.Material.Wood,
			collide = false,
			parent = model,
		})
	end
	model.Parent = parent
	return model
end

-- 提灯(赤い紙の玉に黒い枠)
local function chochin(parent: Instance, pos: Vector3, light: boolean)
	local lamp = Build.part({
		name = "Chochin",
		size = Vector3.new(1.1, 1.5, 1.1),
		cframe = CFrame.new(pos),
		color = Color3.fromRGB(255, 104, 72),
		material = Enum.Material.Neon,
		shape = Enum.PartType.Ball,
		collide = false,
		parent = parent,
	})
	Build.part({
		name = "ChochinCap",
		size = Vector3.new(0.25, 0.8, 0.8),
		cframe = CFrame.new(pos + Vector3.new(0, 0.78, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		color = Color3.fromRGB(30, 24, 22),
		shape = Enum.PartType.Cylinder,
		collide = false,
		parent = parent,
	})
	if light then
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(255, 150, 90)
		l.Range = 14
		l.Brightness = 1.1
		l.Parent = lamp
		CollectionService:AddTag(l, "NightLight")
	end
end
M.chochin = chochin

-- 通りの両側の柱のあいだに張った、提灯の列
function M.lanternLine(parent: Instance, a: Vector3, b: Vector3, count: number)
	rod(parent, a, b, 0.15, Color3.fromRGB(40, 32, 28), Enum.Material.Fabric, "LanternRope")
	for i = 1, count do
		local t = i / (count + 1)
		local p = a:Lerp(b, t) - Vector3.new(0, 0.9 + math.sin(t * math.pi) * 0.6, 0)
		chochin(parent, p, i == math.ceil(count / 2))
	end
end

-- 木の柱(提灯の列を張る)
function M.pole(parent: Instance, pos: Vector3, h: number): Vector3
	Build.part({
		name = "Pole",
		size = Vector3.new(h, 0.6, 0.6),
		cframe = upright(pos, h),
		color = DARK_WOOD,
		material = Enum.Material.Wood,
		shape = Enum.PartType.Cylinder,
		parent = parent,
	})
	return pos + Vector3.new(0, h - 0.4, 0)
end

-- 水辺の見物台(手すり付きの板の台)。cf の -Z が水の側
function M.deck(parent: Instance, cf: CFrame, w: number, l: number)
	local model = Instance.new("Model")
	model.Name = "Deck"
	Build.part({
		name = "Floor",
		size = Vector3.new(w, 0.5, l),
		cframe = cf,
		color = Color3.fromRGB(116, 84, 56),
		material = Enum.Material.WoodPlanks,
		parent = model,
	})
	for _, x in { -w / 2 + 0.4, w / 2 - 0.4 } do
		for _, z in { -l / 2 + 0.4, l / 2 - 0.4 } do
			Build.part({
				name = "Leg",
				size = Vector3.new(0.7, 6, 0.7),
				cframe = cf * CFrame.new(x, -3, z),
				color = DARK_WOOD,
				material = Enum.Material.Wood,
				parent = model,
			})
		end
	end
	-- 手すり(水の側と両横。陸の側は空ける)
	local railH = 2.6
	local function rail(p1: Vector3, p2: Vector3)
		rod(model, p1, p2, 0.3, DARK_WOOD, Enum.Material.Wood, "Rail")
	end
	local fl, fr =
		cf * Vector3.new(-w / 2 + 0.3, railH, -l / 2 + 0.3),
		cf * Vector3.new(w / 2 - 0.3, railH, -l / 2 + 0.3)
	local bl, br =
		cf * Vector3.new(-w / 2 + 0.3, railH, l / 2 - 0.3), cf * Vector3.new(w / 2 - 0.3, railH, l / 2 - 0.3)
	rail(fl, fr)
	rail(fl, bl)
	rail(fr, br)
	for _, p in { fl, fr, bl, br, (fl + fr) / 2 } do
		Build.part({
			name = "RailPost",
			size = Vector3.new(0.4, railH, 0.4),
			cframe = CFrame.new(p - Vector3.new(0, railH / 2, 0)),
			color = DARK_WOOD,
			material = Enum.Material.Wood,
			parent = model,
		})
	end
	model.Parent = parent
	return model
end

-- 五重塔(遠くからでも分かる目印)
function M.pagoda(parent: Instance, cf: CFrame, scale: number?)
	local s = scale or 1
	local model = Instance.new("Model")
	model.Name = "Pagoda"
	local red = Color3.fromRGB(178, 58, 42)
	local white = Color3.fromRGB(236, 230, 214)
	local roof = Color3.fromRGB(46, 48, 58)
	Build.part({
		name = "Base",
		size = Vector3.new(18, 2, 18) * s,
		cframe = cf * CFrame.new(0, 1 * s, 0),
		color = STONE,
		material = Enum.Material.Slate,
		parent = model,
	})
	local y = 2 * s
	for i = 0, 4 do
		local w = (10 - i * 1.3) * s
		local bh = 4.4 * s
		Build.part({
			name = "Story",
			size = Vector3.new(w, bh, w),
			cframe = cf * CFrame.new(0, y + bh / 2, 0),
			color = if i % 2 == 0 then red else white,
			material = Enum.Material.Wood,
			parent = model,
		})
		y += bh
		local rw = w + 6 * s
		Build.part({
			name = "Roof",
			size = Vector3.new(rw, 0.9 * s, rw),
			cframe = cf * CFrame.new(0, y + 0.3 * s, 0),
			color = roof,
			material = Enum.Material.Slate,
			parent = model,
		})
		Build.part({
			name = "RoofTop",
			size = Vector3.new(rw - 3 * s, 0.7 * s, rw - 3 * s),
			cframe = cf * CFrame.new(0, y + 1.0 * s, 0),
			color = roof,
			material = Enum.Material.Slate,
			parent = model,
		})
		y += 1.4 * s
	end
	-- 相輪(屋根の上の金の柱)
	local spireH = 9 * s
	Build.part({
		name = "Sorin",
		size = Vector3.new(spireH, 0.7 * s, 0.7 * s),
		cframe = upright(cf.Position + Vector3.new(0, y, 0), spireH),
		color = Color3.fromRGB(196, 160, 80),
		material = Enum.Material.Foil,
		shape = Enum.PartType.Cylinder,
		parent = model,
	})
	for k = 1, 3 do
		Build.part({
			name = "SorinRing",
			size = Vector3.new(0.3 * s, 2.2 * s, 2.2 * s),
			cframe = CFrame.new(cf.Position + Vector3.new(0, y + spireH * (0.25 + k * 0.17), 0))
				* CFrame.Angles(0, 0, math.rad(90)),
			color = Color3.fromRGB(196, 160, 80),
			material = Enum.Material.Foil,
			shape = Enum.PartType.Cylinder,
			collide = false,
			parent = model,
		})
	end
	model.Parent = parent
	return model
end

-- 山の森(杉を山すそから中腹に散らす。avoid が true の場所は置かない)
function M.mountainForest(
	parent: Instance,
	b: Terrain.Basin,
	count: number,
	rng: Random,
	avoid: ((number, number) -> boolean)?
)
	local placed, tries = 0, 0
	local ring = b.ring or b.half
	while placed < count and tries < count * 8 do
		tries += 1
		local a = rng:NextNumber(0, math.pi * 2)
		local r = ring + rng:NextNumber(-4, 42)
		local x, z = b.center.X + math.cos(a) * r, b.center.Z + math.sin(a) * r
		if avoid and avoid(x, z) then
			continue
		end
		local y = Terrain.heightAt(b, x, z)
		if y - b.center.Y > 44 then
			continue -- 岩の頂上には生えない
		end
		M.cedar(parent, Vector3.new(x, y - 0.6, z), rng, 1.35)
		placed += 1
	end
end

-- 滝つぼのしぶき
function M.spray(parent: Instance, pos: Vector3, width: number)
	local p = Build.part({
		name = "Spray",
		size = Vector3.new(width, 1, 2),
		cframe = CFrame.new(pos + Vector3.new(0, 0.6, 0)),
		transparency = 1,
		collide = false,
		parent = parent,
	})
	p.CanQuery = false
	p.CanTouch = false
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(Color3.fromRGB(240, 248, 255))
	pe.Transparency =
		NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3.5) })
	pe.Lifetime = NumberRange.new(0.8, 1.6)
	pe.Rate = 24
	pe.Speed = NumberRange.new(1.5, 3)
	pe.SpreadAngle = Vector2.new(60, 60)
	pe.Acceleration = Vector3.new(0, -2, 0)
	pe.Parent = p
end

return M
