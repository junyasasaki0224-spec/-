--!strict
-- 効果音。Roblox に最初から入っている音だけを使う(Creator Store の音に替える時は IDS を書き換える)
local SoundService = game:GetService("SoundService")

local Sound = {}
local muted = false

local IDS: { [string]: string } = {
	splash = "rbxasset://sounds/impact_water.mp3",
	click = "rbxasset://sounds/electronicpingshort.wav",
	bite = "rbxasset://sounds/electronicpingshort.wav",
	catch = "rbxasset://sounds/impact_water.mp3",
	rare = "rbxasset://sounds/electronicpingshort.wav",
	coins = "rbxasset://sounds/electronicpingshort.wav",
	fail = "rbxasset://sounds/impact_water.mp3",
}

function Sound.play(name: string, volume: number?, pitch: number?)
	if muted then
		return
	end
	local id = IDS[name]
	if not id or id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 0.5
	s.PlaybackSpeed = pitch or 1
	s.Parent = SoundService
	s:Play()
	s.Ended:Connect(function()
		s:Destroy()
	end)
	task.delay(6, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

function Sound.setMuted(m: boolean)
	muted = m
end

function Sound.isMuted(): boolean
	return muted
end

return Sound
