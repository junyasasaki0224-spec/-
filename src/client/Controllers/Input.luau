--!strict
-- 「押している/離した」の入力をまとめる。
--  * スマホ: 画面右下の大きなボタン(片手で遊べる)。画面のドラッグはカメラ操作なので釣りに使わない
--  * PC: 左クリック(UIの上以外)、F キー、またはボタン
--  * ゲームパッド: R2
local UserInputService = game:GetService("UserInputService")

local Input = {}

local began = Instance.new("BindableEvent")
local ended = Instance.new("BindableEvent")
Input.Began = began.Event
Input.Ended = ended.Event

local holdingSources: { [any]: boolean } = {}
local enabled = true

local function anyHolding(): boolean
	return next(holdingSources) ~= nil
end

function Input.isHolding(): boolean
	return anyHolding()
end

function Input.press(source: any)
	if not enabled then
		return
	end
	local was = anyHolding()
	holdingSources[source] = true
	if not was then
		began:Fire()
	end
end

function Input.release(source: any)
	if not holdingSources[source] then
		return
	end
	holdingSources[source] = nil
	if not anyHolding() then
		ended:Fire()
	end
end

-- パネルを開いている間などは入力を止める
function Input.setEnabled(on: boolean)
	enabled = on
	if not on then
		local had = anyHolding()
		table.clear(holdingSources)
		if had then
			ended:Fire()
		end
	end
end

function Input.init()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			Input.press("mouse")
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 or input.KeyCode == Enum.KeyCode.F then
			Input.press("key")
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			Input.release("mouse")
		elseif input.KeyCode == Enum.KeyCode.ButtonR2 or input.KeyCode == Enum.KeyCode.F then
			Input.release("key")
		end
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		local had = anyHolding()
		table.clear(holdingSources)
		if had then
			ended:Fire()
		end
	end)
end

return Input
