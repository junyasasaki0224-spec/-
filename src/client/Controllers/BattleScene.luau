--!strict
-- バトルの舞台は「水の中」。2匹は水中を泳ぎ回り、技を出す時は相手へ泳いでぶつかる。
-- 背景(水の色・光の筋・海藻・砂・泡)は2D、魚は1つの ViewportFrame の中の3D(真横から見る)。
-- 演出だけを受け持つ(勝ち負け・ダメージはサーバーが決め、BattleUI が順番に呼ぶ)。
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local FishBuilder = require(Shared.Lib.FishBuilder)

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)

local BattleScene = {}

-- カメラ: 真横から、まっすぐ奥(-Z)を見る(回転なし)
local CAMERA = CFrame.new(0, 0.5, 34)
local FOV = 38
local HOME = { player = Vector3.new(-7, 0.6, 0), enemy = Vector3.new(7, 0.6, 0) }
local OFFSCREEN = 26 -- ここまで離れると画面の外
local LENGTH = 6 -- 魚の長さ(スタッド)。どの魚も同じ大きさで戦う
local BOSS_LENGTH = 9.5
local MARGIN = 16 -- 揺れの分だけ画面の外まで広げる

-- 3D の点 → 画面の割合(0〜1)。視野角は縦、aspect は 横/縦
function BattleScene.project(camera: CFrame, fov: number, aspect: number, p: Vector3): (number, number)
	local rel = camera:PointToObjectSpace(p)
	local depth = math.max(0.01, -rel.Z)
	local t = math.tan(math.rad(fov / 2))
	return 0.5 + rel.X / (depth * t * aspect) / 2, 0.5 - rel.Y / (depth * t) / 2
end
local project = BattleScene.project

local function ease(x: number): number
	return x * x * (3 - 2 * x)
end

local function elementColor(el: string?): Color3
	local e = el and Config.ElementById[el]
	return if e then Color3.fromHex(e.color) else Color3.new(1, 1, 1)
end

local function seq(points: { { number } }): NumberSequence
	local kps = {}
	for _, p in points do
		table.insert(kps, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(kps)
end

type Anim = { kind: string, t0: number, dur: number, target: Vector3? }
type Actor = {
	side: string,
	facing: number, -- +1 右向き(自分) / -1 左向き(相手)
	home: Vector3,
	phase: number,
	model: Model?,
	fishId: string,
	element: string,
	center: Vector3, -- ピボットから見たモデルの中心
	length: number,
	ray: boolean,
	pos: Vector3,
	anim: Anim?,
	gone: boolean, -- 倒れた・交代で泳ぎ去った
	tag: Frame, -- 魚について回る見えない枠(吹き出し・数字の置き場)
	nextBubble: number,
}

export type Scene = any

-- 背景 -------------------------------------------------------------------------
local function layer(root: Instance, name: string, z: number): Frame
	return Kit.new("Frame", {
		Name = name,
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = z,
		Parent = root,
	})
end

-- 海藻の房。根元を中心に回したいので、高さ2倍の枠の上半分に葉を置く
local function kelp(
	parent: Instance,
	x: number,
	height: number,
	width: number,
	color: Color3,
	haze: number,
	list: { any }
)
	for j = 1, 3 do
		local h = height * (0.7 + ((j * 37) % 10) / 25)
		local holder = Kit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(x, (j - 2) * width * 0.8, 0.93, 0),
			Size = UDim2.fromOffset(width, h * 2),
			BackgroundTransparency = 1,
			Parent = parent,
		})
		local blade = Kit.new("Frame", {
			Size = UDim2.fromScale(1, 0.5),
			BackgroundColor3 = color,
			BackgroundTransparency = haze,
			BorderSizePixel = 0,
			Parent = holder,
		})
		Kit.corner(blade, UDim.new(1, 0))
		Kit.gradient(blade, color:Lerp(Color3.fromRGB(120, 200, 150), 0.25), color, 90)
		table.insert(list, { frame = holder, base = (j - 2) * 8, seed = x * 13 + j })
	end
end

local function build(self: any, parent: Instance)
	-- 画面より少し大きく作る(揺れた時に端が見えないように)
	local root = Kit.new("Frame", {
		Name = "Underwater",
		Size = UDim2.new(1, 2 * MARGIN, 1, 2 * MARGIN),
		Position = UDim2.fromOffset(-MARGIN, -MARGIN),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 0,
		Parent = parent,
	})
	-- 水面に近いほど明るく、深いほど暗い
	Kit.gradient(root, Color3.fromRGB(70, 160, 196), Color3.fromRGB(6, 24, 48), 90)
	self.root = root

	-- 水面のゆらめき
	local surface = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0.16, 0),
		BackgroundColor3 = Color3.fromRGB(190, 240, 250),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		ZIndex = 1,
		Parent = root,
	})
	Kit.new("UIGradient", { Rotation = 90, Transparency = seq({ { 0, 0.2 }, { 1, 1 } }), Parent = surface })

	-- 光の筋
	local rays = layer(root, "Rays", 2)
	self.rays = {}
	for i = 1, 6 do
		local f = Kit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.04 + (i - 1) * 0.19, 0, -0.1, 0),
			Size = UDim2.new(0, 50 + (i * 41) % 90, 1, 0),
			BackgroundColor3 = Color3.fromRGB(215, 248, 255),
			BackgroundTransparency = 0.8,
			BorderSizePixel = 0,
			Rotation = 16,
			Parent = rays,
		})
		Kit.new("UIGradient", {
			Rotation = 90,
			Transparency = seq({ { 0, 0.15 }, { 0.55, 0.8 }, { 1, 1 } }),
			Parent = f,
		})
		table.insert(self.rays, { frame = f, base = 12 + i * 1.5, seed = i * 1.7 })
	end

	-- 奥: 砂・岩・海藻(かすんで見える)
	local back = layer(root, "Back", 3)
	type Dune = { x: number, y: number, w: number, color: Color3 }
	local dunes: { Dune } = {
		{ x = 0.18, y = 0.86, w = 0.75, color = Color3.fromRGB(150, 132, 96) },
		{ x = 0.78, y = 0.88, w = 0.85, color = Color3.fromRGB(138, 120, 88) },
		{ x = 0.5, y = 0.92, w = 1.3, color = Color3.fromRGB(168, 148, 106) },
	}
	for _, d in dunes do
		local dune = Kit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(d.x, d.y),
			Size = UDim2.fromScale(d.w, 0.4),
			BackgroundColor3 = d.color,
			BackgroundTransparency = 0.3, -- 水の奥でかすむ
			BorderSizePixel = 0,
			Parent = back,
		})
		Kit.corner(dune, UDim.new(1, 0))
		Kit.gradient(dune, d.color, d.color:Lerp(Color3.fromRGB(30, 30, 40), 0.6), 90)
	end
	for _, r in { { 0.3, 64, 40 }, { 0.62, 90, 52 }, { 0.9, 50, 34 } } do
		local rock = Kit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(r[1], 0, 0.9, 0),
			Size = UDim2.fromOffset(r[2], r[3]),
			BackgroundColor3 = Color3.fromRGB(48, 62, 72),
			BackgroundTransparency = 0.3,
			BorderSizePixel = 0,
			Parent = back,
		})
		Kit.corner(rock, UDim.new(0.45, 0))
	end
	self.kelp = {}
	local backKelp = Color3.fromRGB(34, 96, 84)
	for _, k in
		{ { 0.07, 190, 16 }, { 0.24, 130, 13 }, { 0.46, 90, 11 }, { 0.71, 120, 13 }, { 0.88, 200, 17 } }
	do
		kelp(back, k[1], k[2], k[3], backKelp, 0.3, self.kelp)
	end
	self.auraLayer = layer(root, "Aura", 4)

	-- 魚の泳ぐ3D
	local vpf = Kit.new("ViewportFrame", {
		Name = "Water",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(120, 160, 200),
		LightColor = Color3.fromRGB(210, 240, 255),
		LightDirection = Vector3.new(-0.3, -1, -0.4),
		ImageColor3 = Color3.fromRGB(205, 230, 245), -- 水の青みを少し
		ZIndex = 5,
		Parent = root,
	})
	local cam = Instance.new("Camera")
	cam.FieldOfView = FOV
	cam.CFrame = CAMERA
	cam.Parent = vpf
	vpf.CurrentCamera = cam
	self.vpf = vpf

	-- 手前の海藻(暗い影)
	local front = layer(root, "Front", 6)
	for _, k in { { 0.015, 250, 22 }, { 0.985, 230, 20 } } do
		kelp(front, k[1], k[2], k[3], Color3.fromRGB(10, 44, 40), 0, self.kelp)
	end

	self.bubbleLayer = layer(root, "Bubbles", 7)
	self.fx = layer(root, "Effects", 8)
end

-- 1匹分 --------------------------------------------------------------------------
local function newActor(self: any, side: string): Actor
	local tag = Kit.new("Frame", {
		Name = side .. "Tag",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(200, 130),
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(if side == "player" then 0.33 else 0.67, 0.5),
		Parent = self.fx,
	})
	return {
		side = side,
		facing = if side == "player" then 1 else -1,
		home = HOME[side],
		phase = if side == "player" then 0 else 2.4,
		model = nil,
		fishId = "",
		element = "none",
		center = Vector3.zero,
		length = LENGTH,
		ray = false,
		pos = HOME[side],
		anim = nil,
		gone = true,
		tag = tag,
		nextBubble = 0,
	}
end

function BattleScene.new(parent: Instance, opts: { boss: boolean? }?): Scene
	local self: any = setmetatable({}, { __index = BattleScene })
	self.rng = Random.new()
	self.boss = opts ~= nil and opts.boss == true
	self.enraged = false
	self.shakeUntil = 0
	self.shakePower = 0
	self.nextAmbient = 0
	build(self, parent)
	self.actors = { player = newActor(self, "player"), enemy = newActor(self, "enemy") }
	if self.boss then
		-- ボスのまわりの妖気(怒ると赤く)
		self.aura = {}
		for i, size in { 330, 250, 180 } do
			local f = Kit.new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Size = UDim2.fromOffset(size, size * 0.8),
				BackgroundColor3 = Color3.fromRGB(150, 90, 220),
				BackgroundTransparency = 0.82 + i * 0.02,
				Parent = self.auraLayer,
			})
			Kit.corner(f, UDim.new(1, 0))
			table.insert(self.aura, f)
		end
	end
	self.conn = RunService.RenderStepped:Connect(function()
		self:step(os.clock())
	end)
	return self
end

function BattleScene.aspect(self: any): number
	local s = self.vpf.AbsoluteSize
	return if typeof(s) == "Vector2" and s.Y > 0 then s.X / s.Y else 16 / 9
end

-- 画面の上の位置(0〜1)
function BattleScene.screenPos(self: any, side: string): (number, number)
	return project(CAMERA, FOV, self:aspect(), self.actors[side].pos)
end

-- 毎フレーム: 泳ぎ・技の動き・背景のゆらぎ・泡
function BattleScene.place(self: any, a: Actor, t: number)
	local ph = a.phase
	-- ふだんは自分の側をゆったり泳ぎ回る
	local idle = a.home
		+ Vector3.new(
			math.sin(t * 0.55 + ph) * 1.3,
			math.sin(t * 0.83 + ph * 1.7) * 0.8,
			math.sin(t * 0.37 + ph) * 1.4
		)
	local pos = idle
	local heading = a.facing
	local roll, beat = 0, 1
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
			pos = idle + Vector3.new(-a.facing * 1.8 * math.sin(p * math.pi), 0, 0)
			roll = math.sin(p * 28) * 0.3 * (1 - p)
		elseif k == "dodge" then
			pos = idle + Vector3.new(0, 2.4 * math.sin(p * math.pi), 1.5 * math.sin(p * math.pi))
			beat = 2
		elseif k == "hop" then
			pos = idle + Vector3.new(0, 1.3 * math.sin(p * math.pi), 0)
			roll = math.sin(p * math.pi * 2) * 0.35
		elseif k == "faint" then
			-- お腹を上にして、水面へ浮かんでいく
			roll = math.min(p / 0.3, 1) * math.pi
			pos = idle + Vector3.new(0, math.max(0, p - 0.3) * 20, 0)
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
	local model = a.model
	if model and not a.gone then
		-- 頭(-Z)を進む向きへ。少しだけカメラの方へ向けて、顔が見えるように
		local base = if heading > 0 then -math.pi / 2 - 0.35 else math.pi / 2 + 0.35
		local wiggle = math.sin(t * 7 * beat + ph) * 0.09 * math.min(beat, 1.6) -- 尾をふる
		local pitch = math.cos(t * 0.83 + ph * 1.7) * 0.12
		local tilt = if a.ray then 0.55 else 0 -- 鱏は背中を見せる
		model:PivotTo(
			CFrame.new(pos)
				* CFrame.Angles(tilt, 0, 0)
				* CFrame.Angles(0, base + wiggle, 0)
				* CFrame.Angles(pitch, 0, roll)
				* CFrame.new(-a.center)
		)
	end
	local x, y = project(CAMERA, FOV, self:aspect(), pos)
	a.tag.Position = UDim2.fromScale(x, y)
	-- 口から小さな泡
	if model and not a.gone and t >= a.nextBubble then
		a.nextBubble = t + self.rng:NextNumber(1.2, 2.6)
		local hx, hy =
			project(CAMERA, FOV, self:aspect(), pos + Vector3.new(heading * a.length * 0.45, 0.3, 0.5))
		self:bubble(hx, hy, self.rng:NextNumber(5, 9), 160, 2.2)
	end
end

function BattleScene.step(self: any, t: number)
	for _, r in self.rays do
		r.frame.Rotation = r.base + math.sin(t * 0.25 + r.seed) * 4
		r.frame.BackgroundTransparency = 0.8 + 0.07 * math.sin(t * 0.5 + r.seed * 1.3)
	end
	for _, k in self.kelp do
		k.frame.Rotation = k.base + math.sin(t * 0.9 + k.seed) * 7
	end
	for _, a in self.actors do
		self:place(a, t)
	end
	-- ボスの妖気
	if self.aura then
		local boss = self.actors.enemy
		local pulse = 1 + math.sin(t * (if self.enraged then 5 else 2)) * 0.06
		local color = if self.enraged then Color3.fromRGB(240, 60, 50) else Color3.fromRGB(150, 90, 220)
		for i, f in self.aura do
			f.Position = boss.tag.Position
			f.Visible = boss.model ~= nil and not boss.gone
			f.BackgroundColor3 = color
			local base = ({ 330, 250, 180 })[i] * pulse
			f.Size = UDim2.fromOffset(base, base * 0.8)
		end
	end
	-- 下から上る泡
	if t >= self.nextAmbient then
		self.nextAmbient = t + self.rng:NextNumber(0.25, 0.55)
		self:bubble(
			self.rng:NextNumber(0.03, 0.97),
			1.02,
			self.rng:NextNumber(6, 16),
			780,
			self.rng:NextNumber(5, 8)
		)
	end
	-- 画面のゆれ
	if t < self.shakeUntil then
		local s = self.shakePower * (self.shakeUntil - t) / 0.35
		self.root.Position =
			UDim2.fromOffset(-MARGIN + self.rng:NextNumber(-s, s), -MARGIN + self.rng:NextNumber(-s, s))
	else
		self.root.Position = UDim2.fromOffset(-MARGIN, -MARGIN)
	end
end

-- 魚を出す(how = "enter" なら横から泳いでくる)
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
	local model = FishBuilder.build(def, { mutation = mutation, noRarityScale = true })
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
	a.element = def.element
	model.Parent = self.vpf
	a.model = model
	a.gone = false
	a.anim = if how == "enter" then { kind = "enter", t0 = os.clock(), dur = 0.9 } else nil
	self:place(a, os.clock())
end

function BattleScene.hasFish(self: any, side: string, fishId: string?): boolean
	local a: Actor = self.actors[side]
	return a.model ~= nil and not a.gone and (fishId == nil or a.fishId == fishId)
end

function BattleScene.tag(self: any, side: string): Frame
	return self.actors[side].tag
end

local function other(side: string): string
	return if side == "player" then "enemy" else "player"
end

-- 攻撃: 相手へ泳いでぶつかり、戻る(当たるのは約0.25秒後)
function BattleScene.attack(self: any, side: string)
	local a: Actor = self.actors[side]
	local foe: Actor = self.actors[other(side)]
	if not a.model or a.gone then
		return
	end
	local gap = (foe.length + a.length) * 0.4
	a.anim =
		{ kind = "dash", t0 = os.clock(), dur = 0.75, target = foe.pos - Vector3.new(a.facing * gap, 0, 0) }
end

-- 補助の技・強くなった/弱くなった: その場で跳ねて光る
function BattleScene.cast(self: any, side: string, color: Color3)
	local a: Actor = self.actors[side]
	a.anim = { kind = "hop", t0 = os.clock(), dur = 0.6 }
	local x, y = self:screenPos(side)
	self:ring(x, y, color, 190, 0.6)
	self:burst(x, y, color, 8, 80, 9, 0.6)
end

-- 当たった(side = 当たった方)
function BattleScene.hit(self: any, side: string, element: string, eff: number, crit: boolean)
	local a: Actor = self.actors[side]
	if a.model and not a.gone then
		a.anim = { kind = "knock", t0 = os.clock(), dur = 0.5 }
	end
	local x, y = self:screenPos(side)
	local strong = eff > 1 or crit
	self:effect(x, y, element, strong)
	if eff > 1 then
		self:ring(x, y, Color3.fromRGB(255, 227, 160), 260, 0.5)
	end
	if crit then
		self:flash(Color3.new(1, 1, 1), 0.55)
	end
	self:shake(if strong then 12 else 5)
end

-- かわした(side = かわした方)
function BattleScene.dodge(self: any, side: string)
	local a: Actor = self.actors[side]
	a.anim = { kind = "dodge", t0 = os.clock(), dur = 0.55 }
	local x, y = self:screenPos(side)
	self:ring(x, y, Color3.fromRGB(200, 240, 255), 120, 0.4)
end

function BattleScene.heal(self: any, side: string)
	local x, y = self:screenPos(side)
	self:ring(x, y, Color3.fromRGB(120, 230, 140), 170, 0.6)
	for _ = 1, 8 do
		self:bubble(
			x + self.rng:NextNumber(-0.04, 0.04),
			y + self.rng:NextNumber(0, 0.05),
			self.rng:NextNumber(6, 11),
			120,
			0.9,
			Color3.fromRGB(150, 255, 170)
		)
	end
end

function BattleScene.stun(self: any, side: string)
	local x, y = self:screenPos(side)
	self:burst(x, y, Color3.fromRGB(255, 220, 90), 10, 70, 6, 0.4)
	self:pop(x, y - 0.12, "⚡", 54)
end

-- 倒れた: お腹を上にして水面へ。泡がはじける
function BattleScene.faint(self: any, side: string)
	local a: Actor = self.actors[side]
	if not a.model or a.gone then
		return
	end
	a.anim = { kind = "faint", t0 = os.clock(), dur = 1.6 }
	local x, y = self:screenPos(side)
	for _ = 1, 14 do
		self:bubble(
			x + self.rng:NextNumber(-0.05, 0.05),
			y + self.rng:NextNumber(-0.03, 0.05),
			self.rng:NextNumber(7, 15),
			self.rng:NextNumber(180, 320),
			self.rng:NextNumber(1.2, 2)
		)
	end
end

-- 交代や逃げる時: 後ろへ泳ぎ去る
function BattleScene.leave(self: any, side: string)
	local a: Actor = self.actors[side]
	if a.model and not a.gone then
		a.anim = { kind = "leave", t0 = os.clock(), dur = 0.55 }
	end
end

function BattleScene.setEnraged(self: any, on: boolean)
	if on and not self.enraged then
		local x, y = self:screenPos("enemy")
		self:flash(Color3.fromRGB(255, 60, 40), 0.6)
		self:ring(x, y, Color3.fromRGB(255, 80, 60), 340, 0.7)
		self:shake(14)
	end
	self.enraged = on
end

-- 演出の部品 ---------------------------------------------------------------------
function BattleScene.bubble(
	self: any,
	x: number,
	y: number,
	size: number,
	rise: number,
	dur: number,
	color: Color3?
)
	local c = color or Color3.fromRGB(225, 248, 255)
	local b = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = c,
		BackgroundTransparency = 0.8,
		Parent = self.bubbleLayer,
	})
	Kit.corner(b, UDim.new(1, 0))
	Kit.stroke(b, c, 1.5, 0.3)
	local shine = Kit.new("Frame", {
		Size = UDim2.fromScale(0.32, 0.32),
		Position = UDim2.fromScale(0.2, 0.18),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.15,
		Parent = b,
	})
	Kit.corner(shine, UDim.new(1, 0))
	TweenService:Create(
		b,
		TweenInfo.new(dur, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
		{ Position = UDim2.new(x, self.rng:NextNumber(-12, 12), y, -rise) }
	):Play()
	task.delay(dur, function()
		b:Destroy()
	end)
end

function BattleScene.burst(
	self: any,
	x: number,
	y: number,
	color: Color3,
	n: number,
	radius: number,
	size: number,
	dur: number
)
	for i = 1, n do
		local a = (i / n) * math.pi * 2 + self.rng:NextNumber(-0.3, 0.3)
		local r = radius * self.rng:NextNumber(0.6, 1.1)
		local s = size * self.rng:NextNumber(0.6, 1.25)
		local p = Kit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, y),
			Size = UDim2.fromOffset(s, s),
			BackgroundColor3 = color,
			BackgroundTransparency = 0.05,
			Parent = self.fx,
		})
		Kit.corner(p, UDim.new(1, 0))
		TweenService:Create(p, TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(x, math.cos(a) * r, y, math.sin(a) * r),
			BackgroundTransparency = 1,
			Size = UDim2.fromOffset(s * 0.4, s * 0.4),
		}):Play()
		task.delay(dur, function()
			p:Destroy()
		end)
	end
end

function BattleScene.ring(self: any, x: number, y: number, color: Color3, size: number, dur: number?)
	local d = dur or 0.5
	local f = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromOffset(30, 30),
		BackgroundTransparency = 1,
		Parent = self.fx,
	})
	Kit.corner(f, UDim.new(1, 0))
	local s = Kit.stroke(f, color, 5, 0.1)
	local info = TweenInfo.new(d, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(f, info, { Size = UDim2.fromOffset(size, size) }):Play()
	TweenService:Create(s, info, { Transparency = 1, Thickness = 1 }):Play()
	task.delay(d, function()
		f:Destroy()
	end)
end

function BattleScene.glow(self: any, x: number, y: number, color: Color3, size: number)
	local f = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromOffset(size * 0.4, size * 0.4),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.35,
		Parent = self.fx,
	})
	Kit.corner(f, UDim.new(1, 0))
	TweenService:Create(
		f,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1 }
	):Play()
	task.delay(0.5, function()
		f:Destroy()
	end)
end

function BattleScene.flash(self: any, color: Color3, alpha: number)
	local f = Kit.new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = color,
		BackgroundTransparency = 1 - alpha,
		BorderSizePixel = 0,
		Parent = self.fx,
	})
	TweenService:Create(f, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
	task.delay(0.36, function()
		f:Destroy()
	end)
end

function BattleScene.pop(self: any, x: number, y: number, text: string, size: number)
	local l = Kit.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(x, y),
		Size = UDim2.fromOffset(size, size),
		Text = text,
		MaxTextSize = size,
		Parent = self.fx,
	})
	local s = Kit.new("UIScale", { Scale = 0.3, Parent = l })
	TweenService:Create(s, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1.2 }):Play()
	task.delay(0.45, function()
		TweenService:Create(l, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
		task.wait(0.26)
		l:Destroy()
	end)
end

-- 技の属性ごとの当たり方
function BattleScene.effect(self: any, x: number, y: number, element: string, strong: boolean)
	local col = elementColor(element)
	local n = if strong then 16 else 11
	if element == "water" then
		self:ring(x, y, Color3.fromRGB(200, 240, 255), 180)
		self:burst(x, y, Color3.fromRGB(225, 248, 255), n, 100, 12, 0.55)
		for _ = 1, 6 do
			self:bubble(x, y, self.rng:NextNumber(8, 14), self.rng:NextNumber(90, 200), 1)
		end
	elseif element == "fire" then
		self:glow(x, y, Color3.fromRGB(255, 150, 60), 220)
		self:burst(x, y, Color3.fromRGB(255, 120, 40), n, 115, 14, 0.55)
		self:burst(x, y, Color3.fromRGB(255, 225, 130), math.floor(n / 2), 70, 9, 0.45)
	elseif element == "thunder" then
		self:flash(Color3.fromRGB(255, 240, 160), 0.45)
		self:pop(x, y - 0.06, "⚡", 96)
		self:burst(x, y, col, n, 130, 8, 0.35)
	elseif element == "earth" then
		self:glow(x, y, Color3.fromRGB(150, 122, 84), 250)
		self:burst(x, y, Color3.fromRGB(176, 146, 98), n + 4, 105, 18, 0.8)
	elseif element == "spirit" then
		self:ring(x, y, col, 210, 0.7)
		self:burst(x, y, col, n, 125, 12, 0.9)
	else
		self:ring(x, y, Color3.new(1, 1, 1), 160)
		self:burst(x, y, Color3.fromRGB(240, 240, 255), n, 95, 10, 0.45)
	end
end

-- 数字(ダメージ・回復)が魚から浮かぶ
function BattleScene.float(self: any, side: string, text: string, color: Color3)
	local x, y = self:screenPos(side)
	local l = Kit.label({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(x, 0, y, -40),
		Size = UDim2.fromOffset(220, 56),
		Text = text,
		TextColor3 = color,
		Font = Theme.Fonts.title,
		MaxTextSize = 44,
		Parent = self.fx,
	})
	Kit.new("UIStroke", { Color = Color3.fromRGB(10, 20, 40), Thickness = 3, Parent = l })
	TweenService:Create(
		l,
		TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.new(x, 0, y, -120), TextTransparency = 1 }
	):Play()
	task.delay(0.95, function()
		l:Destroy()
	end)
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
	self.root:Destroy()
end

return BattleScene
