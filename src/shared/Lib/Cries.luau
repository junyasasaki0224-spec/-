--!strict
-- 鳴き声の表(Config.Cries)を引く道具。音を鳴らすのはクライアントの Controllers/Cry。
-- 全魚の鳴き声は1本の音にまとまっていて、魚ごとの区間(start〜start+length 秒)だけを鳴らす。
local Config = require(script.Parent.Parent.Config)

local Cries = {}

-- 音が Roblox にアップロード済みか(soundId が rbxassetid://0 のままなら、まだ文字だけ)
function Cries.hasAudio(): boolean
	local id = Config.Cries.soundId
	return type(id) == "string" and id:match("^rbxassetid://%d+$") ~= nil and id ~= "rbxassetid://0"
end

-- 吹き出しに出す文字(「ぴゅるる〜」など)。表に無い魚は nil
function Cries.text(fishId: string, lang: string?): string?
	local c = Config.Cries.cries[fishId]
	if not c then
		return nil
	end
	return if lang == "ja" then c.ja else c.en
end

-- 鳴らす区間(秒)。表に無い魚は nil
function Cries.region(fishId: string): (number?, number?)
	local c = Config.Cries.cries[fishId]
	if not c then
		return nil, nil
	end
	return c.start, c.start + c.length
end

return Cries
