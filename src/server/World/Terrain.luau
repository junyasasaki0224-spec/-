--!strict
-- 地形の共通処理: 楕円の池/湖を中心にした「すり鉢状」の地形を作る。
local M = {}

export type Basin = {
	center: Vector3, -- 水面の中心(y = 水面の高さ)
	rx: number,
	rz: number,
	half: number, -- 地形を作る範囲(中心からの半径)
	groundY: number, -- 平地の高さ(水面からの差)
	hills: number, -- 外側の丘の高さ
	seed: number,
}

-- 楕円の正規化距離(岸の形を少し揺らす)
function M.shape(b: Basin, x: number, z: number): number
	local dx, dz = (x - b.center.X) / b.rx, (z - b.center.Z) / b.rz
	local d = math.sqrt(dx * dx + dz * dz)
	return d + math.noise(x / 18, z / 18, b.seed) * 0.12
end

-- その場所の地面の高さ(ワールド座標)
function M.heightAt(b: Basin, x: number, z: number): number
	local d = M.shape(b, x, z)
	local y0 = b.center.Y
	if d <= 1 then
		return y0
	elseif d <= 1.15 then
		return y0 + 1 + (d - 1) * 6
	end
	local h = b.groundY + math.max(0, d - 1.6) * b.hills + math.noise(x / 40, z / 40, b.seed + 7) * 1.5
	return y0 + math.clamp(h, 1.5, 22)
end

function M.build(b: Basin)
	local terrain = workspace.Terrain
	local y0 = b.center.Y
	local step = 4
	local bottom = y0 - 16
	for x = b.center.X - b.half, b.center.X + b.half, step do
		for z = b.center.Z - b.half, b.center.Z + b.half, step do
			local d = M.shape(b, x, z)
			if d <= 1 then
				-- 深さは中央ほど深い
				local depth = 4 + (1 - d) * 8
				terrain:FillBlock(
					CFrame.new(x, (bottom + y0 - depth) / 2, z),
					Vector3.new(step, y0 - depth - bottom, step),
					Enum.Material.Mud
				)
				terrain:FillBlock(
					CFrame.new(x, y0 - depth / 2, z),
					Vector3.new(step, depth, step),
					Enum.Material.Water
				)
			else
				local top = M.heightAt(b, x, z)
				local mat = if d <= 1.15
					then Enum.Material.Mud
					elseif top - y0 > 9 then Enum.Material.Rock
					elseif math.noise(x / 25, z / 25, b.seed + 3) > 0.25 then Enum.Material.LeafyGrass
					else Enum.Material.Grass
				terrain:FillBlock(
					CFrame.new(x, (bottom + top) / 2, z),
					Vector3.new(step, top - bottom, step),
					mat
				)
			end
		end
	end
end

-- 建物の下を平らにする(地面を埋めて、上の地形を削る)
function M.flatten(cf: CFrame, sizeX: number, sizeZ: number, material: Enum.Material?)
	local terrain = workspace.Terrain
	local flat = CFrame.new(cf.Position) * cf.Rotation
	terrain:FillBlock(
		flat * CFrame.new(0, -4, 0),
		Vector3.new(sizeX, 8, sizeZ),
		material or Enum.Material.Ground
	)
	terrain:FillBlock(flat * CFrame.new(0, 6, 0), Vector3.new(sizeX, 12, sizeZ), Enum.Material.Air)
end

return M
