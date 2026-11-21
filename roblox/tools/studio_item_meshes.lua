-- Studio の編集画面だけで使う(コマンドバーか MCP の execute_luau で実行)。
-- Rojo の生同期は MeshPart の形(MeshId)を書き込めないので、同期で届いた着せ替えの部品
-- (ReplicatedStorage.VisualAssets.Items)には形が入らない。取り込んだ元のモデル
-- (ServerStorage.GachaImportSource。Studio で GLB を取り込んだ物)から、名前で突き合わせて形を写す。
-- rojo build で作った place(公開用)には Items.rbxmx の番号がそのまま入るので、これは要らない。
local source = game:GetService("ServerStorage"):FindFirstChild("GachaImportSource")
local items = game:GetService("ReplicatedStorage"):FindFirstChild("VisualAssets")
items = items and items:FindFirstChild("Items")
if not source or not items then
	return "GachaImportSource か VisualAssets.Items がありません"
end
local byName = {}
for _, p in source:GetDescendants() do
	if p:IsA("MeshPart") then
		byName[p.Name] = p
	end
end
local done, missing = 0, {}
for _, p in items:GetDescendants() do
	if p:IsA("MeshPart") then
		local from = byName[p.Name]
		if from then
			local size, frame = p.Size, p.CFrame
			p:ApplyMesh(from)
			p.Size, p.CFrame = size, frame
			done += 1
		else
			table.insert(missing, p.Name)
		end
	end
end
return done .. " 個に形を写しました。見つからない部品: " .. #missing
