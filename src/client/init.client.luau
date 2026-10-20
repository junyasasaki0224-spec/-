-- クライアント側のメインスクリプト(各プレイヤーの画面で動く)
-- 画面上部にあいさつメッセージを数秒表示する
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "WelcomeGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local label = Instance.new("TextLabel")
label.Size = UDim2.new(0, 400, 0, 50)
label.Position = UDim2.new(0.5, -200, 0, 20)
label.BackgroundTransparency = 0.3
label.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
label.TextColor3 = Color3.new(1, 1, 1)
label.TextScaled = true
label.Text = `ようこそ {player.DisplayName}! コインを集めよう`
label.Parent = screenGui

task.delay(5, function()
	screenGui:Destroy()
end)
