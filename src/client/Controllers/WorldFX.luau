--!strict
-- ワールドの見た目(クライアントだけで動かす演出):
--   看板とボタンの翻訳 / ウキの投げ込みと浮き沈み / 水槽の魚 / 虹の変異 / ぬし / ランキング看板 / 頭上の称号
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Locale = require(Shared.Locale)
local Format = require(Shared.Lib.Format)
local Remotes = require(Shared.Lib.Remotes)

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local Root = require(script.Parent.Parent.UI.Root)
local Sound = require(script.Parent.Sound)
local C = Theme.Colors

local player = Players.LocalPlayer
local WorldFX = {}

-- 看板 ---------------------------------------------------------------
local function localizeSign(part: Instance)
	local key = part:GetAttribute("LocKey")
	local gui = part:FindFirstChild("SignGui")
	local label = gui and gui:FindFirstChild("Text") :: TextLabel?
	if type(key) ~= "string" or not label then
		return
	end
	if part.Name == "OwnerSign" then
		local hut = part.Parent
		local name = hut and hut:GetAttribute("OwnerName")
		if type(name) == "string" and name ~= "" then
			label.Text = Locale.t("tank_owner", { name = name })
		else
			label.Text = Locale.t("sign_my_hut")
		end
		return
	end
	label.Text = Locale.t(key)
end

local function localizePrompt(inst: Instance)
	if not inst:IsA("ProximityPrompt") then
		return
	end
	local prompt = inst :: ProximityPrompt
	local key = prompt:GetAttribute("LocKey")
	if type(key) == "string" then
		prompt.ActionText = Locale.t(key)
	end
	local action = prompt:GetAttribute("Action")
	if type(action) == "string" and action:sub(1, 7) == "travel:" then
		prompt.ObjectText = Locale.t("spot_" .. action:sub(8))
	end
end

function WorldFX.relocalize()
	for _, s in CollectionService:GetTagged("LocSign") do
		localizeSign(s)
	end
	for _, p in CollectionService:GetTagged("YokaiPrompt") do
		localizePrompt(p)
	end
end

-- ウキ -----------------------------------------------------------------
type BobberAnim = { part: BasePart, target: Vector3, start: Vector3, t0: number, splashed: boolean }
local bobbers: { [BasePart]: BobberAnim } = {}

local function splash(pos: Vector3, big: boolean)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.Transparency = 1
	p.Size = Vector3.one
	p.Position = pos
	p.Parent = workspace
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(Color3.fromRGB(220, 240, 255))
	pe.Size = NumberSequence.new(if big then 0.6 else 0.35, 0)
	pe.Lifetime = NumberRange.new(0.4, 0.8)
	pe.Speed = NumberRange.new(4, if big then 12 else 7)
	pe.SpreadAngle = Vector2.new(35, 35)
	pe.Acceleration = Vector3.new(0, -30, 0)
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Rate = 0
	pe.Parent = p
	pe:Emit(if big then 40 else 18)
	task.delay(1.5, function()
		p:Destroy()
	end)
end

local function addBobber(obj: Instance)
	if not obj:IsA("BasePart") then
		return
	end
	local inst = obj :: BasePart
	local ownerId = inst:GetAttribute("Owner")
	local owner = if type(ownerId) == "number" then Players:GetPlayerByUserId(ownerId) else nil
	local char = owner and owner.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local start = if root then root.Position + Vector3.new(0, 4, 0) else inst.Position + Vector3.new(0, 6, 0)
	bobbers[inst] = { part = inst, target = inst.Position, start = start, t0 = os.clock(), splashed = false }
	-- 自分のウキには「!」の看板
	if ownerId == player.UserId then
		local bb = Kit.new("BillboardGui", {
			Name = "BiteMark",
			Size = UDim2.fromOffset(80, 80),
			StudsOffset = Vector3.new(0, 3, 0),
			AlwaysOnTop = true,
			Enabled = false,
			Parent = inst,
		})
		local l = Kit.label({
			Size = UDim2.fromScale(1, 1),
			Text = "!",
			TextColor3 = C.goldLight,
			Font = Theme.Fonts.title,
			MaxTextSize = 80,
			Parent = bb,
		})
		Kit.new("UIStroke", { Color = C.vermilionDark, Thickness = 4, Parent = l })
	end
	inst:GetAttributeChangedSignal("State"):Connect(function()
		if inst:GetAttribute("State") == "bite" then
			splash(inst.Position, true)
			local bb = inst:FindFirstChild("BiteMark") :: BillboardGui?
			if bb then
				bb.Enabled = true
			end
		end
	end)
end

local function updateBobbers()
	local now = os.clock()
	for part, a in bobbers do
		if not part.Parent then
			bobbers[part] = nil
			continue
		end
		local t = (now - a.t0) / 0.55
		if t < 1 then
			-- 放物線で飛んでいく
			local pos = a.start:Lerp(a.target, t) + Vector3.new(0, math.sin(t * math.pi) * 8, 0)
			part.CFrame = CFrame.new(pos)
		else
			if not a.splashed then
				a.splashed = true
				splash(a.target, false)
			end
			local bite = part:GetAttribute("State") == "bite"
			local y = if bite then -0.45 + math.sin(now * 18) * 0.25 else math.sin(now * 2.2) * 0.08
			part.CFrame = CFrame.new(a.target + Vector3.new(0, y, 0))
		end
	end
end

-- 水槽の魚 / 虹 / ぬし ------------------------------------------------
type Swimmer = { model: Model, base: CFrame, phase: number, radius: number }
local swimmers: { [Model]: Swimmer } = {}

local function addSwimmer(obj: Instance)
	if not obj:IsA("Model") then
		return
	end
	local inst = obj :: Model
	local idx = inst:GetAttribute("Index")
	swimmers[inst] = {
		model = inst,
		base = inst:GetPivot(),
		phase = (if type(idx) == "number" then idx else 1) * 1.7,
		radius = 1.2,
	}
end

local rainbow: { [Model]: boolean } = {}
local nushi: { [Model]: CFrame } = {}

local function updateSwimmers(dt: number)
	local cam = workspace.CurrentCamera
	local camPos = if cam then cam.CFrame.Position else Vector3.zero
	local now = os.clock()
	for m, s in swimmers do
		if not m.Parent then
			swimmers[m] = nil
			continue
		end
		if (s.base.Position - camPos).Magnitude > 90 then
			continue
		end
		local a = now * 0.6 + s.phase
		local offset = Vector3.new(
			math.sin(a) * s.radius * 1.6,
			math.sin(a * 2) * 0.25,
			math.sin(a * 2) * s.radius * 0.4
		)
		local dir = Vector3.new(math.cos(a) * 1.6, 0, math.cos(a * 2) * 0.8)
		local cf = CFrame.new(s.base.Position + offset)
		if dir.Magnitude > 0.01 then
			cf = CFrame.lookAt(cf.Position, cf.Position + dir)
		end
		m:PivotTo(cf)
	end
	local hue = (now * 0.25) % 1
	for m in rainbow do
		if not m.Parent then
			rainbow[m] = nil
			continue
		end
		local body = m:FindFirstChild("Body") :: BasePart?
		if body then
			body.Color = Color3.fromHSV(hue, 0.6, 1)
		end
	end
	for m, base in nushi do
		if not m.Parent then
			nushi[m] = nil
			continue
		end
		local a = now * 0.35
		m:PivotTo(
			base
				* CFrame.new(math.sin(a) * 8, math.sin(now * 1.3) * 1.2, math.cos(a) * 8)
				* CFrame.Angles(0, -a, 0)
		)
	end
	local _ = dt
end

-- ランキング看板 ---------------------------------------------------------
local boardData: any = nil
local boardWorld = true

local function renderBoard()
	for _, board in CollectionService:GetTagged("RankingBoard") do
		local gui = board:FindFirstChild("RankingGui")
		if not gui then
			continue
		end
		gui:ClearAllChildren()
		local frame =
			Kit.new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.panel, Parent = gui })
		Kit.padding(frame, 18)
		Kit.label({
			Size = UDim2.new(1, 0, 0.12, 0),
			Text = Locale.t("rank_title") .. "  ·  " .. Locale.t(
				if boardWorld then "rank_world" else "rank_server"
			),
			TextColor3 = C.goldLight,
			Font = Theme.Fonts.title,
			MaxTextSize = 40,
			Parent = frame,
		})
		if not boardData then
			Kit.label({
				Size = UDim2.new(1, 0, 0.2, 0),
				Position = UDim2.fromScale(0, 0.4),
				Text = Locale.t("rank_loading"),
				Parent = frame,
			})
			continue
		end
		local src = if boardWorld then boardData.world else boardData.server
		local featured = Config.FishById[boardData.featured]
		local columns = {
			{
				title = Locale.t("rank_total"),
				rows = src.total,
				fmt = function(v)
					return tostring(v)
				end,
			},
			{
				title = Locale.t(
					"rank_heaviest",
					{ fish = if featured then Locale.fishName(featured) else "?" }
				),
				rows = src.heaviest,
				fmt = function(v)
					return Format.kg(v)
				end,
			},
		}
		for ci, col in columns do
			local x = (ci - 1) * 0.5
			Kit.label({
				Size = UDim2.new(0.48, 0, 0.09, 0),
				Position = UDim2.fromScale(x, 0.14),
				Text = col.title,
				TextColor3 = C.text,
				MaxTextSize = 30,
				Parent = frame,
			})
			for i = 1, 10 do
				local r = col.rows and col.rows[i]
				if not r then
					break
				end
				local medal = if i == 1
					then "🥇"
					elseif i == 2 then "🥈"
					elseif i == 3 then "🥉"
					else ("%d."):format(i)
				Kit.label({
					Size = UDim2.new(0.48, 0, 0.07, 0),
					Position = UDim2.fromScale(x, 0.24 + (i - 1) * 0.075),
					Text = ("%s  %s   %s"):format(medal, tostring(r.name):sub(1, 20), col.fmt(r.value)),
					TextXAlignment = Enum.TextXAlignment.Left,
					TextColor3 = if i <= 3 then C.goldLight else C.textDim,
					Font = Theme.Fonts.body,
					MaxTextSize = 26,
					Parent = frame,
				})
			end
		end
	end
end

-- 頭上の称号 ---------------------------------------------------------------
local function updateTitle(p: Player)
	local char = p.Character
	local head = char and char:FindFirstChild("Head")
	if not head then
		return
	end
	local bb = head:FindFirstChild("YokaiTitle") :: BillboardGui?
	local title = p:GetAttribute("Title")
	if type(title) ~= "string" or title == "" then
		if bb then
			bb:Destroy()
		end
		return
	end
	if not bb then
		bb = Kit.new("BillboardGui", {
			Name = "YokaiTitle",
			Size = UDim2.fromOffset(220, 30),
			StudsOffset = Vector3.new(0, 2.6, 0),
			MaxDistance = 60,
			Parent = head,
		})
		local l = Kit.label({
			Name = "L",
			Size = UDim2.fromScale(1, 1),
			Font = Theme.Fonts.title,
			MaxTextSize = 22,
			Parent = bb,
		})
		Kit.new("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1.5, Parent = l })
	end
	local l = (bb :: BillboardGui):FindFirstChild("L") :: TextLabel
	l.Text = "「" .. Locale.t("title_" .. title) .. "」"
	l.TextColor3 = if title == "vip" then C.goldLight else C.text
end

local function watchPlayer(p: Player)
	p:GetAttributeChangedSignal("Title"):Connect(function()
		updateTitle(p)
	end)
	p.CharacterAdded:Connect(function(char)
		char:WaitForChild("Head", 10)
		updateTitle(p)
	end)
	if p.Character then
		task.spawn(updateTitle, p)
	end
end

-- 初期化 -------------------------------------------------------------------
local function onTag(tag: string, fn: (Instance) -> ())
	CollectionService:GetInstanceAddedSignal(tag):Connect(fn)
	for _, inst in CollectionService:GetTagged(tag) do
		task.spawn(fn, inst)
	end
end

function WorldFX.init()
	onTag("LocSign", function(s)
		localizeSign(s)
		if s.Name == "OwnerSign" and s.Parent then
			s.Parent:GetAttributeChangedSignal("OwnerName"):Connect(function()
				localizeSign(s)
			end)
		end
	end)
	onTag("YokaiPrompt", localizePrompt)
	-- VIP の釣り座の門: VIP パスを持っている人だけ当たり判定を消す(自分の画面と自分のキャラクターだけに効く)
	local State = require(script.Parent.Parent.ClientState)
	local function refreshVipGates()
		local vip = State.hasPass("vip")
		for _, g in CollectionService:GetTagged("VipGate") do
			if g:IsA("BasePart") then
				g.CanCollide = not vip
				g.Transparency = if vip then 0.75 else 0.2
			end
		end
	end
	onTag("VipGate", refreshVipGates)
	player:GetAttributeChangedSignal("Passes"):Connect(refreshVipGates)
	onTag("Bobber", addBobber)
	onTag("TankFish", addSwimmer)
	onTag("RainbowFish", function(m)
		if m:IsA("Model") then
			rainbow[m] = true
		end
	end)
	onTag("Nushi", function(m)
		if m:IsA("Model") then
			nushi[m] = m:GetPivot()
			splash(m:GetPivot().Position, true)
		end
	end)

	-- 近づいて押すボタン(画面を開く系はクライアント、移動はサーバーが処理)
	ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who ~= player or not CollectionService:HasTag(prompt, "YokaiPrompt") then
			return
		end
		local action = prompt:GetAttribute("Action")
		if type(action) ~= "string" then
			return
		end
		Sound.play("click", 0.3)
		if action:sub(1, 10) == "open:shop:" then
			Root.open("shop", action:sub(11))
		elseif action == "open:quests" then
			Root.open("quests")
		elseif action == "open:tank" then
			local hut = prompt.Parent and prompt.Parent.Parent
			if hut and hut:GetAttribute("OwnerId") == player.UserId then
				Root.open("shop", "tank")
			end
		end
	end)

	for _, p in Players:GetPlayers() do
		watchPlayer(p)
	end
	Players.PlayerAdded:Connect(watchPlayer)

	RunService.RenderStepped:Connect(function(dt)
		updateBobbers()
		updateSwimmers(dt)
	end)

	-- ランキング: 1分ごとに取得、10秒ごとに 全世界/このサーバー を切り替え
	local query = Remotes.func("Query")
	task.spawn(function()
		while true do
			local ok, data = pcall(function()
				return query:InvokeServer("leaderboard")
			end)
			if ok and type(data) == "table" then
				boardData = data
			end
			for _ = 1, 6 do
				renderBoard()
				task.wait(10)
				boardWorld = not boardWorld
			end
		end
	end)
end

return WorldFX
