-- レース中の表示(HUD)。ブラウザ版(style.css の #hud)と同じ配置・色・大きさにそろえる。
-- 左上: 順位と周回・時間 / 上中央: スタート前の大時計と予想ST / 右上: 順位表 / 左上の下: ミニマップ
-- 右下: 速度計(スロットルレバーの横) / 下中央: 風と波 / 中央上寄り: 大きな知らせ(ST・周回・ゴール・失格)
local Hud = {}
Hud.__index = Hud

local NAVY = Color3.fromRGB(11, 29, 58)
local GOLD = Color3.fromRGB(255, 210, 60)
local WHITE = Color3.new(1, 1, 1)
local SUB = Color3.fromRGB(207, 220, 243)
local RED = Color3.fromRGB(255, 90, 77)
local GREEN = Color3.fromRGB(109, 255, 168)
local LANE = {
    { Color3.fromRGB(242, 242, 240), Color3.fromRGB(17, 17, 17) },
    { Color3.fromRGB(22, 22, 26), WHITE },
    { Color3.fromRGB(217, 30, 46), WHITE },
    { Color3.fromRGB(27, 80, 212), WHITE },
    { Color3.fromRGB(243, 210, 27), Color3.fromRGB(17, 17, 17) },
    { Color3.fromRGB(24, 162, 76), WHITE },
}
-- 数字は太字の斜体(ブラウザ版の font-weight 900 / italic)。日本語は自動で日本語の書体になる
local NUMBER_FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
local BOLD_FONT = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)
-- コースの範囲(ミニマップ用。メートル)
local MIN_X, MAX_X, MIN_Z, MAX_Z = -262, 252, -78, 58

local function corner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = parent
    return c
end

local function stroke(parent, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Color, s.Thickness, s.Transparency = color, thickness, transparency or 0
    s.Parent = parent
    return s
end

-- 半透明の紺の板
local function panel(parent, name, transparency)
    local f = Instance.new("Frame")
    f.Name = name
    f.BackgroundColor3 = Color3.fromRGB(8, 24, 48)
    f.BackgroundTransparency = transparency or 0.38
    f.BorderSizePixel = 0
    f.Parent = parent
    return f
end

-- 文字(影の代わりに暗い縁取りを薄く付けて、水面の上でも読めるようにする)
local function text(parent, name, size, font, color)
    local t = Instance.new("TextLabel")
    t.Name = name
    t.BackgroundTransparency = 1
    t.FontFace = font or BOLD_FONT
    t.TextSize = size
    t.TextColor3 = color or WHITE
    t.TextStrokeColor3 = Color3.fromRGB(0, 10, 30)
    t.TextStrokeTransparency = 0.55
    t.Text = ""
    t.Parent = parent
    return t
end

-- 艇番の色の四角(ブラウザ版の .chip)
local function chip(parent, lane, size)
    local c = text(parent, "Chip", math.floor(size * 0.62), NUMBER_FONT, LANE[lane][2])
    c.BackgroundTransparency = 0
    c.BackgroundColor3 = LANE[lane][1]
    c.Size = UDim2.fromOffset(size, size)
    c.Text = tostring(lane)
    c.TextStrokeTransparency = 1
    corner(c, 5)
    stroke(c, WHITE, 1, 0.15)
    return c
end

-- タイムを 1'40"2 の形にする
local function formatTime(t)
    local tenths = math.floor(math.max(0, t) * 10 + 0.5)
    return string.format("%d'%02d\"%d", tenths // 600, (tenths // 10) % 60, tenths % 10)
end
Hud.formatTime = formatTime

function Hud.new(gui)
    local self = setmetatable({ gui = gui, flashUntil = 0, chips = {} }, Hud)
    local root = Instance.new("Frame")
    root.Name = "RaceHud"
    root.BackgroundTransparency = 1
    root.Size = UDim2.fromScale(1, 1)
    root.Parent = gui
    self.root = root

    -- 左上: 順位(1着は金)と、周回・時間
    local pos = Instance.new("Frame")
    pos.Name = "Position"
    pos.Position = UDim2.fromOffset(16, 14)
    pos.Size = UDim2.fromOffset(92, 64)
    pos.BackgroundColor3 = WHITE
    pos.Parent = root
    corner(pos, 14)
    stroke(pos, WHITE, 2, 0.15)
    self.posGradient = Instance.new("UIGradient")
    self.posGradient.Rotation = 70
    self.posGradient.Parent = pos
    self.posN = text(pos, "Number", 46, NUMBER_FONT)
    self.posN.Size = UDim2.new(0, 56, 1, 0)
    self.posN.Position = UDim2.fromOffset(6, -2)
    self.posN.TextXAlignment = Enum.TextXAlignment.Right
    self.posUnit = text(pos, "Unit", 18)
    self.posUnit.Size = UDim2.fromOffset(24, 30)
    self.posUnit.Position = UDim2.fromOffset(62, 26)
    self.posUnit.Text = "着"
    self.pos = pos
    self.lap = text(root, "Lap", 20)
    self.lap.Position = UDim2.fromOffset(120, 16)
    self.lap.Size = UDim2.fromOffset(240, 26)
    self.lap.TextXAlignment = Enum.TextXAlignment.Left
    self.time = text(root, "Time", 26, NUMBER_FONT)
    self.time.Position = UDim2.fromOffset(120, 44)
    self.time.Size = UDim2.fromOffset(200, 30)
    self.time.TextXAlignment = Enum.TextXAlignment.Left

    -- 左上の下: 前後の艇との秒差(前は暖色、後ろは寒色。ブラウザ版の #gap)
    self.gaps = {}
    for k, color in ipairs({ Color3.fromRGB(255, 217, 168), Color3.fromRGB(191, 227, 255) }) do
        local row = panel(root, k == 1 and "GapAhead" or "GapBehind")
        row.Position = UDim2.fromOffset(16, 86 + (k - 1) * 25)
        row.Size = UDim2.fromOffset(150, 22)
        corner(row, 7)
        local label = text(row, "Label", 13, BOLD_FONT, color)
        label.Position = UDim2.fromOffset(7, 0)
        label.Size = UDim2.fromOffset(20, 22)
        label.Text = k == 1 and "前" or "後"
        local c = chip(row, 1, 18)
        c.Position = UDim2.fromOffset(28, 2)
        local value = text(row, "Value", 13, NUMBER_FONT, color)
        value.Position = UDim2.fromOffset(52, 0)
        value.Size = UDim2.fromOffset(94, 22)
        value.TextXAlignment = Enum.TextXAlignment.Left
        row.Visible = false
        self.gaps[k] = { frame = row, chip = c, value = value }
    end

    -- 左上の下: ミニマップ(コースの形、ターンマーク、各艇の点。自分は三角)
    local map = panel(root, "Minimap", 0.28)
    map.BackgroundColor3 = Color3.fromRGB(8, 40, 60)
    map.ClipsDescendants = true
    corner(map, 10)
    stroke(map, WHITE, 1.5, 0.45)
    self.map = map
    local line = Instance.new("Frame")
    line.Name = "StartLine"
    line.BackgroundColor3 = WHITE
    line.BackgroundTransparency = 0.3
    line.BorderSizePixel = 0
    line.Parent = map
    self.mapLine = line
    self.mapMarks = {}
    for i, m in ipairs({ { 150, 8 }, { -150, 0 } }) do
        local d = Instance.new("Frame")
        d.Name = "Mark" .. i
        d.AnchorPoint = Vector2.new(0.5, 0.5)
        d.Size = UDim2.fromOffset(8, 8)
        d.BackgroundColor3 = Color3.fromRGB(255, 75, 62)
        d.Parent = map
        corner(d, 4)
        stroke(d, WHITE, 1)
        self.mapMarks[i] = { frame = d, x = m[1], z = m[2] }
    end
    self.mapDots = {}
    for lane = 1, 6 do
        local d = Instance.new("Frame")
        d.Name = "Boat" .. lane
        d.AnchorPoint = Vector2.new(0.5, 0.5)
        d.Size = UDim2.fromOffset(9, 9)
        d.BackgroundColor3 = LANE[lane][1]
        d.Parent = map
        corner(d, 5)
        stroke(d, WHITE, 1)
        self.mapDots[lane] = d
    end
    local me = text(map, "Me", 14, BOLD_FONT, GOLD)
    me.AnchorPoint = Vector2.new(0.5, 0.5)
    me.Size = UDim2.fromOffset(18, 18)
    me.Text = "▲"
    me.TextStrokeTransparency = 0.2
    me.ZIndex = 3
    self.mapMe = me

    -- 右上: 順位表(自分の行は金)
    local order = Instance.new("Frame")
    order.Name = "Order"
    order.BackgroundTransparency = 1
    order.Parent = root
    self.order = order
    self.orderRows = {}
    for i = 1, 6 do
        local row = panel(order, "Row" .. i)
        corner(row, 8)
        local mark = text(row, "Mark", 14)
        mark.Size = UDim2.fromOffset(16, 26)
        mark.Position = UDim2.fromOffset(4, 0)
        local c = chip(row, 1, 20)
        c.Position = UDim2.fromOffset(22, 3)
        local name = text(row, "Name", 14)
        name.Position = UDim2.fromOffset(48, 0)
        name.Size = UDim2.new(1, -52, 1, 0)
        name.TextXAlignment = Enum.TextXAlignment.Left
        name.TextTruncate = Enum.TextTruncate.AtEnd
        self.orderRows[i] = { frame = row, mark = mark, chip = c, name = name }
    end

    -- 上中央: スタート前の大時計と予想ST(スタートアシスト)
    local start = panel(root, "StartBox")
    start.AnchorPoint = Vector2.new(0.5, 0)
    start.Position = UDim2.new(0.5, 0, 0, 10)
    start.Size = UDim2.fromOffset(392, 104)
    corner(start, 14)
    self.start = start
    local face = Instance.new("Frame")
    face.Name = "Clock"
    face.Position = UDim2.fromOffset(6, 6)
    face.Size = UDim2.fromOffset(92, 92)
    face.BackgroundColor3 = Color3.fromRGB(251, 251, 246)
    face.Parent = start
    corner(face, 46)
    stroke(face, Color3.fromRGB(17, 17, 17), 4)
    for i = 0, 11 do
        local tick = Instance.new("Frame")
        tick.Name = "Tick" .. i
        tick.AnchorPoint = Vector2.new(0.5, 0.5)
        tick.Size = UDim2.fromOffset(i == 0 and 4 or 2, i % 3 == 0 and 11 or 7)
        local a = i / 12 * math.pi * 2
        tick.Position = UDim2.new(0.5, math.sin(a) * 37, 0.5, -math.cos(a) * 37)
        tick.Rotation = i * 30
        tick.BackgroundColor3 = Color3.fromRGB(17, 17, 17)
        tick.BorderSizePixel = 0
        tick.ZIndex = 2
        tick.Parent = face
    end
    for _, i in ipairs({ 0, 3, 6, 9 }) do
        local n = text(face, "N" .. i, 12, NUMBER_FONT, Color3.fromRGB(17, 17, 17))
        n.TextStrokeTransparency = 1
        local a = i / 12 * math.pi * 2
        n.AnchorPoint = Vector2.new(0.5, 0.5)
        n.Size = UDim2.fromOffset(16, 14)
        n.Position = UDim2.new(0.5, math.sin(a) * 24, 0.5, -math.cos(a) * 24)
        n.Text = tostring(i)
        n.ZIndex = 2
    end
    -- 中心から外へ伸びる棒。文字盤と同じ大きさの透明な枠ごと回すので、必ず中心の軸で回る
    -- (Frame の Rotation は自分の真ん中で回るため、棒だけを回すと軸がずれる)
    local function spoke(name, angle, length, width, color, z)
        local holder = Instance.new("Frame")
        holder.Name = name
        holder.AnchorPoint = Vector2.new(0.5, 0.5)
        holder.Position = UDim2.fromScale(0.5, 0.5)
        holder.Size = UDim2.fromScale(1, 1)
        holder.BackgroundTransparency = 1
        holder.Rotation = angle
        holder.ZIndex = z
        holder.Parent = face
        local bar = Instance.new("Frame")
        bar.AnchorPoint = Vector2.new(0.5, 1)
        bar.Position = UDim2.fromScale(0.5, 0.5)
        bar.Size = UDim2.fromOffset(width, length)
        bar.BackgroundColor3 = color
        bar.BorderSizePixel = 0
        bar.ZIndex = z
        bar.Parent = holder
        return holder, bar
    end
    -- 0〜1秒の緑の扇形(真上から右へ30°。ブラウザ版と同じ)。細い棒を少しずつ回して並べ、扇の形にする
    for k = 0, 16 do
        spoke("GoodZone" .. k, k * 30 / 16, 35, 3, Color3.fromRGB(166, 222, 184), 1)
    end
    -- 12秒針(0秒で真上)
    local hand, needle = spoke("Hand", 0, 36, 5, Color3.fromRGB(244, 163, 0), 3)
    corner(needle, 3)
    local pin = Instance.new("Frame")
    pin.AnchorPoint = Vector2.new(0.5, 0.5)
    pin.Position = UDim2.fromScale(0.5, 0.5)
    pin.Size = UDim2.fromOffset(12, 12)
    pin.BackgroundColor3 = Color3.fromRGB(34, 34, 34)
    pin.ZIndex = 4
    pin.Parent = face
    corner(pin, 6)
    self.hand = hand
    self.cd = text(start, "Countdown", 22, NUMBER_FONT)
    self.cd.Position = UDim2.fromOffset(110, 6)
    self.cd.Size = UDim2.fromOffset(270, 26)
    self.cd.TextXAlignment = Enum.TextXAlignment.Left
    self.dist = text(start, "Distance", 13, BOLD_FONT, SUB)
    self.dist.Position = UDim2.fromOffset(110, 32)
    self.dist.Size = UDim2.fromOffset(270, 18)
    self.dist.TextXAlignment = Enum.TextXAlignment.Left
    local bar = Instance.new("Frame")
    bar.Name = "AssistBar"
    bar.Position = UDim2.fromOffset(110, 56)
    bar.Size = UDim2.fromOffset(262, 14)
    bar.BackgroundColor3 = WHITE
    bar.ClipsDescendants = false
    bar.Parent = start
    corner(bar, 7)
    stroke(bar, WHITE, 1, 0.2)
    -- 色の帯: フライング(赤) / ST 0〜0.25(緑) / 0.25〜0.5(黄) / 遅い(灰)。ブラウザ版と同じ割合
    local g = Instance.new("UIGradient")
    local red, green, yellow, gray = Color3.fromRGB(217, 48, 37), Color3.fromRGB(47, 191, 113), Color3.fromRGB(224, 178, 26), Color3.fromRGB(107, 114, 128)
    g.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, red), ColorSequenceKeypoint.new(0.332, red),
        ColorSequenceKeypoint.new(0.334, green), ColorSequenceKeypoint.new(0.499, green),
        ColorSequenceKeypoint.new(0.501, yellow), ColorSequenceKeypoint.new(0.659, yellow),
        ColorSequenceKeypoint.new(0.661, gray), ColorSequenceKeypoint.new(1, gray),
    })
    g.Parent = bar
    local marker = Instance.new("Frame")
    marker.Name = "Marker"
    marker.AnchorPoint = Vector2.new(0.5, 0.5)
    marker.Position = UDim2.fromScale(0.5, 0.5)
    marker.Size = UDim2.fromOffset(4, 24)
    marker.BackgroundColor3 = WHITE
    marker.ZIndex = 2
    marker.Parent = bar
    corner(marker, 2)
    stroke(marker, Color3.new(0, 0, 0), 1, 0.4)
    self.marker = marker
    self.assist = text(start, "Assist", 13)
    self.assist.Position = UDim2.fromOffset(110, 76)
    self.assist.Size = UDim2.fromOffset(270, 20)
    self.assist.TextXAlignment = Enum.TextXAlignment.Left

    -- 右下: 速度計(大きな斜体の数字と、色の付いた棒)
    local speed = Instance.new("Frame")
    speed.Name = "Speedo"
    speed.BackgroundTransparency = 1
    speed.AnchorPoint = Vector2.new(1, 1)
    speed.Size = UDim2.fromOffset(200, 74)
    speed.Parent = root
    self.speedo = speed
    self.spd = text(speed, "Speed", 56, NUMBER_FONT)
    self.spd.Size = UDim2.new(1, -52, 0, 56)
    self.spd.TextXAlignment = Enum.TextXAlignment.Right
    local unit = text(speed, "Unit", 16)
    unit.Size = UDim2.fromOffset(48, 20)
    unit.Position = UDim2.new(1, -48, 0, 34)
    unit.Text = "km/h"
    local track = Instance.new("Frame")
    track.Name = "Track"
    track.Position = UDim2.new(0, 10, 0, 62)
    track.Size = UDim2.new(1, -10, 0, 8)
    track.BackgroundColor3 = WHITE
    track.BackgroundTransparency = 0.78
    track.ClipsDescendants = true
    track.Parent = speed
    corner(track, 4)
    local fill = Instance.new("Frame")
    fill.Name = "Fill"
    fill.Size = UDim2.fromScale(0, 1)
    fill.BackgroundColor3 = WHITE
    fill.Parent = track
    corner(fill, 4)
    local fg = Instance.new("UIGradient")
    fg.Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(77, 210, 255)),
        ColorSequenceKeypoint.new(0.7, Color3.fromRGB(255, 225, 77)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 90, 60)),
    })
    fg.Parent = fill
    self.spdFill = fill

    -- 下中央: 風と波
    local wx = panel(root, "Weather", 0.45)
    wx.AnchorPoint = Vector2.new(0.5, 1)
    wx.Position = UDim2.new(0.5, 0, 1, -14)
    wx.Size = UDim2.fromOffset(220, 26)
    corner(wx, 8)
    self.wxArrow = text(wx, "Arrow", 13, BOLD_FONT, Color3.fromRGB(127, 216, 255))
    self.wxArrow.Size = UDim2.fromOffset(22, 26)
    self.wxArrow.Position = UDim2.fromOffset(8, 0)
    self.wxArrow.Text = "▲"
    self.wxText = text(wx, "Text", 13)
    self.wxText.Position = UDim2.fromOffset(32, 0)
    self.wxText.Size = UDim2.new(1, -40, 1, 0)
    self.wxText.TextXAlignment = Enum.TextXAlignment.Left
    self.wx = wx

    -- 中央上寄り: 大きな知らせ
    local msg = text(root, "Message", 54, NUMBER_FONT)
    msg.AnchorPoint = Vector2.new(0.5, 0.5)
    msg.Position = UDim2.fromScale(0.5, 0.27)
    msg.Size = UDim2.fromOffset(600, 64)
    msg.TextStrokeTransparency = 0.25
    msg.TextStrokeColor3 = Color3.fromRGB(0, 20, 60)
    self.msg = msg
    local sub = text(root, "MessageSub", 22)
    sub.AnchorPoint = Vector2.new(0.5, 0)
    sub.Position = UDim2.new(0.5, 0, 0.27, 34)
    sub.Size = UDim2.fromOffset(600, 30)
    self.msgSub = sub
    msg.Visible, sub.Visible = false, false
    return self
end

-- 大きな知らせを数秒だけ出す(ST、周回、ゴール、フライング、沈没)
function Hud:flash(big, small, color, seconds)
    self.msg.Text, self.msgSub.Text = big or "", small or ""
    self.msg.TextColor3 = color or WHITE
    self.flashUntil = os.clock() + (seconds or 2.2)
end

-- 画面の大きさに合わせて配置を変える(スマホの横持ち・縦持ちでは小さく)
function Hud:layout()
    local size = self.gui.AbsoluteSize
    local compact = size.X < 760 or size.Y < 460
    local portrait = size.X < size.Y
    self.compact = compact
    self.map.Position = UDim2.fromOffset(16, 142)
    self.map.Size = compact and UDim2.fromOffset(170, 45) or UDim2.fromOffset(230, 61)
    self.order.Position = UDim2.new(1, compact and -16 or -166, 0, compact and 52 or 62)
    self.order.AnchorPoint = compact and Vector2.new(1, 0) or Vector2.new(0, 0)
    self.order.Size = compact and UDim2.fromOffset(6 * 27, 26) or UDim2.fromOffset(150, 6 * 30)
    for i, row in ipairs(self.orderRows) do
        if compact then
            row.frame.Position = UDim2.fromOffset((i - 1) * 27, 0)
            row.frame.Size = UDim2.fromOffset(24, 26)
            row.frame.BackgroundTransparency = 1
            row.chip.Position = UDim2.fromOffset(2, 3)
        else
            row.frame.Position = UDim2.fromOffset(0, (i - 1) * 30)
            row.frame.Size = UDim2.fromOffset(150, 26)
            row.frame.BackgroundTransparency = 0.38
            row.chip.Position = UDim2.fromOffset(22, 3)
        end
        row.mark.Visible, row.name.Visible = not compact, not compact
    end
    -- 速度計はスロットルレバー(右下、幅74)の左。縦持ちはレバーの上
    self.speedo.Position = portrait and UDim2.new(1, -14, 1, -200) or UDim2.new(1, -106, 1, -14)
    self.speedo.Size = compact and UDim2.fromOffset(150, 60) or UDim2.fromOffset(200, 74)
    self.spd.TextSize = compact and 42 or 56
    -- スタートの枠は、縦持ちでは順位の下へ
    self.start.Position = portrait and UDim2.new(0.5, 0, 0, 140) or UDim2.new(0.5, 0, 0, 10)
    self.wx.Position = UDim2.new(0.5, 0, 1, portrait and -100 or -14)
end

-- 毎フレームの更新。info の中身は Controls.client.lua が作る
function Hud:update(info)
    self.root.Visible = info.visible
    if not info.visible then
        return
    end
    -- 順位(1着は金、失格は赤)
    local rank = info.rank
    if info.out then
        self.posN.Text, self.posUnit.Text = info.out, ""
        self.posGradient.Color = ColorSequence.new(Color3.fromRGB(150, 30, 30), Color3.fromRGB(90, 10, 10))
    else
        self.posN.Text, self.posUnit.Text = tostring(rank or "-"), "着"
        if rank == 1 then
            self.posGradient.Color = ColorSequence.new(Color3.fromRGB(226, 164, 0), Color3.fromRGB(165, 95, 0))
        else
            self.posGradient.Color = ColorSequence.new(Color3.fromRGB(23, 58, 122), NAVY)
        end
    end
    self.pos.Visible = info.rank ~= nil or info.out ~= nil
    self.lap.Text = info.lapText or ""
    self.time.Text = info.time and formatTime(info.time) or ""
    -- スタート前の枠
    self.start.Visible = info.pre == true
    if info.pre then
        local t = info.clock or 0
        self.hand.Rotation = (t / 12) * 360
        self.cd.Text = t < 0 and string.format("スタートまで %.1f", -t) or string.format("+%.2f", t)
        self.cd.TextColor3 = t > -3 and GOLD or WHITE
        self.dist.Text = info.dist and string.format("スタートラインまで %d m", math.max(0, math.floor(info.dist + 0.5))) or ""
        local st = info.st
        self.marker.Visible = st ~= nil
        if st then
            self.marker.Position = UDim2.fromScale(math.clamp((st + 0.5) / 1.5, 0, 1), 0.5)
            if st < 0 then
                self.assist.Text, self.assist.TextColor3 = string.format("全開だと %.2f秒 早い(フライング)", -st), Color3.fromRGB(255, 138, 122)
            elseif st < 0.25 then
                self.assist.Text, self.assist.TextColor3 = string.format("今だ！ 全開で ST %.2f", st), GREEN
            else
                self.assist.Text, self.assist.TextColor3 = string.format("全開で ST %.2f", st), WHITE
            end
        else
            self.assist.Text = info.hint or ""
            self.assist.TextColor3 = SUB
        end
    end
    -- 順位表
    self.order.Visible = info.order ~= nil
    if info.order then
        for i, row in ipairs(self.orderRows) do
            local o = info.order[i]
            row.frame.Visible = o ~= nil
            if o then
                row.chip.Text = tostring(o.lane)
                row.chip.BackgroundColor3, row.chip.TextColor3 = LANE[o.lane][1], LANE[o.lane][2]
                row.mark.Text = o.mark
                row.name.Text = o.name
                local me = o.me
                if not self.compact then
                    row.frame.BackgroundColor3 = me and GOLD or Color3.fromRGB(8, 24, 48)
                    row.frame.BackgroundTransparency = me and 0.08 or 0.38
                end
                row.name.TextColor3 = me and Color3.fromRGB(17, 17, 17) or WHITE
                row.mark.TextColor3 = me and Color3.fromRGB(17, 17, 17) or (o.out and RED or WHITE)
                row.name.TextStrokeTransparency = me and 1 or 0.55
                row.mark.TextStrokeTransparency = me and 1 or 0.55
                local outline = row.chip:FindFirstChildOfClass("UIStroke")
                outline.Color = (self.compact and me) and GOLD or WHITE
                outline.Thickness = (self.compact and me) and 2 or 1
            end
        end
    end
    -- 前後との秒差
    for k, g in ipairs(self.gaps) do
        local item = info.gaps and info.gaps[k]
        g.frame.Visible = item ~= nil
        if item then
            g.chip.Text = tostring(item.lane)
            g.chip.BackgroundColor3, g.chip.TextColor3 = LANE[item.lane][1], LANE[item.lane][2]
            g.value.Text = item.text
        end
    end
    -- ミニマップ
    self.map.Visible = info.boats ~= nil and not (self.compact and info.pre)
    if info.boats then
        local w, h = self.map.AbsoluteSize.X, self.map.AbsoluteSize.Y
        local function at(x, z)
            return UDim2.fromOffset((x - MIN_X) / (MAX_X - MIN_X) * w, (z - MIN_Z) / (MAX_Z - MIN_Z) * h)
        end
        local lineTop = (4 - MIN_Z) / (MAX_Z - MIN_Z) * h
        self.mapLine.Position = UDim2.fromOffset((0 - MIN_X) / (MAX_X - MIN_X) * w, lineTop)
        self.mapLine.Size = UDim2.fromOffset(1, h - lineTop)
        for _, m in ipairs(self.mapMarks) do
            m.frame.Position = at(m.x, m.z)
        end
        for lane, dot in ipairs(self.mapDots) do
            local b = info.boats[lane]
            dot.Visible = b ~= nil and not b.hidden and not b.me
            if b then
                dot.Position = at(b.x, b.z)
            end
            if b and b.me and not b.hidden then
                self.mapMe.Position = at(b.x, b.z)
                -- ▲ は上向きなので、右向き(向き 0)に合わせて90°足す
                self.mapMe.Rotation = math.deg(b.h) + 90
            end
        end
        self.mapMe.Visible = info.myLane ~= nil
    end
    -- 速度計
    self.speedo.Visible = info.speed ~= nil
    if info.speed then
        self.spd.Text = tostring(math.floor(info.speed + 0.5))
        self.spdFill.Size = UDim2.fromScale(math.clamp(info.speed / 82, 0, 1), 1)
    end
    -- 風と波
    self.wx.Visible = info.wind ~= nil
    if info.wind then
        self.wxText.Text = info.wind
        self.wxArrow.Rotation = (info.windRotation or 0) + 90
        self.wx.Size = UDim2.fromOffset(math.max(160, 48 + utf8.len(info.wind) * 13), 26)
    end
    -- 大きな知らせ
    local showing = os.clock() < self.flashUntil
    self.msg.Visible, self.msgSub.Visible = showing, showing and self.msgSub.Text ~= ""
end

return Hud
