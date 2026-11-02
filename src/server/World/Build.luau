--!strict
-- ワールド生成の部品(鳥居・灯籠・木・葦・看板・屋台など)。
-- 看板の文字や案内の文言は、クライアントが言語に合わせて表示する(LocKey 属性)。
local CollectionService = game:GetService("CollectionService")

local Build = {}

export type PartProps = {
	size: Vector3,
	cframe: CFrame,
	color: Color3?,
	material: Enum.Material?,
	shape: Enum.PartType?,
	name: string?,
	transparency: number?,
	collide: boolean?,
	parent: Instance,
	wedge: boolean?,
}

function Build.part(p: PartProps): BasePart
	local part: BasePart = if p.wedge then Instance.new("WedgePart") else Instance.new("Part")
	if p.shape and part:IsA("Part") then
		part.Shape = p.shape
	end
	part.Name = p.name or "Part"
	part.Size = p.size
	part.CFrame = p.cframe
	part.Color = p.color or Color3.fromRGB(160, 160, 160)
	part.Material = p.material or Enum.Material.SmoothPlastic
	part.Transparency = p.transparency or 0
	part.Anchored = true
	part.CanCollide = if p.collide == nil then true else p.collide
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = p.parent
	return part
end

function Build.folder(name: string, parent: Instance): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- 文字を表示する看板。text はクライアント側で LocKey から決まる
function Build.sign(parent: Instance, cf: CFrame, size: Vector2, locKey: string, color: Color3?): BasePart
	local board = Build.part({
		name = "Sign",
		size = Vector3.new(size.X, size.Y, 0.3),
		cframe = cf,
		color = color or Color3.fromRGB(60, 38, 26),
		material = Enum.Material.Wood,
		parent = parent,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.2
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = Color3.fromRGB(255, 236, 196)
	label.Text = ""
	label.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.06, 0)
	pad.PaddingRight = UDim.new(0.06, 0)
	pad.PaddingTop = UDim.new(0.1, 0)
	pad.PaddingBottom = UDim.new(0.1, 0)
	pad.Parent = label
	board:SetAttribute("LocKey", locKey)
	CollectionService:AddTag(board, "LocSign")
	return board
end

-- 近づくと出るボタン。action の例: "open:shop:sell" / "travel:swamp"
function Build.prompt(parent: BasePart, locKey: string, action: string, distance: number?): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = locKey
	prompt.ObjectText = ""
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = distance or 12
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("LocKey", locKey)
	prompt:SetAttribute("Action", action)
	prompt.Parent = parent
	CollectionService:AddTag(prompt, "YokaiPrompt")
	return prompt
end

function Build.torii(parent: Instance, cf: CFrame, scale: number?): Model
	local s = scale or 1
	local model = Instance.new("Model")
	model.Name = "Torii"
	local red = Color3.fromRGB(196, 46, 36)
	local black = Color3.fromRGB(28, 22, 22)
	for _, x in { -5, 5 } do
		Build.part({
			name = "Pillar",
			size = Vector3.new(1.2, 14, 1.2) * s,
			cframe = cf * CFrame.new(x * s, 7 * s, 0),
			color = red,
			material = Enum.Material.SmoothPlastic,
			shape = Enum.PartType.Block,
			parent = model,
		})
		Build.part({
			name = "Base",
			size = Vector3.new(1.6, 1.2, 1.6) * s,
			cframe = cf * CFrame.new(x * s, 0.6 * s, 0),
			color = black,
			parent = model,
		})
	end
	Build.part({
		name = "Nuki",
		size = Vector3.new(13, 0.8, 0.7) * s,
		cframe = cf * CFrame.new(0, 10.5 * s, 0),
		color = red,
		parent = model,
	})
	Build.part({
		name = "Kasagi",
		size = Vector3.new(16, 1, 1.6) * s,
		cframe = cf * CFrame.new(0, 13.6 * s, 0),
		color = red,
		parent = model,
	})
	Build.part({
		name = "KasagiTop",
		size = Vector3.new(17, 0.6, 1.9) * s,
		cframe = cf * CFrame.new(0, 14.4 * s, 0),
		color = black,
		parent = model,
	})
	Build.part({
		name = "Gakuzuka",
		size = Vector3.new(0.8, 2.4, 0.5) * s,
		cframe = cf * CFrame.new(0, 12.1 * s, 0),
		color = black,
		parent = model,
	})
	model.Parent = parent
	return model
end

-- 石灯籠(夜に灯る)
function Build.lantern(parent: Instance, pos: Vector3)
	local stone = Color3.fromRGB(150, 150, 140)
	Build.part({
		name = "LanternBase",
		size = Vector3.new(1.6, 0.6, 1.6),
		cframe = CFrame.new(pos + Vector3.new(0, 0.3, 0)),
		color = stone,
		material = Enum.Material.Slate,
		parent = parent,
	})
	Build.part({
		name = "LanternPost",
		size = Vector3.new(0.7, 2.6, 0.7),
		cframe = CFrame.new(pos + Vector3.new(0, 1.9, 0)),
		color = stone,
		material = Enum.Material.Slate,
		parent = parent,
	})
	local fire = Build.part({
		name = "LanternLight",
		size = Vector3.new(1.3, 1.1, 1.3),
		cframe = CFrame.new(pos + Vector3.new(0, 3.75, 0)),
		color = Color3.fromRGB(255, 196, 120),
		material = Enum.Material.Neon,
		parent = parent,
	})
	Build.part({
		name = "LanternRoof",
		size = Vector3.new(2.2, 0.5, 2.2),
		cframe = CFrame.new(pos + Vector3.new(0, 4.55, 0)),
		color = stone,
		material = Enum.Material.Slate,
		parent = parent,
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 180, 110)
	light.Range = 16
	light.Brightness = 1.4
	light.Shadows = true
	light.Parent = fire
	CollectionService:AddTag(light, "NightLight")
end

function Build.tree(parent: Instance, pos: Vector3, rng: Random, kind: string?)
	local h = rng:NextNumber(10, 18)
	local trunkColor = Color3.fromRGB(78, 58, 42)
	Build.part({
		name = "Trunk",
		size = Vector3.new(h, 1.4, 1.4),
		cframe = CFrame.new(pos + Vector3.new(0, h / 2, 0))
			* CFrame.Angles(0, 0, math.rad(90))
			* CFrame.Angles(rng:NextNumber(-0.08, 0.08), 0, 0),
		color = trunkColor,
		material = Enum.Material.Wood,
		shape = Enum.PartType.Cylinder,
		parent = parent,
	})
	local leaf = if kind == "maple"
		then Color3.fromRGB(196, 78, 52)
		elseif kind == "pine" then Color3.fromRGB(44, 82, 52)
		elseif kind == "sakura" then Color3.fromRGB(255, 183, 205)
		else Color3.fromRGB(60 + rng:NextInteger(0, 20), 98 + rng:NextInteger(0, 24), 52)
	for i = 1, 3 do
		local r = rng:NextNumber(5, 8) * (if i == 1 then 1.2 else 0.85)
		local off =
			Vector3.new(rng:NextNumber(-2.5, 2.5), h + rng:NextNumber(-1, 2.5), rng:NextNumber(-2.5, 2.5))
		Build.part({
			name = "Leaves",
			size = Vector3.new(r, r * 0.8, r),
			cframe = CFrame.new(pos + off),
			color = leaf,
			material = Enum.Material.LeafyGrass,
			shape = Enum.PartType.Ball,
			collide = false,
			parent = parent,
		})
	end
end

function Build.reeds(parent: Instance, pos: Vector3, rng: Random)
	for _ = 1, rng:NextInteger(4, 7) do
		local h = rng:NextNumber(3, 6)
		local off = Vector3.new(rng:NextNumber(-1.2, 1.2), 0, rng:NextNumber(-1.2, 1.2))
		Build.part({
			name = "Reed",
			size = Vector3.new(0.18, h, 0.18),
			cframe = CFrame.new(pos + off + Vector3.new(0, h / 2 - 0.5, 0))
				* CFrame.Angles(rng:NextNumber(-0.15, 0.15), 0, rng:NextNumber(-0.15, 0.15)),
			color = Color3.fromRGB(120 + rng:NextInteger(0, 40), 140 + rng:NextInteger(0, 30), 70),
			material = Enum.Material.Grass,
			collide = false,
			parent = parent,
		})
	end
	-- 穂
	Build.part({
		name = "ReedTip",
		size = Vector3.new(0.4, 1.2, 0.4),
		cframe = CFrame.new(pos + Vector3.new(0, rng:NextNumber(4, 5.5), 0)),
		color = Color3.fromRGB(120, 86, 52),
		material = Enum.Material.Fabric,
		collide = false,
		parent = parent,
	})
end

function Build.lotus(parent: Instance, pos: Vector3, rng: Random)
	local r = rng:NextNumber(2.2, 4)
	Build.part({
		name = "LotusPad",
		size = Vector3.new(0.15, r, r),
		cframe = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, 6.28), math.rad(90)),
		color = Color3.fromRGB(62, 120, 64),
		material = Enum.Material.Grass,
		shape = Enum.PartType.Cylinder,
		collide = false,
		parent = parent,
	})
	if rng:NextNumber() < 0.45 then
		local flower = Build.part({
			name = "LotusFlower",
			size = Vector3.new(1, 0.8, 1),
			cframe = CFrame.new(
				pos + Vector3.new(rng:NextNumber(-0.5, 0.5), 0.45, rng:NextNumber(-0.5, 0.5))
			),
			color = Color3.fromRGB(255, 170, 200),
			material = Enum.Material.SmoothPlastic,
			shape = Enum.PartType.Ball,
			collide = false,
			parent = parent,
		})
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 150, 200)
		light.Range = 5
		light.Brightness = 0.6
		light.Parent = flower
		CollectionService:AddTag(light, "NightLight")
	end
end

-- 蛍(夜だけクライアントが有効にする)
function Build.fireflies(parent: Instance, pos: Vector3, size: Vector3)
	local emitterPart = Build.part({
		name = "Fireflies",
		size = size,
		cframe = CFrame.new(pos),
		transparency = 1,
		collide = false,
		parent = parent,
	})
	emitterPart.CanQuery = false
	emitterPart.CanTouch = false
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(Color3.fromRGB(220, 255, 120))
	pe.LightEmission = 1
	pe.LightInfluence = 0
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.22),
		NumberSequenceKeypoint.new(1, 0),
	})
	pe.Lifetime = NumberRange.new(3, 6)
	pe.Rate = 18
	pe.Speed = NumberRange.new(0.3, 1.2)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Acceleration = Vector3.new(0, 0.15, 0)
	pe.Enabled = false
	pe.Parent = emitterPart
	CollectionService:AddTag(pe, "NightFX")
end

-- 屋台(看板 + 屋根 + 台)。counter を返す
function Build.stall(
	parent: Instance,
	cf: CFrame,
	locKey: string,
	action: string,
	roofColor: Color3
): BasePart
	local model = Instance.new("Model")
	model.Name = "Stall_" .. locKey
	local wood = Color3.fromRGB(122, 86, 56)
	local counter = Build.part({
		name = "Counter",
		size = Vector3.new(10, 3.2, 3),
		cframe = cf * CFrame.new(0, 1.6, 0),
		color = wood,
		material = Enum.Material.WoodPlanks,
		parent = model,
	})
	for _, x in { -4.6, 4.6 } do
		Build.part({
			name = "Post",
			size = Vector3.new(0.6, 9, 0.6),
			cframe = cf * CFrame.new(x, 4.5, 1.6),
			color = wood,
			material = Enum.Material.Wood,
			parent = model,
		})
		Build.part({
			name = "Post",
			size = Vector3.new(0.6, 9, 0.6),
			cframe = cf * CFrame.new(x, 4.5, -1.6),
			color = wood,
			material = Enum.Material.Wood,
			parent = model,
		})
	end
	Build.part({
		name = "Roof",
		size = Vector3.new(12, 0.5, 6),
		cframe = cf * CFrame.new(0, 9.2, 0) * CFrame.Angles(math.rad(-8), 0, 0),
		color = roofColor,
		material = Enum.Material.Fabric,
		parent = model,
	})
	-- のれん
	for i = -2, 2 do
		Build.part({
			name = "Noren",
			size = Vector3.new(1.8, 2, 0.08),
			cframe = cf * CFrame.new(i * 2, 7.8, -2.2),
			color = roofColor,
			material = Enum.Material.Fabric,
			collide = false,
			parent = model,
		})
	end
	Build.sign(model, cf * CFrame.new(0, 10.6, -2.4), Vector2.new(7, 1.8), locKey)
	-- 提灯
	for _, x in { -4.6, 4.6 } do
		local lamp = Build.part({
			name = "Chochin",
			size = Vector3.new(1, 1.4, 1),
			cframe = cf * CFrame.new(x, 7.6, -2.2),
			color = Color3.fromRGB(255, 120, 80),
			material = Enum.Material.Neon,
			shape = Enum.PartType.Ball,
			collide = false,
			parent = model,
		})
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(255, 150, 90)
		l.Range = 12
		l.Brightness = 1.2
		l.Parent = lamp
		CollectionService:AddTag(l, "NightLight")
	end
	Build.prompt(counter, "prompt_open", action, 12)
	model.Parent = parent
	return counter
end

-- 狸の商人(パーツだけで作る)
function Build.tanuki(parent: Instance, cf: CFrame)
	local model = Instance.new("Model")
	model.Name = "Tanuki"
	local brown = Color3.fromRGB(122, 90, 60)
	local dark = Color3.fromRGB(52, 40, 32)
	local cream = Color3.fromRGB(232, 214, 180)
	Build.part({
		name = "Body",
		size = Vector3.new(3, 3.4, 2.8),
		cframe = cf * CFrame.new(0, 1.7, 0),
		color = brown,
		shape = Enum.PartType.Ball,
		parent = model,
	})
	Build.part({
		name = "Belly",
		size = Vector3.new(2.2, 2.4, 1),
		cframe = cf * CFrame.new(0, 1.5, -1.1),
		color = cream,
		shape = Enum.PartType.Ball,
		collide = false,
		parent = model,
	})
	Build.part({
		name = "Head",
		size = Vector3.new(2.4, 2.2, 2.2),
		cframe = cf * CFrame.new(0, 4.1, 0),
		color = brown,
		shape = Enum.PartType.Ball,
		parent = model,
	})
	Build.part({
		name = "Mask",
		size = Vector3.new(1.9, 0.8, 0.6),
		cframe = cf * CFrame.new(0, 4.2, -0.9),
		color = dark,
		shape = Enum.PartType.Ball,
		collide = false,
		parent = model,
	})
	for _, x in { -0.45, 0.45 } do
		Build.part({
			name = "Eye",
			size = Vector3.new(0.3, 0.3, 0.3),
			cframe = cf * CFrame.new(x, 4.25, -1.18),
			color = Color3.new(1, 1, 1),
			material = Enum.Material.Neon,
			shape = Enum.PartType.Ball,
			collide = false,
			parent = model,
		})
		Build.part({
			name = "Ear",
			size = Vector3.new(0.7, 0.7, 0.4),
			cframe = cf * CFrame.new(x * 1.9, 5.2, 0),
			color = dark,
			shape = Enum.PartType.Ball,
			collide = false,
			parent = model,
		})
	end
	Build.part({
		name = "Nose",
		size = Vector3.new(0.35, 0.3, 0.3),
		cframe = cf * CFrame.new(0, 3.85, -1.15),
		color = dark,
		shape = Enum.PartType.Ball,
		collide = false,
		parent = model,
	})
	Build.part({
		name = "Hat",
		size = Vector3.new(0.4, 3.4, 3.4),
		cframe = cf * CFrame.new(0, 5.25, 0) * CFrame.Angles(0, 0, math.rad(90)),
		color = Color3.fromRGB(196, 168, 110),
		material = Enum.Material.Fabric,
		shape = Enum.PartType.Cylinder,
		collide = false,
		parent = model,
	})
	model.Parent = parent
end

return Build
