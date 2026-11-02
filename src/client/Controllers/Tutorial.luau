--!strict
-- 最初の30秒の案内(直帰を防ぐ):
--   0〜5秒: 「長押しして投げてみよう」 → 5〜15秒: 最初の1匹はすぐ掛かり、引き上げも簡単(サーバー側で保証)
--   15〜25秒: 「上」以上の派手な演出 → 25〜30秒: 図鑑登録の通知と「魚屋で売ってみよう」の矢印
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Locale = require(Shared.Locale)
local Config = require(Shared.Config)

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local State = require(script.Parent.Parent.ClientState)
local Fishing = require(script.Parent.Fishing)
local Result = require(script.Parent.Result)
local Notify = require(script.Parent.Notify)
local Quests = require(script.Parent.Quests)
local C = Theme.Colors

local player = Players.LocalPlayer
local Tutorial = {}

local box: Frame
local text: TextLabel
local pointer: TextLabel
local step = -1
local beam: Beam? = nil
local a0: Attachment? = nil

local function show(key: string?, pointAtButton: boolean)
	if not key then
		box.Visible = false
		pointer.Visible = false
		return
	end
	text.Text = Locale.t(key)
	box.Visible = true
	pointer.Visible = pointAtButton
end

local function clearBeam()
	if beam then
		beam:Destroy()
		beam = nil
	end
	if a0 then
		a0:Destroy()
		a0 = nil
	end
end

-- 魚屋への光の道
local function beamToMerchant()
	clearBeam()
	local target: BasePart? = nil
	for _, m in CollectionService:GetTagged("Merchant") do
		if m:IsA("BasePart") and m:GetAttribute("TutorialTarget") == "sell" then
			target = m
		end
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not target or not root then
		return
	end
	local att0 = Instance.new("Attachment")
	att0.Parent = root
	local att1 = target:FindFirstChild("TutorialAttachment") :: Attachment?
	if not att1 then
		local na = Instance.new("Attachment")
		na.Name = "TutorialAttachment"
		na.Position = Vector3.new(0, 3, 0)
		na.Parent = target
		att1 = na
	end
	local b = Instance.new("Beam")
	b.Attachment0 = att0
	b.Attachment1 = att1
	b.Width0 = 1.2
	b.Width1 = 1.2
	b.Color = ColorSequence.new(C.goldLight)
	b.LightEmission = 1
	b.Transparency = NumberSequence.new(0.3)
	b.FaceCamera = true
	b.TextureSpeed = 2
	b.Parent = root
	beam = b
	a0 = att0
end

local function setStep(n: number)
	if n <= step then
		return
	end
	step = n
	if n == 0 then
		show("tut_cast", true)
	elseif n == 1 then
		show("tut_wait", false)
	elseif n == 2 then
		show("tut_reel", true)
	elseif n == 3 then
		show(nil, false)
	elseif n == 4 then
		show("tut_sell", false)
		beamToMerchant()
	elseif n >= 5 then
		show(nil, false)
		clearBeam()
		task.delay(2.5, Quests.showDailyIfPending)
	end
	if n == 1 or n == 3 or n == 5 then
		State.request("tutorial", n)
	end
end

function Tutorial.init(gui: ScreenGui)
	box = Kit.new("Frame", {
		Size = UDim2.fromOffset(520, 64),
		Position = UDim2.new(0.5, 0, 0.72, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = gui,
	})
	Kit.corner(box, UDim.new(1, 0))
	Kit.stroke(box, C.goldLight, 3)
	text = Kit.label({
		Size = UDim2.new(1, -30, 1, -14),
		Position = UDim2.fromOffset(15, 7),
		MaxTextSize = 24,
		Parent = box,
	})
	pointer = Kit.label({
		Size = UDim2.fromOffset(80, 80),
		Position = UDim2.new(1, -110, 1, -200),
		AnchorPoint = Vector2.new(0.5, 1),
		Text = "👇",
		MaxTextSize = 70,
		Visible = false,
		Parent = gui,
	})
	local tw = TweenService:Create(
		pointer,
		TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Position = UDim2.new(1, -110, 1, -180) }
	)
	tw:Play()

	local function fromProfile()
		local p = State.profile
		if not p or step >= 0 then
			return
		end
		if p.tutorial >= 5 then
			step = 5
			return
		end
		if p.firstCatch then
			-- 釣ったけどまだ売っていない
			setStep(4)
		else
			setStep(0)
		end
	end
	State.Changed:Connect(function()
		fromProfile()
		local p = State.profile
		if step == 4 and p and #p.creel == 0 then
			setStep(5)
		end
	end)
	Fishing.StateChanged:Connect(function(s)
		if step < 0 or step >= 3 then
			return
		end
		if s == "waiting" then
			setStep(1)
		elseif s == "reeling" then
			setStep(2)
		end
	end)
	Result.Closed:Connect(function(r)
		if r.firstEver and step < 4 then
			setStep(3)
			local def = Config.FishById[r.fishId]
			if def then
				Notify.show(Locale.t("notify_codex_new", { fish = Locale.fishName(def) }), C.goldLight)
			end
			Notify.key("tut_codex", nil, C.goldLight)
			task.delay(1.2, function()
				setStep(4)
			end)
		end
	end)
	player.CharacterAdded:Connect(function()
		if step == 4 then
			task.wait(1)
			beamToMerchant()
		end
	end)
end

return Tutorial
