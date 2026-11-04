-- 魚の見た目を JSON に書き出す(デザイン確認用のプレビューで使う): lune run tools/export_fish.luau <出力先.json>
-- ゲームと同じ FishBuilder でモデルを組み立て、パーツの形・大きさ・位置・色を書き出す。
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local H = require("../tests/harness")

local shared = H.root("src/shared")
local Config = H.require(shared.Config)
local FishBuilder = H.require(shared.Lib.FishBuilder)

local function c3(c)
	return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
end

local function exportModel(model)
	local parts = {}
	local effects = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local cf = d.CFrame
			local comps = { cf:GetComponents() }
			local shape = "Block"
			if d:IsA("Part") then
				shape = d.Shape.Name
			end
			local mesh = d:FindFirstChildOfClass("SpecialMesh")
			table.insert(parts, {
				name = d.Name,
				class = d.ClassName,
				shape = if mesh then "Ellipsoid" else shape,
				size = { d.Size.X, d.Size.Y, d.Size.Z },
				cf = comps,
				color = c3(d.Color),
				material = d.Material.Name,
				transparency = d.Transparency,
				reflectance = d.Reflectance,
			})
		elseif d:IsA("PointLight") then
			table.insert(effects, { kind = "light", color = c3(d.Color) })
		elseif d:IsA("Fire") then
			table.insert(effects, { kind = "fire", color = c3(d.Color), color2 = c3(d.SecondaryColor) })
		elseif d:IsA("Sparkles") then
			table.insert(effects, { kind = "sparkles", color = c3(d.SparkleColor) })
		elseif d:IsA("ParticleEmitter") then
			table.insert(effects, { kind = "particles", color = c3(d.Color.Keypoints[1].Value) })
		end
	end
	return { parts = parts, effects = effects }
end

local out = { fish = {}, mutations = {}, rarities = {}, elements = {} }
for _, def in Config.Fish do
	local entry = {
		id = def.id,
		ja = def.ja,
		en = def.en,
		kindJa = def.kindJa,
		kindEn = def.kindEn,
		rarity = def.rarity,
		element = def.element,
		shape = def.shape,
		time = def.time,
		weather = def.weather,
		kg = def.kg,
		jaDesc = def.jaDesc,
		enDesc = def.enDesc,
		c1 = def.c1,
		c2 = def.c2,
		c3 = def.c3,
		pattern = def.pattern,
		spot = def.spot,
		eyes = def.eyes,
		mouth = def.mouth,
		visualScale = FishBuilder.sizeOf(def),
		body = def.body,
		tails = def.tails,
		deco = def.deco,
		size = def.size,
		index = def.index,
		model = exportModel(FishBuilder.build(def, {})),
		variants = {},
	}
	for _, m in Config.Mutations do
		entry.variants[m.id] = exportModel(FishBuilder.build(def, { mutation = m.id }))
	end
	table.insert(out.fish, entry)
end
for _, r in Config.Rarities do
	table.insert(out.rarities, { id = r.id, color = r.color })
end
for _, m in Config.Mutations do
	table.insert(out.mutations, { id = m.id, color = m.color })
end
for _, e in Config.Battle.Elements do
	table.insert(out.elements, { id = e.id, color = e.color, icon = e.icon })
end

local path = process.args[1] or "fish_export.json"
fs.writeFile(path, serde.encode("json", out))
print(("wrote %d fish to %s"):format(#out.fish, path))
