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
function Art.put(parent,name)
    if available[name] == nil then
        available[name] = content(name) or false
    end
    local id=ids[name]
    -- Keep the local drawing (or the caller's silhouettes) while an owner image loads.
    local base
    if available[name] then
        base=Instance.new("ImageLabel")
        base.Name=name
        base.Size=UDim2.fromScale(1,1)
        base.BackgroundTransparency=1
        base.ImageContent=available[name]
        base.Parent=parent
    end
    if type(id)=="string" and id:match("^rbxassetid://[1-9]%d*$") then
        local overlay=Instance.new("ImageLabel")
        overlay.Name=name.."Owner"
        overlay.Size=UDim2.fromScale(1,1)
        overlay.BackgroundTransparency=1
        overlay.ZIndex=3
        overlay.Image=id
        overlay.Parent=parent
        if base then
            for _,key in {"ScaleType","TileSize","ImageRectSize","ImageRectOffset"} do
                base:GetPropertyChangedSignal(key):Connect(function() overlay[key]=base[key] end)
            end
        elseif name=="Windows" then
            overlay.ScaleType=Enum.ScaleType.Tile
            overlay.TileSize=UDim2.fromOffset(64,48)
        elseif name=="Crowd" then
            overlay.ImageRectSize=Vector2.new(520,22)
        end
    end
    return base
end
return Art
