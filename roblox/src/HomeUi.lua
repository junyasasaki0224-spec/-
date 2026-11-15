-- ホームとレース選択の部品(ブラウザ版の style.css の .tile / #btn-race / .mcard / #home-prof / .pill と同じ見た目)
local TweenService = game:GetService("TweenService")
local Ui = {}

Ui.NAVY = Color3.fromRGB(11, 29, 58)
Ui.GOLD = Color3.fromRGB(255, 210, 60)
Ui.WHITE = Color3.new(1, 1, 1)
Ui.SUB = Color3.fromRGB(185, 201, 228)
Ui.PALE = Color3.fromRGB(219, 230, 250)
Ui.DARK = Color3.fromRGB(26, 18, 0)
Ui.HEAVY = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy, Enum.FontStyle.Normal)
Ui.HEAVY_ITALIC = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
Ui.BOLD = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold, Enum.FontStyle.Normal)

function Ui.corner(parent, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius)
    c.Parent = parent
    return c
end

function Ui.stroke(parent, color, thickness, transparency)
    local s = Instance.new("UIStroke")
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Color, s.Thickness, s.Transparency = color, thickness or 1, transparency or 0
    s.Parent = parent
    return s
end

function Ui.gradient(parent, top, bottom, rotation)
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new(top, bottom)
    g.Rotation = rotation or 90
    g.Parent = parent
    return g
end

-- 文字(背景なし)
function Ui.text(parent, name, value, size, font, color)
    local t = Instance.new("TextLabel")
    t.Name = name
    t.BackgroundTransparency = 1
    t.Text = value or ""
    t.TextSize = size
    t.FontFace = font or Ui.BOLD
    t.TextColor3 = color or Ui.WHITE
    t.TextXAlignment = Enum.TextXAlignment.Left
    t.TextTruncate = Enum.TextTruncate.AtEnd
    t.Parent = parent
    return t
end

local function place(item, x, y, w, h)
    item.Position = UDim2.fromOffset(x, y)
    item.Size = UDim2.fromOffset(w, h)
    return item
end
Ui.place = place

-- 押せる板(押した時に少し縮む)
local function pressable(button)
    local scale = Instance.new("UIScale")
    scale.Parent = button
    button.MouseButton1Down:Connect(function()
        scale.Scale = 0.97
    end)
    button.MouseButton1Up:Connect(function()
        scale.Scale = 1
    end)
    button.MouseLeave:Connect(function()
        scale.Scale = 1
    end)
    return button
end

local function baseButton(parent, name)
    local b = Instance.new("TextButton")
    b.Name = name
    b.Text = ""
    b.AutoButtonColor = false
    b.BorderSizePixel = 0
    b.Parent = parent
    return pressable(b)
end

-- 線画のアイコン(64×40 の枠の中を、太さ3の線の四角と丸で描く)。kind: gacha / garage / mission / ranking / online / howto
local ICONS = {
    gacha = { { "box", 14, 4, 36, 32, 4 }, { "ring", 25, 9, 14, 14 }, { "bar", 26, 28, 12, 3 } },
    garage = { { "box", 8, 14, 48, 22, 2 }, { "bar", 18, 22, 28, 3 }, { "bar", 18, 28, 28, 3 }, { "roof", 8, 6, 48, 10 } },
    mission = { { "box", 12, 5, 40, 30, 3 }, { "bar", 30, 13, 16, 3 }, { "bar", 30, 25, 16, 3 }, { "ring", 18, 11, 7, 7 }, { "ring", 18, 23, 7, 7 } },
    ranking = { { "box", 22, 5, 20, 16, 8 }, { "bar", 31, 21, 3, 9 }, { "bar", 24, 31, 17, 3 }, { "ring", 13, 8, 9, 9 }, { "ring", 42, 8, 9, 9 } },
    online = { { "ring", 17, 5, 30, 30 }, { "bar", 17, 19, 30, 3 }, { "box", 26, 5, 12, 30, 6 } },
    howto = { { "ring", 17, 5, 30, 30 }, { "bar", 31, 16, 3, 8 }, { "dot", 31, 27, 3, 3 } },
}
function Ui.icon(parent, kind, x, y, scale)
    local holder = Instance.new("Frame")
    holder.Name = "Icon"
    holder.BackgroundTransparency = 1
    place(holder, x, y, 64 * scale, 40 * scale)
    holder.Parent = parent
    for _, p in ipairs(ICONS[kind] or {}) do
        local f = Instance.new("Frame")
        f.BorderSizePixel = 0
        place(f, p[2] * scale, p[3] * scale, p[4] * scale, p[5] * scale)
        f.Parent = holder
        if p[1] == "bar" or p[1] == "dot" then
            f.BackgroundColor3 = Ui.GOLD
            Ui.corner(f, 2)
        else
            f.BackgroundTransparency = 1
            Ui.stroke(f, Ui.GOLD, 2.4 * math.max(scale, 0.8))
            Ui.corner(f, p[1] == "ring" and 999 or (p[6] or 3) * scale)
        end
    end
    return holder
end

-- 赤い丸の数(メール・ミッション)
function Ui.badge(parent, count, x, y)
    if not count or count <= 0 then
        return
    end
    local b = Ui.text(parent, "Badge", tostring(count), 12, Ui.HEAVY)
    b.BackgroundTransparency = 0
    b.BackgroundColor3 = Color3.fromRGB(230, 50, 50)
    b.TextXAlignment = Enum.TextXAlignment.Center
    place(b, x, y, 20, 20)
    b.ZIndex = 5
    Ui.corner(b, 10)
    Ui.stroke(b, Ui.WHITE, 1.5)
    return b
end

-- ホームのタイル(金の細枠、左にアイコン、題と説明)。縦持ちはアイコンを上、題を下(説明なし)
function Ui.tile(parent, name, kind, title, sub, x, y, w, h, vertical, onPress)
    local t = baseButton(parent, name)
    place(t, x, y, w, h)
    t.BackgroundColor3 = Ui.WHITE
    Ui.gradient(t, Color3.fromRGB(20, 52, 104), Color3.fromRGB(8, 24, 48), 45)
    Ui.corner(t, 14)
    Ui.stroke(t, Ui.GOLD, 1.5, 0.25)
    if vertical then
        Ui.icon(t, kind, w / 2 - 22, 8, 0.7)
        local b = Ui.text(t, "Title", title, 14, Ui.HEAVY)
        b.TextXAlignment = Enum.TextXAlignment.Center
        place(b, 2, h - 26, w - 4, 20)
    else
        local scale = h < 56 and 0.66 or 0.82
        Ui.icon(t, kind, 10, h / 2 - 20 * scale, scale)
        local left = 18 + 64 * scale
        local b = Ui.text(t, "Title", title, h < 56 and 15 or 17, Ui.HEAVY)
        place(b, left, h / 2 - 20, w - left - 8, 22)
        local s = Ui.text(t, "Sub", sub, h < 56 and 10 or 11, Ui.BOLD, Ui.SUB)
        place(s, left, h / 2 + 2, w - left - 8, 16)
    end
    t.Activated:Connect(onPress)
    return t
end

-- 金の大きな「レース」ボタン(光が流れる)
function Ui.raceButton(parent, x, y, w, h, title, sub, onPress)
    local shadow = Instance.new("Frame")
    shadow.Name = "RaceShadow"
    shadow.BackgroundColor3 = Color3.fromRGB(154, 100, 0)
    shadow.BorderSizePixel = 0
    place(shadow, x, y + 6, w, h)
    Ui.corner(shadow, 20)
    shadow.Parent = parent
    local b = baseButton(parent, "Race")
    place(b, x, y, w, h)
    b.BackgroundColor3 = Ui.WHITE
    b.ClipsDescendants = true
    Ui.gradient(b, Color3.fromRGB(255, 230, 128), Color3.fromRGB(245, 164, 0), 90)
    Ui.corner(b, 20)
    Ui.stroke(b, Color3.fromRGB(255, 244, 200), 1.5, 0.3)
    local big = Ui.text(b, "Title", title, h < 70 and 27 or 34, Ui.HEAVY_ITALIC, Ui.DARK)
    big.TextXAlignment = Enum.TextXAlignment.Center
    place(big, 0, h * 0.14, w, h * 0.5)
    local small = Ui.text(b, "Sub", sub, 12, Ui.HEAVY, Ui.DARK)
    small.TextXAlignment = Enum.TextXAlignment.Center
    place(small, 0, h * 0.64, w, 16)
    -- 斜めに流れる光
    local shine = Instance.new("Frame")
    shine.Name = "Shine"
    shine.BackgroundColor3 = Ui.WHITE
    shine.BorderSizePixel = 0
    shine.Rotation = 18
    place(shine, -w * 0.6, -20, w * 0.3, h + 40)
    local sg = Instance.new("UIGradient")
    sg.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.45), NumberSequenceKeypoint.new(1, 1),
    })
    sg.Parent = shine
    shine.Parent = b
    local tween = TweenService:Create(shine, TweenInfo.new(3.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, false, 0.4),
        { Position = UDim2.fromOffset(w * 1.3, -20) })
    tween:Play()
    b.Destroying:Connect(function()
        tween:Cancel()
    end)
    b.Activated:Connect(onPress)
    return b
end

-- 丸い小さな札(コイン・シーズンパス・今のモード)
function Ui.pill(parent, name, value, x, y, w, h, onPress, coin)
    local p = onPress and baseButton(parent, name) or Instance.new("Frame")
    p.Name = name
    place(p, x, y, w, h)
    p.BackgroundColor3 = Color3.fromRGB(8, 24, 48)
    p.BackgroundTransparency = 0.18
    p.Parent = parent
    Ui.corner(p, h / 2)
    Ui.stroke(p, Ui.WHITE, 1, 0.7)
    local left = 12
    if coin then
        local c = Instance.new("Frame")
        c.Name = "Coin"
        c.BackgroundColor3 = Ui.GOLD
        place(c, 8, h / 2 - 9, 18, 18)
        Ui.corner(c, 9)
        Ui.stroke(c, Color3.fromRGB(196, 128, 0), 2)
        c.Parent = p
        left = 32
    end
    local t = Ui.text(p, "Text", value, 14, Ui.HEAVY)
    place(t, left, 0, w - left - 8, h)
    if onPress then
        p.Activated:Connect(onPress)
    end
    return p, t
end

-- 白い細枠の四角いボタン(メール・設定・戻る)
function Ui.headButton(parent, name, value, x, y, w, onPress, count)
    local b = baseButton(parent, name)
    place(b, x, y, w, 44)
    b.BackgroundColor3 = Color3.fromRGB(8, 24, 48)
    b.BackgroundTransparency = 0.2
    Ui.corner(b, 10)
    Ui.stroke(b, Ui.WHITE, 1, 0.55)
    local t = Ui.text(b, "Text", value, 14, Ui.HEAVY)
    t.TextXAlignment = Enum.TextXAlignment.Center
    place(t, 0, 0, w, 44)
    Ui.badge(b, count, w - 12, -8)
    b.Activated:Connect(onPress)
    return b
end

-- 左上の選手の札(級別の金の札、名前、RATE、次の級までの棒)
function Ui.profile(parent, x, y, w, gradeName, name, stats, progress)
    local p = Instance.new("Frame")
    p.Name = "Profile"
    place(p, x, y, w, 62)
    p.BackgroundColor3 = Color3.fromRGB(8, 24, 48)
    p.BackgroundTransparency = 0.18
    p.Parent = parent
    Ui.corner(p, 12)
    Ui.stroke(p, Ui.WHITE, 1, 0.72)
    -- 級別の札(金の六角形に近い形: 角を大きく丸めた四角を45°傾けずに重ねる)
    local badge = Instance.new("Frame")
    badge.Name = "Grade"
    badge.BackgroundColor3 = Ui.WHITE
    place(badge, 8, 8, 46, 46)
    Ui.gradient(badge, Color3.fromRGB(255, 224, 102), Color3.fromRGB(245, 164, 0), 110)
    Ui.corner(badge, 12)
    badge.Parent = p
    local g = Ui.text(badge, "Text", gradeName, 20, Ui.HEAVY_ITALIC, Ui.DARK)
    g.TextXAlignment = Enum.TextXAlignment.Center
    place(g, 0, 0, 46, 46)
    local n = Ui.text(p, "Name", name, 16, Ui.HEAVY)
    place(n, 64, 7, w - 74, 20)
    local s = Ui.text(p, "Stats", stats, 11, Ui.BOLD, Color3.fromRGB(207, 220, 243))
    place(s, 64, 28, w - 74, 14)
    local track = Instance.new("Frame")
    track.Name = "Progress"
    track.BackgroundColor3 = Ui.WHITE
    track.BackgroundTransparency = 0.82
    track.BorderSizePixel = 0
    place(track, 64, 47, w - 78, 4)
    Ui.corner(track, 2)
    track.Parent = p
    local fill = Instance.new("Frame")
    fill.BackgroundColor3 = Ui.WHITE
    fill.BorderSizePixel = 0
    fill.Size = UDim2.fromScale(math.clamp(progress, 0, 1), 1)
    Ui.gradient(fill, Color3.fromRGB(255, 224, 102), Color3.fromRGB(245, 164, 0), 0)
    Ui.corner(fill, 2)
    fill.Parent = track
    return p
end

-- 題字「みなとグランプリ」(金の斜体)
function Ui.logo(parent, x, y, w, size)
    local small = Ui.text(parent, "LogoSmall", "MINATO BOAT STADIUM", 11, Ui.HEAVY, Color3.fromRGB(207, 220, 243))
    small.TextXAlignment = Enum.TextXAlignment.Center
    place(small, x, y, w, 14)
    local big = Ui.text(parent, "Logo", "みなとグランプリ", size, Ui.HEAVY_ITALIC, Ui.GOLD)
    big.TextXAlignment = Enum.TextXAlignment.Center
    big.TextStrokeColor3 = Color3.fromRGB(60, 30, 0)
    big.TextStrokeTransparency = 0.4
    place(big, x, y + 12, w, size + 8)
    return big
end

-- レース選択のカード(上に名前の帯、中に場面の絵、下に説明と札)。押すとそのモードへ
function Ui.modeCard(parent, name, title, image, description, tag, x, y, w, h, selected, onPress)
    local c = baseButton(parent, name)
    place(c, x, y, w, h)
    c.BackgroundColor3 = Ui.WHITE
    c.ClipsDescendants = true
    Ui.gradient(c, Color3.fromRGB(20, 48, 95), Color3.fromRGB(8, 26, 54), 90)
    Ui.corner(c, 18)
    Ui.stroke(c, Ui.GOLD, selected and 3 or 2, selected and 0 or 0.2)
    local band = Instance.new("Frame")
    band.Name = "Band"
    band.BackgroundColor3 = Ui.WHITE
    band.BorderSizePixel = 0
    place(band, 0, 0, w, 42)
    Ui.gradient(band, Color3.fromRGB(29, 68, 134), Color3.fromRGB(18, 48, 95), 90)
    band.Parent = c
    local line = Instance.new("Frame")
    line.BackgroundColor3 = Ui.GOLD
    line.BackgroundTransparency = 0.2
    line.BorderSizePixel = 0
    place(line, 0, 42, w, 2)
    line.Parent = c
    local t = Ui.text(band, "Title", title, w < 200 and 16 or 20, Ui.HEAVY)
    t.TextXAlignment = Enum.TextXAlignment.Center
    place(t, 4, 0, w - 8, 42)
    local artH = math.max(60, h - 44 - 78)
    if image and image ~= "" then
        local art = Instance.new("ImageLabel")
        art.Name = "Art"
        art.Image = image
        art.ScaleType = Enum.ScaleType.Crop
        art.BorderSizePixel = 0
        place(art, 0, 44, w, artH)
        art.Parent = c
    end
    local d = Ui.text(c, "Description", description, w < 200 and 11 or 13, Ui.BOLD, Ui.PALE)
    d.TextXAlignment = Enum.TextXAlignment.Center
    d.TextWrapped = true
    place(d, 8, 44 + artH + 6, w - 16, 34)
    local pill = Ui.text(c, "Tag", tag, 11, Ui.HEAVY, Color3.fromRGB(255, 230, 154))
    pill.TextXAlignment = Enum.TextXAlignment.Center
    pill.BackgroundTransparency = 0.88
    pill.BackgroundColor3 = Ui.GOLD
    local pw = math.min(w - 24, 28 + (utf8.len(tag) or 4) * 12)
    place(pill, w / 2 - pw / 2, h - 32, pw, 22)
    Ui.corner(pill, 11)
    Ui.stroke(pill, Ui.GOLD, 1, 0.4)
    c.Activated:Connect(onPress)
    return c
end

return Ui
