-- バトルの水中の舞台(BattleArena)を、ゲームと同じ組み立てコードで作って JSON に書き出す(Lune)。
-- tools/battle/render_battle.py(Blender)が、本物の魚の3Dモデル(assets/fish/YokaiFishMeshes.glb)を置いて絵にする。
--   lune run tools/battle/export_battle.luau build/battle.json
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local H = require("../../tests/harness")

local out = process.args[1] or "build/battle.json"

local game = roblox.Instance.new("DataModel")
local workspace = game:GetService("Workspace")

local function cf(c: any): { number }
	return { c:GetComponents() }
end
local function v3(v: any): { number }
	return { v.X, v.Y, v.Z }
end

local client = H.root("src/client")
local shared = H.root("src/shared")
H.globals = {
	workspace = workspace,
	game = {
		GetService = function(_, name)
			if name == "ReplicatedStorage" then
				return {
					WaitForChild = function()
						return shared
					end,
				}
			end
			return game:GetService(name)
		end,
	},
}
local Arena = H.require(client.Controllers.BattleArena)
local origin = roblox.Vector3.new(0, 0, 0)
local arena = Arena.build(workspace, origin)
local T = 3.2 -- 揺れている途中の一瞬を写す
Arena.step(arena, T, nil)

local parts, lights, beams = {}, {}, {}
for _, d in workspace:GetDescendants() do
	if d:IsA("BasePart") then
		table.insert(parts, {
			name = d.Name,
			shape = if d:IsA("Part") then d.Shape.Name else "Block",
			size = v3(d.Size),
			cf = cf(d.CFrame),
			color = { d.Color.R, d.Color.G, d.Color.B },
			mat = d.Material.Name,
			alpha = d.Transparency,
		})
	elseif d:IsA("PointLight") then
		local p = d.Parent
		if p and p:IsA("BasePart") then
			table.insert(lights, {
				pos = v3(p.CFrame.Position),
				color = { d.Color.R, d.Color.G, d.Color.B },
				range = d.Range,
				brightness = d.Brightness,
			})
		end
	elseif d:IsA("Beam") then
		local a0, a1 = d.Attachment0, d.Attachment1
		local base = (a0.Parent :: any).CFrame
		table.insert(beams, {
			top = v3(base * a0.Position),
			bottom = v3(base * a1.Position),
			w0 = d.Width0,
			w1 = d.Width1,
			color = { 200 / 255, 245 / 255, 255 / 255 },
		})
	end
end

-- 写す場面(カメラと2匹の位置)。魚の向きと泳ぎはゲームと同じ計算
local B = Arena.BASE_SHOT
local function fish(id: string, side: string, pos: any, length: number, heading: number?)
	local h = heading or (if side == "player" then 1 else -1)
	local c = roblox.CFrame.new(pos) * roblox.CFrame.Angles(0, Arena.fishYaw(h), 0)
	return { id = id, side = side, cf = cf(c), length = length }
end
local center = origin + roblox.Vector3.new(0, Arena.FISH_Y, 0)
local pHome, eHome = origin + Arena.HOME.player, origin + Arena.HOME.enemy
local pIdle, eIdle = Arena.idle(pHome, T, 0), Arena.idle(eHome, T, 2.4)
local views = {
	{
		name = "battle",
		camera = cf(Arena.orbit(center, B.yaw, B.pitch, B.dist)),
		fov = B.fov,
		fish = { fish("doro_funa", "player", pIdle, 6), fish("ashi_medaka", "enemy", eIdle, 6) },
	},
	{
		-- 攻撃: 攻める側の後ろへ回りこみ、ぶつかる瞬間
		name = "attack",
		camera = cf(
			Arena.orbit(
				pHome:Lerp(eHome, Arena.ATTACK_SHOT.at),
				-Arena.ATTACK_SHOT.yaw,
				Arena.ATTACK_SHOT.pitch,
				Arena.ATTACK_SHOT.dist
			)
		),
		fov = Arena.ATTACK_SHOT.fov,
		fish = {
			fish("doro_funa", "player", eIdle - roblox.Vector3.new(4.8, 0, 0), 6),
			fish("ashi_medaka", "enemy", eIdle + roblox.Vector3.new(1.4, 0.3, 0), 6),
		},
	},
	{
		name = "boss",
		camera = cf(Arena.orbit(center, 0.06, B.pitch + 0.02, B.bossDist)),
		fov = B.fov,
		fish = { fish("doro_funa", "player", pIdle, 6), fish("raijin_namazu", "enemy", eIdle, 10) },
	},
	{
		-- 登場の始まり(水面の近くの高いところから)
		name = "wide",
		camera = cf(
			Arena.orbit(
				center + roblox.Vector3.new(0, Arena.INTRO_SHOT.up, 0),
				Arena.INTRO_SHOT.yaw,
				Arena.INTRO_SHOT.pitch,
				Arena.INTRO_SHOT.dist
			)
		),
		fov = Arena.INTRO_SHOT.fov,
		fish = { fish("doro_funa", "player", pIdle, 6), fish("ashi_medaka", "enemy", eIdle, 6) },
	},
}

fs.writeFile(
	out,
	serde.encode("json", {
		parts = parts,
		lights = lights,
		beams = beams,
		views = views,
		surfaceY = Arena.SURFACE_Y,
		fog = { color = { 26 / 255, 92 / 255, 122 / 255 }, start = 26, finish = 190 },
	})
)
print(("wrote %s: %d parts, %d lights, %d beams, %d views"):format(out, #parts, #lights, #beams, #views))
