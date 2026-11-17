local AssetService = game:GetService("AssetService")
local ids = require(script.Parent.VenueImages)
local pixels = require(script.Parent.VenuePixels)
local palette = {}

for i = 1, #pixels.palette, 8 do
    local r,g,b,a = string.match(pixels.palette:sub(i,i+7), "(..)(..)(..)(..)")
    palette[pixels.keys:byte((i-1)/8+1)] = tonumber(a..b..g..r,16)
end

local function content(name)
    local rows = pixels[name]
    local size = Vector2.new(#rows[1], #rows)
    local allowed, image = pcall(function()
        return AssetService:CreateEditableImage({Size=size})
    end)
    if not (allowed and image) then
        return nil
    end
    -- 体験の設定で画像の書き込みが許されていない時は、作れても書き込みで失敗する。その時は手描きの絵を使わない
    local written = pcall(function()
        local bytes = buffer.create(size.X*size.Y*4)
        for y,row in rows do
            for x = 1,#row do
                buffer.writeu32(bytes, ((y-1)*size.X+x-1)*4, palette[row:byte(x)])
            end
        end
        image:WritePixelsBuffer(Vector2.zero,size,bytes)
    end)
    if not written then
        image:Destroy()
        return nil
    end
    return Content.fromObject(image)
end

local Art = {}
local available = {}
-- Roblox に保存・公開した体験では、プログラムで作った画像(EditableImage)は設定で許可しないと
-- 表示されず、市松模様(画像なしの印)になる。なので手描きの絵は保存前の Studio(PlaceId 0)だけで使う
local drawable = game.PlaceId == 0

-- 部品に会場の絵を貼る。登録した画像があればそれを、なければ手描きの絵を使う。どちらもなければ nil
-- (呼ぶ側が形だけの絵を描く)。返した ImageLabel の切り抜きや並べ方は呼ぶ側が決める
function Art.put(parent,name)
    local id=ids[name]
    local label=Instance.new("ImageLabel")
    label.Name=name
    label.Size=UDim2.fromScale(1,1)
    label.BackgroundTransparency=1
    if type(id)=="string" and id:match("^rbxassetid://[1-9]%d*$") then
        label.Image=id
        label.Parent=parent
        return label
    end
    if drawable and available[name] == nil then
        available[name] = content(name) or false
    end
    if drawable and available[name] then
        label.ImageContent=available[name]
        label.Parent=parent
        return label
    end
    label:Destroy()
    return nil
end
return Art
