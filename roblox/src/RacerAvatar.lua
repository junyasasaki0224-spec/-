-- プレイヤーの Roblox のアバターを、ボートのレーサーとして乗せる部品。
--   サーバー: RacerAvatar.build(userId) … アバターの見た目(HumanoidDescription)から人形を作り、
--             艇の座席でひざをついた前かがみの姿勢に固めて返す(艇の向き・位置は艇の原点が基準)
--   プレイヤー側: RacerAvatar.attach(艇, 人形) … 艇の共通のレーサー人形を隠し、アバターを乗せる
--             RacerAvatar.detach(艇) … 元の共通の人形に戻す
-- 頭はゲームのヘルメットをかぶせる(ヘルメットのスキンが生きるように)。頭の帽子・髪・顔の飾りは外す。
-- 見た目のデータは動いている間に Roblox から取るだけで、どこにも保存しない。
local Players = game:GetService("Players")

local RacerAvatar = {}

-- 姿勢(関節ごとの回転。ラジアン)。艇の前は -Z。X 軸まわりの + は「下向きの手足を前へ振る」向き
local LEAN = -0.85 -- 上半身を前へ倒す
local POSE = {
	Root = CFrame.Angles(LEAN, 0, 0),
	Waist = CFrame.Angles(-0.15, 0, 0),
	Neck = CFrame.Angles(0.95, 0, 0), -- 顔は前を見る
	LeftHip = CFrame.Angles(-LEAN + 0.55, 0, 0.12),
	RightHip = CFrame.Angles(-LEAN + 0.55, 0, -0.12),
	LeftKnee = CFrame.Angles(-2.1, 0, 0), -- すねは後ろへ、床に沿わせる
	RightKnee = CFrame.Angles(-2.1, 0, 0),
	LeftAnkle = CFrame.Angles(0.9, 0, 0),
	RightAnkle = CFrame.Angles(0.9, 0, 0),
	LeftShoulder = CFrame.Angles(2.05, 0, 0.3), -- 左手はレバーへ(少し内へ)
	RightShoulder = CFrame.Angles(2.15, 0, -0.3), -- 右手はハンドルへ
	LeftElbow = CFrame.Angles(0.35, 0, 0),
	RightElbow = CFrame.Angles(0.45, 0, 0),
	LeftWrist = CFrame.Angles(-0.3, 0, 0),
	RightWrist = CFrame.Angles(-0.3, 0, 0),
}
-- 大きさの目安(立った時の背の高さと、胴の幅。スタッド)と、頭の中心を置く所(共通の人形のヘルメットの中)
local STAND_HEIGHT = 4.2
local TORSO_WIDTH = 1.55
-- 腰はひざをつく所(共通の人形の腰の位置)に置き、ヘルメットは頭の所へ動かす(体の比率はアバターごとに違うため)
local HIPS_AT = Vector3.new(0, 1.55, 2.5)
local HELMET_HEAD = Vector3.new(0, 2.9, 0.56) -- 共通の人形のヘルメットの中の頭の中心
-- 外す飾り(頭まわりと、背中・腰の大きな飾り。座席で艇を突き抜けるため)
local REMOVE = {
	[Enum.AccessoryType.Hat] = true,
	[Enum.AccessoryType.Hair] = true,
	[Enum.AccessoryType.Face] = true,
	[Enum.AccessoryType.Eyebrow] = true,
	[Enum.AccessoryType.Eyelash] = true,
	[Enum.AccessoryType.Back] = true,
	[Enum.AccessoryType.Waist] = true,
	[Enum.AccessoryType.Shoulder] = true,
}
-- 共通の人形のうち、アバターを乗せた時も残す部品(ヘルメット)
local KEEP = { Helmet = true, HelmetStripe = true, Visor = true, Rubber = true }

-- 2つの部品をつなぐ物(関節・溶接・固定)から、「片方の位置がわかればもう片方が決まる」式を作る
local function links(model)
	local list = {}
	for _, j in model:GetDescendants() do
		if j:IsA("JointInstance") and j.Part0 and j.Part1 then
			local turn = j:IsA("Motor6D") and POSE[j.Name] or CFrame.identity
			local offset = j.C0 * turn * j.C1:Inverse()
			table.insert(list, { a = j.Part0, b = j.Part1, offset = offset })
		elseif (j:IsA("AnimationConstraint") or j:IsA("RigidConstraint")) and j.Attachment0 and j.Attachment1 then
			-- 新しいアバターの関節(AnimationConstraint)と、飾りの固定(RigidConstraint)
			local a0, a1 = j.Attachment0, j.Attachment1
			local p0, p1 = a0.Parent, a1.Parent
			if p0 and p1 and p0:IsA("BasePart") and p1:IsA("BasePart") then
				local turn = j:IsA("AnimationConstraint") and POSE[j.Name] or CFrame.identity
				table.insert(list, { a = p0, b = p1, offset = a0.CFrame * turn * a1.CFrame:Inverse() })
			end
		end
	end
	return list
end

-- 腰(HumanoidRootPart)を原点に置き、関節を順にたどって全部の部品の位置を決める
local function solve(model, root)
	local known = { [root] = root.CFrame }
	local list = links(model)
	local progress = true
	while progress do
		progress = false
		for _, l in list do
			if known[l.a] and not known[l.b] then
				known[l.b] = known[l.a] * l.offset
				progress = true
			elseif known[l.b] and not known[l.a] then
				known[l.a] = known[l.b] * l.offset:Inverse()
				progress = true
			end
		end
	end
	return known
end

-- 外す飾りか(種類で見る。種類がわからない物は、頭に付いていれば外す)
local function shouldRemove(accessory)
	if REMOVE[accessory.AccessoryType] then
		return true
	end
	local handle = accessory:FindFirstChild("Handle")
	if not handle then
		return true
	end
	if accessory.AccessoryType == Enum.AccessoryType.Unknown then
		for _, j in handle:GetDescendants() do
			if
				j:IsA("JointInstance") and (j.Part0 and j.Part0.Name == "Head" or j.Part1 and j.Part1.Name == "Head")
			then
				return true
			end
		end
		for _, a in handle:GetChildren() do
			if a:IsA("Attachment") and (a.Name:find("Hat") or a.Name:find("Hair") or a.Name:find("Face")) then
				return true
			end
		end
	end
	return false
end

-- サーバー: userId のアバターから、艇に乗る姿勢の人形を作る。作れない時は nil
function RacerAvatar.build(userId: number)
	if type(userId) ~= "number" or userId <= 0 then
		return nil
	end
	local okDesc, description = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(userId)
	end)
	if not okDesc or not description then
		return nil
	end
	-- アニメーションや表情は使わない(固まった姿勢で乗る)
	local okModel, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not okModel or not model then
		return nil
	end
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	local head = model:FindFirstChild("Head")
	if not humanoid or not root or not head then
		model:Destroy()
		return nil
	end
	for _, d in model:GetDescendants() do
		if d:IsA("LuaSourceContainer") or d:IsA("Animator") then
			d:Destroy()
		end
	end
	for _, a in model:GetChildren() do
		if a:IsA("Accessory") and shouldRemove(a) then
			a:Destroy()
		end
	end
	-- 立った時の背の高さを STAND_HEIGHT にそろえる(大柄なアバターも座席に収まるように)
	root.CFrame = CFrame.new()
	local standing = solve(model, root)
	local top, bottom = -math.huge, math.huge
	for part, cf in standing do
		if part.Name == "Head" then
			top = math.max(top, cf.Y + part.Size.Y / 2)
		elseif part.Name == "LeftFoot" or part.Name == "RightFoot" then
			bottom = math.min(bottom, cf.Y - part.Size.Y / 2)
		end
	end
	local torso = model:FindFirstChild("UpperTorso")
	if top > bottom and torso then
		-- 背の高さと胴の幅の、きつい方に合わせる(四角い体のアバターも座席からはみ出さない)
		local fit = math.min(STAND_HEIGHT / (top - bottom), TORSO_WIDTH / torso.Size.X)
		pcall(function()
			model:ScaleTo(model:GetScale() * math.clamp(fit, 0.3, 2))
		end)
	end
	-- 姿勢を付けて部品を置き、腰がひざをつく所に来るよう全体をずらす
	root.CFrame = CFrame.new()
	local posed = solve(model, root)
	local hips = model:FindFirstChild("LowerTorso")
	local shift = HIPS_AT - (hips and posed[hips] or root.CFrame).Position
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide, part.CanTouch, part.CanQuery = false, false, false
			part.Massless = true
			local cf = posed[part]
			if cf then
				part.CFrame = cf + shift
			end
		end
	end
	-- 頭はヘルメットの中に隠す(顔はバイザー越しに見えない)
	head.Transparency = 1
	for _, d in head:GetChildren() do
		if d:IsA("Decal") then
			d.Transparency = 1
		end
	end
	root.Transparency = 1
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.EvaluateStateMachine = false
	-- ヘルメットを動かす量(艇の向きで)。プレイヤー側でヘルメットの部品をこれだけずらす
	model:SetAttribute("HelmetShift", head.Position - HELMET_HEAD)
	model.Name = "RacerAvatar"
	model.PrimaryPart = nil
	model.WorldPivot = CFrame.new()
	return model
end

-- 上半身の組が傾いている時の「艇の原点」(組の今の向き × 休みの時の組の位置の逆)
local function restFrame(boat: Model, upper: Model)
	local origin = upper:GetAttribute("RestOrigin")
	if typeof(origin) ~= "Vector3" then
		return boat:GetPivot()
	end
	return upper:GetPivot() * CFrame.new(-origin)
end

-- プレイヤー側: 艇(VisualBoat など)にアバターを乗せる。template は build で作った人形
function RacerAvatar.attach(boat: Model, template: Model)
	RacerAvatar.detach(boat)
	local upper = boat:FindFirstChild("RacerUpper")
	if not upper then
		return nil
	end
	local avatar = template:Clone()
	avatar.Name = "RacerAvatar"
	avatar:SetAttribute("RacerAvatar", true)
	local shift = template:GetAttribute("HelmetShift")
	if typeof(shift) ~= "Vector3" then
		shift = Vector3.zero
	end
	-- 上半身の組(ターンで傾く)の今の位置に合わせて置き、その組の中に入れる
	avatar:PivotTo(restFrame(boat, upper))
	avatar.Parent = upper
	for _, groupName in { "RacerUpper", "RacerLower" } do
		local group = boat:FindFirstChild(groupName)
		if group then
			for _, p in group:GetDescendants() do
				if p:IsA("BasePart") and not p:IsDescendantOf(avatar) then
					local material = p.Name:match("__(.-)__")
					if material and KEEP[material] then
						-- ヘルメットはアバターの頭へ動かす
						if groupName == "RacerUpper" and shift.Magnitude > 0.001 then
							local world = upper:GetPivot():VectorToWorldSpace(shift)
							p.CFrame += world
							p:SetAttribute("AvatarMoved", shift)
						end
					elseif p.Transparency < 1 then
						p:SetAttribute("AvatarHidden", p.Transparency)
						p.Transparency = 1
					end
				end
			end
		end
	end
	return avatar
end

-- プレイヤー側: アバターを降ろして、共通の人形に戻す
function RacerAvatar.detach(boat: Model)
	for _, d in boat:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("RacerAvatar") then
			d:Destroy()
		end
	end
	for _, p in boat:GetDescendants() do
		if p:IsA("BasePart") then
			local was = p:GetAttribute("AvatarHidden")
			if was ~= nil then
				p.Transparency = was
				p:SetAttribute("AvatarHidden", nil)
			end
			local moved = p:GetAttribute("AvatarMoved")
			if typeof(moved) == "Vector3" then
				local upper = boat:FindFirstChild("RacerUpper")
				p.CFrame -= (upper or boat):GetPivot():VectorToWorldSpace(moved)
				p:SetAttribute("AvatarMoved", nil)
			end
		end
	end
end

return RacerAvatar
