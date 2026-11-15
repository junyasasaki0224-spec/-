-- レースの結果の画面(ブラウザ版の #result と同じ: 大きな着順、ひとこと、結果の表、記録、ボタン)
local Result = {}
Result.__index = Result

local GOLD = Color3.fromRGB(255, 210, 60)
local WHITE = Color3.new(1, 1, 1)
local RED = Color3.fromRGB(255, 90, 77)
local PALE = Color3.fromRGB(219, 230, 250)
local HEAD = Color3.fromRGB(169, 189, 219)
local LANE = {
    { Color3.fromRGB(242, 242, 240), Color3.fromRGB(17, 17, 17) },
    { Color3.fromRGB(22, 22, 26), WHITE },
    { Color3.fromRGB(217, 30, 46), WHITE },
    { Color3.fromRGB(27, 80, 212), WHITE },
    { Color3.fromRGB(243, 210, 27), Color3.fromRGB(17, 17, 17) },
    { Color3.fromRGB(24, 162, 76), WHITE },
}
local NUMBER = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
local HEAVY = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy, Enum.FontStyle.Normal)
local BOLD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)

local function corner(p, r)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r)
    c.Parent = p
end
local function stroke(p, color, t, tr)
    local s = Instance.new("UIStroke")
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Color, s.Thickness, s.Transparency = color, t, tr or 0
    s.Parent = p
    return s
end
local function text(parent, name, size, font, color, align)
    local t = Instance.new("TextLabel")
    t.Name = name
    t.BackgroundTransparency = 1
    t.TextSize = size
    t.FontFace = font or BOLD
    t.TextColor3 = color or WHITE
    t.TextXAlignment = align or Enum.TextXAlignment.Center
    t.TextTruncate = Enum.TextTruncate.AtEnd
    t.Text = ""
    t.Parent = parent
    return t
end
local function formatTime(t)
    local tenths = math.floor(math.max(0, t) * 10 + 0.5)
    return string.format("%d'%02d\"%d", tenths // 600, (tenths // 10) % 60, tenths % 10)
end

-- ボタン(primary は金のグラデーション)
local function button(parent, name, caption, primary, onPress)
    local b = Instance.new("TextButton")
    b.Name = name
    b.Text = caption
    b.AutoButtonColor = true
    b.FontFace = HEAVY
    b.TextSize = primary and 18 or 15
    b.TextColor3 = primary and Color3.fromRGB(26, 18, 0) or WHITE
    b.BackgroundColor3 = primary and WHITE or Color3.fromRGB(20, 40, 72)
    b.BorderSizePixel = 0
    b.Parent = parent
    corner(b, 10)
    if primary then
        local g = Instance.new("UIGradient")
        g.Color = ColorSequence.new(Color3.fromRGB(255, 224, 102), Color3.fromRGB(245, 164, 0))
        g.Rotation = 90
        g.Parent = b
    else
        stroke(b, WHITE, 1, 0.55)
    end
    b.Activated:Connect(onPress)
    return b
end

function Result.new(hudGui)
    -- レース中の表示より手前に出すため、専用の画面(ScreenGui)を作る
    local gui = Instance.new("ScreenGui")
    gui.Name = "MinatoResult"
    gui.ResetOnSpawn = false
    gui.DisplayOrder = 10
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
    gui.Parent = hudGui.Parent
    local self = setmetatable({ gui = gui, actions = {} }, Result)
    local shade = Instance.new("Frame")
    shade.Name = "ResultShade"
    shade.BackgroundColor3 = Color3.fromRGB(4, 14, 32)
    shade.BackgroundTransparency = 0.45
    shade.Size = UDim2.fromScale(1, 1)
    shade.Visible = false
    shade.Parent = gui
    self.shade = shade
    local panel = Instance.new("ScrollingFrame")
    panel.Name = "ResultPanel"
    panel.AnchorPoint = Vector2.new(0.5, 0.5)
    panel.Position = UDim2.fromScale(0.5, 0.5)
    panel.BackgroundColor3 = Color3.fromRGB(9, 24, 50)
    panel.BackgroundTransparency = 0.12
    panel.BorderSizePixel = 0
    panel.ScrollBarThickness = 4
    panel.Parent = shade
    corner(panel, 18)
    stroke(panel, WHITE, 1, 0.78)
    self.panel = panel
    self.head = text(panel, "Head", 72, NUMBER)
    self.sub = text(panel, "Sub", 15, BOLD, PALE)
    self.sub.TextWrapped = true
    -- 表の見出し
    self.cols = {}
    for _, c in ipairs({ { "着", 0.1 }, { "艇", 0.1 }, { "選手", 0.38 }, { "タイム", 0.22 }, { "ST", 0.2 } }) do
        local h = text(panel, "Col", 12, BOLD, HEAD)
        h.Text = c[1]
        table.insert(self.cols, { label = h, width = c[2] })
    end
    self.rows = {}
    for i = 1, 6 do
        local row = Instance.new("Frame")
        row.Name = "Row" .. i
        row.BackgroundColor3 = GOLD
        row.BackgroundTransparency = 1
        row.BorderSizePixel = 0
        row.Parent = panel
        local line = Instance.new("Frame")
        line.BackgroundColor3 = WHITE
        line.BackgroundTransparency = 0.88
        line.BorderSizePixel = 0
        line.Size = UDim2.new(1, 0, 0, 1)
        line.Parent = row
        local cells = {}
        cells.place = text(row, "Place", 15, NUMBER)
        cells.chip = text(row, "Lane", 13, HEAVY)
        cells.chip.BackgroundTransparency = 0
        corner(cells.chip, 5)
        stroke(cells.chip, WHITE, 1, 0.2)
        cells.name = text(row, "Name", 15, BOLD, WHITE, Enum.TextXAlignment.Left)
        cells.time = text(row, "Time", 15, NUMBER)
        cells.st = text(row, "ST", 15, NUMBER)
        self.rows[i] = { frame = row, cells = cells }
    end
    self.extra = text(panel, "Extra", 14, BOLD, PALE, Enum.TextXAlignment.Left)
    self.extra.TextWrapped = true
    self.extra.TextYAlignment = Enum.TextYAlignment.Top
    self.extra.TextTruncate = Enum.TextTruncate.None
    self.buttons = Instance.new("Frame")
    self.buttons.Name = "Buttons"
    self.buttons.BackgroundTransparency = 1
    self.buttons.Parent = panel
    return self
end

-- 結果を見せる。rows = サーバーの結果の行 {艇番, 着か失格, 名前, AIか, 塗装, ヘルメット, タイム, ST}
-- mySeat = 自分の艇番(観戦なら 0)、extra = 記録の文(タイムアタック・大会の得点など)
-- buttons = { {name, caption, primary, onPress}, ... }
-- opts(なくてもよい): { head = 大きな文字, sub = ひとこと, color = 色, placeHeader = 表の1列目の見出し }
function Result:show(rows, mySeat, extra, buttons, key, opts)
    local size = self.gui.AbsoluteSize
    local w = math.min(560, size.X - 24)
    local compact = size.Y < 520
    local x0, inner = 22, w - 44
    local mine
    for _, r in ipairs(rows) do
        if r[1] == mySeat then
            mine = r
        end
    end
    -- 大きな着順と、ひとこと
    local head, sub, color = "レース結果", "", WHITE
    if mine then
        local place = tonumber(mine[2])
        if place then
            head, color = place .. "着", place == 1 and GOLD or WHITE
            local top = rows[1]
            sub = place == 1 and "おめでとう！" or string.format("1着 %d号艇 %s", top[1], top[3] or "")
        elseif mine[2] == "F" then
            head, color, sub = "フライング", RED, "スタートが早すぎました。0秒〜1秒の間にスタートラインを越えよう"
        elseif mine[2] == "沈" then
            head, color, sub = "沈没", RED, "ターンマークや消波装置に強く当たりました"
        else
            head, color, sub = tostring(mine[2]), RED, ""
        end
    elseif rows[1] then
        sub = string.format("1着 %d号艇 %s", rows[1][1], rows[1][3] or "")
    end
    if opts then
        head, sub, color = opts.head or head, opts.sub or sub, opts.color or color
    end
    self.cols[1].label.Text = opts and opts.placeHeader or "着"
    local y = compact and 10 or 18
    local headSize = compact and 46 or ((not opts and mine and tonumber(mine[2])) and 72 or 50)
    self.head.TextSize = headSize
    self.head.Text, self.head.TextColor3 = head, color
    self.head.Position, self.head.Size = UDim2.fromOffset(x0, y), UDim2.fromOffset(inner, headSize + 6)
    y += headSize + 8
    self.sub.Text = sub
    self.sub.Position, self.sub.Size = UDim2.fromOffset(x0, y), UDim2.fromOffset(inner, 20)
    y += compact and 24 or 30
    -- 結果の表
    local cx = x0
    for _, c in ipairs(self.cols) do
        c.label.Position, c.label.Size = UDim2.fromOffset(cx, y), UDim2.fromOffset(inner * c.width, 18)
        cx += inner * c.width
    end
    y += 20
    local rowH = compact and 28 or 34
    for i, row in ipairs(self.rows) do
        local r = rows[i]
        row.frame.Visible = r ~= nil
        if r then
            local cells = row.cells
            local me = r[1] == mySeat
            row.frame.Position, row.frame.Size = UDim2.fromOffset(x0 - 8, y), UDim2.fromOffset(inner + 16, rowH)
            row.frame.BackgroundTransparency = me and 0.84 or 1
            local place = tonumber(r[2])
            cells.place.Text = place and tostring(place) or tostring(r[2])
            cells.place.TextColor3 = place == 1 and GOLD or (place and WHITE or RED)
            cells.place.Position, cells.place.Size = UDim2.fromOffset(8, 0), UDim2.fromOffset(inner * 0.1, rowH)
            cells.chip.Text = tostring(r[1])
            cells.chip.BackgroundColor3, cells.chip.TextColor3 = LANE[r[1]][1], LANE[r[1]][2]
            local chipX = 8 + inner * 0.1 + inner * 0.05 - 11
            cells.chip.Position, cells.chip.Size = UDim2.fromOffset(chipX, rowH / 2 - 11), UDim2.fromOffset(22, 22)
            cells.name.Text = (r[3] or "") .. (r[4] == true and "　AI" or "")
            cells.name.FontFace = me and HEAVY or BOLD
            cells.name.Position, cells.name.Size = UDim2.fromOffset(8 + inner * 0.2, 0), UDim2.fromOffset(inner * 0.38, rowH)
            cells.time.Text = type(r[7]) == "number" and formatTime(r[7]) or "—"
            cells.time.Position, cells.time.Size = UDim2.fromOffset(8 + inner * 0.58, 0), UDim2.fromOffset(inner * 0.22, rowH)
            cells.st.Text = type(r[8]) == "number" and string.format("%.2f", r[8]) or "—"
            cells.st.TextColor3 = (type(r[8]) == "number" and r[8] < 0) and RED or WHITE
            cells.st.Position, cells.st.Size = UDim2.fromOffset(8 + inner * 0.8, 0), UDim2.fromOffset(inner * 0.2, rowH)
            y += rowH
        end
    end
    -- 記録(タイムアタックの順位、大会の得点など)
    y += 10
    self.extra.Text = extra or ""
    local lines = 0
    for _ in (extra or ""):gmatch("[^\n]+") do
        lines += 1
    end
    local extraH = lines > 0 and lines * 19 + 4 or 0
    self.extra.Position, self.extra.Size = UDim2.fromOffset(x0, y), UDim2.fromOffset(inner, extraH)
    y += extraH + (lines > 0 and 10 or 0)
    -- ボタン(1つ目が金。毎回作り直す)
    for _, b in ipairs(self.buttons:GetChildren()) do
        b:Destroy()
    end
    local n = #buttons
    self.buttons.Visible = n > 0
    if n > 0 then
        local primary = buttons[1]
        local pb = button(self.buttons, primary[1], primary[2], true, primary[4])
        pb.Position, pb.Size = UDim2.fromOffset(0, 0), UDim2.fromOffset(inner, 48)
        local bw = n > 1 and math.floor((inner - 8 * (n - 2)) / (n - 1)) or inner
        for k = 2, n do
            local b = buttons[k]
            local sb = button(self.buttons, b[1], b[2], false, b[4])
            sb.Position, sb.Size = UDim2.fromOffset((k - 2) * (bw + 8), 56), UDim2.fromOffset(bw, 42)
        end
        local bh = n > 1 and 98 or 48
        self.buttons.Position, self.buttons.Size = UDim2.fromOffset(x0, y), UDim2.fromOffset(inner, bh)
        y += bh + 16
    else
        y += 6
    end
    local h = math.min(y, size.Y - 24)
    self.panel.Size = UDim2.fromOffset(w, h)
    self.panel.CanvasSize = UDim2.fromOffset(0, y)
    self.shade.Visible = true
    self.key = key
end

function Result:hide()
    self.shade.Visible = false
    self.key = nil
end

return Result
