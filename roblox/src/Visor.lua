-- ヘルメットのシールドを上げ下げする部品(設定の「ヘルメットの目元」)。
--   Visor.apply(艇やヘルメットのモデル, 上げるか) … シールドを横の丸い金具(蝶番)を中心に 45° 上げ、
--   少し大きくして殻の外に出す。アバターが乗っていれば、ヘルメットの中に頭を見せて目元が見えるようにする。
-- すべてのヘルメットは同じ殻とシールドの形(色だけ違う)なので、同じ蝶番・同じ角度で動かす。
-- 着せ替え素材(ZIP)のヘルメット30点の「Visor」部品と同じ値(45°・1.1倍・蝶番の位置)。
local Visor = {}

local OPEN = math.rad(45)
local GROW = 1.1
-- 蝶番の位置: ヘルメットの殻の部品の中心から、殻の大きさに対する割合(前は -Z)
local HINGE = Vector3.new(0, 0.0035, -0.0719)
-- 頭はヘルメットの殻の高さの 0.78 倍までに縮めて、殻からはみ出さないようにする
local HEAD_FIT = 0.78

-- 殻の「前が -Z」の向き。着せ替えの品は部品を半回転して置いてある(Turned)ので、半回転して戻す
local function frameOf(shell: BasePart): CFrame
	if shell:GetAttribute("Turned") then
		return shell.CFrame * CFrame.Angles(0, math.pi, 0)
	end
	return shell.CFrame
end

-- モデルの中から、ヘルメットの殻とシールドの部品を探す(アバターの部品は名前に "__" がないので入らない)
local function findParts(model: Instance)
	local shell: BasePart? = nil
	local visors: { BasePart } = {}
	for _, p in model:GetDescendants() do
		-- 着せ替えで隠した元のヘルメット(OutfitHidden)は使わない
		if p:IsA("BasePart") and p:GetAttribute("OutfitHidden") == nil then
			local material = p.Name:match("__(.-)__")
			if material == "Helmet" and not shell then
				shell = p
			elseif material == "Visor" then
				table.insert(visors, p)
			end
		end
	end
	return shell, visors
end

-- 乗っているアバターの頭(RacerAvatar が作った人形の Head)
local function findHead(model: Instance): BasePart?
	for _, d in model:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("RacerAvatar") then
			local head = d:FindFirstChild("Head")
			if head and head:IsA("BasePart") then
				return head
			end
		end
	end
	return nil
end

-- 頭を見せる・隠す。見せる時は殻に収まる大きさに縮める(元の大きさは属性に覚えておく)
local function showHead(head: BasePart, shell: BasePart, on: boolean)
	local original = head:GetAttribute("VisorHeadSize")
	if typeof(original) ~= "Vector3" then
		original = head.Size
		head:SetAttribute("VisorHeadSize", original)
	end
	local mesh = head:FindFirstChildOfClass("SpecialMesh")
	local meshScale = head:GetAttribute("VisorMeshScale")
	if mesh and typeof(meshScale) ~= "Vector3" then
		meshScale = mesh.Scale
		head:SetAttribute("VisorMeshScale", meshScale)
	end
	local k = 1
	if on then
		local biggest = math.max(original.X, original.Y, original.Z)
		k = math.min(1, shell.Size.Y * HEAD_FIT / math.max(biggest, 0.01))
	end
	local at = head.CFrame
	head.Size = original * k
	if mesh and typeof(meshScale) == "Vector3" then
		mesh.Scale = meshScale * k
	end
	-- 頭の中心は殻の中心の少し下・後ろ(顔が目元の穴の奥に来る)
	if on then
		head.CFrame = CFrame.new(
			frameOf(shell):PointToWorldSpace(Vector3.new(0, -0.04 * shell.Size.Y, 0.04 * shell.Size.Z))
		) * at.Rotation
	end
	head.Transparency = on and 0 or 1
	for _, d in head:GetChildren() do
		if d:IsA("Decal") then
			d.Transparency = on and 0 or 1
		end
	end
end

-- ヘルメットの中の暗い玉(頭を隠している時に、シールド越しにヘルメットの白い内側が見えて
-- 「頭が透けている」ように見えないように)。名前の材質は Rubber(アバターを乗せた時、ヘルメットと一緒に動く)
local SHADE = "VisorShade__Rubber__Inner"
local function placeShade(model: Instance, shell: BasePart, visible: boolean)
	local shade = nil
	for _, d in model:GetDescendants() do
		if d.Name == SHADE and d:IsA("BasePart") then
			if shade or d.Parent ~= shell.Parent then
				d:Destroy()
			else
				shade = d
			end
		end
	end
	if not shade then
		local made = Instance.new("Part")
		made.Name = SHADE
		made.Shape = Enum.PartType.Ball
		made.Material = Enum.Material.SmoothPlastic
		made.Color = Color3.fromRGB(14, 16, 22)
		made.Anchored = true
		made.CanCollide, made.CanTouch, made.CanQuery = false, false, false
		made.CastShadow = false
		made.Massless = true
		made.Parent = shell.Parent
		shade = made
	end
	local s = shade :: BasePart
	-- 殻より一回り小さく、少し下・後ろ(殻の外へ出ないように)
	s.Size = Vector3.one * math.min(shell.Size.X, shell.Size.Y, shell.Size.Z) * 0.78
	s.CFrame = frameOf(shell) * CFrame.new(0, -0.04 * shell.Size.Y, 0.05 * shell.Size.Z)
	s.Transparency = visible and 0 or 1
end

-- シールドを上げる(up=true)・下ろす(false)。何度呼んでも同じ形になる
function Visor.apply(model: Instance, up: boolean)
	local shell, visors = findParts(model)
	if not shell then
		return
	end
	for _, visor in visors do
		-- 閉じた時の位置(殻から見た所)と大きさを、最初に1回だけ覚える
		local rest = visor:GetAttribute("VisorRest")
		local size = visor:GetAttribute("VisorSize")
		if typeof(rest) ~= "CFrame" or typeof(size) ~= "Vector3" then
			rest = frameOf(shell):ToObjectSpace(visor.CFrame)
			size = visor.Size
			visor:SetAttribute("VisorRest", rest)
			visor:SetAttribute("VisorSize", size)
		end
		if up then
			-- 蝶番から見たシールドを回して、蝶番を中心に少し大きくする
			local hinge = CFrame.new(HINGE * shell.Size)
			local fromHinge = hinge:Inverse() * rest
			local turned = CFrame.Angles(OPEN, 0, 0) * (fromHinge.Rotation + fromHinge.Position * GROW)
			visor.CFrame = frameOf(shell) * hinge * turned
			visor.Size = size * GROW
		else
			visor.CFrame = frameOf(shell) * rest
			visor.Size = size
		end
		visor:SetAttribute("VisorUp", up)
	end
	local head = findHead(model)
	if head then
		showHead(head, shell, up)
	end
	-- 頭を見せていない時は、ヘルメットの中を暗くする
	placeShade(model, shell, not (up and head ~= nil))
end

return Visor
