-- ワールド生成の動作確認(Lune): lune run tests/world_smoke.luau
-- Terrain の地形操作は Lune では動かないので「呼ばれた回数」だけ数え、パーツ・看板・ボタンの生成を実際に行う。
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local H = require("./harness")

local game = roblox.Instance.new("DataModel")
local workspace = game:GetService("Workspace")
local terrain = roblox.Instance.new("Terrain")
terrain.Parent = workspace

local fills = 0
for _, m in { "FillBlock", "FillBall", "FillCylinder" } do
	roblox.implementMethod("Terrain", m, function()
		fills += 1
	end)
end
roblox.implementMethod("Terrain", "SetMaterialColor", function() end)

local tags: { [string]: { any } } = {}
local CollectionService = {
	AddTag = function(_, inst, tag)
		tags[tag] = tags[tag] or {}
		table.insert(tags[tag], inst)
	end,
	HasTag = function()
		return false
	end,
}
local shared = H.root("src/shared")
local fakeGame = setmetatable({}, {
	__index = function(_, k)
		if k == "GetService" then
			return function(_, name)
				if name == "ReplicatedStorage" then
					return {
						WaitForChild = function()
							return shared
						end,
					}
				elseif name == "CollectionService" then
					return CollectionService
				end
				return game:GetService(name)
			end
		end
		return (game :: any)[k]
	end,
})

H.globals = { game = fakeGame, workspace = workspace }
-- Instance:AddTag は Lune でも動くが、数えるために置き換える
roblox.implementMethod("Instance", "AddTag", function(inst, tag)
	CollectionService.AddTag(nil, inst, tag)
end)

local server = H.root("src/server")
print("World")
H.test("光の設定", function()
	H.require(server.World.Lighting).setup()
	local lighting = game:GetService("Lighting")
	H.assert(lighting:FindFirstChild("Atmosphere") ~= nil, "Atmosphere")
end)
H.test("沼を生成できる(出現地点・桟橋・行商・鳥居)", function()
	H.require(server.World.Swamp).build()
	local swamp = workspace.World.Swamp
	H.assert(swamp:FindFirstChild("SwampSpawn") ~= nil, "spawn")
	H.assert(swamp:FindFirstChild("Pier") ~= nil, "pier")
	H.assert(#swamp.Pier:GetChildren() > 10, "pier planks")
end)
H.test("川を生成できる(橋・飛び石・釣り台・水車小屋・行商・鳥居・沢)", function()
	H.require(server.World.River).build()
	local river = workspace.World.River
	H.assert(river:FindFirstChild("RiverSpawn") ~= nil, "spawn")
	H.assert(#river.Bridge:GetChildren() > 20, "bridge planks")
	H.assert(#river.SteppingStones:GetChildren() >= 10, "stepping stones")
	H.assert(river:FindFirstChild("Deck") ~= nil, "fishing deck")
	H.assert(river:FindFirstChild("WaterMill") ~= nil, "water mill")
	H.assert(river:FindFirstChild("Spray", true) ~= nil, "waterfall spray")
	H.assert(river:FindFirstChild("Bamboo", true) ~= nil, "bamboo")
end)
H.test("海を生成できる(桟橋・大鳥居・灯台・岩礁・松・行商・鳥居)", function()
	H.require(server.World.Sea).build()
	local sea = workspace.World.Sea
	H.assert(sea:FindFirstChild("SeaSpawn") ~= nil, "spawn")
	H.assert(#sea.Pier:GetChildren() > 20, "pier planks")
	H.assert(sea:FindFirstChild("Lighthouse", true) ~= nil, "lighthouse")
	H.assert(sea:FindFirstChild("SeaRock", true) ~= nil, "sea rocks")
	local torii = 0
	for _, d in sea:GetDescendants() do
		if d.Name == "Torii" then
			torii += 1
		end
	end
	H.assertEq(torii, 2, "village torii + sea torii")
end)
H.test(
	"新しい釣り場には最初に出現しない(最初は沼。鳥居・お店から移動)",
	function()
		for _, name in { "RiverSpawn", "SeaSpawn" } do
			local sp = workspace.World:FindFirstChild(name, true)
			H.assert(sp and sp.Enabled == false and sp.Neutral == false, name .. " must not be a start spawn")
		end
	end
)
H.test("釣り村を生成できる(小屋10軒・水槽・ランキング看板)", function()
	H.require(server.World.Village).build()
	local huts = workspace.World.Village.Huts:GetChildren()
	H.assertEq(#huts, 10, "huts")
	for _, hut in huts do
		H.assert(hut:FindFirstChild("Tank") ~= nil, "tank")
		H.assert(hut:FindFirstChild("TankFish") ~= nil, "TankFish")
		H.assert(hut:FindFirstChild("OwnerSign") ~= nil, "OwnerSign")
	end
end)
H.test("看板・ボタン・魚屋のタグが付いている", function()
	H.assert(#(tags.LocSign or {}) >= 15, "LocSign " .. #(tags.LocSign or {}))
	H.assert(#(tags.YokaiPrompt or {}) >= 16, "YokaiPrompt " .. #(tags.YokaiPrompt or {}))
	H.assertEq(#(tags.Merchant or {}), 4, "Merchant")
	H.assertEq(#(tags.RankingBoard or {}), 1, "RankingBoard")
	local actions = {}
	for _, p in tags.YokaiPrompt do
		actions[p:GetAttribute("Action")] = true
	end
	for _, a in
		{
			"open:shop:sell",
			"open:shop:rods",
			"open:shop:bait",
			"open:quests",
			"open:tank",
			"open:battle",
			"travel:swamp",
			"travel:nushi_lake",
			"travel:river",
			"travel:sea",
		}
	do
		H.assert(actions[a], "missing prompt action " .. a)
	end
end)
H.test(
	"山の手前に見えない壁があり、遊ぶ場所(出現地点・店・鳥居・看板)はすべて壁の内側",
	function()
		for _, area in
			{ workspace.World.Swamp, workspace.World.Village, workspace.World.River, workspace.World.Sea }
		do
			local walls = area:FindFirstChild("Boundary")
			H.assert(walls ~= nil, "no boundary in " .. area.Name)
			local list = walls:GetChildren()
			H.assertEq(#list, 36, "wall segments")
			local c = roblox.Vector3.new(0, 0, 0)
			for _, w in list do
				H.assertEq(w.Transparency, 1, "visible wall")
				H.assert(w.CanCollide and not w.CanQuery, "wall collision/query")
				c += w.CFrame.Position
			end
			c /= #list
			local radius = 0
			for _, w in list do
				local p = w.CFrame.Position
				radius += roblox.Vector3.new(p.X - c.X, 0, p.Z - c.Z).Magnitude
			end
			radius /= #list
			-- 遊ぶ物(ボタンの付いた物・出現地点)が壁から十分内側にある
			for _, d in area:GetDescendants() do
				local pos = nil
				if d:IsA("ProximityPrompt") and d.Parent and d.Parent:IsA("BasePart") then
					pos = d.Parent.CFrame.Position
				elseif d:IsA("SpawnLocation") then
					pos = d.CFrame.Position
				end
				if pos then
					local r = roblox.Vector3.new(pos.X - c.X, 0, pos.Z - c.Z).Magnitude
					H.assert(
						r < radius - 10,
						("%s in %s is at r=%.0f, walls at %.0f"):format(d:GetFullName(), area.Name, r, radius)
					)
				end
			end
		end
	end
)
H.test("景色の目印がある(神木・竹林・小舟・五重塔・見物台・提灯の列)", function()
	local swamp, village = workspace.World.Swamp, workspace.World.Village
	H.assert(swamp:FindFirstChild("Shinboku", true) ~= nil, "sacred tree")
	H.assert(swamp:FindFirstChild("Boat", true) ~= nil, "boat")
	H.assert(swamp:FindFirstChild("Bamboo", true) ~= nil, "bamboo")
	H.assert(swamp:FindFirstChild("Spray", true) ~= nil, "waterfall spray")
	H.assert(village:FindFirstChild("Pagoda", true) ~= nil, "pagoda")
	H.assert(village:FindFirstChild("Deck", true) ~= nil, "deck")
	H.assert(village:FindFirstChild("LanternRope", true) ~= nil, "lantern line")
end)
H.test("地形の生成が呼ばれている", function()
	H.assert(fills > 3000, "fills " .. fills)
end)
H.test("パーツの数が重すぎない(スマホ向け)", function()
	local n = 0
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	print(("      parts: %d"):format(n))
	H.assert(n < 5000, "too many parts: " .. n)
end)

process.exit(if H.summary() then 0 else 1)
