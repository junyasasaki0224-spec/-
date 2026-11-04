-- 公開前の確認: 設定が残っているものを一覧にする(コードの中で確かめられるもの + Studio で手でやること)。
--   lune run tools/launch_check.luau
-- ✗ が 0 なら、コード側の準備は終わり。□ は Studio / Creator Dashboard で人がやること。
local fs = require("@lune/fs")
local process = require("@lune/process")
local H = require("../tests/harness")

local shared = H.root("src/shared")
local Config = H.require(shared.Config)
local Locale = H.require(shared.Locale)
local Products = H.require(shared.Config.Products)
local Cries = H.require(shared.Config.Cries)

local missing = 0
local function ok(text: string)
	print("  ✓ " .. text)
end
local function bad(text: string)
	missing += 1
	print("  ✗ " .. text)
end
local function todo(text: string)
	print("  □ " .. text)
end

print("■ ゲームのデータ")
local problems = Config.Validate()
if #problems == 0 then
	ok("Config.Validate(): 問題なし")
else
	bad(("Config.Validate(): %d 件 — %s"):format(#problems, problems[1]))
end
local miss = Locale.missingKeys()
if #miss == 0 then
	ok("日本語・英語の文言がそろっている")
else
	bad(("英語にない文言 %d 件(例: %s)"):format(#miss, miss[1]))
end

print("■ 課金(Creator Dashboard で作って、Config/Products.luau に ID を書く)")
local unset = {}
for _, gp in Products.GamePasses do
	if gp.id == 0 then
		table.insert(unset, "パス " .. gp.key)
	end
end
for _, dp in Products.DevProducts do
	if dp.id == 0 then
		table.insert(unset, "アイテム " .. dp.key)
	end
end
if #unset == 0 then
	ok("ゲームパス・開発者アイテムの ID がすべて入っている")
else
	bad(
		("ID が 0 のまま(購入ボタンが出ない): %d 件 — %s"):format(
			#unset,
			table.concat(unset, ", ")
		)
	)
end
if Products.RewardedAd.enabled and Products.RewardedAd.devProductId == 0 then
	bad("動画広告を有効にしたのに devProductId が 0")
end

print("■ 音と見た目")
if Cries.soundId == "rbxassetid://0" or Cries.soundId == "" then
	bad(
		"鳴き声の音(assets/sounds/YokaiCries.ogg)を Roblox にアップロードして、Config/Cries.luau の soundId に書く"
	)
else
	ok("鳴き声の音: " .. Cries.soundId)
end
for _, f in { "icon.png", "thumb_collection.png", "thumb_attack.png", "thumb_boss.png", "thumb_sea.png" } do
	if fs.isFile("assets/marketing/" .. f) then
		ok("assets/marketing/" .. f)
	else
		bad("assets/marketing/" .. f .. " が無い(python tools/marketing/render_marketing.py で作る)")
	end
end
todo(
	"魚の3Dモデル: Studio で assets/fish/YokaiFishMeshes.glb と YokaiFishMeshes_RiverSea.glb を読み込み、ReplicatedStorage.FishMeshes に置く(docs/ANIME_MESHES.md)"
)

print("■ 中身")
local open, soon = {}, {}
for _, s in Config.Spots do
	table.insert(if s.available then open else soon, s.id)
end
ok(
	("遊べる釣り場 %d(%s)/ 近日公開 %d(%s)"):format(
		#open,
		table.concat(open, ", "),
		#soon,
		table.concat(soon, ", ")
	)
)
ok(
	("妖怪魚 %d 種・相棒の技 %d・妖怪退治の相手 %d・ボス %d"):format(
		#Config.Fish,
		#Config.Battle.Moves,
		#Config.Trainers,
		#Config.Bosses
	)
)

print("■ Studio / Creator Dashboard で人がやること(docs/LAUNCH.md)")
todo(("ゲーム設定 → 場所 → 最大プレイヤー数を %d に"):format(Config.Online.MaxPlayers))
todo(
	"ゲーム設定 → セキュリティ → API サービスへのアクセスを有効に(DataStore / MemoryStore)"
)
todo("アイコンとサムネイルを Creator Dashboard にアップロード(assets/marketing)")
todo(
	"Studio の「テスト → サーバーとクライアント」で2〜3人の通しプレイ(docs/LAUNCH.md のチェックリスト)"
)
todo("スマホ表示(デバイスエミュレーター)で 釣り・お店・バトル を一通り")

print(("\n未設定: %d 件"):format(missing))
process.exit(if missing == 0 then 0 else 1)
