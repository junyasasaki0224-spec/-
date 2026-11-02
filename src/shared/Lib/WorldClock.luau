--!strict
-- 昼夜・天気・ぬし出現の時刻計算(純粋関数)。
-- サーバー時刻(workspace:GetServerTimeNow())から決定的に計算するので、
-- 全サーバー・全クライアントで同じ時刻と天気になり、通信も不要。

local WorldClock = {}

export type WorldSettings = {
	dayLengthSeconds: number,
	weatherPeriodSeconds: number,
	weatherWeights: { [string]: number },
	morningStart: number,
	dayStart: number,
	nightStart: number,
}

-- 0..24 の時刻。1日の始まりを朝6時にずらす(入った時に真っ暗になりにくい)
function WorldClock.clockTime(now: number, s: WorldSettings): number
	local frac = (now % s.dayLengthSeconds) / s.dayLengthSeconds
	return (frac * 24 + 6) % 24
end

function WorldClock.phase(clock: number, s: WorldSettings): string
	if clock >= s.morningStart and clock < s.dayStart then
		return "morning"
	elseif clock >= s.dayStart and clock < s.nightStart then
		return "day"
	end
	return "night"
end

-- 32bit の掛け算(倍精度の桁あふれを避けるため16bitずつ計算)
local function mul32(a: number, b: number): number
	local aHi, aLo = a // 0x10000, a % 0x10000
	local hi = (aHi * b) % 0x10000 -- 上位16bitに入る分だけ使う
	return (hi * 0x10000 + aLo * b) % 0x100000000
end

-- 32bit の整数ハッシュ → 0..1
local function hash01(n: number): number
	local x = math.floor(n) % 0x100000000
	x = bit32.bxor(x, bit32.rshift(x, 16))
	x = mul32(x, 0x45d9f3b)
	x = bit32.bxor(x, bit32.rshift(x, 16))
	x = mul32(x, 0x45d9f3b)
	x = bit32.bxor(x, bit32.rshift(x, 16))
	return x / 0x100000000
end
WorldClock.hash01 = hash01

local WEATHER_ORDER = { "sunny", "rain", "fog", "thunder" }

function WorldClock.weatherAt(now: number, s: WorldSettings): string
	local slot = math.floor(now / s.weatherPeriodSeconds)
	local total = 0
	for _, id in WEATHER_ORDER do
		total += s.weatherWeights[id] or 0
	end
	local x = hash01(slot * 7919 + 13) * total
	for _, id in WEATHER_ORDER do
		x -= s.weatherWeights[id] or 0
		if x < 0 then
			return id
		end
	end
	return "sunny"
end

-- 次の天気が変わるまでの秒数
function WorldClock.secondsToNextWeather(now: number, s: WorldSettings): number
	return s.weatherPeriodSeconds - (now % s.weatherPeriodSeconds)
end

export type NushiSettings = { periodSeconds: number, offsetSeconds: number, durationSeconds: number }

-- ぬしの状態: active なら残り秒、そうでなければ次の出現までの秒
function WorldClock.nushi(now: number, s: NushiSettings): (boolean, number, number)
	local t = (now - s.offsetSeconds) % s.periodSeconds
	local cycle = math.floor((now - s.offsetSeconds) / s.periodSeconds)
	if t < s.durationSeconds then
		return true, s.durationSeconds - t, cycle
	end
	return false, s.periodSeconds - t, cycle
end

-- 依頼・デイリー報酬用の「日」の番号
function WorldClock.dayIndex(unixTime: number, offsetSeconds: number): number
	return math.floor((unixTime + offsetSeconds) / 86400)
end

return WorldClock
