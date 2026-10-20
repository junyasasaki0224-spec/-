-- サーバーとクライアントの両方から使う設定値
local Config = {
	COIN_COUNT = 10, -- マップに置くコインの数
	COIN_VALUE = 1, -- コイン1枚で増えるポイント
	RESPAWN_SECONDS = 5, -- 取られたコインが復活するまでの秒数
	SPAWN_RADIUS = 40, -- コインを置く範囲(原点からの距離)
}

return Config
