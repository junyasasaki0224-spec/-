--!strict
-- 妖怪魚の鳴き声。釣れた時・図鑑・相棒バトル・ぬしの出現で鳴く。
-- 音は1本(Config.Cries.soundId)にまとまっていて、魚ごとの区間だけを鳴らす。
-- 音をまだアップロードしていない(soundId が 0)時やミュート中は鳴らさず、吹き出しの文字だけ出す。
local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Locale = require(Shared.Locale)
local Cries = require(Shared.Lib.Cries)

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local Sound = require(script.Parent.Sound)
local C = Theme.Colors

local Cry = {}

local LOAD_TIMEOUT = 2 -- 音の読み込みをこれ以上待つなら、その回は鳴かせない(遅れて鳴ると変なので)

export type Options = {
	volume: number?,
	pitch: number?, -- 1 より小さいと低く・ゆっくり(バトルで倒れた時など)
	parent: Instance?, -- 3D の位置で鳴らす時はパーツを渡す
}

function Cry.text(fishId: string): string?
	return Cries.text(fishId, Locale.get())
end

-- 鳴かせる。吹き出し用の文字を返す(音が鳴らない時も返す)
function Cry.play(fishId: string, opts: Options?): string?
	local text = Cry.text(fishId)
	local a0, b0 = Cries.region(fishId)
	if a0 == nil or b0 == nil or not Cries.hasAudio() or Sound.isMuted() then
		return text
	end
	local a: number, b: number = a0 :: number, b0 :: number
	local o: Options = opts or {}
	local pitch = math.clamp(o.pitch or 1, 0.5, 2)
	local s = Instance.new("Sound")
	s.Name = "Cry_" .. fishId
	s.SoundId = Config.Cries.soundId
	s.Volume = o.volume or 0.8
	s.PlaybackSpeed = pitch
	s.PlaybackRegionsEnabled = true
	s.PlaybackRegion = NumberRange.new(a, b)
	s.Parent = o.parent or SoundService
	task.spawn(function()
		-- 読み込み前に Play すると、鳴り始めが遅れて片付けの時間までに鳴り終わらない。読み込みを待つ
		local waited = 0
		while not s.IsLoaded and waited < LOAD_TIMEOUT and s.Parent do
			waited += task.wait(0.05)
		end
		if not s.IsLoaded or not s.Parent then
			s:Destroy()
			return
		end
		s.TimePosition = a
		s:Play()
		-- 区間の終わりで止まるが、念のため時間でも止めて片付ける
		task.delay((b - a) / pitch + 0.2, function()
			s:Stop()
			s:Destroy()
		end)
	end)
	return text
end

-- 吹き出しの幅(文字数に合わせる。英数字は細く、かなと漢字は太く数える)
local function bubbleWidth(text: string): number
	local w = 34
	for _, cp in utf8.codes(text) do
		w += if cp < 128 then 10 else 19
	end
	return math.clamp(w, 110, 360)
end
Cry.bubbleWidth = bubbleWidth

-- 吹き出し(「ぴゅるる〜」)をぽんと出して、少ししたら消す
function Cry.bubble(parent: GuiObject, text: string?, position: UDim2?, zIndex: number?): TextLabel?
	if text == nil or text == "" then
		return nil
	end
	local t: string = text :: string
	local quoted = if Locale.get() == "ja" then "「" .. t .. "」" else "“" .. t .. "”"
	local z = zIndex or 30
	local b = Kit.label({
		Name = "CryBubble",
		Size = UDim2.fromOffset(bubbleWidth(quoted), 40),
		Position = position or UDim2.new(1, -12, 0, 12),
		AnchorPoint = Vector2.new(1, 0),
		BackgroundTransparency = 0.05,
		BackgroundColor3 = C.text,
		TextColor3 = C.textDark,
		Font = Theme.Fonts.title,
		Text = quoted,
		MaxTextSize = 20,
		ZIndex = z,
		Parent = parent,
	})
	b.AutomaticSize = Enum.AutomaticSize.None
	Kit.corner(b, UDim.new(0, 14))
	Kit.padding(b, 6)
	local stroke = Kit.stroke(b, C.gold, 2, 0.1)
	local scale = Kit.new("UIScale", { Scale = 0.2, Parent = b })
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(2.2, function()
		if b.Parent then
			local fade = TweenInfo.new(0.35)
			TweenService:Create(b, fade, { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
			TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
			task.delay(0.4, function()
				b:Destroy()
			end)
		end
	end)
	return b
end

-- 鳴かせて吹き出しも出す
function Cry.say(fishId: string, parent: GuiObject, position: UDim2?, opts: Options?, zIndex: number?)
	Cry.bubble(parent, Cry.play(fishId, opts), position, zIndex)
end

function Cry.init()
	-- 最初に鳴く時に待たないよう、音を先に読み込んでおく
	if Cries.hasAudio() then
		task.spawn(function()
			local s = Instance.new("Sound")
			s.SoundId = Config.Cries.soundId
			pcall(function()
				ContentProvider:PreloadAsync({ s })
			end)
			s:Destroy()
		end)
	end
end

return Cry
