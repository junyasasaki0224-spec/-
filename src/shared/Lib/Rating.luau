--!strict
-- 対戦の強さの点数(イロレーティング)。純粋な計算だけ(テストしやすいように Roblox のサービスを使わない)。
local Rating = {}

-- a が b に勝つ見込み(0〜1)
function Rating.expected(a: number, b: number): number
	return 1 / (1 + 10 ^ ((b - a) / 400))
end

-- 対戦の後の点数。scoreA = 1(a の勝ち)/ 0(a の負け)。k は1回で動く幅の大きさ
function Rating.update(a: number, b: number, scoreA: number, k: number): (number, number)
	local ea = Rating.expected(a, b)
	local da = k * (scoreA - ea)
	return math.floor(a + da + 0.5), math.floor(b - da + 0.5)
end

return Rating
