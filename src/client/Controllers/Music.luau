--!strict
-- BGM。いる場所(いちばん近い釣り場)で曲を変え、バトルの間はバトルの曲にする。
-- 曲は Config/Music.luau(tools/music/yokai_bgm.py が作る)。soundId が 0 の曲は鳴らさない。
-- 切り替えはフェードで重ねる。効果音を消した時(Sound.isMuted)や BGM を切った時は止める
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Sound = require(script.Parent.Sound)

local M = Config.Music
local player = Players.LocalPlayer
local Music = {}

local AREA_RADIUS = 400 -- 釣り場の中心からこの距離までがその場所

local enabled = true
local override: string? = nil -- バトル中など、場所より優先する曲
local playing: { [string]: Sound } = {} -- 曲 → 鳴っている Sound(フェード中も含む)
local wanted: string? = nil

local function hasAudio(name: string): boolean
	local t = M.tracks[name]
	return t ~= nil and t.soundId ~= "" and t.soundId ~= "rbxassetid://0"
end

-- いまいる場所の曲
function Music.areaTrack(pos: Vector3): string
	local best, bestD = nil :: string?, AREA_RADIUS
	for _, spot in Config.Spots do
		local o = spot.origin
		local d = (Vector3.new(o.x, pos.Y, o.z) - pos).Magnitude
		if d < bestD then
			best, bestD = spot.id, d
		end
	end
	return if best then M.areaTrack[best] or "village" else "village"
end

-- 今鳴らすべき曲(なければ nil)
function Music.want(): string?
	if not enabled or Sound.isMuted() then
		return nil
	end
	local name = override
	if not name then
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			return nil
		end
		name = Music.areaTrack(root.Position)
	end
	return if name and hasAudio(name) then name else nil
end

local function ensure(name: string): Sound
	local s = playing[name]
	if s and s.Parent then
		return s
	end
	local n = Instance.new("Sound")
	n.Name = "BGM_" .. name
	n.SoundId = M.tracks[name].soundId
	n.Looped = true
	n.Volume = 0
	n.Parent = SoundService
	n:Play()
	playing[name] = n
	return n
end

-- フェードを少しずつ進める(dt 秒ぶん)
function Music.step(dt: number)
	wanted = Music.want()
	if wanted then
		ensure(wanted)
	end
	local rate = M.volume / math.max(M.fade, 0.05) * dt
	for name, s in playing do
		local target = if name == wanted then M.volume else 0
		if s.Volume < target then
			s.Volume = math.min(target, s.Volume + rate)
		elseif s.Volume > target then
			s.Volume = math.max(target, s.Volume - rate)
		end
		if target == 0 and s.Volume <= 0 then
			s:Stop()
			s:Destroy()
			playing[name] = nil
		end
	end
end

-- バトルなど、場所より優先する曲(nil で場所の曲に戻す)
function Music.setOverride(name: string?)
	override = name
end

function Music.battle(on: boolean)
	Music.setOverride(if on then M.battleTrack else nil)
end

function Music.setEnabled(on: boolean)
	enabled = on
end

function Music.isEnabled(): boolean
	return enabled
end

-- テスト用: 今の曲
function Music.current(): string?
	return wanted
end

function Music.init()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.1 then
			Music.step(acc)
			acc = 0
		end
	end)
end

return Music
