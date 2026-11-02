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
	H.assertEq(#(tags.Merchant or {}), 2, "Merchant")
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
			"travel:swamp",
			"travel:nushi_lake",
		}
	do
		H.assert(actions[a], "missing prompt action " .. a)
	end
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
