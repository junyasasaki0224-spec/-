-- 音を鳴らす部品(クライアント)。音はすべてこのゲーム用に合成した物(roblox/tools/make_audio.py)。
-- 3つの音素材(効果音の列・くり返す音の列・BGM)を AudioConfig の ID で読み、列の中の位置は AudioSheet にある。
-- ID が空の間は何も鳴らさず、エラーも出さない(公開前に登録する。PUBLISH.md)。
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local config = require(ReplicatedStorage:WaitForChild("AudioConfig"))
local sheet = require(ReplicatedStorage:WaitForChild("AudioSheet"))

local Sfx = {}
local player = Players.LocalPlayer
local folder = Instance.new("Folder")
folder.Name = "MinatoSfx"
folder.Parent = SoundService

-- 設定の音量(0〜100。サーバーが本人の属性 MinatoVolume に入れる)
function Sfx.master()
    return math.clamp((player:GetAttribute("MinatoVolume") or 80) / 100, 0, 1)
end

local function ready(id)
    return type(id) == "string" and id ~= ""
end
Sfx.enabled = ready(config.sfx)

-- 効果音を1回鳴らす。name は AudioSheet.sfx の名前。pitch は速さ(高さ)
function Sfx.play(name, volume, pitch)
    local region = sheet.sfx[name]
    if not region or not ready(config.sfx) then
        return nil
    end
    local sound = Instance.new("Sound")
    sound.Name = name
    sound.SoundId = config.sfx
    sound.Volume = (volume or 1) * Sfx.master()
    sound.PlaybackSpeed = pitch or 1
    sound.PlaybackRegionsEnabled = true
    sound.PlaybackRegion = NumberRange.new(region[1], region[2])
    sound.Parent = folder
    sound:Play()
    sound.Ended:Once(function()
        sound:Destroy()
    end)
    -- 念のため、長さを過ぎたら片付ける(Ended が来ない場合)
    task.delay((region[2] - region[1]) / math.max(pitch or 1, 0.25) + 1, function()
        if sound.Parent then
            sound:Destroy()
        end
    end)
    return sound
end

-- くり返す音を作る(止まった状態・音量0で返す。呼ぶ側が Volume と PlaybackSpeed を動かす)
-- parent が部品なら、その場所から聞こえる音になる
function Sfx.loop(name, parent)
    local region = sheet.loops[name]
    if not region or not ready(config.loops) then
        return nil
    end
    local sound = Instance.new("Sound")
    sound.Name = name
    sound.SoundId = config.loops
    sound.Looped = true
    sound.Volume = 0
    sound.PlaybackRegionsEnabled = true
    sound.PlaybackRegion = NumberRange.new(region[1], region[2])
    sound.LoopRegion = NumberRange.new(region[1], region[2])
    sound.Parent = parent or folder
    sound:Play()
    return sound
end

-- BGM(ホーム)。on で静かに鳴らし始め、off で1秒かけて消す
local music, musicTarget = nil, 0
function Sfx.music(on, volume)
    if not ready(config.music) then
        return
    end
    if not music then
        music = Instance.new("Sound")
        music.Name = "Music"
        music.SoundId = config.music
        music.Looped = true
        music.Volume = 0
        music.Parent = folder
        task.spawn(function()
            while music.Parent do
                local goal = musicTarget * Sfx.master()
                music.Volume += (goal - music.Volume) * 0.08
                if goal > 0.001 and not music.IsPlaying then
                    music:Play()
                elseif goal <= 0.001 and music.Volume < 0.004 and music.IsPlaying then
                    music:Pause()
                end
                task.wait(0.05)
            end
        end)
    end
    musicTarget = on and (volume or 0.32) or 0
end

-- くり返す曲(オープニング・ガチャの演出)。最初の幕開けは1回だけ鳴らし、あとは AudioSheet の区切りをくり返す
local tracks = {}
local function track(key, name, loop, volume, on)
    local id = config[key]
    if not ready(id) then return end
    local t = tracks[key] or {}
    tracks[key] = t
    if t.fade then t.fade:Cancel(); t.fade = nil end
    if on then
        if not t.sound then
            local sound = Instance.new("Sound")
            sound.Name = name
            sound.SoundId = id
            sound.Looped = true
            if loop then
                sound.PlaybackRegionsEnabled = true
                sound.LoopRegion = NumberRange.new(loop[1], loop[2])
            end
            sound.Parent = folder
            t.sound = sound
        end
        t.sound.Volume = volume * Sfx.master()
        if not t.sound.IsPlaying then t.sound.TimePosition = 0; t.sound:Play() end
    elseif t.sound then
        local sound = t.sound
        local tween = game:GetService("TweenService"):Create(sound, TweenInfo.new(key == "gacha" and .6 or 1.4), {Volume = 0})
        t.fade = tween
        tween.Completed:Once(function(state)
            if state == Enum.PlaybackState.Completed and t.fade == tween then
                sound:Destroy(); t.sound = nil; t.fade = nil
            end
        end)
        tween:Play()
    end
end
-- オープニングの曲(ブラウザ版と同じ曲)
function Sfx.opening(on)
    track("opening", "OpeningMusic", sheet.openingLoop, .42, on)
end
-- ガチャの演出の曲(ホームの BGM はその間だけ止める)
function Sfx.gacha(on)
    if on then Sfx.music(false) else Sfx.music(true) end
    track("gacha", "GachaMusic", sheet.gachaLoop, .5, on)
end
return Sfx
