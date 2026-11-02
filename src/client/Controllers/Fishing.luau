--!strict
-- 釣りの操作と演出(クライアント側)。結果を決めるのはサーバーで、ここは入力と見た目だけ。
--   idle → (長押し) charging → (離す) casting → waiting → bite → (タップ) reeling → idle
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Locale = require(Shared.Locale)
local Remotes = require(Shared.Lib.Remotes)

local Kit = require(script.Parent.Parent.UI.Kit)
local Theme = require(script.Parent.Parent.UI.Theme)
local Root = require(script.Parent.Parent.UI.Root)
local Input = require(script.Parent.Input)
local ReelGame = require(script.Parent.ReelGame)
local Notify = require(script.Parent.Notify)
local Sound = require(script.Parent.Sound)
local C = Theme.Colors

local FT = Config.Tuning.Fishing
local player = Players.LocalPlayer

local Fishing = {}
local stateChanged = Instance.new("BindableEvent")
Fishing.StateChanged = stateChanged.Event -- (state)

local state = "idle"
local chargeStart = 0
local castTimeout = 0
local biteAt = 0
local reel: any = nil

local actionButton: TextButton
local actionLabel: TextLabel
local powerBg: Frame
local powerFill: Frame
local hintLabel: TextLabel
local biteMark: TextLabel
local autoBadge: TextLabel

local castRemote: RemoteEvent
local hookRemote: RemoteEvent
local reelRemote: RemoteEvent
local cancelRemote: RemoteEvent

local function setState(s: string)
	state = s
	stateChanged:Fire(s)
end

function Fishing.state(): string
	return state
end

local function setHint(key: string?)
	if key then
		hintLabel.Text = Locale.t(key)
		hintLabel.Visible = true
	else
		hintLabel.Visible = false
	end
end

local function refreshButton()
	local auto = player:GetAttribute("AutoFishing") == true
	autoBadge.Visible = auto
	local text, color
	if state == "bite" then
		text, color = "!", C.goldLight
	elseif state == "reeling" then
		text, color = "🎣", C.jade
	elseif state == "waiting" or state == "casting" then
		text, color = "…", C.indigo
	else
		text, color = "🎣", C.vermilion
	end
	actionLabel.Text = text
	actionButton.BackgroundColor3 = color
end

local function stopReel()
	if reel then
		reel:destroy()
		reel = nil
	end
end

local function onPress()
	if Root.isOpen() then
		return
	end
	if player:GetAttribute("AutoFishing") == true then
		return
	end
	if state == "idle" then
		chargeStart = os.clock()
		setState("charging")
		powerBg.Visible = true
	elseif state == "bite" then
		hookRemote:FireServer()
		setState("hooking")
		biteMark.Visible = false
	end
	refreshButton()
end

local function onRelease()
	if state == "charging" then
		local power = math.clamp((os.clock() - chargeStart) / FT.castMaxHoldSeconds, 0, 1)
		powerBg.Visible = false
		-- カメラの向きに投げる(キャラクターもそちらを向かせる)
		local cam = workspace.CurrentCamera
		local look = if cam then cam.CFrame.LookVector else Vector3.new(0, 0, -1)
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude < 0.01 then
			flat = Vector3.new(0, 0, -1)
		end
		flat = flat.Unit
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
		end
		castRemote:FireServer(power, flat.X, flat.Z)
		setState("casting")
		castTimeout = os.clock() + 2
		Sound.play("click", 0.3, 0.8)
	end
	refreshButton()
end

local function onServerState(s: any, data: any)
	if type(s) ~= "string" then
		return
	end
	data = if type(data) == "table" then data else {}
	if s == "waiting" then
		stopReel()
		setState("waiting")
		setHint(if data.auto then nil else "fish_waiting")
		Sound.play("splash", 0.5, 1.2)
	elseif s == "bite" then
		setState("bite")
		biteAt = os.clock()
		if player:GetAttribute("AutoFishing") ~= true then
			biteMark.Visible = true
			biteMark.Rotation = 0
			local sc = biteMark:FindFirstChildOfClass("UIScale") :: UIScale
			sc.Scale = 0.2
			TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			setHint("fish_tap_now")
			Sound.play("bite", 0.8, 1.6)
		end
	elseif s == "reel" then
		biteMark.Visible = false
		setState("reeling")
		if player:GetAttribute("AutoFishing") == true then
			setHint(nil)
		else
			setHint("fish_reel_hint")
			stopReel()
			reel = ReelGame.new(Root.gui(), data :: any, "catch", {
				onFinish = function(success)
					reelRemote:FireServer(success)
					reel = nil
					if not success then
						Sound.play("fail", 0.6, 0.7)
					end
				end,
			})
		end
	elseif s == "idle" then
		stopReel()
		biteMark.Visible = false
		powerBg.Visible = false
		setHint(nil)
		local reason = data.reason
		if reason == "escaped" then
			Notify.key("fish_escaped", nil, C.textDim)
		elseif reason == "broke" then
			Notify.key("fish_line_broke", nil, C.danger)
		end
		setState("idle")
	end
	refreshButton()
end

function Fishing.cancel()
	if state == "waiting" or state == "bite" then
		cancelRemote:FireServer()
	end
end

function Fishing.init(gui: ScreenGui)
	castRemote = Remotes.event("Cast")
	hookRemote = Remotes.event("Hook")
	reelRemote = Remotes.event("ReelResult")
	cancelRemote = Remotes.event("CancelFishing")

	-- 右下の大きなボタン(片手で押せる位置)
	actionButton = Kit.new("TextButton", {
		Name = "Action",
		Size = UDim2.fromOffset(132, 132),
		Position = UDim2.new(1, -36, 1, -40),
		AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = C.vermilion,
		AutoButtonColor = false,
		Text = "",
		Parent = gui,
	})
	Kit.corner(actionButton, UDim.new(1, 0))
	Kit.stroke(actionButton, C.goldLight, 4)
	Kit.gradient(actionButton, Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170))
	actionLabel = Kit.label({
		Size = UDim2.fromScale(0.7, 0.7),
		Position = UDim2.fromScale(0.15, 0.15),
		Font = Theme.Fonts.title,
		MaxTextSize = 60,
		Parent = actionButton,
	})
	local btnScale = Kit.new("UIScale", { Parent = actionButton })
	actionButton.InputBegan:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			TweenService:Create(btnScale, TweenInfo.new(0.06), { Scale = 0.92 }):Play()
			Input.press(actionButton)
		end
	end)
	actionButton.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			TweenService:Create(btnScale, TweenInfo.new(0.12, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			Input.release(actionButton)
		end
	end)

	-- 投げる強さのゲージ(ボタンの上)
	local bg, fill = Kit.bar(gui, C.goldLight)
	powerBg = bg
	powerFill = fill
	powerBg.Size = UDim2.fromOffset(160, 18)
	powerBg.Position = UDim2.new(1, -18, 1, -190)
	powerBg.AnchorPoint = Vector2.new(1, 1)
	powerBg.Visible = false
	Kit.stroke(powerBg, C.gold, 2)

	hintLabel = Kit.label({
		Name = "Hint",
		Size = UDim2.fromOffset(620, 40),
		Position = UDim2.new(0.5, 0, 1, -70),
		AnchorPoint = Vector2.new(0.5, 1),
		TextColor3 = C.text,
		MaxTextSize = 26,
		Visible = false,
		Parent = gui,
	})
	Kit.new(
		"UIStroke",
		{ Color = Color3.new(0, 0, 0), Thickness = 2, Transparency = 0.2, Parent = hintLabel }
	)

	biteMark = Kit.label({
		Name = "Bite",
		Size = UDim2.fromOffset(160, 160),
		Position = UDim2.fromScale(0.5, 0.36),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Text = "!",
		TextColor3 = C.goldLight,
		Font = Theme.Fonts.title,
		MaxTextSize = 150,
		Visible = false,
		Parent = gui,
	})
	Kit.new("UIStroke", { Color = C.vermilionDark, Thickness = 5, Parent = biteMark })
	Kit.new("UIScale", { Parent = biteMark })

	autoBadge = Kit.label({
		Name = "AutoBadge",
		Size = UDim2.fromOffset(150, 30),
		Position = UDim2.new(1, -36, 1, -180),
		AnchorPoint = Vector2.new(1, 1),
		Text = Locale.t("hud_auto_on"),
		TextColor3 = C.success,
		Visible = false,
		Parent = gui,
	})

	Input.Began:Connect(onPress)
	Input.Ended:Connect(onRelease)
	Remotes.event("FishingState").OnClientEvent:Connect(onServerState)
	player:GetAttributeChangedSignal("AutoFishing"):Connect(refreshButton)
	player.CharacterAdded:Connect(function()
		onServerState("idle", {})
	end)

	RunService.RenderStepped:Connect(function()
		if state == "charging" then
			local power = math.clamp((os.clock() - chargeStart) / FT.castMaxHoldSeconds, 0, 1)
			powerFill.Size = UDim2.fromScale(power, 1)
			powerFill.BackgroundColor3 = C.goldLight:Lerp(C.vermilion, power)
		elseif state == "casting" and os.clock() > castTimeout then
			setState("idle") -- サーバーが投げるのを断った(水辺から遠いなど)
			refreshButton()
		elseif state == "bite" then
			biteMark.Rotation = math.sin(os.clock() * 30) * 8
			if os.clock() - biteAt > FT.hookWindow + 0.6 then
				biteMark.Visible = false
			end
		elseif state == "hooking" and os.clock() - biteAt > 3 then
			setState("idle")
			refreshButton()
		end
	end)
	refreshButton()
end

return Fishing
