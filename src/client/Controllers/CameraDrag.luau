--!strict
-- PC: 左クリックしたままマウスを動かすと視点が回る(Roblox 標準の右ドラッグもそのまま使える)。
-- 左クリックの長押しは竿を振る溜めにも使うので、動かした距離が DRAG_START を超えたら
-- 「視点を回している」とみなして溜めを取り消す(動かさずに離せば今まで通り投げる)。
-- リールを巻いている間・魚がかかった時は回さない(巻く操作をじゃましない)。
-- 回し方: 標準カメラが動いた後(RenderPriority.Camera + 1)にカメラを注視点のまわりで回す。
-- 標準カメラは次のフレームで今のカメラの向きから続けるので、そのまま向きが残る
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Input = require(script.Parent.Input)
local Fishing = require(script.Parent.Fishing)

local CameraDrag = {}

local DRAG_START = 8 -- この距離(ピクセル)を超えて動かしたら視点を回す
local SENSITIVITY = math.rad(0.35) -- 1ピクセルで回る角度
local PITCH_LIMIT = math.rad(75)
-- 視点を回してよい釣りの状態(巻いている時・かかった時は回さない)
local FREE_STATES = { idle = true, charging = true, casting = true, waiting = true }

local pressing = false
local dragging = false
local moved = 0
local pendingYaw, pendingPitch = 0, 0

function CameraDrag.isDragging(): boolean
	return dragging
end

local function stop()
	pressing = false
	moved = 0
	if dragging then
		dragging = false
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
end

-- 注視点のまわりでカメラを回す(上下は真上・真下の手前で止める)
function CameraDrag.rotate(cf: CFrame, focus: Vector3, yaw: number, pitch: number): CFrame
	local offset = cf.Position - focus
	local dist = offset.Magnitude
	if dist < 0.01 then
		return cf
	end
	local look = -offset.Unit
	local curPitch = math.asin(math.clamp(look.Y, -1, 1))
	local newPitch = math.clamp(curPitch - pitch, -PITCH_LIMIT, PITCH_LIMIT)
	local curYaw = math.atan2(-look.X, -look.Z)
	local newYaw = curYaw - yaw
	local dir = Vector3.new(
		-math.sin(newYaw) * math.cos(newPitch),
		math.sin(newPitch),
		-math.cos(newYaw) * math.cos(newPitch)
	)
	local pos = focus - dir * dist
	return CFrame.lookAt(pos, focus)
end

-- マウスが動いた(ピクセル)。回し始めたら true
function CameraDrag.onMove(dx: number, dy: number): boolean
	if not pressing then
		return false
	end
	if not dragging then
		moved += math.abs(dx) + math.abs(dy)
		if moved < DRAG_START or not FREE_STATES[Fishing.state()] then
			return false
		end
		dragging = true
		Input.cancel("mouse") -- 溜めていた竿は振らない
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCurrentPosition
	end
	pendingYaw += dx * SENSITIVITY
	pendingPitch += dy * SENSITIVITY
	return true
end

function CameraDrag.init()
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.UserInputType == Enum.UserInputType.MouseButton1 then
			pressing = true
			moved = 0
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			CameraDrag.onMove(input.Delta.X, input.Delta.Y)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			stop()
		end
	end)
	UserInputService.WindowFocusReleased:Connect(stop)
	RunService:BindToRenderStep("YokaiCameraDrag", Enum.RenderPriority.Camera.Value + 1, function()
		if pendingYaw == 0 and pendingPitch == 0 then
			return
		end
		local cam = workspace.CurrentCamera
		if cam and cam.CameraType == Enum.CameraType.Custom then
			cam.CFrame = CameraDrag.rotate(cam.CFrame, cam.Focus.Position, pendingYaw, pendingPitch)
		end
		pendingYaw, pendingPitch = 0, 0
	end)
	Players.LocalPlayer.CharacterAdded:Connect(stop)
end

return CameraDrag
