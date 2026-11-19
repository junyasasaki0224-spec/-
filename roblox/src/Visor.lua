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

-- モデルの中から、ヘルメットの殻とシールドの部品を探す(アバターの部品は名前に "__" がないので入らない)
local function findParts(model: Instance)
	local shell: BasePart? = nil
	local visors: { BasePart } = {}
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
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
			shell.CFrame:PointToWorldSpace(Vector3.new(0, -0.04 * shell.Size.Y, 0.04 * shell.Size.Z))
		) * at.Rotation
	end
	head.Transparency = on and 0 or 1
	for _, d in head:GetChildren() do
		if d:IsA("Decal") then
			d.Transparency = on and 0 or 1
		end
	end
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
			rest = shell.CFrame:ToObjectSpace(visor.CFrame)
			size = visor.Size
			visor:SetAttribute("VisorRest", rest)
			visor:SetAttribute("VisorSize", size)
		end
		if up then
			-- 蝶番から見たシールドを回して、蝶番を中心に少し大きくする
			local hinge = CFrame.new(HINGE * shell.Size)
			local fromHinge = hinge:Inverse() * rest
			local turned = CFrame.Angles(OPEN, 0, 0) * (fromHinge.Rotation + fromHinge.Position * GROW)
			visor.CFrame = shell.CFrame * hinge * turned
			visor.Size = size * GROW
		else
			visor.CFrame = shell.CFrame * rest
			visor.Size = size
		end
		visor:SetAttribute("VisorUp", up)
	end
	local head = findHead(model)
	if head then
		showHead(head, shell, up)
	end
end

return Visor
