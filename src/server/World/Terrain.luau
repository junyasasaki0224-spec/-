--!strict
-- 地形の共通処理: 楕円の池/湖を中心にした「すり鉢状」の地形を作る。
-- 外側は山の輪で囲む(地形の端や何も無い空間が見えないように。山の手前には見えない壁を置く)。
local M = {}

export type Basin = {
	center: Vector3, -- 水面の中心(y = 水面の高さ)
	rx: number,
	rz: number,
	half: number, -- 平地の範囲の目安(中心からの半径)
	groundY: number, -- 平地の高さ(水面からの差)
	hills: number, -- 外側の丘の高さ
	seed: number,
	ring: number?, -- 山が始まる距離(中心から。山すそは角度で少し揺れる)
	ringHeight: number?, -- 山の高さ
	extent: number?, -- 地形を作る範囲(中心から。省略で half)
}

-- 楕円の正規化距離(岸の形を少し揺らす)
function M.shape(b: Basin, x: number, z: number): number
	local dx, dz = (x - b.center.X) / b.rx, (z - b.center.Z) / b.rz
	local d = math.sqrt(dx * dx + dz * dz)
	return d + math.noise(x / 18, z / 18, b.seed) * 0.12
end

-- 山すそが始まる距離(角度で揺らして、輪がきれいな円に見えないようにする)
function M.ringStart(b: Basin, x: number, z: number): number
	local ring = b.ring or math.huge
	local a = math.atan2(z - b.center.Z, x - b.center.X)
	return ring + math.noise(math.cos(a) * 1.7, math.sin(a) * 1.7, b.seed + 21) * 16
end

-- 外側の山の高さ(山すそから 70 スタッドで頂上へ。急すぎると地形が段々に見える。峰は場所ごとに高さが違う)
function M.mountain(b: Basin, x: number, z: number): number
	local height: number = b.ringHeight or 0
	if not b.ring or height <= 0 then
		return 0
	end
	local r = math.sqrt((x - b.center.X) ^ 2 + (z - b.center.Z) ^ 2)
	local t = math.clamp((r - M.ringStart(b, x, z)) / 70, 0, 1)
	t = t * t * (3 - 2 * t)
	local ridge = 0.6 + 0.6 * math.abs(math.noise(x / 50, z / 50, b.seed + 31))
	return t * height * ridge
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
	return y0 + math.clamp(h, 1.5, 22) + M.mountain(b, x, z)
end

local function groundMaterial(b: Basin, x: number, z: number, d: number, top: number): Enum.Material
	local y0 = b.center.Y
	if d <= 1.15 then
		return Enum.Material.Mud
	end
	local high = top - y0
	local n = math.noise(x / 25, z / 25, b.seed + 3)
	if high > 52 or (high > 22 and math.noise(x / 14, z / 14, b.seed + 41) > 0.4) then
		-- 峰と、ところどころの岩肌(山の斜面は森の緑)
		return if n > 0.2 then Enum.Material.Slate else Enum.Material.Rock
	elseif high > 9 then
		return if n > 0.05 then Enum.Material.LeafyGrass else Enum.Material.Grass
	end
	return if n > 0.25 then Enum.Material.LeafyGrass else Enum.Material.Grass
end

function M.build(b: Basin)
	local terrain = workspace.Terrain
	local y0 = b.center.Y
	local bottom = y0 - 16
	local ext = b.extent or b.half
	local step = 4
	for x = b.center.X - ext, b.center.X + ext, step do
		for z = b.center.Z - ext, b.center.Z + ext, step do
			-- 山の輪の外の四隅は見えないので作らない(地形の操作の数を抑える)
			if (x - b.center.X) ^ 2 + (z - b.center.Z) ^ 2 > (ext + 4) ^ 2 then
				continue
			end
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
				terrain:FillBlock(
					CFrame.new(x, (bottom + top) / 2, z),
					Vector3.new(step, top - bottom, step),
					groundMaterial(b, x, z, d, top)
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

-- 道: 地面の高さは変えずに、表面の材質だけを塗り替える(パーツを使わないので軽い)
function M.paintPath(b: Basin, points: { Vector3 }, width: number, material: Enum.Material)
	local terrain = workspace.Terrain
	for i = 1, #points - 1 do
		local a, c = points[i], points[i + 1]
		local seg = Vector3.new(c.X - a.X, 0, c.Z - a.Z)
		local len = seg.Magnitude
		if len < 0.01 then
			continue
		end
		local n = math.max(1, math.ceil(len / 3))
		for k = 0, n do
			local p = a + seg * (k / n)
			-- 道の中心を少しだけ揺らして、定規で引いた線に見えないようにする
			local wobble = math.noise(p.X / 9, p.Z / 9, b.seed + 51) * 1.2
			local side = Vector3.new(-seg.Z, 0, seg.X).Unit
			local q = p + side * wobble
			local top = M.heightAt(b, q.X, q.Z)
			terrain:FillBlock(CFrame.new(q.X, top - 1, q.Z), Vector3.new(width, 2, width), material)
		end
	end
end

-- 段になって池へ流れ込む沢。points は上流 → 下流、levels は各区間の水面の高さ。
-- 区間の境目には、上の水面から下の水面へ落ちる滝(水の壁)ができる
function M.creek(b: Basin, points: { Vector3 }, levels: { number }, width: number): { Vector3 }
	local terrain = workspace.Terrain
	local falls = {}
	for i = 1, #points - 1 do
		local a, c = points[i], points[i + 1]
		local level = levels[i]
		local seg = Vector3.new(c.X - a.X, 0, c.Z - a.Z)
		local n = math.max(1, math.ceil(seg.Magnitude / 3))
		for k = 0, n do
			local p = a + seg * (k / n)
			local top = math.max(M.heightAt(b, p.X, p.Z), level + 1)
			-- 両岸より上を削って川床を作り、水を張る
			terrain:FillBlock(
				CFrame.new(p.X, (level - 2 + top + 6) / 2, p.Z),
				Vector3.new(width + 2, top + 6 - (level - 2), width + 2),
				Enum.Material.Air
			)
			terrain:FillBlock(
				CFrame.new(p.X, level - 3, p.Z),
				Vector3.new(width + 6, 2, width + 6),
				Enum.Material.Rock
			)
			terrain:FillBlock(
				CFrame.new(p.X, level - 1, p.Z),
				Vector3.new(width + 2, 2, width + 2),
				Enum.Material.Water
			)
		end
		if i < #points - 1 and levels[i + 1] < level then
			-- 滝: 境目に上の水面から下の水面まで水の壁を立てる
			local lower = levels[i + 1]
			local mid = Vector3.new(c.X, (level + lower) / 2, c.Z)
			terrain:FillBlock(
				CFrame.lookAt(mid, mid + seg),
				Vector3.new(width + 2, level - lower + 1, 2),
				Enum.Material.Water
			)
			table.insert(falls, Vector3.new(c.X, lower, c.Z))
		end
	end
	return falls
end

return M
