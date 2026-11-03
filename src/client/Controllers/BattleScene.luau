--!strict
-- バトルの舞台: 本物の3Dの水の中(BattleArena)へカメラを移し、相棒の3Dモデルが泳ぎ回る。
-- 技は3Dの演出(光る粒・衝撃の輪・炎・雷・砂けむり・泡・光)。カメラは場面に合わせて動く(登場・攻撃・倒れる・勝利)。
-- 演出だけを受け持つ(勝ち負け・ダメージはサーバーが決め、BattleUI が順番に呼ぶ)。
-- 光の設定はバトルの間だけ水の中のものに変え、終わったら元に戻す(LightingFX は止めておく)。
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local FishBuilder = require(Shared.Lib.FishBuilder)

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local BattleArena = require(script.Parent.BattleArena)
local LightingFX = require(script.Parent.LightingFX)

local BattleScene = {}

local FISH_Y = BattleArena.FISH_Y
local HOME = BattleArena.HOME -- 舞台の中心から
local BASE = BattleArena.BASE_SHOT
local ATTACK = BattleArena.ATTACK_SHOT
local OFFSCREEN = 30
local LENGTH = 6 -- 魚の長さ(スタッド)。どの魚も同じ大きさで戦う
local BOSS_LENGTH = 10

local TEX = {
	sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
}

-- 水の中の光(バトルの間だけ)
local UNDERWATER: { [string]: { [string]: any } } = {
	Lighting = {
		ClockTime = 12.2,
		Brightness = 2.4,
		Ambient = Color3.fromRGB(60, 100, 122),
		OutdoorAmbient = Color3.fromRGB(84, 146, 168),
		FogColor = Color3.fromRGB(26, 92, 122),
		FogStart = 26,
		FogEnd = 190,
		ExposureCompensation = 0.1,
	},
	Grade = {
		TintColor = Color3.fromRGB(205, 240, 248),
		Saturation = 0.15,
		Contrast = 0.12,
		Brightness = 0.02,
	},
	Bloom = { Intensity = 0.9, Size = 28, Threshold = 0.85 },
	SunRays = { Intensity = 0 },
}

-- カメラ: 注目点のまわりを回る(計算は BattleArena と同じ)
BattleScene.orbit = BattleArena.orbit
local orbit = BattleArena.orbit

local function ease(x: number): number
	return x * x * (3 - 2 * x)
end

local function elementColor(el: string?): Color3
	local e = el and Config.ElementById[el]
	return if e then Color3.fromHex(e.color) else Color3.new(1, 1, 1)
end

type Shot = { focus: Vector3, yaw: number, pitch: number, dist: number, fov: number }
type Anim = { kind: string, t0: number, dur: number, target: Vector3? }
type Actor = {
	side: string,
	facing: number, -- +1 右向き(自分) / -1 左向き(相手)
	home: Vector3,
	phase: number,
	model: Model?,
	fishId: string,
	center: Vector3, -- ピボットから見たモデルの中心
	length: number,
	ray: boolean,
	pos: Vector3,
	anim: Anim?,
	gone: boolean,
	anchor: BasePart, -- 魚について回る見えない点(吹き出し・数字・光)
	tag: Frame,
	nextBubble: number,
	aura: ParticleEmitter?,
	auraLight: PointLight?,
}

export type Scene = any

-- 1つの舞台を使い回す(2回目からは作り直さない)
local cachedArena: BattleArena.Arena? = nil

local function lerpShot(a: Shot, b: Shot, k: number): Shot
	return {
		focus = a.focus:Lerp(b.focus, k),
		yaw = a.yaw + (b.yaw - a.yaw) * k,
		pitch = a.pitch + (b.pitch - a.pitch) * k,
		dist = a.dist + (b.dist - a.dist) * k,
		fov = a.fov + (b.fov - a.fov) * k,
	}
end

-- 部品 ----------------------------------------------------------------------------
local function fxPart(self: any, props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	if props.Shape then
		p.Shape = props.Shape
	end
	for k, v in props do
		if k ~= "Shape" then
			(p :: any)[k] = v
		end
	end
	p.Parent = self.fx
	return p
end

local function later(dur: number, fn: () -> ())
	task.delay(dur, fn)
end

-- 1匹分 --------------------------------------------------------------------------
local function newActor(self: any, side: string): Actor
	local home = self.origin + HOME[side]
	local anchor = fxPart(self, {
		Name = side .. "Anchor",
		Size = Vector3.new(0.2, 0.2, 0.2),
		Transparency = 1,
		CFrame = CFrame.new(home),
	})
	anchor.Parent = self.folder
	local bb = Instance.new("BillboardGui")
	bb.Name = side .. "Tag"
	bb.Adornee = anchor
	bb.Size = UDim2.fromOffset(220, 150)
	bb.StudsOffset = Vector3.new(0, 2.5, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 400
	bb.Parent = self.folder
	local tag = Kit.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Parent = bb })
	return {
		side = side,
		facing = if side == "player" then 1 else -1,
		home = home,
		phase = if side == "player" then 0 else 2.4,
		model = nil,
		fishId = "",
		center = Vector3.zero,
		length = LENGTH,
		ray = false,
		pos = home,
		anim = nil,
		gone = true,
		anchor = anchor,
		tag = tag,
		nextBubble = 0,
		aura = nil,
		auraLight = nil,
	}
end

-- 光の設定を水の中へ(元の値は覚えておく)
local function applyLook(self: any)
	self.saved = {}
	local function set(inst: Instance, props: { [string]: any })
		for k, v in props do
			table.insert(self.saved, { inst = inst, key = k, value = (inst :: any)[k] })
			pcall(function()
				(inst :: any)[k] = v
			end)
		end
	end
	set(Lighting, UNDERWATER.Lighting)
	for _, name in { "Grade", "Bloom", "SunRays" } do
		local e = Lighting:FindFirstChild(name)
		if e then
			set(e, UNDERWATER[name])
		end
	end
	-- Atmosphere があると霧(FogEnd)が効かないので、バトルの間だけ外す
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if atm then
		self.atmosphere = atm
		atm.Parent = nil
	end
	local dof = Instance.new("DepthOfFieldEffect")
	dof.Name = "BattleDepth"
	dof.FarIntensity = 0.35
	dof.NearIntensity = 0.55
	dof.FocusDistance = 30
	dof.InFocusRadius = 14
	dof.Parent = Lighting
	self.dof = dof
end

local function restoreLook(self: any)
	for i = #self.saved, 1, -1 do
		local s = self.saved[i]
		pcall(function()
			(s.inst :: any)[s.key] = s.value
		end)
	end
	if self.atmosphere then
		self.atmosphere.Parent = Lighting
	end
	if self.dof then
		self.dof:Destroy()
	end
end

function BattleScene.new(gui: Instance, opts: { boss: boolean? }?): Scene
	local self: any = setmetatable({}, { __index = BattleScene })
	self.rng = Random.new()
	self.boss = opts ~= nil and opts.boss == true
	self.enraged = false
	self.speed = 1
	self.shakeScale = 1
	self.shakeUntil = 0
	self.shakePower = 0
	self.fovKick = 0
	self.lastT = os.clock()

	-- 舞台(2回目からは使い回し)
	local arena = cachedArena or BattleArena.build(workspace)
	cachedArena = arena
	arena.folder.Parent = workspace
	self.arena = arena
	self.origin = arena.origin
	self.fx = arena.fx
	local folder = Instance.new("Folder")
	folder.Name = "Battle"
	folder.Parent = arena.folder
	self.folder = folder

	LightingFX.hold(true)
	applyLook(self)

	-- カメラを借りる
	local cam = workspace.CurrentCamera
	self.camera = cam
	if cam then
		self.camSaved = { type = cam.CameraType, subject = cam.CameraSubject, fov = cam.FieldOfView }
		cam.CameraType = Enum.CameraType.Scriptable
	end
	local center = self.origin + Vector3.new(0, FISH_Y, 0)
	-- 登場: 水面の近くの高いところから、すべり降りる
	local intro = BattleArena.INTRO_SHOT
	self.cam = {
		focus = center + Vector3.new(0, intro.up, 0),
		yaw = intro.yaw,
		pitch = intro.pitch,
		dist = intro.dist,
		fov = intro.fov,
	}
	self.shot = nil
	self.shotUntil = 0
	self.shotRate = 1.4
	self.victory = nil

	-- 画面の閃光と、潜る時の暗転(2D)
	self.flashFrame = Kit.new("Frame", {
		Name = "Flash",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 0,
		Parent = gui,
	})
	local dive = Kit.new("Frame", {
		Name = "Dive",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(16, 64, 96),
		BackgroundTransparency = 0,
		BorderSizePixel = 0,
		ZIndex = 0,
		Parent = gui,
	})
	TweenService:Create(dive, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
	later(0.85, function()
		dive:Destroy()
	end)

	self.actors = { player = newActor(self, "player"), enemy = newActor(self, "enemy") }
	-- カメラについて回るやわらかい光(水の中でも相棒がはっきり見えるように)
	local key = fxPart(self, {
		Name = "KeyLight",
		Size = Vector3.new(0.2, 0.2, 0.2),
		Transparency = 1,
		CFrame = CFrame.new(self.origin),
	})
	key.Parent = folder
	local keyLight = Instance.new("PointLight")
	keyLight.Color = Color3.fromRGB(255, 244, 228)
	keyLight.Brightness = 1.4
	keyLight.Range = 46
	keyLight.Shadows = false
	keyLight.Parent = key
	self.keyLight = key
	self.conn = RunService.RenderStepped:Connect(function()
		self:step(os.clock())
	end)
	self:step(os.clock())
	return self
end

-- 2倍速(演出の時間を半分に)・画面の揺れを弱く
function BattleScene.setSpeed(self: any, speed: number)
	self.speed = math.clamp(speed, 1, 3)
end

function BattleScene.setShake(self: any, on: boolean)
	self.shakeScale = if on then 1 else 0.2
end

-- 毎フレーム ----------------------------------------------------------------------
function BattleScene.place(self: any, a: Actor, t: number, parts: { BasePart }, cfs: { CFrame })
	local ph = a.phase
	-- ふだんは自分の側をゆったり泳ぎ回る(奥行きの方向にも動く)
	local idle = BattleArena.idle(a.home, t, ph)
	local pos = idle
	local heading = a.facing
	local roll, beat, spin = 0, 1, 0
	local anim = a.anim
	if anim then
		local p = math.clamp((t - anim.t0) / anim.dur, 0, 1)
		local k = anim.kind
		local away = a.home - Vector3.new(a.facing * OFFSCREEN, 0, 0)
		if k == "enter" then
			pos = away:Lerp(idle, 1 - (1 - p) ^ 3)
			beat = 2
		elseif k == "leave" then
			pos = idle:Lerp(away, p * p)
			heading = -a.facing
			beat = 2.5
		elseif k == "dash" and anim.target then
			local q = if p < 0.35 then ease(p / 0.35) elseif p < 0.5 then 1 else 1 - ease((p - 0.5) / 0.5)
			pos = idle:Lerp(anim.target, q)
			beat = 2.6
		elseif k == "knock" then
			pos = idle + Vector3.new(-a.facing * 2 * math.sin(p * math.pi), 0.4 * math.sin(p * math.pi), 0)
			roll = math.sin(p * 28) * 0.35 * (1 - p)
		elseif k == "dodge" then
			pos = idle + Vector3.new(0, 2.6 * math.sin(p * math.pi), 2.2 * math.sin(p * math.pi))
			beat = 2
		elseif k == "hop" then
			pos = idle + Vector3.new(0, 1.4 * math.sin(p * math.pi), 0)
			roll = math.sin(p * math.pi * 2) * 0.35
		elseif k == "joy" then
			pos = idle + Vector3.new(0, 2 * math.sin(p * math.pi), 0)
			spin = p * math.pi * 2
		elseif k == "faint" then
			-- お腹を上にして、水面へ浮かんでいく
			roll = math.min(p / 0.3, 1) * math.pi
			pos = idle + Vector3.new(0, math.max(0, p - 0.3) * 30, 0)
			beat = 0.15
		end
		if p >= 1 then
			a.anim = nil
			if k == "faint" or k == "leave" then
				a.gone = true
				if a.model then
					a.model.Parent = nil
				end
			end
		end
	end
	a.pos = pos
	table.insert(parts, a.anchor)
	table.insert(cfs, CFrame.new(pos))
	local model = a.model
	if model and not a.gone then
		-- 頭(-Z)を進む向きへ。少しだけカメラの方へ向けて、顔が見えるように
		local base = BattleArena.fishYaw(heading)
		local wiggle = math.sin(t * 7 * beat + ph) * 0.09 * math.min(beat, 1.6) -- 尾をふる
		local pitch = math.cos(t * 0.83 + ph * 1.7) * 0.12
		local tilt = if a.ray then 0.55 else 0 -- 鱏は背中を見せる
		model:PivotTo(
			CFrame.new(pos)
				* CFrame.Angles(tilt, spin, 0)
				* CFrame.Angles(0, base + wiggle, 0)
				* CFrame.Angles(pitch, 0, roll)
				* CFrame.new(-a.center)
		)
		-- 口から泡
		if t >= a.nextBubble then
			a.nextBubble = t + self.rng:NextNumber(1.2, 2.6)
			self:bubble(
				pos + Vector3.new(heading * a.length * 0.45, 0.3, 0),
				self.rng:NextNumber(0.2, 0.4),
				7
			)
		end
	end
end

function BattleScene.baseShot(self: any, t: number): Shot
	local center = self.origin + Vector3.new(0, FISH_Y, 0)
	return {
		focus = center + Vector3.new(math.sin(t * 0.11) * 1.5, math.sin(t * 0.17) * 0.6, 0),
		yaw = BASE.yaw + math.sin(t * 0.13) * 0.14,
		pitch = BASE.pitch + math.sin(t * 0.21) * 0.03,
		dist = (if self.boss then BASE.bossDist else BASE.dist) + math.sin(t * 0.17) * 1.5,
		fov = BASE.fov,
	}
end

function BattleScene.step(self: any, t: number)
	local dt = math.clamp(t - self.lastT, 0, 0.1)
	self.lastT = t
	local parts: { BasePart } = {}
	local cfs: { CFrame } = {}
	for _, a in self.actors do
		self:place(a, t, parts, cfs)
	end
	local function move(ps: { BasePart }, cs: { CFrame })
		for i, p in ps do
			table.insert(parts, p)
			table.insert(cfs, cs[i])
		end
	end
	BattleArena.step(self.arena, t, move)
	-- まとめて動かす(1つずつ CFrame を入れるより軽い)
	local ok = pcall(function()
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end)
	if not ok then
		for i, p in parts do
			p.CFrame = cfs[i]
		end
	end

	-- カメラ
	local target: Shot
	if self.victory then
		local a = self.actors[self.victory.side]
		target = {
			focus = a.pos + Vector3.new(0, 0.5, 0),
			yaw = (t - self.victory.t0) * 0.35 - 0.4,
			pitch = 0.12,
			dist = 15,
			fov = 46,
		}
		self.shotRate = 2
	elseif self.shot and t < self.shotUntil then
		target = self.shot
	else
		target = self:baseShot(t)
		if self.shot then
			self.shot = nil
			self.shotRate = 2.2
		end
	end
	self.cam = lerpShot(self.cam, target, 1 - math.exp(-dt * self.shotRate))
	local cf = orbit(self.cam.focus, self.cam.yaw, self.cam.pitch, self.cam.dist)
	if t < self.shakeUntil then
		local s = self.shakePower * self.shakeScale * (self.shakeUntil - t) / 0.35 * 0.03
		cf = cf * CFrame.new(self.rng:NextNumber(-s, s), self.rng:NextNumber(-s, s), 0)
	end
	self.fovKick *= math.exp(-dt * 8)
	self.cameraCFrame = cf
	if self.keyLight then
		self.keyLight.CFrame = cf * CFrame.new(0, 5, -4)
	end
	local cam = self.camera
	if cam then
		cam.CFrame = cf
		cam.FieldOfView = self.cam.fov + self.fovKick
	end
	if self.dof then
		self.dof.FocusDistance = self.cam.dist
	end
end

-- カメラの場面 ----------------------------------------------------------------------
function BattleScene.shotFor(self: any, kind: string, side: string?): Shot?
	local a: Actor? = side and self.actors[side]
	local center = self.origin + Vector3.new(0, FISH_Y, 0)
	if kind == "attack" and a then
		local foe: Actor = self.actors[if a.side == "player" then "enemy" else "player"]
		-- 攻める側の後ろへ回りこむ
		return {
			focus = a.home:Lerp(foe.home, ATTACK.at),
			yaw = -a.facing * ATTACK.yaw,
			pitch = ATTACK.pitch,
			dist = ATTACK.dist,
			fov = ATTACK.fov,
		}
	elseif kind == "enter" and a then
		return { focus = a.home, yaw = -a.facing * 0.22, pitch = 0.08, dist = 22, fov = 48 }
	elseif kind == "faint" and a then
		return { focus = a.pos + Vector3.new(0, 4, 0), yaw = 0, pitch = -0.08, dist = 20, fov = 48 }
	elseif kind == "boss" then
		return {
			focus = self.origin + HOME.enemy + Vector3.new(0, 2, 0),
			yaw = 0.25,
			pitch = 0.2,
			dist = 34,
			fov = 52,
		}
	elseif kind == "wide" then
		return { focus = center, yaw = 0, pitch = 0.16, dist = 38, fov = 52 }
	end
	return nil
end

function BattleScene.shotTo(self: any, kind: string, side: string?, hold: number?, rate: number?)
	local s = self:shotFor(kind, side)
	if not s then
		return
	end
	self.shot = s
	self.shotUntil = os.clock() + (hold or 1) / self.speed
	self.shotRate = rate or 4
end

-- 勝った子のまわりをカメラが回る(結果の画面の間)
function BattleScene.celebrate(self: any, side: string)
	local a: Actor = self.actors[side]
	self.victory = { side = side, t0 = os.clock() }
	if a.model and not a.gone then
		a.anim = { kind = "joy", t0 = os.clock(), dur = 1.2 }
	end
	if side == "player" then
		for i = 1, 3 do
			later(0.25 * i, function()
				if self.folder.Parent then
					local p = a.pos + Vector3.new(self.rng:NextNumber(-3, 3), 4, self.rng:NextNumber(-2, 2))
					self:burst(p, Color3.fromHSV(self.rng:NextNumber(), 0.6, 1), 14, 6, 0.4, 0.9)
				end
			end)
		end
	end
end

-- 魚 --------------------------------------------------------------------------------
function BattleScene.setFish(self: any, side: string, fishId: string, mutation: string?, how: string?)
	local a: Actor = self.actors[side]
	if a.model then
		a.model:Destroy()
		a.model = nil
	end
	a.fishId = fishId
	local def = Config.FishById[fishId]
	if not def then
		return
	end
	local model = FishBuilder.build(def, { mutation = mutation, noRarityScale = true, anchored = true })
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
	model:PivotTo(CFrame.new())
	local _, size = model:GetBoundingBox()
	local long = math.max(size.X, size.Y, size.Z, 0.1)
	a.length = if self.boss and side == "enemy" then BOSS_LENGTH else LENGTH
	pcall(function()
		model:ScaleTo(model:GetScale() * a.length / long)
	end)
	model:PivotTo(CFrame.new())
	local box = model:GetBoundingBox()
	a.center = box.Position
	a.ray = model:GetAttribute("Shape") == "ray"
	model.Parent = self.folder
	a.model = model
	a.gone = false
	a.anim = if how == "enter" then { kind = "enter", t0 = os.clock(), dur = 0.9 / self.speed } else nil
	if how == "enter" then
		self:shotTo("enter", side, 0.9, 3)
	end
	-- ボスのまわりの妖気(怒ると赤く)
	if self.boss and side == "enemy" and not a.aura then
		local aura = Instance.new("ParticleEmitter")
		aura.Texture = TEX.smoke
		aura.Rate = 18
		aura.Lifetime = NumberRange.new(1.2, 2)
		aura.Speed = NumberRange.new(1, 2.5)
		aura.SpreadAngle = Vector2.new(180, 180)
		aura.Size = NumberSequence.new(3, 7)
		aura.Transparency = NumberSequence.new(0.55, 1)
		aura.LightEmission = 0.5
		aura.Color = ColorSequence.new(Color3.fromRGB(150, 90, 230))
		aura.Parent = a.anchor
		a.aura = aura
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(150, 90, 230)
		light.Brightness = 2
		light.Range = 20
		light.Parent = a.anchor
		a.auraLight = light
	end
	local placeParts, placeCfs = {}, {}
	self:place(a, os.clock(), placeParts, placeCfs)
	a.anchor.CFrame = CFrame.new(a.pos)
end

function BattleScene.hasFish(self: any, side: string, fishId: string?): boolean
	local a: Actor = self.actors[side]
	return a.model ~= nil and not a.gone and (fishId == nil or a.fishId == fishId)
end

function BattleScene.tag(self: any, side: string): Frame
	return self.actors[side].tag
end

-- 動き ------------------------------------------------------------------------------
-- 攻撃: 相手へ泳いでぶつかり、戻る(当たるのは約0.25秒後)
function BattleScene.attack(self: any, side: string)
	local a: Actor = self.actors[side]
	local foe: Actor = self.actors[if side == "player" then "enemy" else "player"]
	if not a.model or a.gone then
		return
	end
	local gap = (foe.length + a.length) * 0.4
	a.anim = {
		kind = "dash",
		t0 = os.clock(),
		dur = 0.75 / self.speed,
		target = foe.pos - Vector3.new(a.facing * gap, 0, 0),
	}
	self:shotTo("attack", side, 1.0, 4)
	-- 泳ぎ出しの水しぶき
	self:burst(a.pos, Color3.fromRGB(220, 245, 255), 8, 3, 0.35, 0.5, Enum.Material.Glass)
end

-- 補助の技・強くなった/弱くなった: その場で跳ねて光る
function BattleScene.cast(self: any, side: string, color: Color3)
	local a: Actor = self.actors[side]
	a.anim = { kind = "hop", t0 = os.clock(), dur = 0.6 / self.speed }
	self:ring(a.pos, color, 9, 0.6)
	self:burst(a.pos, color, 10, 4, 0.35, 0.6)
	self:light(a.pos, color, 4, 18, 0.6)
end

-- 当たった(side = 当たった方)
function BattleScene.hit(self: any, side: string, element: string, eff: number, crit: boolean)
	local a: Actor = self.actors[side]
	if a.model and not a.gone then
		a.anim = { kind = "knock", t0 = os.clock(), dur = 0.5 / self.speed }
		self:highlight(a.model, if eff > 1 then Color3.fromRGB(255, 230, 150) else Color3.new(1, 1, 1))
	end
	local strong = eff > 1 or crit
	self:effect(a.pos, element, strong)
	if eff > 1 then
		self:ring(a.pos, Color3.fromRGB(255, 227, 160), 14, 0.5)
	end
	if crit then
		self:flash(Color3.new(1, 1, 1), 0.45)
	end
	self.fovKick = if strong then -8 else -4
	self:shake(if strong then 12 else 5)
end

-- かわした(side = かわした方)
function BattleScene.dodge(self: any, side: string)
	local a: Actor = self.actors[side]
	a.anim = { kind = "dodge", t0 = os.clock(), dur = 0.55 / self.speed }
	self:ring(a.pos, Color3.fromRGB(200, 240, 255), 7, 0.4)
end

function BattleScene.heal(self: any, side: string)
	local a: Actor = self.actors[side]
	self:ring(a.pos, Color3.fromRGB(120, 230, 140), 9, 0.6)
	self:emit(a.pos, TEX.sparkle, Color3.fromRGB(150, 255, 170), 30, 0.6, 4, 1)
	self:light(a.pos, Color3.fromRGB(120, 255, 160), 3, 16, 0.8)
	for _ = 1, 6 do
		self:bubble(
			a.pos + Vector3.new(self.rng:NextNumber(-1.5, 1.5), 0, self.rng:NextNumber(-1, 1)),
			0.3,
			5
		)
	end
end

function BattleScene.stun(self: any, side: string)
	local a: Actor = self.actors[side]
	self:burst(a.pos, Color3.fromRGB(255, 220, 90), 12, 3.5, 0.25, 0.4)
	self:bolt(a.pos, 6)
end

-- 倒れた: お腹を上にして水面へ。泡がはじける
function BattleScene.faint(self: any, side: string)
	local a: Actor = self.actors[side]
	if not a.model or a.gone then
		return
	end
	a.anim = { kind = "faint", t0 = os.clock(), dur = 1.6 / self.speed }
	self:shotTo("faint", side, 1.4, 3)
	for _ = 1, 14 do
		self:bubble(
			a.pos
				+ Vector3.new(
					self.rng:NextNumber(-2, 2),
					self.rng:NextNumber(-1, 1),
					self.rng:NextNumber(-1.5, 1.5)
				),
			self.rng:NextNumber(0.25, 0.6),
			self.rng:NextNumber(8, 16)
		)
	end
end

-- 交代や逃げる時: 後ろへ泳ぎ去る
function BattleScene.leave(self: any, side: string)
	local a: Actor = self.actors[side]
	if a.model and not a.gone then
		a.anim = { kind = "leave", t0 = os.clock(), dur = 0.55 / self.speed }
	end
end

function BattleScene.setEnraged(self: any, on: boolean)
	local a: Actor = self.actors.enemy
	local red = Color3.fromRGB(240, 60, 50)
	if on and not self.enraged then
		self:flash(red, 0.4)
		self:ring(a.pos, red, 22, 0.7)
		self:light(a.pos, red, 6, 30, 1)
		self:shake(14)
		self:shotTo("boss", nil, 1.2, 3)
	end
	if a.aura then
		a.aura.Color = ColorSequence.new(if on then red else Color3.fromRGB(150, 90, 230))
		a.aura.Rate = if on then 40 else 18
	end
	if a.auraLight then
		a.auraLight.Color = if on then red else Color3.fromRGB(150, 90, 230)
	end
	self.enraged = on
end

-- 演出の部品(3D) --------------------------------------------------------------------
function BattleScene.bubble(self: any, at: Vector3, size: number, rise: number)
	local b = fxPart(self, {
		Name = "Bubble",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(size, size, size),
		CFrame = CFrame.new(at),
		Color = Color3.fromRGB(225, 248, 255),
		Material = Enum.Material.Glass,
		Transparency = 0.45,
		Reflectance = 0.2,
	})
	local dur = rise / 4
	TweenService:Create(
		b,
		TweenInfo.new(dur, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
		{ CFrame = CFrame.new(at + Vector3.new(self.rng:NextNumber(-0.6, 0.6), rise, 0)) }
	):Play()
	later(dur, function()
		b:Destroy()
	end)
end

-- 光る粒が四方へ
function BattleScene.burst(
	self: any,
	at: Vector3,
	color: Color3,
	n: number,
	radius: number,
	size: number,
	dur: number,
	material: Enum.Material?
)
	for _ = 1, n do
		local dir = Vector3.new(
			self.rng:NextNumber(-1, 1),
			self.rng:NextNumber(-1, 1),
			self.rng:NextNumber(-0.6, 0.6)
		)
		if dir.Magnitude < 0.05 then
			dir = Vector3.new(0, 1, 0)
		end
		local d = size * self.rng:NextNumber(0.6, 1.3)
		local p = fxPart(self, {
			Name = "Spark",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(d, d, d),
			CFrame = CFrame.new(at),
			Color = color,
			Material = material or Enum.Material.Neon,
			Transparency = if material then 0.4 else 0,
		})
		TweenService:Create(p, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = CFrame.new(at + dir.Unit * radius * self.rng:NextNumber(0.6, 1.1)),
			Size = Vector3.new(d, d, d) * 0.3,
			Transparency = 1,
		}):Play()
		later(dur, function()
			p:Destroy()
		end)
	end
end

-- カメラの方を向いた衝撃の輪
function BattleScene.ring(self: any, at: Vector3, color: Color3, size: number, dur: number)
	local camPos = if self.cameraCFrame then self.cameraCFrame.Position else at + Vector3.new(0, 0, 30)
	-- 円柱の X 軸をカメラへ(円盤がこちらを向く)。裏表が同じ形なので向きの正負は気にしない
	local cf = CFrame.lookAt(at, camPos) * CFrame.Angles(0, math.pi / 2, 0)
	local r = fxPart(self, {
		Name = "Ring",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.15, 1, 1),
		CFrame = cf,
		Color = color,
		Transparency = 0.15,
	})
	TweenService:Create(
		r,
		TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.15, size, size), Transparency = 1 }
	):Play()
	later(dur, function()
		r:Destroy()
	end)
end

function BattleScene.light(
	self: any,
	at: Vector3,
	color: Color3,
	brightness: number,
	range: number,
	dur: number
)
	local p = fxPart(self, {
		Name = "Glow",
		Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = CFrame.new(at),
		Transparency = 1,
	})
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Parent = p
	TweenService:Create(l, TweenInfo.new(dur), { Brightness = 0 }):Play()
	later(dur, function()
		p:Destroy()
	end)
end

-- 粒子(炎・砂けむり・きらきら)
function BattleScene.emit(
	self: any,
	at: Vector3,
	texture: string,
	color: Color3,
	count: number,
	size: number,
	speed: number,
	life: number
)
	local p = fxPart(self, {
		Name = "Emitter",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(at),
		Transparency = 1,
	})
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Rate = 0
	e.Color = ColorSequence.new(color)
	e.Size = NumberSequence.new(size, size * 0.3)
	e.Transparency = NumberSequence.new(0.1, 1)
	e.Lifetime = NumberRange.new(life * 0.6, life)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.LightEmission = 0.8
	e.Parent = p
	pcall(function()
		e:Emit(count)
	end)
	later(life + 0.2, function()
		p:Destroy()
	end)
end

-- 稲妻: 上からジグザグに落ちる
function BattleScene.bolt(self: any, at: Vector3, height: number)
	local points = { at + Vector3.new(self.rng:NextNumber(-2, 2), height, 0) }
	for i = 1, 5 do
		local f = 1 - i / 6
		table.insert(
			points,
			at + Vector3.new(self.rng:NextNumber(-1.4, 1.4), height * f, self.rng:NextNumber(-0.6, 0.6))
		)
	end
	table.insert(points, at)
	for i = 1, #points - 1 do
		local a, b = points[i], points[i + 1]
		local seg = fxPart(self, {
			Name = "Bolt",
			Size = Vector3.new(0.35, 0.35, (b - a).Magnitude),
			CFrame = CFrame.lookAt((a + b) / 2, b),
			Color = Color3.fromRGB(255, 240, 150),
		})
		TweenService:Create(seg, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		later(0.32, function()
			seg:Destroy()
		end)
	end
	self:light(at, Color3.fromRGB(255, 240, 150), 8, 30, 0.35)
end

-- 当たった魚が光る
function BattleScene.highlight(self: any, model: Model, color: Color3)
	local h = Instance.new("Highlight")
	h.Adornee = model
	h.FillColor = color
	h.FillTransparency = 0.15
	h.OutlineColor = Color3.new(1, 1, 1)
	h.OutlineTransparency = 0.3
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = self.fx
	TweenService:Create(h, TweenInfo.new(0.4), { FillTransparency = 1, OutlineTransparency = 1 }):Play()
	later(0.42, function()
		h:Destroy()
	end)
end

-- 技の属性ごとの当たり方
function BattleScene.effect(self: any, at: Vector3, element: string, strong: boolean)
	local col = elementColor(element)
	local n = if strong then 18 else 12
	if element == "water" then
		self:ring(at, Color3.fromRGB(200, 240, 255), 10, 0.5)
		self:burst(at, Color3.fromRGB(225, 248, 255), n, 5, 0.5, 0.6, Enum.Material.Glass)
		for _ = 1, 8 do
			self:bubble(
				at + Vector3.new(self.rng:NextNumber(-1.5, 1.5), 0, self.rng:NextNumber(-1, 1)),
				0.4,
				8
			)
		end
	elseif element == "fire" then
		self:emit(at, TEX.fire, Color3.fromRGB(255, 140, 50), 40, 2.4, 8, 0.7)
		self:burst(at, Color3.fromRGB(255, 120, 40), n, 5.5, 0.45, 0.55)
		self:light(at, Color3.fromRGB(255, 150, 60), 6, 24, 0.6)
	elseif element == "thunder" then
		self:bolt(at, 14)
		self:flash(Color3.fromRGB(255, 240, 160), 0.35)
		self:burst(at, col, n, 6, 0.3, 0.35)
	elseif element == "earth" then
		self:emit(at, TEX.smoke, Color3.fromRGB(176, 146, 98), 26, 3, 5, 1.1)
		self:burst(at, Color3.fromRGB(110, 96, 80), n, 5, 0.7, 0.8, Enum.Material.Slate)
	elseif element == "spirit" then
		self:ring(at, col, 12, 0.7)
		self:burst(at, col, n, 6, 0.5, 0.9)
		self:light(at, col, 5, 24, 0.9)
	else
		self:ring(at, Color3.new(1, 1, 1), 9, 0.45)
		self:burst(at, Color3.fromRGB(240, 240, 255), n, 4.5, 0.4, 0.45)
	end
end

-- 数字(ダメージ・回復)が魚の上に浮かぶ
function BattleScene.float(self: any, side: string, text: string, color: Color3)
	local a: Actor = self.actors[side]
	local bb = Instance.new("BillboardGui")
	bb.Adornee = a.anchor
	bb.Size = UDim2.fromOffset(240, 64)
	bb.StudsOffset = Vector3.new(0, 3, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Parent = self.folder
	local l = Kit.label({
		Size = UDim2.fromScale(1, 1),
		Text = text,
		TextColor3 = color,
		Font = Theme.Fonts.title,
		MaxTextSize = 46,
		Parent = bb,
	})
	Kit.new("UIStroke", { Color = Color3.fromRGB(10, 20, 40), Thickness = 3, Parent = l })
	local info = TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(bb, info, { StudsOffset = Vector3.new(0, 6, 0) }):Play()
	TweenService:Create(l, info, { TextTransparency = 1 }):Play()
	later(0.95, function()
		bb:Destroy()
	end)
end

function BattleScene.flash(self: any, color: Color3, alpha: number)
	local f = self.flashFrame
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 1 - alpha
	TweenService:Create(f, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
end

function BattleScene.shake(self: any, power: number)
	self.shakeUntil = os.clock() + 0.35
	self.shakePower = power
end

function BattleScene.destroy(self: any)
	if self.conn then
		self.conn:Disconnect()
		self.conn = nil
	end
	-- カメラと光を元に戻す
	local cam = self.camera
	if cam and self.camSaved then
		cam.CameraType = self.camSaved.type or Enum.CameraType.Custom
		if self.camSaved.subject then
			cam.CameraSubject = self.camSaved.subject
		end
		if self.camSaved.fov then
			cam.FieldOfView = self.camSaved.fov
		end
	end
	restoreLook(self)
	LightingFX.hold(false)
	-- 魚と演出を片付け、舞台はしまっておく(次のバトルで使い回す)
	self.folder:Destroy()
	for _, c in self.fx:GetChildren() do
		c:Destroy()
	end
	self.arena.folder.Parent = nil
	if self.flashFrame then
		self.flashFrame:Destroy()
	end
end

return BattleScene
