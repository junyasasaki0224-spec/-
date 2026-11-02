--!strict
-- UI部品。すべてコードで作るので画像アセットは不要。
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local C = Theme.Colors

local Kit = {}

-- 汎用のインスタンス生成: Kit.new("Frame", { Size = ... }, { children })
function Kit.new(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	if props then
		for k, v in props do
			if k ~= "Parent" then
				(inst :: any)[k] = v
			end
		end
	end
	if children then
		for _, c in children do
			c.Parent = inst
		end
	end
	if props and props.Parent then
		inst.Parent = props.Parent
	end
	return inst
end

function Kit.corner(parent: Instance, radius: UDim?): UICorner
	return Kit.new("UICorner", { CornerRadius = radius or Theme.Corner, Parent = parent })
end

function Kit.stroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?): UIStroke
	return Kit.new("UIStroke", {
		Color = color or C.gold,
		Thickness = thickness or 2,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function Kit.padding(parent: Instance, px: number)
	Kit.new("UIPadding", {
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		Parent = parent,
	})
end

function Kit.gradient(parent: Instance, top: Color3, bottom: Color3, rotation: number?): UIGradient
	return Kit.new("UIGradient", {
		Color = ColorSequence.new(top, bottom),
		Rotation = rotation or 90,
		Parent = parent,
	})
end

function Kit.label(props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		Font = Theme.Fonts.bold,
		TextColor3 = C.text,
		TextScaled = true,
		Text = "",
	}
	for k, v in props do
		if k ~= "MaxTextSize" then -- UITextSizeConstraint 用(TextLabel のプロパティではない)
			defaults[k] = v
		end
	end
	local l = Kit.new("TextLabel", defaults)
	Kit.new("UITextSizeConstraint", { MaxTextSize = props.MaxTextSize or 28, MinTextSize = 8, Parent = l })
	return l
end

-- 押した時に少し縮むボタン
function Kit.button(props: { [string]: any }, onClick: (() -> ())?): TextButton
	local color = props.Color or C.vermilion
	local b = Kit.new("TextButton", {
		Name = props.Name or "Button",
		Size = props.Size or UDim2.fromOffset(160, 48),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		BackgroundColor3 = color,
		AutoButtonColor = false,
		Font = Theme.Fonts.title,
		Text = props.Text or "",
		TextColor3 = props.TextColor or C.text,
		TextScaled = true,
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	})
	Kit.new("UITextSizeConstraint", { MaxTextSize = props.MaxTextSize or 24, MinTextSize = 8, Parent = b })
	Kit.corner(b, props.Corner or Theme.CornerSmall)
	Kit.stroke(b, props.StrokeColor or C.gold, 2, 0.2)
	Kit.gradient(b, Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190))
	Kit.padding(b, 6)
	local scale = Kit.new("UIScale", { Parent = b })
	b.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.93 }):Play()
	end)
	local function release()
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	b.MouseButton1Up:Connect(release)
	b.MouseLeave:Connect(release)
	if onClick then
		b.Activated:Connect(function()
			if b:GetAttribute("Disabled") then
				return
			end
			onClick()
		end)
	end
	return b
end

function Kit.setEnabled(b: TextButton, enabled: boolean, enabledColor: Color3?)
	b:SetAttribute("Disabled", not enabled)
	b.BackgroundColor3 = if enabled then (enabledColor or C.vermilion) else C.disabled
	b.TextTransparency = if enabled then 0 else 0.35
end

-- タイトルと閉じるボタンつきのパネル
export type Panel = { root: Frame, body: Frame, title: TextLabel, close: TextButton }
function Kit.panel(parent: Instance, name: string, size: UDim2): Panel
	local root = Kit.new("Frame", {
		Name = name,
		Size = size,
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.panel,
		Visible = false,
		Parent = parent,
	})
	Kit.corner(root)
	Kit.stroke(root, C.gold, 3)
	Kit.gradient(root, Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 170, 200))
	Kit.new("UISizeConstraint", { MaxSize = Vector2.new(900, 640), Parent = root })
	local header = Kit.new("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, 54),
		BackgroundColor3 = C.vermilionDark,
		Parent = root,
	})
	Kit.corner(header)
	Kit.gradient(header, C.vermilion, C.vermilionDark)
	-- 下の角を四角にするための帯
	Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, 14),
		Position = UDim2.new(0, 0, 1, -14),
		BackgroundColor3 = C.vermilionDark,
		BorderSizePixel = 0,
		Parent = header,
	})
	local title = Kit.label({
		Name = "Title",
		Size = UDim2.new(1, -120, 1, -12),
		Position = UDim2.fromOffset(20, 6),
		Font = Theme.Fonts.title,
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 30,
		ZIndex = 2,
		Parent = header,
	})
	local close = Kit.button({
		Name = "Close",
		Text = "✕",
		Size = UDim2.fromOffset(42, 42),
		Position = UDim2.new(1, -8, 0, 6),
		AnchorPoint = Vector2.new(1, 0),
		Color = C.panelDark,
		Parent = header,
	})
	close.ZIndex = 3
	local body = Kit.new("Frame", {
		Name = "Body",
		Size = UDim2.new(1, -24, 1, -70),
		Position = UDim2.fromOffset(12, 62),
		BackgroundTransparency = 1,
		Parent = root,
	})
	return { root = root, body = body, title = title, close = close }
end

-- 縦にスクロールするリスト
function Kit.list(parent: Instance, padding: number?): ScrollingFrame
	local sf = Kit.new("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.gold,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = parent,
	})
	Kit.new("UIListLayout", {
		Padding = UDim.new(0, padding or 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = sf,
	})
	Kit.new("UIPadding", {
		PaddingRight = UDim.new(0, 10),
		PaddingTop = UDim.new(0, 2),
		PaddingLeft = UDim.new(0, 2),
		Parent = sf,
	})
	return sf
end

-- 行(リストの1項目)
function Kit.row(parent: Instance, height: number, order: number?): Frame
	local f = Kit.new("Frame", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = C.panelLight,
		LayoutOrder = order or 0,
		Parent = parent,
	})
	Kit.corner(f, Theme.CornerSmall)
	Kit.stroke(f, C.gold, 1, 0.6)
	return f
end

function Kit.clear(container: Instance)
	for _, c in container:GetChildren() do
		if not c:IsA("UIListLayout") and not c:IsA("UIGridLayout") and not c:IsA("UIPadding") then
			c:Destroy()
		end
	end
end

-- 横長のゲージ
function Kit.bar(parent: Instance, color: Color3): (Frame, Frame)
	local bg = Kit.new("Frame", { BackgroundColor3 = C.panelDark, Parent = parent })
	Kit.corner(bg, UDim.new(1, 0))
	local fill = Kit.new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = color, Parent = bg })
	Kit.corner(fill, UDim.new(1, 0))
	return bg, fill
end

-- ビューポートにモデルを映す(回転させる場合は呼び出し側で)
function Kit.viewport(parent: Instance, model: Model?, props: { [string]: any }?): ViewportFrame
	local vpf = Kit.new("ViewportFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(170, 170, 190),
		LightColor = Color3.fromRGB(255, 245, 230),
		LightDirection = Vector3.new(-1, -1.5, -1),
		Parent = parent,
	})
	if props then
		for k, v in props do
			(vpf :: any)[k] = v
		end
	end
	if model then
		Kit.setViewportModel(vpf, model)
	end
	return vpf
end

function Kit.setViewportModel(vpf: ViewportFrame, model: Model)
	for _, c in vpf:GetChildren() do
		if c:IsA("Model") or c:IsA("Camera") or c:IsA("WorldModel") then
			c:Destroy()
		end
	end
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = vpf
	vpf.CurrentCamera = cam
	model:PivotTo(CFrame.new())
	model.Parent = vpf
	local _, size = model:GetBoundingBox()
	local radius = size.Magnitude / 2
	local dist = radius / math.tan(math.rad(cam.FieldOfView / 2)) * 1.05
	-- 斜め横から(魚の頭 = -Z を左に向ける)
	cam.CFrame = CFrame.lookAt(Vector3.new(dist, dist * 0.25, -dist * 0.05), Vector3.zero)
end

return Kit
