-- ガチャの演出(プレイヤー側。表示だけ。何が出るかはサーバーがもう決めている)。
--   GachaShow.play(gui, results, options)
--     results: { {item = Meta の品, dupe = かぶりで戻るコイン}, ... }
--     options: rarity(レア度の色)・outfit(今の装備 {skin, helmet, cowl, wheel, flag})・avatar(自分のアバターの人形。なくてもよい)・onDone
-- 流れ: 暗転して曲 → カプセルが落ちてきて震え、出た中でいちばん高いレア度の色まで光が変わる → 白く光って開く →
--       品を3Dで見せる(ヘルメットはそのヘルメット、塗装はその塗装の艇。自分のアバターが乗る)→
--       10回の時はタップで次へ(スキップで一覧)→ 一覧 → 閉じる
-- 色はレア度そのもの(出ていないレア度の色には変わらない)。
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local visuals = require(RS:WaitForChild("VisualModels"))
local outfit = require(RS:WaitForChild("Outfit"))
local Sfx = require(RS:WaitForChild("Sfx"))
local RacerAvatar = require(RS:WaitForChild("RacerAvatar"))

local GachaShow = {}
local Meta = require(RS:WaitForChild("Meta"))
local ORDER = { N = 1, R = 2, SR = 3, SSR = 4, UR = 5 }
local NAMES = { "N", "R", "SR", "SSR", "UR" }
local WHITE = Color3.new(1, 1, 1)
local HELMET_PARTS = { Helmet = true, HelmetStripe = true, Visor = true, Rubber = true }

local function tween(object, seconds, goal, style, direction)
	local t = TweenService:Create(
		object,
		TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out),
		goal
	)
	t:Play()
	return t
end

local function label(parent, text, size, color)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextSize = size
	t.Font = Enum.Font.GothamBlack
	t.TextColor3 = color or WHITE
	t.Size = UDim2.new(1, 0, 0, size + 8)
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Parent = parent
	return t
end

-- 回る光の筋(12本)。フレームは自分の真ん中で回るので、全面の入れ物ごと回す
local function rays(parent)
	local holder = Instance.new("Frame")
	holder.Name = "Rays"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.45)
	holder.SizeConstraint = Enum.SizeConstraint.RelativeXX
	holder.Size = UDim2.fromScale(1.6, 1.6)
	holder.Parent = parent
	local beams = {}
	for i = 1, 12 do
		local arm = Instance.new("Frame")
		arm.BackgroundTransparency = 1
		arm.Size = UDim2.fromScale(1, 1)
		arm.Rotation = i * 30
		arm.Parent = holder
		local beam = Instance.new("Frame")
		beam.BorderSizePixel = 0
		beam.AnchorPoint = Vector2.new(0.5, 1)
		beam.Position = UDim2.fromScale(0.5, 0.5)
		beam.Size = UDim2.fromScale(0.07, 0.5)
		beam.BackgroundColor3 = WHITE
		beam.Parent = arm
		local fadeOut = Instance.new("UIGradient")
		fadeOut.Rotation = 90
		fadeOut.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.6, 0.75),
			NumberSequenceKeypoint.new(1, 0.35),
		})
		fadeOut.Parent = beam
		table.insert(beams, beam)
	end
	return holder, beams
end

-- 3D の窓(ViewportFrame)と、その中のカメラ
local function viewport(parent)
	local view = Instance.new("ViewportFrame")
	view.Name = "Stage"
	view.BackgroundTransparency = 1
	view.AnchorPoint = Vector2.new(0.5, 0.5)
	view.Position = UDim2.fromScale(0.5, 0.45)
	view.SizeConstraint = Enum.SizeConstraint.RelativeYY
	view.Size = UDim2.fromScale(0.72, 0.72)
	view.Ambient = Color3.fromRGB(150, 160, 185)
	view.LightColor = Color3.fromRGB(255, 250, 240)
	view.LightDirection = Vector3.new(-0.6, -1, -0.5)
	view.Parent = parent
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.Parent = view
	view.CurrentCamera = camera
	return view, camera
end

-- カプセル(このゲームの丸いカプセル。上は光の色、下は白、真ん中に帯と留め金)
local function capsule()
	local model = Instance.new("Model")
	model.Name = "Capsule"
	local function ball(name, size, cf, color, material)
		local p = Instance.new("Part")
		p.Name = name
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.one * size
		p.CFrame = cf
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.Anchored = true
		p.Parent = model
		return p
	end
	local shell = ball("Shell", 4, CFrame.new(), WHITE, Enum.Material.Glass)
	shell.Transparency = 0.05
	local band = Instance.new("Part")
	band.Name = "Band"
	band.Shape = Enum.PartType.Cylinder
	band.Size = Vector3.new(0.45, 4.12, 4.12)
	band.CFrame = CFrame.Angles(0, 0, math.pi / 2)
	band.Color = Color3.fromRGB(235, 240, 248)
	band.Anchored = true
	band.Parent = model
	ball("Clasp", 0.9, CFrame.new(0, 0, -2), Color3.fromRGB(255, 210, 60), Enum.Material.Neon)
	-- 足元の水色の台
	local base = Instance.new("Part")
	base.Name = "Base"
	base.Shape = Enum.PartType.Cylinder
	base.Size = Vector3.new(0.4, 7, 7)
	base.CFrame = CFrame.new(0, -2.3, 0) * CFrame.Angles(0, 0, math.pi / 2)
	base.Color = Color3.fromRGB(40, 120, 170)
	base.Material = Enum.Material.SmoothPlastic
	base.Anchored = true
	base.Parent = model
	model.PrimaryPart = shell
	return model, shell
end

-- 今の装備(options.outfit。古い呼び方の options.skin / options.helmet にも合わせる)
local function currentOutfit(options)
	local o = options.outfit or {}
	return {
		skin = o.skin or options.skin,
		helmet = o.helmet or options.helmet,
		cowl = o.cowl,
		wheel = o.wheel,
		flag = o.flag,
	}
end

-- 品の部品(着せ替えで付けた部品。隠した元の部品は入れない)
local function itemParts(model)
	local list = {}
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") and p:GetAttribute("OutfitItem") then
			table.insert(list, p)
		end
	end
	return list
end

-- 出た品の3D と、カメラを向ける部品(なければ全体)。
--   艇外装・スタンダードの塗装: その艇(今のほかの装備・自分のアバターが乗る)
--   ヘルメット: そのヘルメットだけ
--   モーターカバー・ステアリング・艇首旗: 今の装備の艇に付けて、その部品を大きく見せる
local function itemModel(item, options)
	local boat = visuals.boat(nil)
	if not boat then
		return nil
	end
	local o = currentOutfit(options)
	o[item.kind] = item.id
	outfit(boat, o.skin, o.helmet, o.cowl, o.wheel, o.flag)
	if item.kind == "helmet" then
		local model = Instance.new("Model")
		model.Name = "Helmet"
		model:SetAttribute("Detailed", true)
		local upper = boat:FindFirstChild("RacerUpper") or boat
		for _, p in upper:GetDescendants() do
			if p:IsA("MeshPart") and p:GetAttribute("OutfitHidden") == nil then
				local material = p.Name:match("__(.-)__")
				if material and HELMET_PARTS[material] then
					p.Parent = model
				end
			end
		end
		boat:Destroy()
		return model, nil
	end
	if options.avatar then
		pcall(RacerAvatar.attach, boat, options.avatar)
	end
	if item.kind == "cowl" or item.kind == "wheel" or item.kind == "flag" then
		local focus = itemParts(boat)
		local keep = {}
		for _, p in focus do
			local material = p.Name:match("__(.-)__")
			if p.Name:sub(1, #item.id + 2) == item.id .. "__" and material then
				table.insert(keep, p)
			end
		end
		return boat, #keep > 0 and keep or nil
	end
	return boat, nil
end

-- 3D の品をカメラに収める(回転の中心と、離れる距離)。focus があれば、その部品を中心に大きく
local FOCUS_ZOOM = { cowl = 2.6, wheel = 2.4, flag = 2.8 }
local function frameModel(camera, model, kind, focus)
	local cf, size
	if focus then
		local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
		for _, p in focus do
			local c, half = p.CFrame, p.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local point = c:PointToWorldSpace(Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
						lo, hi = lo:Min(point), hi:Max(point)
					end
				end
			end
		end
		cf, size = CFrame.new((lo + hi) / 2), hi - lo
	else
		cf, size = model:GetBoundingBox()
	end
	local radius = size.Magnitude / 2
	local scale = focus and (FOCUS_ZOOM[kind] or 2.5) or (kind == "helmet" and 1.15 or 0.82)
	local distance = radius / math.tan(math.rad(camera.FieldOfView / 2)) * scale
	return cf.Position, distance
end

function GachaShow.play(gui, results, options)
	options = options or {}
	local rarityColor = options.rarity or {}
	local best = 1
	for _, r in results do
		best = math.max(best, ORDER[r.item.r] or 1)
	end
	local links = {}
	local overlay = Instance.new("Frame")
	overlay.Name = "GachaShow"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(5, 10, 24)
	overlay.BackgroundTransparency = 1
	overlay.Active = true
	-- 専用の画面(いちばん手前・画面の端まで)に出す
	local screen = Instance.new("ScreenGui")
	screen.Name = "MinatoGachaShow"
	screen.DisplayOrder = 50
	screen.IgnoreGuiInset = true
	screen.ScreenInsets = Enum.ScreenInsets.None
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.ResetOnSpawn = false
	screen.Parent = gui.Parent
	overlay.Parent = screen
	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Color = ColorSequence.new(Color3.fromRGB(30, 50, 90), Color3.fromRGB(2, 4, 12))
	shade.Parent = overlay
	local rayHolder, beams = rays(overlay)
	for _, b in beams do
		b.BackgroundTransparency = 1
	end
	local view, camera = viewport(overlay)
	local flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = WHITE
	flash.BackgroundTransparency = 1
	flash.BorderSizePixel = 0
	flash.ZIndex = 60
	flash.Parent = overlay
	-- 文字の入れ物(レア度・名前・NEW など)
	local info = Instance.new("Frame")
	info.BackgroundTransparency = 1
	info.AnchorPoint = Vector2.new(0.5, 0)
	info.Position = UDim2.fromScale(0.5, 0.74)
	info.Size = UDim2.new(1, -24, 0.24, 0)
	info.ZIndex = 55
	info.Parent = overlay
	local infoScale = Instance.new("UIScale")
	infoScale.Parent = info
	local rarityText = label(info, "", 46)
	rarityText.Position = UDim2.fromScale(0.5, 0.12)
	local rarityStroke = Instance.new("UIStroke")
	rarityStroke.Thickness = 2
	rarityStroke.Color = Color3.fromRGB(10, 14, 30)
	rarityStroke.Parent = rarityText
	local nameText = label(info, "", 24)
	nameText.Position = UDim2.fromScale(0.5, 0.45)
	local noteText = label(info, "", 18, Color3.fromRGB(255, 210, 60))
	noteText.Position = UDim2.fromScale(0.5, 0.72)
	local hint = label(overlay, "", 16, Color3.fromRGB(190, 205, 230))
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -14)
	hint.ZIndex = 55
	local skip = Instance.new("TextButton")
	skip.Text = "スキップ"
	skip.Font = Enum.Font.GothamBold
	skip.TextSize = 16
	skip.TextColor3 = WHITE
	skip.BackgroundColor3 = Color3.fromRGB(11, 29, 58)
	skip.BackgroundTransparency = 0.25
	skip.AnchorPoint = Vector2.new(1, 0)
	skip.Position = UDim2.new(1, -14, 0, 14)
	skip.Size = UDim2.fromOffset(110, 40)
	skip.ZIndex = 58
	skip.Parent = overlay
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = skip

	-- 状態: "capsule"(カプセル)→ "item"(1つずつ)→ "list"(一覧)→ 閉じる
	local state, index, started, revealAt = "capsule", 0, os.clock(), 0
	local shown, capsuleModel, shell = nil, nil, nil
	local center, distance, spin = Vector3.zero, 10, 0
	local rayColor, raySpeed, rayAlpha = WHITE, 20, 1
	local closed = false
	local listFrame

	local function finish()
		if closed then
			return
		end
		closed = true
		for _, l in links do
			l:Disconnect()
		end
		Sfx.gacha(false)
		tween(overlay, 0.25, { BackgroundTransparency = 1 })
		task.delay(0.26, function()
			screen:Destroy()
		end)
		if options.onDone then
			options.onDone()
		end
	end

	-- 10回の一覧(色見本・名前・レア度・NEW)
	local function showList()
		state = "list"
		if shown then
			shown:Destroy()
			shown = nil
		end
		view.Visible = false
		info.Visible = false
		skip.Visible = false
		rayAlpha = 0.8
		listFrame = Instance.new("Frame")
		listFrame.BackgroundTransparency = 1
		local w = screen.AbsoluteSize.X
		local columns = w < 520 and 2 or 5
		local rows = math.ceil(#results / columns)
		-- 画面の真ん中に、題と一緒に置く(上の Roblox のボタンと重ならないように)
		listFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		listFrame.Position = UDim2.new(0.5, 0, 0.5, 10)
		listFrame.Size = UDim2.new(1, -24, 0, rows * 100)
		listFrame.ZIndex = 56
		listFrame.Parent = overlay
		local title = label(overlay, "ガチャの結果", 26, Color3.fromRGB(255, 210, 60))
		title.ZIndex = 56
		title.Position = UDim2.new(0.5, 0, 0.5, -rows * 50 - 18)
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.new(1 / columns, -8, 0, 92)
		grid.CellPadding = UDim2.fromOffset(8, 8)
		grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
		grid.Parent = listFrame
		for k, r in results do
			local it = r.item
			local card = Instance.new("Frame")
			card.LayoutOrder = k
			card.BackgroundColor3 = Color3.fromRGB(11, 29, 58)
			card.BackgroundTransparency = 0.1
			card.ZIndex = 56
			card.Parent = listFrame
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, 10)
			c.Parent = card
			local s = Instance.new("UIStroke")
			s.Color = rarityColor[it.r] or WHITE
			s.Thickness = ORDER[it.r] >= 3 and 3 or 1.5
			s.Parent = card
			-- 品の見た目は3Dで(色見本ではなく)
			local thumb = GachaShow.preview(card, it, 8, 8, 72, 76, { outfit = currentOutfit(options) })
			thumb.ZIndex = 57
			local t1 = label(card, it.r, 18, rarityColor[it.r])
			t1.ZIndex = 57
			t1.AnchorPoint = Vector2.zero
			t1.TextXAlignment = Enum.TextXAlignment.Left
			t1.Position = UDim2.fromOffset(88, 6)
			t1.Size = UDim2.new(1, -92, 0, 22)
			local t2 = label(card, it.name, 14)
			t2.ZIndex = 57
			t2.AnchorPoint = Vector2.zero
			t2.TextXAlignment = Enum.TextXAlignment.Left
			t2.TextTruncate = Enum.TextTruncate.AtEnd
			t2.Position = UDim2.fromOffset(88, 30)
			t2.Size = UDim2.new(1, -92, 0, 20)
			local t3 = label(
				card,
				r.dupe > 0 and ("かぶり +" .. r.dupe) or "NEW!",
				14,
				r.dupe > 0 and Color3.fromRGB(190, 205, 230) or Color3.fromRGB(255, 210, 60)
			)
			t3.ZIndex = 57
			t3.AnchorPoint = Vector2.zero
			t3.TextXAlignment = Enum.TextXAlignment.Left
			t3.Position = UDim2.fromOffset(88, 58)
			t3.Size = UDim2.new(1, -92, 0, 22)
		end
		hint.Text = "タップで閉じる"
		revealAt = os.clock()
	end

	-- k 番目の品を見せる
	local function reveal(k)
		index = k
		state = "item"
		revealAt = os.clock()
		if shown then
			shown:Destroy()
			shown = nil
		end
		local r = results[k]
		local it = r.item
		local color = rarityColor[it.r] or WHITE
		local focus
		shown, focus = itemModel(it, options)
		if shown then
			shown.Parent = view
			center, distance = frameModel(camera, shown, it.kind, focus)
		end
		spin = it.kind == "helmet" and math.pi or 2.4
		rayColor, rayAlpha, raySpeed = color, ORDER[it.r] >= 3 and 0.25 or 0.55, ORDER[it.r] >= 3 and 40 or 22
		rarityText.Text = it.r
		rarityText.TextColor3 = color
		rarityText.TextSize = it.r == "UR" and 64 or it.r == "SSR" and 58 or 46
		local slot = Meta.slot(it.kind)
		nameText.Text = (slot and slot.name or "") .. "　" .. it.name
		noteText.Text = r.dupe > 0 and ("かぶり　+" .. r.dupe .. " コイン") or "NEW!　倉庫に届きました"
		noteText.TextColor3 = r.dupe > 0 and Color3.fromRGB(190, 205, 230) or Color3.fromRGB(255, 210, 60)
		info.Visible = true
		infoScale.Scale = 0.6
		tween(infoScale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		view.Size = UDim2.fromScale(0.5, 0.5)
		tween(view, 0.4, { Size = UDim2.fromScale(0.72, 0.72) }, Enum.EasingStyle.Back)
		flash.BackgroundTransparency = ORDER[it.r] >= 3 and 0 or 0.4
		tween(flash, 0.45, { BackgroundTransparency = 1 })
		-- UR は SSR の音(いちばん高い音)
		Sfx.play("gacha" .. (it.r == "UR" and "SSR" or it.r), 0.9)
		if #results > 1 then
			hint.Text = string.format("タップで次へ　%d / %d", k, #results)
		else
			hint.Text = "タップで閉じる"
		end
	end

	-- タップ(クリック・画面タッチ・Enter)で進む
	local function advance()
		if closed then
			return
		end
		local wait = os.clock() - revealAt
		if state == "capsule" then
			return
		elseif state == "item" then
			if wait < 0.45 then
				return
			end
			if index < #results then
				reveal(index + 1)
			elseif #results > 1 then
				showList()
			else
				finish()
			end
		elseif state == "list" and wait > 0.4 then
			finish()
		end
	end
	table.insert(
		links,
		overlay.InputBegan:Connect(function(input)
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				advance()
			end
		end)
	)
	table.insert(
		links,
		UserInputService.InputBegan:Connect(function(input)
			if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.Space then
				advance()
			end
		end)
	)
	table.insert(
		links,
		skip.Activated:Connect(function()
			if state == "capsule" or state == "item" then
				if #results > 1 then
					showList()
				elseif state == "capsule" then
					if capsuleModel then
						capsuleModel:Destroy()
					end
					reveal(1)
				else
					finish()
				end
			end
		end)
	)

	-- 始め: 暗転と曲、カプセルを置く
	Sfx.gacha(true)
	tween(overlay, 0.3, { BackgroundTransparency = 0 })
	capsuleModel, shell = capsule()
	capsuleModel.Parent = view
	center, distance = Vector3.new(0, -0.3, 0), 15
	hint.Text = ""
	-- {秒, レア度}: 出た中でいちばん高いレア度まで色が上がる(UR は開く直前に、もう一段)
	local stages = { { 0.9, 2 }, { 1.3, 3 }, { 1.7, 4 }, { 2.15, 5 } }
	local litRarity = 1
	local DROP, OPEN = 0.7, 2.5

	table.insert(
		links,
		RunService.RenderStepped:Connect(function(dt)
			local now = os.clock() - started
			rayHolder.Rotation += raySpeed * dt
			for _, b in beams do
				b.BackgroundColor3 = rayColor
				b.BackgroundTransparency += (rayAlpha - b.BackgroundTransparency) * math.min(1, dt * 6)
			end
			if state == "capsule" and capsuleModel then
				-- 落ちてきて弾む → 震えが大きくなる → 光の色が上がる
				local y
				if now < DROP then
					local u = now / DROP
					y = 9 * (1 - u * u)
				else
					local u = now - DROP
					y = math.abs(math.sin(u * 9)) * 0.9 * math.exp(-u * 5)
				end
				local shake = now > DROP and (now - DROP) / (OPEN - DROP) or 0
				local wobble = math.sin(now * 38) * 0.18 * shake * shake
				for _, st in stages do
					if now >= st[1] and best >= st[2] and litRarity < st[2] then
						litRarity = st[2]
						local c = rarityColor[NAMES[litRarity]] or WHITE
						shell.Color = c
						rayColor, rayAlpha = c, 0.45
						raySpeed = 30 + litRarity * 12
						Sfx.play("select", 0.7, 0.9 + litRarity * 0.12)
					end
				end
				if now > DROP and rayAlpha > 0.7 then
					rayAlpha = 0.7
				end
				capsuleModel:PivotTo(CFrame.new(0, y, 0) * CFrame.Angles(0, now * 2.2, wobble))
				if now >= OPEN then
					capsuleModel:Destroy()
					capsuleModel = nil
					flash.BackgroundTransparency = 0
					reveal(1)
				end
			end
			-- 品はゆっくり回る
			spin += dt * 0.7
			local look = CFrame.new(center)
				* CFrame.Angles(0, spin, 0)
				* CFrame.Angles(-0.32, 0, 0)
				* CFrame.new(0, 0, distance)
			camera.CFrame = CFrame.lookAt(look.Position, center)
		end)
	)
	return {
		close = finish,
	}
end

-- 品の小さな3Dの窓(ガチャの結果のカード・倉庫で使う)。色見本の代わりに、見た目そのままを見せる。
--   艇外装はその艇(options.outfit の今の装備)、ヘルメットはそのヘルメット、モーター・ハンドル・旗はその部分を大きく。止まった斜め前からの眺め
--   options.spin = true で、ゆっくり回す(装備中の品など)
local previewLinks = {}
function GachaShow.preview(parent, item, x, y, w, h, options)
	options = options or {}
	local view = Instance.new("ViewportFrame")
	view.Name = "Preview"
	view.Position = UDim2.fromOffset(x, y)
	view.Size = UDim2.fromOffset(w, h)
	view.BackgroundColor3 = Color3.fromRGB(28, 52, 92)
	view.BackgroundTransparency = 0.2
	view.BorderSizePixel = 0
	view.Ambient = Color3.fromRGB(160, 170, 190)
	view.LightColor = Color3.fromRGB(255, 250, 240)
	view.LightDirection = Vector3.new(-0.6, -1, -0.5)
	view.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = view
	local shade = Instance.new("UIGradient")
	shade.Rotation = 90
	shade.Color = ColorSequence.new(Color3.fromRGB(120, 150, 200), Color3.fromRGB(40, 60, 100))
	shade.Parent = view
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.Parent = view
	view.CurrentCamera = camera
	local model, focus = itemModel(item, options)
	if not model then
		return view
	end
	model.Parent = view
	local center, distance = frameModel(camera, model, item.kind, focus)
	-- 横長の窓では、艇がはみ出さないよう少し近づける
	if item.kind ~= "helmet" and not focus then
		distance *= w > h * 1.4 and 0.66 or 0.85
	end
	local yaw = item.kind == "helmet" and math.pi + 0.6 or 2.4
	local function place()
		local look = CFrame.new(center)
			* CFrame.Angles(0, yaw, 0)
			* CFrame.Angles(-0.32, 0, 0)
			* CFrame.new(0, 0, distance)
		camera.CFrame = CFrame.lookAt(look.Position, center)
	end
	place()
	if options.spin then
		local link
		link = RunService.RenderStepped:Connect(function(dt)
			if not view.Parent then
				link:Disconnect()
				previewLinks[link] = nil
				return
			end
			yaw += dt * 0.6
			place()
		end)
		previewLinks[link] = true
	end
	return view
end

return GachaShow
