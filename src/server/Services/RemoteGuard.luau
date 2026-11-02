--!strict
-- クライアントからの通信の門番。
--  * プレイヤー×通信ごとのトークンバケットで連打・スパムを止める
--  * 引数の型チェック用のヘルパー(NaN/無限大/長すぎる文字列を弾く)
--  * ハンドラ内のエラーで他の処理が止まらないよう pcall で包む
-- クライアントから来た値は「すべて嘘かもしれない」前提で扱うこと。

local Players = game:GetService("Players")

local RemoteGuard = {}

type Bucket = { tokens: number, last: number }
local buckets: { [Player]: { [string]: Bucket } } = {}

Players.PlayerRemoving:Connect(function(p)
	buckets[p] = nil
end)

-- rate: 1秒あたりに回復する回数, burst: 連続で許す回数
function RemoteGuard.allow(player: Player, key: string, rate: number, burst: number): boolean
	local per = buckets[player]
	if not per then
		per = {}
		buckets[player] = per
	end
	local now = os.clock()
	local b = per[key]
	if not b then
		b = { tokens = burst, last = now }
		per[key] = b
	end
	b.tokens = math.min(burst, b.tokens + (now - b.last) * rate)
	b.last = now
	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

function RemoteGuard.connect(
	remote: RemoteEvent,
	rate: number,
	burst: number,
	handler: (Player, ...any) -> ()
): RBXScriptConnection
	local key = remote.Name
	return remote.OnServerEvent:Connect(function(player: Player, ...)
		if typeof(player) ~= "Instance" or not player:IsA("Player") or player.Parent ~= Players then
			return
		end
		if not RemoteGuard.allow(player, key, rate, burst) then
			return
		end
		local ok, err = pcall(handler, player, ...)
		if not ok then
			warn(("[RemoteGuard] %s handler error for %d: %s"):format(key, player.UserId, tostring(err)))
		end
	end)
end

-- 有限の数値か
function RemoteGuard.isNumber(v: any, min: number?, max: number?): boolean
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return false
	end
	if min and v < min then
		return false
	end
	if max and v > max then
		return false
	end
	return true
end

function RemoteGuard.isInt(v: any, min: number?, max: number?): boolean
	return RemoteGuard.isNumber(v, min, max) and math.floor(v) == v
end

-- 短い識別子(英数字と _ のみ)
function RemoteGuard.isId(v: any, maxLen: number?): boolean
	return type(v) == "string" and #v > 0 and #v <= (maxLen or 40) and v:match("^[%w_]+$") ~= nil
end

return RemoteGuard
