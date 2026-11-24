--!strict
-- 艇の模型に装備を付ける(見た目だけ。速さや強さは変わらない)。
--   outfit(model, skinId, helmetId, cowlId, wheelId, flagId)
--   ・スタンダードと VIP の品(s0・v1・h0・v2)は、元の艇の部品に色を塗る
--   ・ガチャの着せ替え(hull01 など)は、ReplicatedStorage.VisualAssets.Items の同じ番号の部品を付けて、
--     その種類の元の部品を隠す。ハンドル・モーター・上半身の組の中に入れるので、操作やターンで一緒に動く
--   何度呼んでも同じ形になる(前に付けた品は外し、隠した部品は戻してから付け直す)
local RS = game:GetService("ReplicatedStorage")
local Meta = require(RS:WaitForChild("Meta"))
local Assets = RS:WaitForChild("VisualAssets")

-- プレイヤー側: 着せ替えの形と模様を先に読み込んでおく(付けた瞬間や倉庫の小さな絵で、形が後から現れないように)
if game:GetService("RunService"):IsClient() then
	task.spawn(function()
		local items = Assets:WaitForChild("Items", 30)
		if items then
			pcall(function()
				game:GetService("ContentProvider"):PreloadAsync({ items })
			end)
		end
	end)
end

-- 艇番の色(1〜6号艇)。艇外装の時の側面の艇番の板に使う
local LANE = { 0xf2f2f0, 0x16161a, 0xd91e2e, 0x1b50d4, 0xf3d21b, 0x18a24c }

local function color(n: number): Color3
	return Color3.fromRGB(bit32.rshift(n, 16), bit32.band(bit32.rshift(n, 8), 255), bit32.band(n, 255))
end

-- 品を付けた時に隠す元の部品: 種類 → { 組の名前 = 隠す材質(true は組の全部) }
local HIDE: { [string]: { [string]: any } } = {
	-- 艇外装は元の操縦席まわりの板(Cowl)をすべて覆う。茶色の内壁(Plywood)と前の板(Cockpit)も外装の塗装の面と
	-- ぴったり同じ所にあり、残すと艇の後ろ半分で茶色と塗装が交互に見えてちらつくので、Cowl は全部隠す
	skin = { Hull = true, Plates = true, Cowl = true },
	cowl = { Motor = { BoatColor = true } },
	wheel = { Wheel = true },
	helmet = { RacerUpper = { Helmet = true, HelmetStripe = true, Visor = true } },
	flag = { Flag = true },
}
-- 品の部品を入れる組(動く組に入れると一緒に動く)。艇外装は艇の模型の直下
local GROUP: { [string]: string } = { cowl = "Motor", wheel = "Wheel", flag = "Flag", helmet = "RacerUpper" }

local function materialOf(p: Instance): string?
	return p.Name:match("__(.-)__")
end

-- 前に付けた品を外し、隠した部品を戻す
local function reset(model: Model)
	local remove = {}
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			if p:GetAttribute("OutfitItem") then
				table.insert(remove, p)
			else
				local was = p:GetAttribute("OutfitHidden")
				if typeof(was) == "number" then
					p.Transparency = was
					p:SetAttribute("OutfitHidden", nil)
				end
			end
		end
	end
	for _, p in remove do
		p:Destroy()
	end
end

local function hide(p: BasePart)
	if p:GetAttribute("OutfitHidden") == nil then
		p:SetAttribute("OutfitHidden", p.Transparency)
		p.Transparency = 1
	end
end

-- 元の(品ではない)ヘルメットの殻
local function originalShell(model: Model): BasePart?
	local upper = model:FindFirstChild("RacerUpper") or model
	for _, p in upper:GetDescendants() do
		if p:IsA("BasePart") and not p:GetAttribute("OutfitItem") and materialOf(p) == "Helmet" then
			return p
		end
	end
	return nil
end

-- その種類の元の部品を隠す
local function hideOriginal(model: Model, kind: string)
	for groupName, materials in HIDE[kind] do
		local group = model:FindFirstChild(groupName)
		if group then
			for _, p in group:GetDescendants() do
				if p:IsA("BasePart") and not p:GetAttribute("OutfitItem") then
					local material = materialOf(p)
					if materials == true or (material and materials[material]) then
						hide(p)
					end
				end
			end
		end
	end
end

-- 品の部品を複製して付ける。部品の CFrame は「休みの姿勢の艇の原点から見た位置」(ヘルメットは元の殻から見た位置)
local function attach(model: Model, id: string, kind: string, laneColor: Color3)
	local folder = Assets:FindFirstChild("Items")
	local source = folder and folder:FindFirstChild(id)
	if not source then
		return
	end
	local frame = model:GetPivot()
	local parent: Instance = model
	local moved = nil
	local groupName = GROUP[kind]
	local group = groupName and model:FindFirstChild(groupName)
	if kind == "helmet" then
		local shell = originalShell(model)
		if not shell then
			return
		end
		frame = shell.CFrame
		-- アバターを乗せてヘルメットを頭へずらしている時は、同じずれを覚えておく(降ろす時に戻すため)
		moved = shell:GetAttribute("AvatarMoved")
		parent = shell.Parent or model
	elseif group then
		local rest = group:GetAttribute("RestOrigin")
		if typeof(rest) ~= "Vector3" then
			rest = model:GetPivot():PointToObjectSpace(group:GetPivot().Position)
		end
		frame = group:GetPivot() * CFrame.new(-(rest :: Vector3))
		parent = group
	end
	for _, src in source:GetChildren() do
		if src:IsA("BasePart") then
			local p = src:Clone()
			p.CFrame = frame * src.CFrame
			p:SetAttribute("OutfitItem", true)
			-- 品の部品は縦の軸まわりに半回転して置いてある(取り込みの向きを戻すため)。Visor はこの印で前を知る
			p:SetAttribute("Turned", true)
			if moved ~= nil then
				p:SetAttribute("AvatarMoved", moved)
			end
			local material = materialOf(p)
			-- 旗の布は模様そのまま(倉庫で見た旗が、どの艇番でも同じに見えるように)。布は両面で描く部品(Items.rbxmx)
			if material == "NumberPlate" then
				-- 側面の艇番の板は艇番の色
				p.Color = laneColor
			end
			p.Parent = parent
		end
	end
end

-- 色だけの品(スタンダード・VIP)で元の部品を塗る
local function paint(model: Model, skin: any, helmet: any)
	-- 艇番が決まっていない艇(ホーム・倉庫・ガチャの見本)は、艇首と側面の艇番の板を甲板の色にする
	-- (VIP の黒い甲板で、旗の下に白い板だけが浮いて見えないように)
	local noLane = model:GetAttribute("Lane") == nil
	for _, p in model:GetDescendants() do
		if p:IsA("MeshPart") and not p:GetAttribute("OutfitItem") then
			local material = materialOf(p)
			local key = ({ HullWhite = "hull", Trim = "trim", Deck = "deck", MotorRed = "cowl" })[material or ""]
			if skin and skin.hull and key then
				p.Color = color(skin[key])
			end
			if skin and skin.deck and noLane and material == "NumberPlate" and p.Parent and p.Parent.Name == "Plates" then
				p.Color = color(skin.deck)
			end
			if helmet and helmet.base and material == "Helmet" then
				p.Color = color(helmet.base)
			end
			if helmet and helmet.stripe and material == "HelmetStripe" then
				p.Color = color(helmet.stripe)
			end
		end
	end
end

-- 細かい模型がない時(画質を下げた時など)の箱の艇: 色だけ塗る
local function simple(model: Model, skin: any, helmet: any)
	if skin and skin.hull then
		for name, key in { Hull = "hull", Bow = "trim", Deck = "deck", Motor = "cowl" } do
			local part = model:FindFirstChild(name)
			if part and part:IsA("BasePart") then
				part.Color = color(skin[key])
			end
		end
	end
	if helmet and helmet.base then
		local part = model:FindFirstChild("Helmet")
		if part and part:IsA("BasePart") then
			part.Color = color(helmet.base)
			local stripe = model:FindFirstChild("HelmetStripe") :: BasePart?
			if not stripe then
				local made = Instance.new("Part")
				made.Name = "HelmetStripe"
				made.Anchored = true
				made.CanCollide = false
				made.Size = Vector3.new(part.Size.X * 0.19, part.Size.Y * 1.01, part.Size.Z * 0.92)
				made.CFrame = part.CFrame
				made.Parent = model
				stripe = made
			end
			(stripe :: BasePart).Color = color(helmet.stripe)
		end
	end
end

return function(model: Model, skinId: string?, helmetId: string?, cowlId: string?, wheelId: string?, flagId: string?)
	local ids = { skin = skinId, helmet = helmetId, cowl = cowlId, wheel = wheelId, flag = flagId }
	local skin, helmet = Meta.item(skinId), Meta.item(helmetId)
	if not model:GetAttribute("Detailed") then
		simple(model, skin, helmet)
		return
	end
	reset(model)
	paint(model, skin, helmet)
	local lane = model:GetAttribute("Lane")
	local laneColor = color(LANE[typeof(lane) == "number" and lane or 1] or LANE[1])
	-- 先にヘルメット以外(艇の組の位置は変わらない)、最後にヘルメット(元の殻を目印にする)
	for _, kind in { "skin", "cowl", "wheel", "flag", "helmet" } do
		local it = Meta.item(ids[kind])
		if it and it.gacha and it.kind == kind then
			hideOriginal(model, kind)
			attach(model, it.id, kind, laneColor)
			if kind == "skin" then
				attach(model, "plates", kind, laneColor)
			end
		end
	end
end
