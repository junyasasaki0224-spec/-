-- マップ(沼・釣り村)をゲームと同じ生成コードで作り、地形とパーツを JSON に書き出す(Lune)。
-- 書き出した JSON は tools/map/render_map.py(Blender)で絵にして、見た目を確かめる。
--   lune run tools/map/export_map.luau build/map.json
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local H = require("../../tests/harness")

local out = process.args[1] or "build/map.json"

local game = roblox.Instance.new("DataModel")
local workspace = game:GetService("Workspace")
local terrain = roblox.Instance.new("Terrain")
terrain.Parent = workspace

local function cf(c: any): { number }
	return { c:GetComponents() }
end
local function v3(v: any): { number }
	return { v.X, v.Y, v.Z }
end

-- 地形の操作を順番どおりに記録する(Lune では地形は作れないので)
local fills = {}
roblox.implementMethod("Terrain", "FillBlock", function(_, c, size, mat)
	table.insert(fills, { kind = "block", cf = cf(c), size = v3(size), mat = mat.Name })
end)
roblox.implementMethod("Terrain", "FillBall", function(_, center, radius, mat)
	table.insert(fills, { kind = "ball", center = v3(center), r = radius, mat = mat.Name })
end)
roblox.implementMethod("Terrain", "FillCylinder", function(_, c, height, radius, mat)
	table.insert(fills, { kind = "cylinder", cf = cf(c), h = height, r = radius, mat = mat.Name })
end)
roblox.implementMethod("Terrain", "FillWedge", function(_, c, size, mat)
	table.insert(fills, { kind = "wedge", cf = cf(c), size = v3(size), mat = mat.Name })
end)
local materialColors = {}
roblox.implementMethod("Terrain", "SetMaterialColor", function(_, mat, color)
	materialColors[mat.Name] = { color.R, color.G, color.B }
end)

local CollectionService = {
	AddTag = function() end,
	HasTag = function()
		return false
	end,
}
roblox.implementMethod("Instance", "AddTag", function() end)
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

local server = H.root("src/server")
H.require(server.World.Lighting).setup()
H.require(server.World.Swamp).build()
H.require(server.World.River).build()
H.require(server.World.Sea).build()
H.require(server.World.Village).build()

local parts = {}
local lights = {}
for _, d in workspace:GetDescendants() do
	if d:IsA("BasePart") and d.ClassName ~= "Terrain" then
		local shape = "Block"
		if d.ClassName == "WedgePart" then
			shape = "Wedge"
		elseif d.ClassName == "CornerWedgePart" then
			shape = "CornerWedge"
		elseif d:IsA("Part") then
			shape = d.Shape.Name
		end
		table.insert(parts, {
			name = d.Name,
			shape = shape,
			size = v3(d.Size),
			cf = cf(d.CFrame),
			color = { d.Color.R, d.Color.G, d.Color.B },
			mat = d.Material.Name,
			alpha = d.Transparency,
		})
	elseif d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
		local p = d.Parent
		if p and p:IsA("BasePart") then
			table.insert(
				lights,
				{ pos = v3(p.CFrame.Position), color = { d.Color.R, d.Color.G, d.Color.B }, range = d.Range }
			)
		end
	end
end

-- 地形の色(Lune は SetMaterialColor を自前で持っているので、設定後に読み出す)
for _, name in
	{
		"Grass",
		"LeafyGrass",
		"Mud",
		"Rock",
		"Ground",
		"Sand",
		"Slate",
		"Cobblestone",
		"Pavement",
		"Snow",
		"Basalt",
		"Limestone",
		"Sandstone",
		"WoodPlanks",
		"Brick",
	}
do
	local ok, c = pcall(function()
		return terrain:GetMaterialColor(roblox.Enum.Material[name])
	end)
	if ok and c then
		materialColors[name] = { c.R, c.G, c.B }
	end
end

local Config = H.require(shared.Config)
local spots = {}
for _, s in Config.Spots do
	if s.available then
		spots[s.id] = { origin = s.origin, water = s.water, spawn = s.spawn, available = s.available }
	end
end

fs.writeFile(
	out,
	serde.encode("json", {
		fills = fills,
		parts = parts,
		lights = lights,
		materialColors = materialColors,
		spots = spots,
		water = { color = { 46 / 255, 92 / 255, 84 / 255 } },
	})
)
print(("wrote %s: %d fills, %d parts, %d lights"):format(out, #fills, #parts, #lights))
